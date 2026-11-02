#!/usr/bin/env bash
# Tests for the release-tag signature check in `install.sh update` (v0.26.1 lane S; spec .agents/handoff/01-spec.md,
# slices S1-S3). Hermetic: a throw-away origin built from this working tree (every fixture tag carries the code under
# test), SSH keys made here with ssh-keygen, a hand-built PGP tag object, no network, own git/gpg/playbook config.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/releases-fixture.sh"

if ! (cd "$PB_ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  echo "skip: $PB_ROOT is not a git checkout"; t_summary; exit 0
fi

W="$(cd "$(mk_tmp)" && pwd -P)"
# Isolation: no global/system git config (a developer's tag.gpgsign, allowedSignersFile ...), own gpg home, and the
# playbook global conf in a temp dir (a real require_signed_tags=yes must not leak in). HOME is a separate empty dir,
# so an implementation that ignores PLAYBOOK_HOME does not see the conf written here.
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
: > "$GIT_CONFIG_GLOBAL"
GNUPGHOME="$(mk_tmp)"; export GNUPGHOME
PLAYBOOK_HOME="$(mk_tmp)"; export PLAYBOOK_HOME
HOME="$(mk_tmp)"; export HOME
# v0.33.0 S4 (AC6'): update checks the GitHub Release of the target tag first. This suite is about the signature check, so
# it uses the test seam (PB_RELEASES_API) with a fake curl that answers 200 for every tag; the Release check is tested in
# tests/test-update-release.sh.
rf_fake_curl "$W/bin" || { echo "fake curl setup failed"; exit 3; }
export PATH="$W/bin:$PATH" PB_RELEASES_API="http://releases.test.invalid" PB_RELEASES_REPO="test/playbook" PB_FAKE_CURL_DEFAULT=200
mkdir -p "$PLAYBOOK_HOME/.agents" || { echo "conf dir setup failed"; exit 3; }
CONF="$PLAYBOOK_HOME/.agents/playbook.conf"
conf() { printf 'require_signed_tags=%s\n' "$1" > "$CONF"; }   # conf VALUE
conf_unset() { : > "$CONF"; }                                    # empty conf file = key unset

G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# ---- probe: can this git + ssh-keygen sign a tag and verify it against an allowed signers file? (AC16, L-0004) ----
probe_ssh() {
  local p
  p="$(cd "$(mk_tmp)" && pwd -P)" || return 1
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  ssh-keygen -q -t ed25519 -N '' -C probe -f "$p/k" < /dev/null > /dev/null 2>&1 || return 1
  printf 'probe@example.invalid namespaces="git" %s\n' "$(cat "$p/k.pub")" > "$p/allowed" || return 1
  ( cd "$p" && git init -q r && cd r && printf 'x\n' > f && G add f && G commit -qm p &&
    G -c gpg.format=ssh -c user.signingkey="$p/k" tag -s probe -m probe ) > /dev/null 2>&1 || return 1
  git -C "$p/r" -c gpg.ssh.allowedSignersFile="$p/allowed" verify-tag probe > /dev/null 2>&1 || return 1
  if git -C "$p/r" verify-tag probe > /dev/null 2>&1; then return 1; fi
  return 0
}
SSH_OK=0
if probe_ssh; then SSH_OK=1; fi

# ---- fixture: one origin, linear history, one release tag per commit, each with its own VERSION ----
# v0.1.0 annotated unsigned (the client starts here)      v0.2.0 annotated unsigned       v0.2.1 lightweight
# v0.4.0 annotated, message ends with a PGP signature block that cannot verify (hand-built tag object, AC18)
# v0.5.0 / v0.5.1 annotated unsigned (AC13 shadowing refs)
# SSH only: v0.3.0 signed by K1 (trusted), v0.3.1 signed by K1 then altered (tampered), v0.3.2 signed by K2 (not trusted)
SRC="$W/src"
mkdir -p "$SRC"
copy_tree() {   # same copy as tests/test-update.sh: tracked + untracked non-ignored files, exec bits kept
  ( cd "$1" && git ls-files -co --exclude-standard ) | while IFS= read -r f; do
    [ -f "$1/$f" ] && printf './%s\n' "$f"
  done | ( cd "$1" && tar -cf - -T - ) | ( cd "$2" && tar -xf - )
}
copy_tree "$PB_ROOT" "$SRC"
mkv() { printf '%s\n' "$1" > VERSION && G commit -qam "r$1"; }   # mkv VERSION (inside $SRC)
pgp_tag() {   # pgp_tag NAME: annotated tag object on HEAD with a PGP signature block that does not verify
  local obj
  obj="$( { printf 'object %s\ntype commit\ntag %s\ntagger tester <t@example.invalid> 1700000000 +0000\n\nrelease %s\n' \
              "$(git rev-parse HEAD)" "$1" "$1"
            printf '%s\n' '-----BEGIN PGP SIGNATURE-----' '' \
              'iHUEABYKAB0WIQRAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
              'AAoJEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
              '=AAAA' '-----END PGP SIGNATURE-----'; } | git hash-object -t tag -w --stdin)" || return 1
  git update-ref "refs/tags/$1" "$obj"
}
( cd "$SRC" && git init -q && printf '0.1.0\n' > VERSION && G add -A && G commit -qm r0.1.0 && G tag -a v0.1.0 -m v0.1.0 &&
  mkv 0.2.0 && G tag -a v0.2.0 -m v0.2.0 &&
  mkv 0.2.1 && G tag v0.2.1 &&
  mkv 0.4.0 && pgp_tag v0.4.0 &&
  mkv 0.5.0 && G tag -a v0.5.0 -m v0.5.0 &&
  mkv 0.5.1 && G tag -a v0.5.1 -m v0.5.1 ) || { echo "fixture setup failed"; exit 3; }
[ "$(git -C "$SRC" cat-file -t refs/tags/v0.2.1)" = commit ] || { echo "fixture: v0.2.1 is not lightweight"; exit 3; }
git -C "$SRC" cat-file tag refs/tags/v0.4.0 | grep -q '^-----BEGIN PGP SIGNATURE-----$' || { echo "fixture: v0.4.0 has no PGP block"; exit 3; }
if git -C "$SRC" verify-tag v0.4.0 > /dev/null 2>&1; then echo "fixture: v0.4.0 must not verify"; exit 3; fi

KD="$W/keys"
if [ "$SSH_OK" = 1 ]; then
  mkdir -p "$KD" &&
  ssh-keygen -q -t ed25519 -N '' -C k1 -f "$KD/k1" < /dev/null > /dev/null 2>&1 &&
  ssh-keygen -q -t ed25519 -N '' -C k2 -f "$KD/k2" < /dev/null > /dev/null 2>&1 &&
  printf 'release@example.invalid namespaces="git" %s\n' "$(cat "$KD/k1.pub")" > "$KD/allowed" &&
  : > "$KD/empty" || { echo "key setup failed"; exit 3; }
  S() { G -c gpg.format=ssh -c user.signingkey="$KD/$1" tag -s "$2" -m "signed release $2"; }   # S KEY TAG
  ( cd "$SRC" &&
    mkv 0.3.0 && S k1 v0.3.0 &&
    mkv 0.3.1 && S k1 v0.3.1 &&
    mkv 0.3.2 && S k2 v0.3.2 ) > /dev/null 2>&1 || { echo "signed tag setup failed"; exit 3; }
  old="$(git -C "$SRC" rev-parse refs/tags/v0.3.1)"
  new="$(git -C "$SRC" cat-file tag refs/tags/v0.3.1 | sed 's/^signed release v0.3.1$/signed release v0.3.1 (altered)/' |
         git -C "$SRC" hash-object -t tag -w --stdin)" &&
  [ -n "$new" ] && [ "$new" != "$old" ] && git -C "$SRC" update-ref refs/tags/v0.3.1 "$new" || { echo "tamper setup failed"; exit 3; }
  AL() { git -C "$SRC" -c gpg.ssh.allowedSignersFile="$KD/allowed" verify-tag "$1" > /dev/null 2>&1; }
  AL v0.3.0 || { echo "fixture: v0.3.0 must verify"; exit 3; }
  if AL v0.3.1; then echo "fixture: tampered v0.3.1 must not verify"; exit 3; fi
  if AL v0.3.2; then echo "fixture: v0.3.2 (other key) must not verify"; exit 3; fi
fi

git clone -q --bare "$SRC" "$W/origin.git" || { echo "origin setup failed"; exit 3; }
C="$W/client"
git clone -q "$W/origin.git" "$C" 2> /dev/null || { echo "client setup failed"; exit 3; }
BASE="$(git -C "$C" rev-parse 'refs/tags/v0.1.0^{commit}')"
base() { git -C "$C" -c advice.detachedHead=false checkout -q "$BASE" || { echo "reset to v0.1.0 failed"; exit 3; }; }
base

REG_EMPTY="$W/registry-empty"; : > "$REG_EMPTY"
REG_FULL="$W/registry-full"; : > "$REG_FULL"
export PLAYBOOK_REGISTRY="$REG_EMPTY"   # nothing to re-install: keeps each update cheap
UPD() { bash "$C/install.sh" update "$@" < /dev/null; }
UPDF() { PLAYBOOK_REGISTRY="$REG_FULL" bash "$C/install.sh" update "$@" < /dev/null; }   # with one recorded install
# one recorded install at v0.1.0, so "state unchanged" also covers a target's managed block (AC4)
TH="$(mk_tmp)"
PLAYBOOK_REGISTRY="$REG_FULL" bash "$C/install.sh" install --home "$TH" --harness claude --yes $MODEFLAG < /dev/null > /dev/null 2>&1 ||
  { echo "install setup failed"; exit 3; }
hdr() { grep -o 'BEGIN agent-playbook v[0-9.]*' "$1" | head -n 1; }
[ "$(hdr "$TH/.claude/CLAUDE.md")" = "BEGIN agent-playbook v0.1.0" ] || { echo "install setup: block is not v0.1.0"; exit 3; }

# lines of $OUT that contain both needles (fixed strings)
line_with() { printf '%s\n' "$OUT" | grep -F -e "$1" | grep -F -e "$2"; }
head_is() {   # head_is NAME TAG -> HEAD is the tag's commit (refs/tags/TAG, never another ref of that name)
  assert_eq "$1" "$(git -C "$C" rev-parse "refs/tags/$2^{commit}")" "$(git -C "$C" rev-parse HEAD)"
}
unchanged() { assert_eq "$1" "$BASE" "$(git -C "$C" rev-parse HEAD)"; }   # unchanged NAME -> HEAD still at v0.1.0

# =====================================================================================================
# S1: unsigned tags warn and continue; the checkout is the tag's commit; --check is untouched
# =====================================================================================================
echo "S1 unsigned annotated tag (AC2)"
conf_unset; base
run UPD --to v0.2.0 --yes
assert_rc "AC2 unsigned annotated tag: update completes with exit 0" 0
assert_contains "AC2 a WARN: line names v0.2.0 and says not signed" "$(line_with 'WARN:' 'not signed')" "v0.2.0"
head_is "AC2 HEAD is the commit of v0.2.0" v0.2.0
assert_not_contains "AC2 an unsigned tag is not reported as verified" "$OUT" "signature verified"

echo "S1 lightweight tag, as tools/release.sh makes today (AC3)"
conf_unset; base
run UPD --to v0.2.1 --yes
assert_rc "AC3 lightweight tag: update completes with exit 0" 0
assert_contains "AC3 a WARN: line names v0.2.1 and says not signed" "$(line_with 'WARN:' 'not signed')" "v0.2.1"
head_is "AC3 HEAD is the commit of v0.2.1" v0.2.1

echo "S1 explicit require_signed_tags=no behaves like unset (Oracle row UNSIGNED, conf no)"
conf no; base
run UPD --to v0.2.0 --yes
assert_rc "Oracle conf no: unsigned tag still updates with exit 0" 0
assert_contains "Oracle conf no: a WARN: line names v0.2.0 and says not signed" "$(line_with 'WARN:' 'not signed')" "v0.2.0"

echo "S1 a local branch named like the tag points elsewhere (AC13, D7)"
conf_unset; base
git -C "$C" branch v0.5.0 'refs/tags/v0.2.0^{commit}' || { echo "AC13 branch setup failed"; exit 3; }
run UPD --to v0.5.0 --yes
assert_rc "AC13 same-named branch: update exits 0" 0
head_is "AC13 same-named branch: HEAD is refs/tags/v0.5.0^{commit}, not the branch" v0.5.0

echo "S1 a ref refs/<tag> points elsewhere (AC13, D7: refs/T wins over refs/tags/T for a bare name)"
conf_unset; base
git -C "$C" update-ref refs/v0.5.1 'refs/tags/v0.2.0^{commit}' || { echo "AC13 ref setup failed"; exit 3; }
run UPD --to v0.5.1 --yes
assert_rc "AC13 refs/v0.5.1 shadow: update exits 0" 0
head_is "AC13 refs/v0.5.1 shadow: HEAD is refs/tags/v0.5.1^{commit}, not refs/v0.5.1" v0.5.1

echo "S1 update --check prints no signature line (AC14, D8; characterization: passes before and after)"
conf_unset; base
run UPD --check
assert_rc "AC14 --check exits 0" 0
assert_contains "AC14 --check still reports the update" "$OUT" "UPDATE AVAILABLE"
assert_not_contains "AC14 --check prints no 'signature verified'" "$OUT" "signature verified"
assert_not_contains "AC14 --check prints no 'not signed' warning" "$OUT" "not signed"
conf yes; base
run UPD --check
assert_rc "AC14 D8 --check under require_signed_tags=yes still exits 0 (no verification)" 0
assert_not_contains "AC14 D8 --check under require_signed_tags=yes names no require_signed_tags refusal" "$OUT" "require_signed_tags"

# =====================================================================================================
# S2 (no SSH needed): a PGP signature that does not verify is UNTRUSTED -> warn (AC18, D4)
# =====================================================================================================
echo "S2 PGP signature block that cannot be checked (AC18)"
conf_unset; base
run UPD --to v0.4.0 --yes
assert_rc "AC18 failing PGP signature, conf unset: update completes with exit 0" 0
assert_contains "AC18 a WARN: line names v0.4.0 and says cannot be checked" "$(line_with 'WARN:' 'cannot be checked')" "v0.4.0"
head_is "AC18 HEAD is the commit of v0.4.0" v0.4.0
assert_not_contains "AC18 a failing PGP signature is not reported as 'does not verify' (not BAD, D4)" "$OUT" "does not verify"

# =====================================================================================================
# S3: require_signed_tags (global conf only) and --allow-unsigned; usage text
# =====================================================================================================
refused() {   # refused LABEL TAG -> the require-mode refusal assertions (AC7 shape)
  assert_rc "$1 exits 1" 1
  assert_contains "$1 the require_signed_tags message names $2" "$(line_with 'require_signed_tags' "$2")" "$2"
  assert_contains "$1 the message names --allow-unsigned" "$OUT" "--allow-unsigned"
  assert_not_contains "$1 stops before the changelog" "$OUT" "CHANGELOG at"
  unchanged "$1 HEAD unchanged"
}
echo "S3 require_signed_tags=yes refuses an unsigned annotated tag (AC7)"
conf yes; base
run UPD --to v0.2.0 --yes
refused "AC7 unsigned annotated v0.2.0 under require_signed_tags=yes:" v0.2.0

echo "S3 require_signed_tags=yes refuses a lightweight tag (AC7)"
conf yes; base
run UPD --to v0.2.1 --yes
refused "AC7 lightweight v0.2.1 under require_signed_tags=yes:" v0.2.1

echo "S3 require_signed_tags=yes refuses a PGP tag that cannot be checked (AC18 require rows)"
conf yes; base
run UPD --to v0.4.0 --yes
refused "AC18 failing PGP v0.4.0 under require_signed_tags=yes:" v0.4.0
conf yes; base
run UPD --to v0.4.0 --yes --allow-unsigned
assert_rc "AC18 failing PGP v0.4.0 under require_signed_tags=yes with --allow-unsigned: exit 0" 0
head_is "AC18 failing PGP v0.4.0 with --allow-unsigned: HEAD is the commit of v0.4.0" v0.4.0

echo "S3 --allow-unsigned lets an unsigned tag through under require_signed_tags=yes (AC8)"
conf yes; base
run UPD --to v0.2.0 --yes --allow-unsigned
assert_rc "AC8 --allow-unsigned under require_signed_tags=yes: exit 0" 0
assert_contains "AC8 a WARN: line names v0.2.0 and says not signed" "$(line_with 'WARN:' 'not signed')" "v0.2.0"
head_is "AC8 HEAD is the commit of v0.2.0" v0.2.0

echo "S3 an invalid require_signed_tags value fails closed (AC10, D5)"
for bad in Yes true; do
  conf "$bad"; base
  run UPD --to v0.2.0 --yes
  assert_rc "AC10 require_signed_tags=$bad: exit 2" 2
  assert_contains "AC10 require_signed_tags=$bad: the message names the key and the bad value" "$(line_with 'require_signed_tags' "$bad")" "$bad"
  unchanged "AC10 require_signed_tags=$bad: HEAD unchanged"
done

echo "S3 a project conf cannot switch the global requirement off (AC11, D5)"
conf yes; base
P="$(mk_tmp)"
mk_repo "$P" > /dev/null 2>&1 && mkdir -p "$P/.agents" && printf 'require_signed_tags=no\n' > "$P/.agents/playbook.conf" ||
  { echo "AC11 project setup failed"; exit 3; }
run_in "$P" UPD --to v0.2.0 --yes
assert_rc "AC11 global yes + project no, run from the project: still exits 1" 1
unchanged "AC11 global yes + project no: HEAD unchanged"

echo "S3 usage text (AC15)"
run bash "$C/install.sh" help
assert_contains "AC15 help lists --allow-unsigned" "$OUT" "--allow-unsigned"
assert_contains "AC15 help names require_signed_tags" "$OUT" "require_signed_tags"
SIGSEC="$(printf '%s\n' "$OUT" | awk '/^Release tag signatures/ { f = 1 } f')"
assert_contains "fix3 S-D4 help: the signatures section names PGP (a failing PGP/x509 signature warns)" "$SIGSEC" "PGP"
assert_contains "fix3 S-D4 help: the signatures section names SSH (stops with an allowed signers file)" "$SIGSEC" "SSH"
assert_not_contains "fix3 S-D4 help: no claim that a signature that does not verify always stops" "$OUT" "always stops the update"
conf_unset; base
run UPD --no-such-option
assert_rc "AC15 an unknown option still exits 2 (characterization)" 2

# =====================================================================================================
# S2 + S3 rows that need SSH signing (probe above; skipped as one block with the same count, AC16)
# =====================================================================================================
SSH_ASSERTS=44   # the assertions in the else branch below; keep in step when adding one
if [ "$SSH_OK" != 1 ]; then
  t_skip "$SSH_ASSERTS" "SSH-signed tag cases: git SSH signing or ssh-keygen -Y not usable here (AC16, L-0004)"
else
  git -C "$C" config gpg.ssh.allowedSignersFile "$KD/allowed" || { echo "allowed signers config failed"; exit 3; }

  echo "S2 SSH-signed tag, key in the allowed signers file (AC1)"
  conf_unset; base
  run UPD --to v0.3.0 --yes
  assert_rc "AC1 verified tag: exit 0" 0
  assert_contains "AC1 the 'signature verified' line names v0.3.0" "$(line_with 'signature verified' 'v0.3.0')" "v0.3.0"
  head_is "AC1 HEAD is the commit of v0.3.0" v0.3.0
  assert_not_contains "AC1 a verified tag gets no WARN" "$OUT" "WARN:"

  echo "S2 tampered signed tag (AC4): stops, nothing changes, even with --allow-unsigned or --dry-run"
  conf_unset; base
  run UPDF --to v0.3.1 --yes
  assert_rc "AC4 tampered v0.3.1: exit 1" 1
  assert_contains "AC4 tampered: the 'does not verify' message names v0.3.1" "$(line_with 'does not verify' 'v0.3.1')" "v0.3.1"
  unchanged "AC4 tampered: HEAD unchanged"
  assert_eq "AC4 tampered: the recorded target's CLAUDE.md block is still v0.1.0" "BEGIN agent-playbook v0.1.0" "$(hdr "$TH/.claude/CLAUDE.md")"
  base
  run UPD --to v0.3.1 --yes --allow-unsigned
  assert_rc "AC4 D3 tampered with --allow-unsigned: still exit 1" 1
  assert_contains "AC4 D3 tampered with --allow-unsigned: says does not verify" "$OUT" "does not verify"
  unchanged "AC4 D3 tampered with --allow-unsigned: HEAD unchanged"
  base
  run UPD --to v0.3.1 --yes --dry-run
  assert_rc "AC4 D6 tampered with --dry-run: exit 1" 1
  assert_contains "AC4 D6 tampered with --dry-run: says does not verify" "$OUT" "does not verify"
  conf yes; base
  run UPD --to v0.3.1 --yes --allow-unsigned
  assert_rc "Oracle BAD row, any conf: tampered under require_signed_tags=yes with --allow-unsigned: exit 1" 1

  echo "S2 tag signed by a key not in the allowed signers file (AC5)"
  conf_unset; base
  run UPD --to v0.3.2 --yes
  assert_rc "AC5 unknown signer v0.3.2: exit 1" 1
  assert_contains "AC5 unknown signer: the 'does not verify' message names v0.3.2" "$(line_with 'does not verify' 'v0.3.2')" "v0.3.2"
  unchanged "AC5 unknown signer: HEAD unchanged"
  base
  run UPD --to v0.3.2 --yes --allow-unsigned
  assert_rc "AC5 D3 unknown signer with --allow-unsigned: still exit 1" 1
  unchanged "AC5 D3 unknown signer with --allow-unsigned: HEAD unchanged"

  echo "S2 verification comes before the confirmation prompt (AC12)"
  conf_unset; base
  run UPD --to v0.3.1
  assert_rc "AC12 tampered tag, no --yes, non-interactive: exit 1 (not the confirm exit 2)" 1
  assert_not_contains "AC12 no changelog is shown before the refusal" "$OUT" "CHANGELOG at"

  echo "S2 SSH signature without a usable allowed signers file is UNTRUSTED -> warn (AC6, D2)"
  git -C "$C" config --unset gpg.ssh.allowedSignersFile
  conf_unset; base
  run UPD --to v0.3.0 --yes
  assert_rc "AC6 allowedSignersFile unset: exit 0" 0
  wl="$(line_with 'WARN:' 'cannot be checked')"
  assert_contains "AC6 allowedSignersFile unset: the 'cannot be checked' WARN line names v0.3.0" "$wl" "v0.3.0"
  assert_contains "AC6 allowedSignersFile unset: the WARN line names gpg.ssh.allowedSignersFile" "$wl" "gpg.ssh.allowedSignersFile"
  head_is "AC6 allowedSignersFile unset: HEAD is the commit of v0.3.0" v0.3.0
  git -C "$C" config gpg.ssh.allowedSignersFile "$KD/no-such-file"
  base
  run UPD --to v0.3.0 --yes
  assert_rc "AC6 allowedSignersFile names a missing file: exit 0" 0
  wl="$(line_with 'WARN:' 'cannot be checked')"
  assert_contains "AC6 missing file: the 'cannot be checked' WARN line names v0.3.0" "$wl" "v0.3.0"
  assert_contains "AC6 missing file: the WARN line names gpg.ssh.allowedSignersFile" "$wl" "gpg.ssh.allowedSignersFile"
  git -C "$C" config gpg.ssh.allowedSignersFile "$KD/empty"
  base
  run UPD --to v0.3.0 --yes
  assert_rc "AC6 allowedSignersFile names an empty file: exit 0" 0
  wl="$(line_with 'WARN:' 'cannot be checked')"
  assert_contains "AC6 empty file: the 'cannot be checked' WARN line names v0.3.0" "$wl" "v0.3.0"
  assert_contains "AC6 empty file: the WARN line names gpg.ssh.allowedSignersFile" "$wl" "gpg.ssh.allowedSignersFile"

  echo "S3 require_signed_tags=yes refuses an UNTRUSTED SSH tag (AC7)"
  git -C "$C" config --unset gpg.ssh.allowedSignersFile
  conf yes; base
  run UPD --to v0.3.0 --yes
  refused "AC7 untrusted SSH v0.3.0 under require_signed_tags=yes:" v0.3.0

  echo "S3 require_signed_tags=yes accepts a verified tag (AC9)"
  git -C "$C" config gpg.ssh.allowedSignersFile "$KD/allowed"
  conf yes; base
  run UPD --to v0.3.0 --yes
  assert_rc "AC9 verified tag under require_signed_tags=yes: exit 0" 0
  assert_contains "AC9 says signature verified" "$OUT" "signature verified"
  head_is "AC9 HEAD is the commit of v0.3.0" v0.3.0

  echo "S2 a relative gpg.ssh.allowedSignersFile is read from the top of the work tree, as git does (review fix 4)"
  # git-config(1), gpg.ssh.allowedSignersFile: a repository can store the file "using a path relative to the top-level of
  # the working tree" (https://git-scm.com/docs/git-config, page for git 2.56.0). The update runs from another directory.
  cp "$KD/allowed" "$C/.git/pb-allowed-rel" || { echo "relative allowed signers setup failed"; exit 3; }
  git -C "$C" config gpg.ssh.allowedSignersFile .git/pb-allowed-rel || { echo "relative allowed signers config failed"; exit 3; }
  git -C "$C" verify-tag v0.3.0 > /dev/null 2>&1 || { echo "fixture: git does not resolve the relative allowed signers file"; exit 3; }
  OD="$(mk_tmp)"
  conf_unset; base
  run_in "$OD" UPD --to v0.3.2 --yes
  assert_rc "fix4 relative allowedSignersFile, signer not in it, run from another directory: exit 1" 1
  assert_contains "fix4 ... the 'does not verify' message names v0.3.2" "$(line_with 'does not verify' 'v0.3.2')" "v0.3.2"
  unchanged "fix4 ... HEAD unchanged"
  base
  run_in "$OD" UPD --to v0.3.0 --yes
  assert_rc "fix4 relative allowedSignersFile, trusted signer, run from another directory: exit 0" 0
  assert_contains "fix4 ... the 'signature verified' line names v0.3.0" "$(line_with 'signature verified' 'v0.3.0')" "v0.3.0"
  git -C "$C" config gpg.ssh.allowedSignersFile "$KD/allowed"
fi

t_summary
