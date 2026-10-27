#!/usr/bin/env bash
# Tests for scripts/learn.sh (project-local learnings file)
. "$(dirname "$0")/lib.sh"
LEARN="$PB_ROOT/scripts/learn.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
export PLAYBOOK_DATE="2026-10-09"

R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
F=".agents/LEARNINGS.md"

echo "init"
run bash "$LEARN" init
assert_rc "init ok" 0
assert_file "LEARNINGS.md created" "$F"
assert_contains ".gitignore ignores handoff" "$(cat .gitignore)" ".agents/handoff/"
run bash "$LEARN" init
assert_rc "init is idempotent" 0
assert_eq "gitignore entry not duplicated" "1" "$(grep -c '^\.agents/handoff/$' .gitignore)"
run bash "$LEARN" init --link-agents
assert_file "AGENTS.md created by --link-agents" "AGENTS.md"
assert_contains "AGENTS.md points to learnings" "$(cat AGENTS.md)" ".agents/LEARNINGS.md"
run bash "$LEARN" init --link-agents
assert_eq "pointer not duplicated" "1" "$(grep -c 'agent-playbook:learnings' AGENTS.md)"

echo "add"
run bash "$LEARN" add --title "Run lint before test" --rule "Always run pnpm lint before pnpm test." \
  --why "CI fails on lint first." --evidence "CI run 123 failed at lint step" --source failure
assert_rc "add ok" 0
assert_contains "first id" "$(cat $F)" "### L-0001 · 2026-10-09 · Run lint before test"
assert_contains "status active" "$(cat $F)" "- Status: active"
run bash "$LEARN" add --title "Use UTC" --rule "Store timestamps in UTC." \
  --why "User correction." --evidence "User said: 'always UTC' in chat" --source user --scope "src/db/**"
assert_contains "second id increments" "$(cat $F)" "### L-0002"
assert_contains "scope recorded" "$(cat $F)" "- Scope: src/db/**"

run bash "$LEARN" add --title "dup" --rule "always run pnpm lint before pnpm test." \
  --why w --evidence e --source user
assert_rc "duplicate rule (case-insensitive) rejected" 4
run bash "$LEARN" add --title "no evidence" --rule "Something new." --why w --source user
assert_rc "missing evidence rejected" 2
run bash "$LEARN" add --title t --rule r --why w --evidence e --source web
assert_rc "invalid source rejected (web content is not a valid source)" 2
run bash "$LEARN" add --title t --rule "Use token sk-abcdef1234567890abcdef" --why w --evidence e --source user
assert_rc "secret-looking content rejected" 2
LONG="$(printf 'x%.0s' $(seq 1 400))"
run bash "$LEARN" add --title t --rule "$LONG" --why w --evidence e --source user
assert_rc "over-long rule rejected" 2

echo "cap"
export LEARN_MAX_ENTRIES=2
run bash "$LEARN" add --title third --rule "A third distinct rule." --why w --evidence e --source user
assert_rc "cap reached: add rejected" 5
assert_contains "message tells how to proceed" "$OUT" "retire"

echo "retire + check"
run bash "$LEARN" retire L-0001 --reason "superseded"
assert_rc "retire ok" 0
assert_contains "retired status written" "$(cat $F)" "- Status: retired"
run bash "$LEARN" add --title third --rule "A third distinct rule." --why w --evidence e --source user
assert_rc "after retire there is room again" 0
unset LEARN_MAX_ENTRIES
run bash "$LEARN" retire L-9999 --reason x
assert_rc "retire unknown id fails" 2
run bash "$LEARN" check
assert_rc "check passes on a valid file" 0
assert_contains "check summarises counts" "$OUT" "active"
printf '### garbage entry\n' >> "$F"
run bash "$LEARN" check
assert_rc "check fails on malformed entry" 1

# ---- v0.22.4 AC5: --role and checklist (a fresh repo; the cases above stay as they are) ----
echo "v0.22.4 AC5.1 add --role"
R2="$(mk_tmp)"; mk_repo "$R2"; cd "$R2" || exit 3
bash "$LEARN" init >/dev/null
add() { run bash "$LEARN" add --why w --evidence e --source user "$@"; }
add --title "Tester rule" --rule "Name each test after its AC." --scope "src/**" --role tester
assert_rc "AC5.1 add --role tester ok" 0
add --title "All rule" --rule "Keep commits small."
assert_rc "AC5.1 add without --role ok (default all)" 0
add --title "Reviewer rule" --rule "Run the mutation script on the diff." --role reviewer
assert_rc "AC5.1 add --role reviewer ok" 0
add --title "Impl rule" --rule "Run lint before the tests." --role implementer
assert_rc "AC5.1 add --role implementer ok" 0
add --title "Explicit all" --rule "Write the why in every commit." --role all
assert_rc "AC5.1 add --role all ok" 0
AFTER_SCOPE="$(awk '/^### L-0001 /{f=1} f && /^- Scope: /{getline nxt; print nxt; exit}' "$F")"
assert_eq "AC5.1 '- Role: tester' is written right after '- Scope:'" "- Role: tester" "$AFTER_SCOPE"
add --title "Bad role" --rule "A rule with a bad role." --role janitor
assert_rc "AC5.1 an unknown --role is rejected (exit 2)" 2
add --title "Bad role case" --rule "Another bad role rule." --role Tester
assert_rc "AC5.1 --role is case-sensitive (Tester rejected)" 2
assert_eq "AC5.1 a rejected --role adds nothing" "0" "$(grep -c 'A rule with a bad role\|Another bad role rule' "$F")"
run bash "$LEARN" check
assert_rc "AC5.2 check passes with Role lines" 0

echo "v0.22.4 AC5.1 entries without a Role line count as all"
# a hand-written entry of the old format (no Role line)
printf '\n### L-0006 · 2026-10-09 · Legacy\n- Status: active\n- Rule: Legacy rule without a role.\n- Why: old\n- Evidence: old\n- Source: user\n- Scope: project-wide\n' >> "$F"
run bash "$LEARN" check
assert_rc "AC5.2 a missing Role is fine (check passes)" 0
run bash "$LEARN" checklist implementer
assert_rc "AC5.3 checklist implementer exits 0" 0
assert_eq "AC5.1 a legacy entry without Role is in the implementer checklist" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- '- [ ] Legacy rule without a role. (L-0006, scope: project-wide)')"

echo "v0.22.4 AC5.3 checklist ROLE: the role's entries and all"
TESTER_L='- [ ] Name each test after its AC. (L-0001, scope: src/**)'
ALL_L='- [ ] Keep commits small. (L-0002, scope: project-wide)'
REV_L='- [ ] Run the mutation script on the diff. (L-0003, scope: project-wide)'
IMPL_L='- [ ] Run lint before the tests. (L-0004, scope: project-wide)'
ALL2_L='- [ ] Write the why in every commit. (L-0005, scope: project-wide)'
LEG_L='- [ ] Legacy rule without a role. (L-0006, scope: project-wide)'
n_items() { printf '%s\n' "$OUT" | grep -c '^- \[ \] '; }
inout() { # NAME LINE WANT(1|0)
  local got; got="$(printf '%s\n' "$OUT" | grep -cxF -- "$2")"
  if [ "$got" = "$3" ]; then t_ok "$1"; else t_bad "$1" "line [$2] count $got, want $3; output: $OUT"; fi
}
run bash "$LEARN" checklist tester
assert_rc "AC5.3 checklist tester exits 0" 0
inout "AC5.3 tester: the tester entry, as '- [ ] <rule> (L-000N, scope: <scope>)'" "$TESTER_L" 1
inout "AC5.3 tester: an entry for all (default)" "$ALL_L" 1
inout "AC5.3 tester: an entry with --role all" "$ALL2_L" 1
inout "AC5.3 tester: the legacy entry" "$LEG_L" 1
inout "AC5.3 tester: not the reviewer entry" "$REV_L" 0
inout "AC5.3 tester: not the implementer entry" "$IMPL_L" 0
assert_eq "AC5.3 tester: exactly four checklist items" "4" "$(n_items)"
run bash "$LEARN" checklist reviewer
inout "AC5.3 reviewer: the reviewer entry" "$REV_L" 1
inout "AC5.3 reviewer: an entry for all" "$ALL_L" 1
inout "AC5.3 reviewer: not the tester entry" "$TESTER_L" 0
assert_eq "AC5.3 reviewer: exactly four checklist items (reviewer, all, all, legacy)" "4" "$(n_items)"
run bash "$LEARN" checklist implementer
inout "AC5.3 implementer: the implementer entry" "$IMPL_L" 1
inout "AC5.3 implementer: not the reviewer entry" "$REV_L" 0
assert_eq "AC5.3 implementer: exactly four checklist items" "4" "$(n_items)"
FILE_BEFORE="$(cksum "$F")"
run bash "$LEARN" checklist tester
assert_eq "AC5.3 checklist is read-only (the file is unchanged)" "$FILE_BEFORE" "$(cksum "$F")"

echo "v0.22.4 AC5.1 retire still works with Role lines; retired entries are never listed"
run bash "$LEARN" retire L-0001 --reason "superseded"
assert_rc "AC5.1 retire an entry that has a Role line" 0
assert_contains "AC5.1 retire writes the retired status" "$(cat "$F")" "- Status: retired (superseded"
assert_eq "AC5.1 retire keeps the Role line of the entry" "1" "$(awk '/^### L-0001 /{f=1;next} /^### /{f=0} f && /^- Role: tester$/{n++} END{print n+0}' "$F")"
assert_eq "AC5.1 retire does not touch other entries (L-0003 still active)" "1" "$(awk '/^### L-0003 /{f=1;next} /^### /{f=0} f && /^- Status: active$/{n++} END{print n+0}' "$F")"
run bash "$LEARN" check
assert_rc "AC5.2 check passes after retiring" 0
run bash "$LEARN" checklist tester
inout "AC5.3 a retired tester entry is no longer listed" "$TESTER_L" 0
assert_eq "AC5.3 tester: three items left" "3" "$(n_items)"

echo "v0.22.4 AC5.2 check flags an unknown Role value"
cp "$F" "$F.keep"
sed 's/^- Role: reviewer$/- Role: janitor/' "$F.keep" > "$F"
run bash "$LEARN" check
assert_rc "AC5.2 an unknown Role value fails check (exit 1)" 1
assert_contains "AC5.2 the problem names Role" "$OUT" "Role"
cp "$F.keep" "$F"; rm -f "$F.keep"
run bash "$LEARN" check
assert_rc "AC5.2 the file is valid again after the fix" 0

echo "v0.22.4 AC5.2 the Role line counts toward the line budget"
LINES="$(wc -l < "$F" | tr -d ' ')"
LEARN_MAX_LINES="$LINES" run bash "$LEARN" check
assert_rc "AC5.2 at the budget: check passes" 0
LEARN_MAX_LINES="$((LINES - 1))" run bash "$LEARN" check
assert_rc "AC5.2 one line over the budget: check fails" 1
R3="$(mk_tmp)"; mk_repo "$R3"; ( cd "$R3" && bash "$LEARN" init >/dev/null && bash "$LEARN" add --title a --rule "Rule one." --why w --evidence e --source user >/dev/null )
L_NOROLE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
( cd "$R3" && bash "$LEARN" add --title b --rule "Rule two." --why w --evidence e --source user --role tester >/dev/null )
L_ROLE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
( cd "$R3" && bash "$LEARN" add --title c --rule "Rule three." --why w --evidence e --source user >/dev/null )
L_THREE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
if [ "$((L_ROLE - L_NOROLE))" -ge "$((L_THREE - L_ROLE))" ]; then t_ok "AC5.2 an entry written with --role is not shorter than one without"; else t_bad "AC5.2 an entry written with --role is not shorter than one without" "deltas: role $((L_ROLE - L_NOROLE)), no role $((L_THREE - L_ROLE))"; fi

echo "v0.22.4 AC5.3 checklist: nothing to list, and usage"
R4="$(mk_tmp)"; mk_repo "$R4"; cd "$R4" || exit 3
bash "$LEARN" init >/dev/null
run bash "$LEARN" checklist tester
assert_rc "AC5.3 no entries at all: exit 0" 0
assert_contains "AC5.3 no entries: 'no learnings for tester'" "$OUT" "no learnings for tester"
bash "$LEARN" add --title r --rule "Only for the reviewer." --why w --evidence e --source user --role reviewer >/dev/null
run bash "$LEARN" checklist tester
assert_contains "AC5.3 entries only for other roles: 'no learnings for tester'" "$OUT" "no learnings for tester"
assert_eq "AC5.3 ... and no checklist item" "0" "$(n_items)"
bash "$LEARN" retire L-0001 --reason gone >/dev/null
run bash "$LEARN" checklist reviewer
assert_contains "AC5.3 only a retired entry: 'no learnings for reviewer'" "$OUT" "no learnings for reviewer"
run bash "$LEARN" checklist janitor
assert_rc "AC5.3 an invalid ROLE exits 2" 2
run bash "$LEARN" checklist
assert_rc "AC5.3 a missing ROLE exits 2" 2
run bash "$LEARN" checklist Tester
assert_rc "AC5.3 ROLE is case-sensitive (Tester exits 2)" 2
# ---- v0.29.0 lane w, slice T: learn.sh trust | untrust | trusted (AC-T1, AC-T4, AC-T5) ----
# The cases above are untouched. Every case below starts from a fresh PLAYBOOK_HOME (the trust file lives in it).
fresh_home() { PLAYBOOK_HOME="$(mk_tmp)"; export PLAYBOOK_HOME; TF="$PLAYBOOK_HOME/.agents/trusted-projects"; }
# ents -> the entries of the trust file, comments and blank lines left out
ents() { grep -v '^[[:space:]]*#' "$TF" 2>/dev/null | grep -v '^[[:space:]]*$'; return 0; }
n_ents() { ents | wc -l | tr -d ' '; }
write_tf() { mkdir -p "$PLAYBOOK_HOME/.agents"; printf '%s\n' "$@" > "$TF"; }
TRD="$(mk_tmp)"; TR="$TRD/trproj"; mkdir -p "$TR"; mk_repo "$TR"
TR2="${TR}2"; mkdir -p "$TR2"
CTR="$(cd "$TR" && pwd -P)"; CTR2="$(cd "$TR2" && pwd -P)"
EXPF="$CTR"; if command -v cygpath >/dev/null 2>&1; then EXPF="$(cygpath -m "$CTR")"; fi   # Git Bash stores the cygpath -m form
spell() { # NAME ARG: 'trust ARG' adds nothing (3 assertions)
  run bash "$LEARN" trust "$2"
  assert_rc "$1: exit 0" 0
  assert_contains "$1: says already trusted" "$OUT" "already trusted"
  assert_eq "$1: still one entry" "1" "$(n_ents)"
}

echo "T trust: the project root, canonical and absolute (AC-T5)"
fresh_home; cd "$TR" || exit 3
run bash "$LEARN" trust
assert_rc "T AC-T5 trust without DIR exits 0" 0
assert_file "T AC-T1 the trust file is created at PLAYBOOK_HOME/.agents/trusted-projects" "$TF"
assert_eq "T AC-T5 trust without DIR stores the project root (canonical, absolute)" "$EXPF" "$(ents)"
assert_no_path "T AC-T1 nothing is written into the project" "$TR/.agents"
assert_eq "T AC-T1 the project tree stays clean" "" "$(git -C "$TR" status --porcelain)"
run bash "$LEARN" trust
assert_rc "T AC-T5 a second trust of the same project exits 0" 0
assert_contains "T AC-T5 a second trust says already trusted" "$OUT" "already trusted"
assert_eq "T AC-T5 a second trust adds nothing" "1" "$(n_ents)"

echo "T trust: idempotent across spellings (AC-T4, AC-T5)"
cd "$TRD" || exit 3
spell "T AC-T5 relative DIR" "trproj"
spell "T AC-T5 ./DIR/ with a trailing slash" "./trproj/"
spell "T AC-T5 absolute DIR with a trailing slash" "$TR/"
spell "T AC-T5 absolute DIR with .. segments" "$TR/src/.."
spell "T AC-T5 relative DIR with .. segments" "trproj/src/.."
ln -s "$TR" "$TRD/trlink" 2>/dev/null
if [ -L "$TRD/trlink" ]; then
  spell "T AC-T4 absolute symlink to the project" "$TRD/trlink"
  spell "T AC-T4 relative symlink to the project" "trlink"
else
  t_skip 6 "ln -s made no symlink here (Windows copy): symlink rows not testable"
fi
assert_eq "T AC-T5 after every spelling the one entry is still the canonical path" "$EXPF" "$(ents)"

echo "T trust: a relative DIR and the default root are stored absolute (AC-T5)"
fresh_home; cd "$TRD" || exit 3
run bash "$LEARN" trust trproj
assert_rc "T AC-T5 relative DIR: exit 0" 0
assert_eq "T AC-T5 relative DIR is stored as the absolute canonical path" "$EXPF" "$(ents)"
fresh_home; cd "$TR/src" || exit 3
run bash "$LEARN" trust ../
assert_eq "T AC-T5 DIR ../ from a subdirectory is stored as the project root" "$EXPF" "$(ents)"
fresh_home; cd "$TR/src" || exit 3
run bash "$LEARN" trust
assert_rc "T AC-T5 no DIR from a subdirectory: exit 0" 0
assert_eq "T AC-T5 no DIR from a subdirectory stores the project root, not the subdirectory" "$EXPF" "$(ents)"

echo "T trust: a missing DIR is exit 2 and adds nothing (AC-T5)"
fresh_home; cd "$TR" || exit 3
run bash "$LEARN" trust "$TRD/does-not-exist"
assert_rc "T AC-T5 missing DIR exits 2" 2
assert_eq "T AC-T5 missing DIR adds nothing" "0" "$(n_ents)"
if [ -n "$OUT" ]; then t_ok "T AC-T5 missing DIR says why"; else t_bad "T AC-T5 missing DIR says why" "no output"; fi

echo "T trust: an existing file keeps its comments and entries (AC-T1, AC-T5)"
fresh_home; mkdir -p "$PLAYBOOK_HOME/.agents"; printf '# keep me\n/some/other/project' > "$TF"   # no final newline
cd "$TR" || exit 3
run bash "$LEARN" trust
assert_rc "T AC-T5 trust into an existing file: exit 0" 0
assert_eq "T AC-T5 the file now holds two entries" "2" "$(n_ents)"
assert_eq "T AC-T1 the comment line is kept" "1" "$(grep -c '^# keep me$' "$TF")"
assert_eq "T AC-T5 the other entry is kept on its own line" "1" "$(grep -cxF '/some/other/project' "$TF")"
assert_eq "T AC-T5 the project is on its own line" "1" "$(grep -cxF -- "$EXPF" "$TF")"

echo "T trusted: lists the entries (AC-T5)"
run bash "$LEARN" trusted
assert_rc "T AC-T5 trusted exits 0" 0
assert_contains "T AC-T5 trusted lists the project" "$OUT" "$EXPF"
assert_contains "T AC-T5 trusted lists the other entry" "$OUT" "/some/other/project"
fresh_home
run bash "$LEARN" trusted
assert_rc "T AC-T5 trusted with no trust file exits 0" 0
if printf '%s' "$OUT" | grep -qi 'no trusted projects'; then t_ok "T AC-T5 trusted with no trust file says 'no trusted projects'"; else t_bad "T AC-T5 trusted with no trust file says 'no trusted projects'" "got [$OUT]"; fi
write_tf "# only a comment" ""
run bash "$LEARN" trusted
assert_rc "T AC-T5 trusted with only comments exits 0" 0
if printf '%s' "$OUT" | grep -qi 'no trusted projects'; then t_ok "T AC-T5 trusted with only comments says 'no trusted projects'"; else t_bad "T AC-T5 trusted with only comments says 'no trusted projects'" "got [$OUT]"; fi

echo "T untrust: removes every line that matches, any spelling (AC-T5)"
fresh_home; write_tf "# keep" "$CTR" "/some/other/project" "$CTR/"   # the same project twice, in two spellings
cd "$TRD" || exit 3
run bash "$LEARN" untrust trproj
assert_rc "T AC-T5 untrust exits 0" 0
if printf '%s' "$OUT" | grep -Eiq 'remov|untrust'; then t_ok "T AC-T5 untrust says what it did"; else t_bad "T AC-T5 untrust says what it did" "got [$OUT]"; fi
assert_eq "T AC-T5 untrust removes both spellings and keeps the other entry" "/some/other/project" "$(ents)"
assert_eq "T AC-T5 untrust keeps the comment" "1" "$(grep -c '^# keep$' "$TF")"
if [ -L "$TRD/trlink" ]; then
  fresh_home; write_tf "$TRD/trlink" "/some/other/project"
  run bash "$LEARN" untrust "$TR"
  assert_eq "T AC-T4 untrust removes a line that is a symlink to the project" "/some/other/project" "$(ents)"
else
  t_skip 1 "ln -s made no symlink here (Windows copy): symlink row not testable"
fi
fresh_home; write_tf "$CTR" "$CTR2"
run bash "$LEARN" untrust "$TR"
assert_eq "T AC-T5 untrust does not remove a project whose name extends the given one" "$CTR2" "$(ents)"
before="$(cksum < "$TF")"
run bash "$LEARN" untrust "$TRD"
assert_rc "T AC-T5 untrust of a parent directory exits 0" 0
assert_eq "T AC-T5 untrust of a parent directory removes no child" "$before" "$(cksum < "$TF")"
run bash "$LEARN" untrust "$TR"
assert_rc "T AC-T5 untrust of a project that is not listed exits 0" 0
if [ -n "$OUT" ]; then t_ok "T AC-T5 untrust of a project that is not listed says so"; else t_bad "T AC-T5 untrust of a project that is not listed says so" "no output"; fi
assert_eq "T AC-T5 that leaves the file unchanged" "$before" "$(cksum < "$TF")"
fresh_home
run bash "$LEARN" untrust "$TR"
assert_rc "T AC-T5 untrust with no trust file exits 0" 0
fresh_home; write_tf "$CTR" "/some/other/project"; cd "$TR/src" || exit 3
run bash "$LEARN" untrust
assert_rc "T AC-T5 untrust without DIR exits 0" 0
assert_eq "T AC-T5 untrust without DIR removes the project root" "/some/other/project" "$(ents)"

echo "T usage names the new commands (AC-T5)"
run bash "$LEARN" frobnicate
assert_rc "T AC-T5 an unknown command exits 2" 2
assert_contains "T AC-T5 the usage line names untrust" "$OUT" "untrust"
assert_contains "T AC-T5 the usage line names trusted" "$OUT" "trusted"

# mk_cygpath_stub DIR: writes DIR/cygpath, a fake cygpath (v0.29.0 slice T): drive C: holds the temp dir; see the stub header
mk_cygpath_stub() {
  cat > "$1/cygpath" <<'PB_STUB'
#!/usr/bin/env bash
# Stub cygpath for the tests (Git Bash has the real one). The drive C: holds the temp dir: a POSIX path under the temp base
# maps to C:/Users/Tester/AppData/Local/Temp/..., and the C:\..., C:/..., c:/... and /c/... spellings map back to it.
# Supports -m, -u, -w (-a and other flags are ignored). Env: PB_STUB_REAL (canonical temp base), PB_STUB_RAW (temp base as given).
mode=u
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -m | -am | -ma) mode=m ;;
    -w | -aw | -wa) mode=w ;;
    -u | -au | -ua) mode=u ;;
    -*) ;;
    *) break ;;
  esac
  shift
done
PFX='/Users/Tester/AppData/Local/Temp'
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }
fwd() { printf '%s' "$1" | tr '\\' '/'; }
to_unix() {
  local p rest low letter
  p="$(fwd "$1")"
  case "$p" in
    [A-Za-z]:*) rest="${p#?:}"; letter="${p%%:*}" ;;
    /[A-Za-z] | /[A-Za-z]/*) rest="${p#/?}"; letter="${p#/}"; letter="${letter%%/*}" ;;
    *) printf '%s\n' "$p"; return ;;
  esac
  low="$(lower "$rest")"
  case "$low" in
    "$(lower "$PFX")" | "$(lower "$PFX")"/*) printf '%s%s\n' "$PB_STUB_REAL" "${rest:${#PFX}}" ;;
    *) printf '/%s%s\n' "$(lower "$letter")" "$rest" ;;
  esac
}
to_m() {
  local p b l
  p="$(fwd "$1")"
  case "$p" in
    [A-Za-z]:*) printf '%s\n' "$p"; return ;;
    /[A-Za-z]) printf '%s:/\n' "$(upper "${p#/}")"; return ;;
    /[A-Za-z]/*) l="${p#/}"; printf '%s:%s\n' "$(upper "${l%%/*}")" "${p#/?}"; return ;;
  esac
  for b in "$PB_STUB_REAL" "$PB_STUB_RAW"; do
    [ -n "$b" ] || continue
    case "$p" in
      "$b") printf 'C:%s\n' "$PFX"; return ;;
      "$b"/*) printf 'C:%s%s\n' "$PFX" "${p#"$b"}"; return ;;
    esac
  done
  printf 'C:/stubroot%s\n' "$p"
}
for a in "$@"; do
  case "$mode" in
    u) to_unix "$a" ;;
    m) to_m "$a" ;;
    w) to_m "$a" | tr '/' '\\' ;;
  esac
done
exit 0
PB_STUB
  chmod +x "$1/cygpath"
}

echo "T trust stores the cygpath -m form when cygpath exists (AC-T5, AC-T4; stub cygpath on PATH)"
STUBD="$(mk_tmp)"; mk_cygpath_stub "$STUBD"
export PB_STUB_REAL="$(cd "$PB_TMPBASE" && pwd -P)" PB_STUB_RAW="$PB_TMPBASE"
WCTR="C:/Users/Tester/AppData/Local/Temp${CTR#"$PB_STUB_REAL"}"
if [ "$(PATH="$STUBD:$PATH" cygpath -m "$CTR" 2>/dev/null)" = "$WCTR" ]; then
  fresh_home; cd "$TR" || exit 3
  PATH="$STUBD:$PATH" run bash "$LEARN" trust
  assert_rc "T AC-T5 stub cygpath: trust exits 0" 0
  assert_eq "T AC-T5 stub cygpath: the stored line is the cygpath -m form" "$WCTR" "$(ents)"
  PATH="$STUBD:$PATH" spell "T AC-T5 stub cygpath: a second trust (POSIX spelling, trailing slash)" "$TR/"
  PATH="$STUBD:$PATH" run bash "$LEARN" trusted
  assert_contains "T AC-T5 stub cygpath: trusted lists the cygpath -m line" "$OUT" "$WCTR"
  fresh_home; write_tf "$CTR"
  PATH="$STUBD:$PATH" run bash "$LEARN" trust
  assert_contains "T AC-T4 stub cygpath: a hand-written POSIX line is the same project" "$OUT" "already trusted"
  assert_eq "T AC-T4 stub cygpath: that adds no second line" "1" "$(n_ents)"
  fresh_home; write_tf "$WCTR" "/some/other/project"
  PATH="$STUBD:$PATH" run bash "$LEARN" untrust "$TR"
  assert_eq "T AC-T4 stub cygpath: untrust (POSIX spelling) removes the cygpath -m line" "/some/other/project" "$(ents)"
else
  t_skip 9 "the stub cygpath is not runnable here: Windows form rows not testable"
fi
unset PB_STUB_REAL PB_STUB_RAW


# ---- review round 1 fix (05-review.md finding 4): trust and untrust are case-sensitive for POSIX paths without cygpath ----
echo "T trust: two directories that differ only by case are two projects on a case-sensitive file system without cygpath (F4)"
CSD="$(mk_tmp)"; mkdir -p "$CSD/CaseProj-7c2" "$CSD/caseproj-7c2" 2>/dev/null
# probe (L-0004): case-insensitive file system or a cygpath on PATH (Git Bash folds case by design): t_skip with the same count (9)
if [ "$(ls "$CSD" | wc -l | tr -d ' ')" = 2 ] && ! command -v cygpath > /dev/null 2>&1; then
  CU="$(cd "$CSD/CaseProj-7c2" && pwd -P)"; CL="$(cd "$CSD/caseproj-7c2" && pwd -P)"
  fresh_home; cd "$CSD" || exit 3
  run bash "$LEARN" trust "$CU"
  assert_rc "T F4 trust CaseProj-7c2: exit 0" 0
  run bash "$LEARN" trust "$CL"
  assert_not_contains "T F4 trusting caseproj-7c2 after CaseProj-7c2 is not 'already trusted'" "$OUT" "already trusted"
  assert_eq "T F4 both case spellings are stored as two entries" "2" "$(n_ents)"
  run bash "$LEARN" untrust "$CL"
  assert_rc "T F4 untrust caseproj-7c2: exit 0" 0
  assert_eq "T F4 untrust caseproj-7c2 removes only that entry and keeps CaseProj-7c2" "$CU" "$(ents)"
  fresh_home; cd "$CSD" || exit 3
  run bash "$LEARN" trust "$CU"
  run bash "$LEARN" untrust "$CL"
  assert_rc "T F4 untrust of the other-case dir when only CaseProj-7c2 is listed: exit 0" 0
  assert_eq "T F4 that untrust removes nothing (the entry stays)" "$CU" "$(ents)"
  run bash "$LEARN" untrust "$CU"
  assert_eq "T F4 untrust CaseProj-7c2 removes it" "0" "$(n_ents)"
  fresh_home; cd "$CSD" || exit 3
  write_tf "$CL"
  run bash "$LEARN" untrust "$CU"
  assert_eq "T F4 untrust CaseProj-7c2 does not remove a hand-written caseproj-7c2 line" "$CL" "$(ents)"
else
  t_skip 9 "case-sensitive file system without cygpath not available here: case rows not testable"
fi

t_summary
