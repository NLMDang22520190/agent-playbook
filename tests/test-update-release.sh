#!/usr/bin/env bash
# Tests for the GitHub Release check of `install.sh update` (v0.33.0 slice S4: AC6, AC6', N7; decisions D5, D9).
# Hermetic: a throw-away origin built from this working tree, a fake `curl` on PATH (tests/releases-fixture.sh) that
# answers the Releases API, no network, own git/playbook config. No fixture tag is signed.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/releases-fixture.sh"

if ! (cd "$PB_ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  echo "skip: $PB_ROOT is not a git checkout"; t_summary; exit 0
fi

W="$(cd "$(mk_tmp)" && pwd -P)"
# Isolation: no global/system git config, a playbook global conf in a temp dir, a separate empty HOME, and no way to
# reach the network from git: fetches of a github.com origin fail at once (closed proxy port, ssh replaced by `false`).
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_NOSYSTEM=1 LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false
: > "$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0=http://127.0.0.1:9
PLAYBOOK_HOME="$(mk_tmp)"; export PLAYBOOK_HOME
HOME="$(mk_tmp)"; export HOME
mkdir -p "$PLAYBOOK_HOME/.agents" || { echo "conf dir setup failed"; exit 3; }
CONF="$PLAYBOOK_HOME/.agents/playbook.conf"
: > "$CONF"
unset PB_RELEASES_API PB_RELEASES_REPO

G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# ---- fixture: linear history, annotated unsigned tags v0.1.0 (client start) v0.2.0 v0.3.0 v0.4.0; every tag has install.sh ----
SRC="$W/src"; mkdir -p "$SRC"
copy_tree() {
  ( cd "$1" && git ls-files -co --exclude-standard ) | while IFS= read -r f; do
    [ -f "$1/$f" ] && printf './%s\n' "$f"
  done | ( cd "$1" && tar -cf - -T - ) | ( cd "$2" && tar -xf - )
}
copy_tree "$PB_ROOT" "$SRC"
mkv() { printf '%s\n' "$1" > VERSION && G commit -qam "r$1"; }
( cd "$SRC" && git init -q && printf '0.1.0\n' > VERSION && G add -A && G commit -qm r0.1.0 && G tag -a v0.1.0 -m v0.1.0 &&
  mkv 0.2.0 && G tag -a v0.2.0 -m v0.2.0 &&
  mkv 0.3.0 && G tag -a v0.3.0 -m v0.3.0 &&
  mkv 0.4.0 && G tag -a v0.4.0 -m v0.4.0 ) || { echo "fixture setup failed"; exit 3; }
ORIGIN="$W/origin.git"
git clone -q --bare "$SRC" "$ORIGIN" || { echo "origin setup failed"; exit 3; }
C="$W/client"
git clone -q "$ORIGIN" "$C" 2> /dev/null || { echo "client setup failed"; exit 3; }
BASE="$(git -C "$C" rev-parse 'refs/tags/v0.1.0^{commit}')"
rf_fake_curl "$W/bin" || { echo "fake curl setup failed"; exit 3; }
export PATH="$W/bin:$PATH"
export PB_FAKE_CURL_LOG="$W/curl.log" PB_FAKE_CURL_MAP="$W/curl.map"
REG="$W/registry"; : > "$REG"; export PLAYBOOK_REGISTRY="$REG"
git -C "$C" -c advice.detachedHead=false checkout -q "$BASE" || { echo "checkout v0.1.0 failed"; exit 3; }
TH="$(mk_tmp)"
# the one recorded install (v0.1.0) is also what "nothing was changed" is measured on; the seam answers 200 for this setup
PB_RELEASES_API="http://releases.test.invalid" PB_FAKE_CURL_DEFAULT=200 \
  bash "$C/install.sh" install --home "$TH" --harness claude --yes $MODEFLAG < /dev/null > /dev/null 2>&1 || { echo "install setup failed"; exit 3; }
hdr() { grep -o 'BEGIN agent-playbook v[0-9.]*' "$1" | head -n 1; }
[ "$(hdr "$TH/.claude/CLAUDE.md")" = "BEGIN agent-playbook v0.1.0" ] || { echo "install setup: block is not v0.1.0"; exit 3; }

API="http://releases.test.invalid"
RREPO="zed/pb"
U() { printf '%s/repos/%s/releases/tags/%s' "$API" "$RREPO" "$1"; }   # U TAG -> the request URL under the seam
# rel TAG=CODE ...: what the fake Releases API answers (unlisted tags get 404)
rel() { : > "$PB_FAKE_CURL_MAP"; local a; for a in "$@"; do printf '%s %s\n' "$(U "${a%%=*}")" "${a#*=}" >> "$PB_FAKE_CURL_MAP"; done; export PB_FAKE_CURL_DEFAULT=404; }
# reld CODE: every tag gets CODE (404, 500 or FAIL)
reld() { : > "$PB_FAKE_CURL_MAP"; export PB_FAKE_CURL_DEFAULT="$1"; }
base() {   # back to v0.1.0 (HEAD and the recorded install), the local bare origin, an empty curl log, an empty conf
  git -C "$C" -c advice.detachedHead=false checkout -q "$BASE" || { echo "reset to v0.1.0 failed"; exit 3; }
  git -C "$C" remote set-url origin "$ORIGIN"
  : > "$PB_FAKE_CURL_LOG"; : > "$CONF"
  PB_RELEASES_API="$API" PB_FAKE_CURL_DEFAULT=200 bash "$C/install.sh" install --home "$TH" --harness claude --yes $MODEFLAG < /dev/null > /dev/null 2>&1
  : > "$PB_FAKE_CURL_LOG"
}
SEAM() { PB_RELEASES_API="$API" PB_RELEASES_REPO="$RREPO" "$@"; }
UPD() { bash "$C/install.sh" update "$@" < /dev/null; }
line_with() { printf '%s\n' "$OUT" | grep -F -e "$1" | grep -F -e "$2"; }
head_is() { assert_eq "$1" "$(git -C "$C" rev-parse "refs/tags/$2^{commit}")" "$(git -C "$C" rev-parse HEAD)"; }
unchanged() {   # unchanged NAME: HEAD still at v0.1.0 and the recorded install's block still v0.1.0 (nothing was changed)
  assert_eq "$1 (HEAD)" "$BASE" "$(git -C "$C" rev-parse HEAD)"
  assert_eq "$1 (installed block)" "BEGIN agent-playbook v0.1.0" "$(hdr "$TH/.claude/CLAUDE.md")"
}
HINT="(pass --allow-unreleased to update anyway)"

# =====================================================================================================
echo "AC6' the Releases request (contract) and the plain update target (D9)"
base; rel v0.4.0=404 v0.3.0=200 v0.2.0=200
run SEAM UPD --yes
assert_rc "AC6' plain update: newest tag v0.4.0 unreleased, v0.3.0 released -> exit 0" 0
head_is "AC6' plain update targets the newest RELEASED tag v0.3.0" v0.3.0
assert_contains "D9 INFO line for the newer unreleased tag (exact text)" "$OUT" "INFO  newer tag v0.4.0 has no GitHub Release; skipped"
assert_not_contains "D9 no INFO line for v0.3.0, the released one" "$OUT" "newer tag v0.3.0"
assert_contains "AC6 the chosen tag is reported: GitHub Release found" "$OUT" "release tag v0.3.0: GitHub Release found"
assert_eq "AC6' the request is exactly curl -q -sS -o /dev/null -w '%{http_code}' <api>/repos/<o>/<r>/releases/tags/<tag> (newest first, stops at the first 200)" \
  "$(printf '%s\n%s\n' "-q -sS -o /dev/null -w %{http_code} $(U v0.4.0)" "-q -sS -o /dev/null -w %{http_code} $(U v0.3.0)")" "$(cat "$PB_FAKE_CURL_LOG")"
assert_eq "AC6 the recorded install was re-installed at v0.3.0" "BEGIN agent-playbook v0.3.0" "$(hdr "$TH/.claude/CLAUDE.md")"

echo "D9 two newer tags unreleased: one INFO line each, the released v0.2.0 is taken"
base; rel v0.4.0=404 v0.3.0=404 v0.2.0=200
run SEAM UPD --yes
assert_rc "D9 exit 0" 0
head_is "D9 target is v0.2.0" v0.2.0
assert_contains "D9 INFO line for v0.4.0" "$OUT" "INFO  newer tag v0.4.0 has no GitHub Release; skipped"
assert_contains "D9 INFO line for v0.3.0" "$OUT" "INFO  newer tag v0.3.0 has no GitHub Release; skipped"
assert_not_contains "D9 no INFO line for v0.2.0 (the target)" "$OUT" "newer tag v0.2.0"

echo "AC6' the newest tag is released: no INFO line, target is the newest"
base; rel v0.4.0=200
run SEAM UPD --yes
assert_rc "AC6' newest released -> exit 0" 0
head_is "AC6' target is v0.4.0" v0.4.0
assert_not_contains "D9 no INFO line when nothing was skipped" "$OUT" "has no GitHub Release; skipped"

echo "AC6' --to T: T must be released"
base; rel v0.2.0=200
run SEAM UPD --to v0.2.0 --yes
assert_rc "AC6' --to a released tag -> exit 0" 0
head_is "AC6' --to v0.2.0 checked out" v0.2.0
assert_contains "AC6 --to released: GitHub Release found" "$OUT" "release tag v0.2.0: GitHub Release found"
base; rel v0.4.0=404 v0.3.0=200
run SEAM UPD --to v0.4.0 --yes
assert_rc "AC6' --to an unreleased tag -> exit 1" 1
assert_contains "AC6' exact refusal message" "$OUT" "release tag v0.4.0 has no GitHub Release (its CI release gate did not pass, or it was pushed by hand); nothing was changed $HINT"
unchanged "AC6' --to unreleased: nothing changed"
assert_not_contains "N7 no changelog is shown for a refused tag" "$OUT" "---- CHANGELOG"
base; rel v0.4.0=404 v0.3.0=200
run SEAM UPD --to v0.4.0 --dry-run --yes
assert_rc "AC6' --dry-run --to an unreleased tag -> exit 1 too" 1

echo "AC6' nothing released: refuse, nothing changed"
base; reld 404
run SEAM UPD --yes
assert_rc "AC6' no tag has a Release -> exit 1" 1
assert_contains "AC6' says no GitHub Release" "$OUT" "has no GitHub Release"
assert_contains "AC6' says nothing was changed" "$OUT" "nothing was changed"
assert_contains "AC6' gives the --allow-unreleased hint" "$OUT" "$HINT"
unchanged "AC6' nothing released: nothing changed"

echo "AC6' cannot check (HTTP 500, curl failure): refuse with the reason and the same hint"
base; reld 500
run SEAM UPD --yes
assert_rc "AC6' HTTP 500 on the Releases API -> exit 1" 1
assert_contains "AC6' the reason names the answer 500" "$OUT" "500"
assert_contains "AC6' says nothing was changed" "$OUT" "nothing was changed"
assert_contains "AC6' same hint" "$OUT" "$HINT"
assert_not_contains "AC6' a cannot-check is not reported as unreleased" "$OUT" "has no GitHub Release"
unchanged "AC6' HTTP 500: nothing changed"
base; reld FAIL
run SEAM UPD --yes
assert_rc "AC6' curl fails (exit 6) -> exit 1" 1
assert_contains "AC6' says nothing was changed" "$OUT" "nothing was changed"
assert_contains "AC6' same hint" "$OUT" "$HINT"
unchanged "AC6' curl failure: nothing changed"
base; rel v0.2.0=403
run SEAM UPD --to v0.2.0 --yes
assert_rc "AC6' --to with HTTP 403 (rate limit) -> exit 1" 1
assert_contains "AC6' 403: same hint" "$OUT" "$HINT"
unchanged "AC6' 403: nothing changed"
base; reld FAIL
run SEAM UPD --to v0.2.0 --yes
assert_rc "AC6' --to with a curl failure -> exit 1" 1
unchanged "AC6' --to curl failure: nothing changed"
base; rel v0.4.0=201 v0.3.0=302
run SEAM UPD --yes
assert_rc "AC6' only 200 is released: 201 and 302 are cannot-check -> exit 1" 1
unchanged "AC6' 201/302: nothing changed"
base; rel v0.4.0=201
run SEAM UPD --yes
assert_rc "R1-6 plain update, the newest tag answered 201 alone -> cannot check -> exit 1" 1
assert_contains "R1-6 201: the reason names the answer" "$OUT" "201"
assert_contains "R1-6 201: same hint" "$OUT" "$HINT"
assert_not_contains "R1-6 201 is not reported as unreleased" "$OUT" "has no GitHub Release"
unchanged "R1-6 201 alone: nothing changed"
base; rel v0.3.0=302
run SEAM UPD --to v0.3.0 --yes
assert_rc "R1-6 --to v0.3.0 answered 302 alone (a redirect is not a Release) -> cannot check -> exit 1" 1
assert_contains "R1-6 302: the reason names the answer" "$OUT" "302"
assert_contains "R1-6 302: says nothing was changed" "$OUT" "nothing was changed"
assert_contains "R1-6 302: same hint" "$OUT" "$HINT"
assert_not_contains "R1-6 302 is not reported as unreleased (404)" "$OUT" "has no GitHub Release"
assert_not_contains "R1-6 302 is not taken as released" "$OUT" "GitHub Release found"
unchanged "R1-6 302 alone: nothing changed"

echo "D5 --allow-unreleased"
base; reld 404
run SEAM UPD --allow-unreleased --yes
assert_rc "D5 plain update with --allow-unreleased and nothing released -> exit 0" 0
head_is "D5 takes the newest tag v0.4.0 as before" v0.4.0
assert_contains "D5 a WARN line says v0.4.0 has no GitHub Release" "$(line_with 'WARN:' 'GitHub Release')" "v0.4.0"
base; rel v0.4.0=404 v0.3.0=200
run SEAM UPD --allow-unreleased --yes
assert_rc "D5 --allow-unreleased with a released older tag -> exit 0" 0
head_is "D5 --allow-unreleased still takes the NEWEST tag, not the newest released" v0.4.0
assert_contains "D5 WARN line" "$(line_with 'WARN:' 'GitHub Release')" "v0.4.0"
base; reld 500
run SEAM UPD --allow-unreleased --yes
assert_rc "D5 --allow-unreleased also overrides a failed check -> exit 0" 0
head_is "D5 cannot-check + override takes the newest tag" v0.4.0
assert_contains "D5 WARN line on cannot-check" "$(line_with 'WARN:' 'GitHub Release')" "v0.4.0"
base; reld 404
run SEAM UPD --allow-unreleased --to v0.2.0 --yes
assert_rc "D5 --to an unreleased tag with --allow-unreleased -> exit 0" 0
head_is "D5 --to v0.2.0 checked out" v0.2.0
assert_contains "D5 WARN line names v0.2.0" "$(line_with 'WARN:' 'GitHub Release')" "v0.2.0"

echo "AC6' update --check"
base; rel v0.4.0=404 v0.3.0=200
run SEAM UPD --check
assert_rc "AC6' --check exit 0" 0
assert_contains "AC6' HEAD v0.1.0: UPDATE AVAILABLE" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC6' the update offered is the newest released tag" "$(line_with 'UPDATE AVAILABLE' 'v0.3.0')" "v0.3.0"
assert_contains "AC6' names the newer unreleased tag" "$OUT" "v0.4.0"
assert_contains "AC6' says that tag has no GitHub Release" "$OUT" "no GitHub Release"
assert_eq "AC6' --check changes nothing" "$BASE" "$(git -C "$C" rev-parse HEAD)"
git -C "$C" -c advice.detachedHead=false checkout -q v0.3.0
: > "$PB_FAKE_CURL_LOG"
run SEAM UPD --check
assert_rc "AC6' --check at the newest released tag -> exit 0" 0
assert_contains "AC6' at the newest released tag: up to date (not behind the unreleased v0.4.0)" "$OUT" "up to date"
assert_not_contains "AC6' at the newest released tag: no UPDATE AVAILABLE" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC6' still names the newer unreleased tag" "$OUT" "v0.4.0"
base; rel v0.4.0=200
run SEAM UPD --check
assert_rc "AC6' --check, newest tag released -> exit 0" 0
assert_contains "AC6' newest released v0.4.0 is the update" "$(line_with 'UPDATE AVAILABLE' 'v0.4.0')" "v0.4.0"
assert_not_contains "AC6' no unreleased note when the newest is released" "$OUT" "no GitHub Release"
base; reld 500
run SEAM UPD --check
assert_rc "AC6' --check cannot check (500) -> exit 0, it only reports" 0
assert_contains "AC6' prints 'cannot check GitHub Releases: <reason>'" "$OUT" "cannot check GitHub Releases: "
assert_contains "AC6' reports against the newest tag" "$(line_with 'UPDATE AVAILABLE' 'v0.4.0')" "v0.4.0"
base; reld FAIL
run SEAM UPD --check
assert_rc "AC6' --check with a curl failure -> exit 0" 0
assert_contains "AC6' curl failure: 'cannot check GitHub Releases: '" "$OUT" "cannot check GitHub Releases: "
assert_contains "AC6' curl failure: reports against the newest tag" "$OUT" "v0.4.0"
base; reld 404
run SEAM UPD --check
assert_rc "AC6' --check with no released tag -> exit 0" 0
assert_not_contains "AC6' nothing released is not 'cannot check'" "$OUT" "cannot check GitHub Releases"

echo "N7 order: Release check before the signature check, signature check before the changelog"
base; rel v0.4.0=404 v0.3.0=200; printf 'require_signed_tags=yes\n' > "$CONF"
run SEAM UPD --to v0.4.0 --yes
assert_rc "N7 unreleased AND unsigned with require_signed_tags=yes -> exit 1" 1
assert_contains "N7 the Release refusal comes first" "$OUT" "has no GitHub Release"
assert_not_contains "N7 the signature check was not reached" "$OUT" "require_signed_tags"
unchanged "N7 unreleased+unsigned: nothing changed"
base; rel v0.3.0=200; printf 'require_signed_tags=yes\n' > "$CONF"
run SEAM UPD --to v0.3.0 --yes
assert_rc "N7 released but unsigned with require_signed_tags=yes -> exit 1" 1
assert_contains "N7 the signature refusal follows a passed Release check" "$OUT" "require_signed_tags=yes"
assert_not_contains "N7 no changelog before the signature check" "$OUT" "---- CHANGELOG"
unchanged "N7 released+unsigned: nothing changed"
base; rel v0.3.0=404; printf 'require_signed_tags=yes\n' > "$CONF"
run SEAM UPD --allow-unreleased --to v0.3.0 --yes
assert_rc "N7 --allow-unreleased does not skip the signature check -> exit 1" 1
assert_contains "N7 the signature refusal is printed" "$OUT" "require_signed_tags=yes"
unchanged "N7 override does not skip signatures: nothing changed"
base; rel v0.3.0=200
run SEAM UPD --to v0.3.0 --yes
assert_rc "N7 control: released + unsigned, require_signed_tags unset -> exit 0 with a WARN" 0
N_REL="$(printf '%s\n' "$OUT" | grep -n -F 'GitHub Release found' | head -n 1 | cut -d: -f1)"
N_SIG="$(printf '%s\n' "$OUT" | grep -n -F 'is not signed' | head -n 1 | cut -d: -f1)"
N_LOG="$(printf '%s\n' "$OUT" | grep -n -F -e '---- CHANGELOG' | head -n 1 | cut -d: -f1)"
if [ -n "$N_REL" ] && [ -n "$N_SIG" ] && [ -n "$N_LOG" ] && [ "$N_REL" -lt "$N_SIG" ] && [ "$N_SIG" -lt "$N_LOG" ]; then
  t_ok "N7 output order: Release found, then the signature WARN, then the changelog"
else
  t_bad "N7 output order: Release found, then the signature WARN, then the changelog" "line numbers rel=[$N_REL] sig=[$N_SIG] changelog=[$N_LOG] in: $OUT"
fi

echo "AC6' origin forms (no seam: <api> is https://api.github.com, owner/repo from the origin)"
GH="https://api.github.com/repos/Some-Org/agent-playbook/releases/tags/v0.2.0"
for form in "https://github.com/Some-Org/agent-playbook" "https://github.com/Some-Org/agent-playbook.git" \
            "git@github.com:Some-Org/agent-playbook" "git@github.com:Some-Org/agent-playbook.git" \
            "ssh://git@github.com/Some-Org/agent-playbook" "ssh://git@github.com/Some-Org/agent-playbook.git"; do
  base; git -C "$C" remote set-url origin "$form"
  printf '%s 200\n' "$GH" > "$PB_FAKE_CURL_MAP"; export PB_FAKE_CURL_DEFAULT=404
  run UPD --to v0.2.0 --yes
  assert_rc "AC6' origin $form: released -> exit 0" 0
  head_is "AC6' origin $form: v0.2.0 checked out" v0.2.0
  assert_eq "AC6' origin $form: asks api.github.com for Some-Org/agent-playbook" "-q -sS -o /dev/null -w %{http_code} $GH" "$(cat "$PB_FAKE_CURL_LOG")"
done
base; git -C "$C" remote set-url origin "https://github.com/acme/pb.v2.git"
printf '%s 404\n' "https://api.github.com/repos/acme/pb.v2/releases/tags/v0.2.0" > "$PB_FAKE_CURL_MAP"; export PB_FAKE_CURL_DEFAULT=200
run UPD --to v0.2.0 --yes
assert_rc "AC6' origin repo name with a dot (pb.v2.git): only the final .git is stripped -> 404 refused" 1
assert_contains "AC6' the request for acme/pb.v2 was made" "$(cat "$PB_FAKE_CURL_LOG")" "/repos/acme/pb.v2/releases/tags/v0.2.0"

echo "AC6' origin not on github.com, no seam: refuse unless --allow-unreleased"
for form in "$ORIGIN" "https://gitlab.com/o/r.git" "https://github.com.evil.example/o/r.git" "https://notgithub.com/o/r" "git@bitbucket.org:o/r.git"; do
  base; git -C "$C" remote set-url origin "$form"; reld 200
  run UPD --to v0.2.0 --yes
  assert_rc "AC6' origin $form without the seam -> exit 1" 1
  assert_contains "AC6' origin $form: says nothing was changed" "$OUT" "nothing was changed"
  assert_contains "AC6' origin $form: same hint" "$OUT" "$HINT"
  assert_eq "AC6' origin $form: no Releases request is made" "" "$(cat "$PB_FAKE_CURL_LOG")"
  unchanged "AC6' origin $form: nothing changed"
done
base; reld 200
run UPD --allow-unreleased --to v0.2.0 --yes
assert_rc "AC6' non-github origin with --allow-unreleased -> exit 0" 0
head_is "AC6' non-github origin with --allow-unreleased: v0.2.0 checked out" v0.2.0
base; reld 200
run UPD --check
assert_rc "AC6' --check on a non-github origin without the seam -> exit 0 (it only reports)" 0
assert_contains "AC6' --check on a non-github origin: cannot check" "$OUT" "cannot check GitHub Releases: "

echo "AC6' the seam: PB_RELEASES_API replaces the host, PB_RELEASES_REPO the owner/repo, the github.com check is skipped"
base; git -C "$C" remote set-url origin "https://github.com/acme/pb"
printf '%s 200\n' "$API/repos/acme/pb/releases/tags/v0.2.0" > "$PB_FAKE_CURL_MAP"; export PB_FAKE_CURL_DEFAULT=404
run env PB_RELEASES_API="$API" bash "$C/install.sh" update --to v0.2.0 --yes < /dev/null
assert_rc "AC6' seam without PB_RELEASES_REPO: owner/repo from the origin -> exit 0" 0
assert_eq "AC6' seam: <api>/repos/acme/pb/..." "-q -sS -o /dev/null -w %{http_code} $API/repos/acme/pb/releases/tags/v0.2.0" "$(cat "$PB_FAKE_CURL_LOG")"
base; git -C "$C" remote set-url origin "https://github.com/acme/pb"
printf '%s 200\n' "$API/repos/zed/pb/releases/tags/v0.2.0" > "$PB_FAKE_CURL_MAP"; export PB_FAKE_CURL_DEFAULT=404
run SEAM UPD --to v0.2.0 --yes
assert_rc "AC6' PB_RELEASES_REPO wins over a github.com origin -> exit 0" 0
assert_eq "AC6' seam: <api>/repos/zed/pb/..." "-q -sS -o /dev/null -w %{http_code} $API/repos/zed/pb/releases/tags/v0.2.0" "$(cat "$PB_FAKE_CURL_LOG")"
base; rel v0.2.0=200
run SEAM UPD --to v0.2.0 --yes
assert_rc "AC6' seam with a local-path origin: the github.com origin check is skipped -> exit 0" 0

echo "R1-1 tag names that are not release names (v0.5.0#hotfix, v0.5.0-rc1, v0.4.0-rc1) are never a target and never reach the API"
# three hand tags on one commit newer than v0.4.0; the fake curl (like the real one) drops a #fragment, so the old code asked for v0.5.0
( cd "$SRC" && printf '0.5.0\n' > VERSION && G commit -qam "r0.5.0-hand" &&
  G tag -a 'v0.5.0#hotfix' -m hand && G tag -a v0.5.0-rc1 -m rc && G tag -a v0.4.0-rc1 -m rc4 &&
  G push -q "$ORIGIN" --tags ) || { echo "hand tag setup failed"; exit 3; }
HASH='v0.5.0#hotfix'
urls_clean() {   # urls_clean NAME: the log is not empty and every logged URL (last field) matches [A-Za-z0-9._/:-]+
  local bad n
  n="$(grep -c . "$PB_FAKE_CURL_LOG" || true)"
  bad="$(awk '{ print $NF }' "$PB_FAKE_CURL_LOG" | grep -vE '^[A-Za-z0-9._/:-]+$' || true)"
  assert_eq "$1: no request URL holds a character outside [A-Za-z0-9._/:-]" "" "$bad"
  if [ "$n" -ge 1 ]; then t_ok "$1: the log is not empty (a request was made for the real release tag)"; else t_bad "$1: the log is not empty" "no request was logged"; fi
}
HANDMAP="v0.4.0=200 v0.5.0=200 v0.5.0-rc1=200 v0.4.0-rc1=200"
base; rel $HANDMAP
run SEAM UPD --yes
assert_rc "R1-1 plain update with hand tags newer than the released v0.4.0 -> exit 0" 0
head_is "R1-1 plain update takes v0.4.0, not a hand tag" v0.4.0
assert_contains "R1-1 INFO line for v0.5.0#hotfix (exact text)" "$OUT" "INFO  tag $HASH is not a release tag name; skipped"
assert_contains "R1-1 INFO line for v0.5.0-rc1 (exact text)" "$OUT" "INFO  tag v0.5.0-rc1 is not a release tag name; skipped"
assert_contains "R1-1 INFO line for v0.4.0-rc1 (exact text)" "$OUT" "INFO  tag v0.4.0-rc1 is not a release tag name; skipped"
assert_not_contains "R1-1 a hand tag is not reported as 'no GitHub Release'" "$OUT" "newer tag v0.5.0"
assert_not_contains "R1-1 the release tag itself gets no 'not a release tag name' line" "$OUT" "tag v0.4.0 is not a release tag name"
assert_eq "R1-1 the only request is the one for v0.4.0 (no name of a hand tag is sent)" \
  "-q -sS -o /dev/null -w %{http_code} $(U v0.4.0)" "$(cat "$PB_FAKE_CURL_LOG")"
urls_clean "R1-1 plain update"
assert_eq "R1-1 the installed block is v0.4.0" "BEGIN agent-playbook v0.4.0" "$(hdr "$TH/.claude/CLAUDE.md")"

base; rel $HANDMAP
run SEAM UPD --check
assert_rc "R1-1 --check with hand tags -> exit 0" 0
assert_contains "R1-1 --check: the update offered is v0.4.0" "$(line_with 'UPDATE AVAILABLE' 'v0.4.0')" "v0.4.0"
assert_not_contains "R1-1 --check never offers a hand tag" "$(line_with 'UPDATE AVAILABLE' 'v0.')" "hotfix"
assert_contains "R1-1 --check names the skipped v0.5.0#hotfix" "$OUT" "tag $HASH is not a release tag name; skipped"
assert_contains "R1-1 --check names the skipped v0.5.0-rc1" "$OUT" "tag v0.5.0-rc1 is not a release tag name; skipped"
assert_eq "R1-1 --check sends only the request for v0.4.0" "-q -sS -o /dev/null -w %{http_code} $(U v0.4.0)" "$(cat "$PB_FAKE_CURL_LOG")"
urls_clean "R1-1 --check"
assert_eq "R1-1 --check changes nothing" "$BASE" "$(git -C "$C" rev-parse HEAD)"
git -C "$C" -c advice.detachedHead=false checkout -q v0.4.0
run SEAM UPD --check
assert_rc "R1-1 --check at the newest released tag -> exit 0" 0
assert_contains "R1-1 --check at v0.4.0: up to date (not behind a hand tag)" "$OUT" "up to date"
assert_not_contains "R1-1 --check at v0.4.0: no UPDATE AVAILABLE" "$OUT" "UPDATE AVAILABLE"

for T in "$HASH" v0.5.0-rc1 v0.4.0-rc1; do
  base; rel $HANDMAP
  run SEAM UPD --to "$T" --yes
  assert_rc "R1-1 --to $T -> exit 1" 1
  assert_contains "R1-1 --to $T: exact refusal message" "$OUT" "release tag $T is not a release tag name (vMAJOR.MINOR.PATCH); nothing was changed $HINT"
  assert_eq "R1-1 --to $T: no request is sent for it" "" "$(cat "$PB_FAKE_CURL_LOG")"
  assert_not_contains "R1-1 --to $T: it is not reported as released" "$OUT" "GitHub Release found"
  unchanged "R1-1 --to $T: nothing changed"
done
base; rel $HANDMAP
run SEAM UPD --to "$HASH" --dry-run --yes
assert_rc "R1-1 --dry-run --to v0.5.0#hotfix -> exit 1 too" 1

base; rel $HANDMAP
run SEAM UPD --allow-unreleased --to "$HASH" --yes
assert_rc "R1-1 --allow-unreleased --to v0.5.0#hotfix -> exit 0 (the override still applies)" 0
head_is "R1-1 --allow-unreleased --to $HASH: the hand tag is checked out" "$HASH"
assert_eq "R1-1 --allow-unreleased: the check is skipped, no request is sent for it" "" "$(cat "$PB_FAKE_CURL_LOG")"
assert_contains "R1-1 --allow-unreleased: a WARN line names the tag" "$(line_with 'WARN:' 'GitHub Release')" "$HASH"
base; rel $HANDMAP
run SEAM UPD --allow-unreleased --yes
assert_rc "R1-1 plain update --allow-unreleased takes the newest v* tag, a hand tag here -> exit 0" 0
head_is "R1-1 plain --allow-unreleased: the newest v* tag (all hand tags share this commit)" v0.5.0-rc1
assert_eq "R1-1 plain --allow-unreleased: no request is sent for a name that is not a release name" "" "$(cat "$PB_FAKE_CURL_LOG")"
assert_contains "R1-1 plain --allow-unreleased: a WARN line" "$(line_with 'WARN:' 'GitHub Release')" "v0."

echo "AC6' usage text"
run bash "$C/install.sh" help
assert_rc "help exits 0" 0
assert_contains "AC6' usage example is 'rollback: --to v0.31.0'" "$OUT" "rollback: --to v0.31.0"
assert_not_contains "AC6' the old example v0.1.0 is gone" "$OUT" "rollback: --to v0.1.0"

t_summary
