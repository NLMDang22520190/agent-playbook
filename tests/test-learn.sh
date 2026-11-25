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

# ---- v0.38 Q9 S1: budget warning and entry-line counts in `learn.sh check` (AC1-AC6) ----
echo "Q9 S1 AC1: entry lines in the summary line (counts measured on the fixture file)"
S1R="$(mk_tmp)"; mk_repo "$S1R"; cd "$S1R" || exit 3
bash "$LEARN" init >/dev/null
s1add() { bash "$LEARN" add --why w --evidence "${S1EV:-e}" --source user "$@" >/dev/null; }
s1add --title "S1 one" --rule "S1 rule number one."
s1add --title "S1 two" --rule "S1 rule number two."
s1add --title "S1 three" --rule "S1 rule number three."
# independent count: lines from a '### ' heading to the line before the next heading (or EOF); first Status line decides
s1count() { # FILE -> "A R"
  awk '
    function flush() { if (inent) { if (st == "retired") r += n; else a += n } }
    /^### / { flush(); inent = 1; n = 0; st = "" }
    { if (inent) { n++; if (st == "" && $0 ~ /^- Status: /) st = ($0 ~ /^- Status: retired/) ? "retired" : "active" } }
    END { flush(); printf "%d %d\n", a, r }' "$1"
}
run bash "$LEARN" retire L-0003 --reason "s1"
S1C="$(s1count "$F")"
assert_eq "Q9 S1 AC1 fixture sanity: independent count is 18 active, 8 retired lines" "18 8" "$S1C"
run bash "$LEARN" check
assert_rc "Q9 S1 AC1 check exit 0" 0
assert_contains "Q9 S1 AC1 old prefix of the summary line is kept" "$OUT" "learnings: 2 active, 1 retired, 38 lines (.agents/LEARNINGS.md)"
assert_eq "Q9 S1 AC1 summary line ends with '; entry lines: 18 active, 8 retired'" "1" "$(printf '%s\n' "$OUT" | grep -c '^learnings: 2 active, 1 retired, 38 lines (\.agents/LEARNINGS\.md); entry lines: 18 active, 8 retired$')"
# retire the middle entry instead
S1R2="$(mk_tmp)"; mk_repo "$S1R2"; cd "$S1R2" || exit 3
bash "$LEARN" init >/dev/null
s1add --title "S1 one" --rule "S1 rule number one."
s1add --title "S1 two" --rule "S1 rule number two."
s1add --title "S1 three" --rule "S1 rule number three."
run bash "$LEARN" retire L-0002 --reason "s1"
assert_eq "Q9 S1 AC1 fixture sanity: middle retired, independent count is 17 active, 9 retired" "17 9" "$(s1count "$F")"
run bash "$LEARN" check
assert_eq "Q9 S1 AC1 middle entry retired: '; entry lines: 17 active, 9 retired'" "1" "$(printf '%s\n' "$OUT" | grep -c '; entry lines: 17 active, 9 retired$')"
assert_contains "Q9 S1 AC1 middle retired: old prefix kept" "$OUT" "learnings: 2 active, 1 retired, 38 lines (.agents/LEARNINGS.md)"
# file without entries
S1R3="$(mk_tmp)"; mk_repo "$S1R3"; cd "$S1R3" || exit 3
bash "$LEARN" init >/dev/null
run bash "$LEARN" check
assert_rc "Q9 S1 AC1 empty file: check exit 0" 0
assert_eq "Q9 S1 AC1 file without entries: '; entry lines: 0 active, 0 retired'" "1" "$(printf '%s\n' "$OUT" | grep -c '^learnings: 0 active, 0 retired, [0-9]* lines (\.agents/LEARNINGS\.md); entry lines: 0 active, 0 retired$')"
run bash "$LEARN" checklist tester
assert_not_contains "Q9 S1 AC6 checklist output does not carry the new summary" "$OUT" "entry lines"

echo "Q9 S1 AC3: no warning on a small file, and with only an old problem"
S1R4="$(mk_tmp)"; mk_repo "$S1R4"; cd "$S1R4" || exit 3
bash "$LEARN" init >/dev/null
s1add --title "S1 one" --rule "S1 rule number one."
s1add --title "S1 two" --rule "S1 rule number two."
run bash "$LEARN" check
assert_rc "Q9 S1 AC3 small file: exit 0" 0
assert_not_contains "Q9 S1 AC3 small file: no warning line" "$OUT" "warning:"
LEARN_MAX_LINES=5 run bash "$LEARN" check
assert_rc "Q9 S1 AC3 over the line budget: exit 1 as before" 1
assert_contains "Q9 S1 AC3 over the line budget: the old problem names the budget" "$OUT" "problem: "
assert_contains "Q9 S1 AC3 over the line budget: budget text" "$OUT" "exceeds the 5-line budget"
assert_not_contains "Q9 S1 AC3 over the line budget with no hook cut: no warning line" "$OUT" "warning:"

echo "Q9 S1 AC2: hook truncates, check warns (N = M - K from the real hook)"
S1R5="$(mk_tmp)"; mk_repo "$S1R5"; cd "$S1R5" || exit 3
bash "$LEARN" init >/dev/null
S1M=20
s1big() { S1EV="$(printf 'e%.0s' $(seq 1 400))"; for i in $(seq 1 $S1M); do s1add --title "S1 big $i" --rule "S1 big rule number $i."; done; S1EV=""; }
s1big
S1_LINES="$(wc -l < "$F" | tr -d ' ')"; S1_BYTES="$(wc -c < "$F" | tr -d ' ')"
S1_ACT="$(grep -c '^- Status: active' "$F")"
assert_eq "Q9 S1 AC2 fixture sanity: $S1M active entries" "$S1M" "$S1_ACT"
if [ "$S1_LINES" -lt 250 ]; then t_ok "Q9 S1 AC2 fixture sanity: $S1_LINES lines < 250"; else t_bad "Q9 S1 AC2 fixture sanity: lines < 250" "$S1_LINES"; fi
if [ "$S1_BYTES" -gt 8000 ]; then t_ok "Q9 S1 AC2 fixture sanity: $S1_BYTES bytes > 8000"; else t_bad "Q9 S1 AC2 fixture sanity: bytes > 8000" "$S1_BYTES"; fi
S1_HOUT="$(PB_EVAL_HOOK_LOG= CLAUDE_PROJECT_DIR="$S1R5" bash "$PB_ROOT/scripts/learnings-hook.sh" --eval </dev/null 2>/dev/null)"
S1_K="$(printf '%s\n' "$S1_HOUT" | sed -n 's/^\[\([0-9][0-9]*\) more entries not shown: read .*\]$/\1/p' | tail -n 1)"
case "$S1_K" in
  ''|*[!0-9]*) t_bad "Q9 S1 AC2 fixture sanity: hook reports a K" "K=[$S1_K]"; S1_K=0 ;;
  *) if [ "$S1_K" -ge 1 ] && [ "$S1_K" -lt "$S1M" ]; then t_ok "Q9 S1 AC2 fixture sanity: hook cuts, K=$S1_K"; else t_bad "Q9 S1 AC2 fixture sanity: 1 <= K < M" "K=$S1_K"; fi ;;
esac
S1_N=$((S1M - S1_K))
S1_WARN="warning: $S1_N of $S1M active entries are injected by the hook (oldest first); the rest are shown only as a count"
run bash "$LEARN" check
assert_rc "Q9 S1 AC2 within both check budgets: exit 0" 0
assert_eq "Q9 S1 AC2 exactly one warning line with N = M - K" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- "$S1_WARN")"
assert_eq "Q9 S1 AC2 only one 'warning:' line in total" "1" "$(printf '%s\n' "$OUT" | grep -c '^warning:')"
assert_eq "Q9 S1 AC2 the warning is the last line (after the summary line)" "$S1_WARN" "$(printf '%s\n' "$OUT" | tail -n 1)"
assert_contains "Q9 S1 AC2 summary line carries entry lines" "$OUT" "; entry lines: "
# structural error (one entry loses its Why): problem first, then summary, then warning, exit 1
awk '$0 == "- Why: w" && !d { d = 1; next } { print }' "$F" > "$F.s1" && mv "$F.s1" "$F"
run bash "$LEARN" check
assert_rc "Q9 S1 AC2 with a structural problem: exit 1" 1
S1_P="$(printf '%s\n' "$OUT" | grep -n '^problem:' | head -n 1 | cut -d: -f1)"
S1_S="$(printf '%s\n' "$OUT" | grep -n '^learnings: ' | head -n 1 | cut -d: -f1)"
S1_W="$(printf '%s\n' "$OUT" | grep -n '^warning: ' | head -n 1 | cut -d: -f1)"
if [ -n "$S1_P" ] && [ -n "$S1_S" ] && [ -n "$S1_W" ] && [ "$S1_P" -lt "$S1_S" ] && [ "$S1_S" -lt "$S1_W" ]; then t_ok "Q9 S1 AC2 order: problem, summary, warning (lines $S1_P < $S1_S < $S1_W)"; else t_bad "Q9 S1 AC2 order: problem, summary, warning" "p=[$S1_P] s=[$S1_S] w=[$S1_W]; output: $OUT"; fi
assert_eq "Q9 S1 AC2 with a problem: exactly one warning line, N = M - K" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- "$S1_WARN")"

echo "Q9 S1 AC5: check never touches the eval hook log"
S1LOG="$(mk_tmp)/hook.log"
PB_EVAL_HOOK_LOG="$S1LOG" run bash "$LEARN" check
assert_no_path "Q9 S1 AC5 PB_EVAL_HOOK_LOG file is not created by check" "$S1LOG"
printf 'sentinel line\n' > "$S1LOG"
PB_EVAL_HOOK_LOG="$S1LOG" run bash "$LEARN" check
assert_eq "Q9 S1 AC5 an existing PB_EVAL_HOOK_LOG file is not modified by check" "sentinel line" "$(cat "$S1LOG")"

echo "Q9 S1 AC4: the hook is the only source of N (temp scripts dir with fake hooks)"
S1SD="$(mk_tmp)"; mkdir -p "$S1SD/scripts"; cp "$PB_ROOT/scripts/learn.sh" "$PB_ROOT/scripts/lib.sh" "$S1SD/scripts/"
S1L="$S1SD/scripts/learn.sh"
# Case A: no learnings-hook.sh next to learn.sh, on a fresh big fixture
S1R6="$(mk_tmp)"; mk_repo "$S1R6"; cd "$S1R6" || exit 3
bash "$LEARN" init >/dev/null
s1big
run bash "$LEARN" check; S1_RC0="$RC"
run bash "$S1L" check
assert_eq "Q9 S1 AC4 A: no hook script: exit code as before" "$S1_RC0" "$RC"
assert_not_contains "Q9 S1 AC4 A: no hook script: no warning" "$OUT" "warning:"
assert_not_contains "Q9 S1 AC4 A: no error text (No such file)" "$OUT" "No such file"
assert_not_contains "Q9 S1 AC4 A: no error text (not found)" "$OUT" "not found"
assert_not_contains "Q9 S1 AC4 A: no error text (rror)" "$OUT" "rror"
assert_contains "Q9 S1 AC4 A: summary line still printed" "$OUT" "learnings: $S1M active"
# Case B: hook prints garbage / exits 7
printf '#!/usr/bin/env bash\necho "garbage [99 more entries not shown"\necho "more garbage"\n' > "$S1SD/scripts/learnings-hook.sh"
run bash "$S1L" check
assert_eq "Q9 S1 AC4 B: garbage hook: exit code as before" "$S1_RC0" "$RC"
assert_not_contains "Q9 S1 AC4 B: garbage hook: no warning" "$OUT" "warning:"
printf '#!/usr/bin/env bash\necho "[3 more entries not shown: read X]"\necho "</project-learnings>"\nexit 7\n' > "$S1SD/scripts/learnings-hook.sh"
run bash "$S1L" check
assert_eq "Q9 S1 AC4 B: hook exits 7: exit code as before" "$S1_RC0" "$RC"
assert_not_contains "Q9 S1 AC4 B: hook exits 7: no warning, even with a valid-looking note" "$OUT" "warning:"
# Case C: fake hook says K=3 on a small 5-entry file that no byte math would flag
S1R7="$(mk_tmp)"; mk_repo "$S1R7"; cd "$S1R7" || exit 3
bash "$LEARN" init >/dev/null
for i in 1 2 3 4 5; do s1add --title "S1 small $i" --rule "S1 small rule number $i."; done
s1fake() { # NOTE-LINE: hook that prints the note line then the closing tag
  printf '#!/usr/bin/env bash\ncat <<"EOT"\n<project-learnings>\n%s\n</project-learnings>\nEOT\n' "$1" > "$S1SD/scripts/learnings-hook.sh"
}
s1fake "[3 more entries not shown: read X]"
run bash "$S1L" check
assert_rc "Q9 S1 AC4 C: fake hook K=3: exit 0" 0
assert_eq "Q9 S1 AC4 C: warning 2 of 5 comes from the hook's K, not from bytes" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- 'warning: 2 of 5 active entries are injected by the hook (oldest first); the rest are shown only as a count')"
s1fake "[5 more entries not shown: read X]"
run bash "$S1L" check
assert_eq "Q9 S1 AC4 C: K = M is valid (N = 0)" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- 'warning: 0 of 5 active entries are injected by the hook (oldest first); the rest are shown only as a count')"
run bash "$LEARN" check
assert_not_contains "Q9 S1 AC4 C: real hook, small file: no warning" "$OUT" "warning:"
# Case D: invalid K or misplaced note
s1fake "[0 more entries not shown: read X]"
run bash "$S1L" check
assert_not_contains "Q9 S1 AC4 D: K = 0: no warning" "$OUT" "warning:"
assert_rc "Q9 S1 AC4 D: K = 0: exit 0" 0
s1fake "[6 more entries not shown: read X]"
run bash "$S1L" check
assert_not_contains "Q9 S1 AC4 D: K > M: no warning" "$OUT" "warning:"
assert_rc "Q9 S1 AC4 D: K > M: exit 0" 0
printf '#!/usr/bin/env bash\ncat <<"EOT"\n<project-learnings>\n[3 more entries not shown: read X]\nsome later line\n</project-learnings>\nEOT\n' > "$S1SD/scripts/learnings-hook.sh"
run bash "$S1L" check
assert_not_contains "Q9 S1 AC4 D: note not directly before the closing tag: no warning" "$OUT" "warning:"
assert_rc "Q9 S1 AC4 D: misplaced note: exit 0" 0
printf '#!/usr/bin/env bash\ncat <<"EOT"\n<project-learnings>\n[2 more entries not shown: read X]\n[4 more entries not shown: read Y]\n</project-learnings>\nEOT\n' > "$S1SD/scripts/learnings-hook.sh"
run bash "$S1L" check
assert_eq "Q9 S1 AC4 D: the last note line before the tag wins (K=4, N=1)" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- 'warning: 1 of 5 active entries are injected by the hook (oldest first); the rest are shown only as a count')"
# ---- Q9 S1 review gaps: first Status line decides, spaced project root, hook stderr hygiene ----
echo "Q9 S1 AC1: a later '- Status: retired' line inside an active entry does not retire it"
S1R7="$(mk_tmp)"; mk_repo "$S1R7"; cd "$S1R7" || exit 3
bash "$LEARN" init >/dev/null
s1add --title "S1 g one" --rule "S1 gap rule number one."
s1add --title "S1 g two" --rule "S1 gap rule number two."
# hand edit: after the first entry's Scope line add a body line that starts like a Status line
awk '/^- Scope: / && !d { print; print "- Status: retired (quoted in the body, not the entry status)"; d = 1; next } { print }' "$F" > "$F.s1" && mv "$F.s1" "$F"
S1G="$(s1count "$F")"
S1GA="${S1G% *}"; S1GR="${S1G#* }"
assert_eq "Q9 S1 AC1 gap fixture sanity: first entry still starts with an active Status line" "active" "$(awk '/^### /{n++} n==1 && /^- Status: /{sub(/^- Status: /,""); print; exit}' "$F")"
assert_eq "Q9 S1 AC1 gap fixture sanity: the body holds a later retired line" "1" "$(grep -c '^- Status: retired' "$F")"
assert_eq "Q9 S1 AC1 gap fixture sanity: independent count has no retired lines" "0" "$S1GR"
run bash "$LEARN" check
assert_eq "Q9 S1 AC1 first Status line decides: '; entry lines: $S1GA active, 0 retired'" "1" "$(printf '%s\n' "$OUT" | grep -c "; entry lines: $S1GA active, 0 retired\$")"

echo "Q9 S1 AC2: project root with a space gives the same warning as the hook run by hand"
S1RS="$(mk_tmp)/proj with space"; mkdir -p "$S1RS"; mk_repo "$S1RS"; cd "$S1RS" || exit 3
bash "$LEARN" init >/dev/null
s1big
S1SH="$(PB_EVAL_HOOK_LOG= CLAUDE_PROJECT_DIR="$S1RS" bash "$PB_ROOT/scripts/learnings-hook.sh" --eval </dev/null 2>/dev/null)"
S1SK="$(printf '%s\n' "$S1SH" | sed -n 's/^\[\([0-9][0-9]*\) more entries not shown: read .*\]$/\1/p' | tail -n 1)"
case "$S1SK" in
  ''|*[!0-9]*) t_bad "Q9 S1 AC2 space root sanity: hook run by hand reports a K" "K=[$S1SK]"; S1SK=0 ;;
  *) t_ok "Q9 S1 AC2 space root sanity: hook run by hand cuts, K=$S1SK" ;;
esac
S1SW="warning: $((S1M - S1SK)) of $S1M active entries are injected by the hook (oldest first); the rest are shown only as a count"
run bash "$LEARN" check
assert_rc "Q9 S1 AC2 space root: exit 0" 0
assert_eq "Q9 S1 AC2 space root: same warning N = M - K as the hook by hand" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- "$S1SW")"

echo "Q9 S1 AC4: hook stderr does not leak into check output"
S1R8="$(mk_tmp)"; mk_repo "$S1R8"; cd "$S1R8" || exit 3
bash "$LEARN" init >/dev/null
for i in 1 2 3 4 5; do s1add --title "S1 e $i" --rule "S1 e rule number $i."; done
printf '#!/usr/bin/env bash\necho "STRAY-HOOK-STDERR-7731" >&2\ncat <<"EOT"\n<project-learnings>\n[3 more entries not shown: read X]\n</project-learnings>\nEOT\n' > "$S1SD/scripts/learnings-hook.sh"
run bash "$S1L" check
assert_rc "Q9 S1 AC4 stderr hook: exit 0" 0
assert_eq "Q9 S1 AC4 stderr hook: the warning still prints" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- 'warning: 2 of 5 active entries are injected by the hook (oldest first); the rest are shown only as a count')"
assert_not_contains "Q9 S1 AC4 stderr hook: no stray stderr text in the output" "$OUT" "STRAY-HOOK-STDERR-7731"
# ---- v0.38 Q9 S2: `learn.sh stale [--days N] [--fail]` (AC1-AC11); expected numbers counted by hand, see comments ----
SERRF="$(mk_tmp)/stale.err"
srun() { SOUT="$("$@" 2>"$SERRF")"; SRC=$?; SERR="$(cat "$SERRF")"; }   # SOUT stdout, SERR stderr, SRC exit code
SD="2026-11-17"
sst() { PLAYBOOK_DATE="$SD" srun bash "$LEARN" stale "$@"; }
sst_at() { local d="$1"; shift; PLAYBOOK_DATE="$d" srun bash "$LEARN" stale "$@"; }
st_fix() { # fresh git repo in SR (cwd), scripts/a.sh tracked, learnings file with a header and no entry
  SR="$(mk_tmp)"; mk_repo "$SR"; cd "$SR" || exit 3
  mkdir -p scripts .agents; printf '#!/bin/sh\n' > scripts/a.sh; git add scripts/a.sh
  printf '# Learnings\n' > "$F"
}
st_e() { # ID DATE TITLE SCOPE(@none: no Scope line) [STATUS] [EXTRA-LINE-AFTER-SCOPE]
  {
    printf '\n### %s · %s · %s\n' "$1" "$2" "$3"
    printf -- '- Status: %s\n' "${5:-active}"
    printf -- '- Rule: r\n- Why: w\n- Evidence: e\n- Source: user\n'
    if [ "$4" != "@none" ]; then printf -- '- Scope: %s\n' "$4"; fi
    if [ -n "${6:-}" ]; then printf -- '%s\n' "$6"; fi
  } >> "$F"
}
NOSCOPE="scope matches no tracked file"

echo "Q9 S2 AC1: age in days (320; threshold 180/181; leap years; year spans)"
st_fix
st_e L-0001 2026-01-01 "Old rule" project-wide
sst
assert_rc "Q9 S2 AC1 default run: exit 0" 0
assert_eq "Q9 S2 AC1 2026-01-01 to 2026-11-17 is 320 days; summary names the 180-day default" "$(printf 'L-0001 · 2026-01-01 · Old rule: 320 days old\nstale: 1 of 1 active entries listed (older than 180 days)')" "$SOUT"
assert_eq "Q9 S2 AC1 stderr is empty" "" "$SERR"
st_fix
st_e L-0001 2026-05-21 "Age 180" project-wide
st_e L-0002 2026-05-20 "Age 181" project-wide
sst
assert_eq "Q9 S2 AC1 exactly N days is not stale (180), N+1 is (181)" "$(printf 'L-0002 · 2026-05-20 · Age 181: 181 days old\nstale: 1 of 2 active entries listed (older than 180 days)')" "$SOUT"
st_fix
st_e L-0001 2024-02-28 "Leap" project-wide
sst_at 2024-03-01 --days 1
assert_eq "Q9 S2 AC1 2024-02-28 to 2024-03-01 is 2 days (29 Feb exists)" "$(printf 'L-0001 · 2024-02-28 · Leap: 2 days old\nstale: 1 of 1 active entries listed (older than 1 days)')" "$SOUT"
st_fix
st_e L-0001 2026-02-28 "No leap" project-wide
sst_at 2026-03-01 --days 1
assert_eq "Q9 S2 AC1 2026-02-28 to 2026-03-01 is 1 day: not older than 1" "stale: 0 of 1 active entries listed (older than 1 days)" "$SOUT"
st_fix
st_e L-0001 2000-02-28 "Y2000" project-wide
st_e L-0002 1900-02-28 "Y1900" project-wide
sst_at 2000-03-01 --days 1
assert_eq "Q9 S2 AC1 2000 is a leap year (2 days)" "$(printf 'L-0001 · 2000-02-28 · Y2000: 2 days old\nstale: 1 of 2 active entries listed (older than 1 days)')" "$SOUT"
sst_at 1900-03-01 --days 1
assert_eq "Q9 S2 AC1 1900 is not a leap year (1 day)" "$(printf 'L-0002 · 1900-02-28 · Y1900: 1 days old\nstale: 1 of 2 active entries listed (older than 1 days)')" "$SOUT"
st_fix
st_e L-0001 2026-01-01 "Year" project-wide
st_e L-0002 2024-01-01 "Leap year" project-wide
sst_at 2027-01-01 --days 364
assert_eq "Q9 S2 AC1 a plain year is 365 days, a leap year 366 (2024-01-01 to 2027-01-01 is 1096)" "$(printf 'L-0001 · 2026-01-01 · Year: 365 days old\nL-0002 · 2024-01-01 · Leap year: 1096 days old\nstale: 2 of 2 active entries listed (older than 364 days)')" "$SOUT"
st_fix
st_e L-0001 2026-01-01 "Mid · dot title" project-wide
sst
assert_eq "Q9 S2 AC1 a title with the separator is printed as written" "$(printf 'L-0001 · 2026-01-01 · Mid · dot title: 320 days old\nstale: 1 of 1 active entries listed (older than 180 days)')" "$SOUT"
st_fix
sst
assert_rc "Q9 S2 AC1 no entry: exit 0" 0
assert_eq "Q9 S2 AC1 no active entry: '0 of 0' summary only (repo: no skipped line)" "stale: 0 of 0 active entries listed (older than 180 days)" "$SOUT"
st_fix
st_e L-0001 2027-01-01 "Future" project-wide
sst
assert_eq "Q9 S2 AC1 a future date is not stale because of age" "stale: 0 of 1 active entries listed (older than 180 days)" "$SOUT"

echo "Q9 S2 AC2: scope check in a git repo"
st_fix
st_e L-0001 "$SD" "S nope" scripts/nope.sh
st_e L-0002 "$SD" "S glob" 'scripts/*.sh'
st_e L-0003 "$SD" "S dir" scripts/
st_e L-0004 "$SD" "S file" src/app.js
st_e L-0005 "$SD" "S star2" '**'
st_e L-0006 "$SD" "S readme" README.md
st_e L-0007 "$SD" "S docs" 'docs/**'
st_e L-0008 "$SD" "S dot" .
st_e L-0009 "$SD" "S star" '*'
st_e L-0010 2026-01-01 "Both" scripts/nope.sh
sst
assert_rc "Q9 S2 AC2 scope run: exit 0" 0
assert_eq "Q9 S2 AC2 only nope.sh, docs/** (nothing tracked there) and the old+nope entry; ** . * and real paths pass" "$(printf 'L-0001 · %s · S nope: %s\nL-0007 · %s · S docs: %s\nL-0010 · 2026-01-01 · Both: 320 days old; %s\nstale: 3 of 10 active entries listed (older than 180 days)' "$SD" "$NOSCOPE" "$SD" "$NOSCOPE" "$NOSCOPE")" "$SOUT"
assert_eq "Q9 S2 AC2 stderr is empty" "" "$SERR"
GIT_DIR=/nonexistent GIT_INDEX_FILE=/nonexistent GIT_WORK_TREE=/nonexistent sst
assert_eq "Q9 S2 AC2 GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE of the environment do not change the result" "3" "$(printf '%s\n' "$SOUT" | grep -c "$NOSCOPE")"
assert_not_contains "Q9 S2 AC2 ... and the repo is still recognised" "$SOUT" "scope check skipped"
ER="$(mk_tmp)"; ( cd "$ER" && git init -q ) ; mkdir -p "$ER/.agents"
cd "$ER" || exit 3
printf '# Learnings\n' > "$F"
st_e L-0001 "$SD" "Empty dot" .
st_e L-0002 "$SD" "Empty star2" '**'
sst
assert_eq "Q9 S2 AC2 a repo with no tracked file: . and ** match nothing and are listed" "$(printf 'L-0001 · %s · Empty dot: %s\nL-0002 · %s · Empty star2: %s\nstale: 2 of 2 active entries listed (older than 180 days)' "$SD" "$NOSCOPE" "$SD" "$NOSCOPE")" "$SOUT"

echo "Q9 S2 AC3: scopes that are never checked"
st_fix
st_e L-0001 "$SD" "t1" project-wide
st_e L-0002 "$SD" "t2" "the build scripts"
st_e L-0003 "$SD" "t3" "tests and docs"
st_e L-0004 "$SD" "t4" v1
st_e L-0005 "$SD" "t5" ../x
st_e L-0006 "$SD" "t6" /abs/x
st_e L-0007 "$SD" "t7" ':(top)x'
st_e L-0008 "$SD" "t8" C:x
st_e L-0009 "$SD" "t9" 'scripts\a.sh'
st_e L-0010 "$SD" "t10" @none
st_e L-0011 "$SD" "t11" ""
st_e L-0012 "$SD" "t12" @none "active" "- Scope:"
st_e L-0013 "$SD" "t13" "src/nope file.js"
sst
assert_rc "Q9 S2 AC3 exit 0" 0
assert_eq "Q9 S2 AC3 none of the 13 is flagged (the whole stdout is the summary)" "stale: 0 of 13 active entries listed (older than 180 days)" "$SOUT"
assert_eq "Q9 S2 AC3 no stderr (no git fatal leaks out)" "" "$SERR"

echo "Q9 S2 AC4: which entries count"
st_fix
st_e L-0001 2026-01-01 "Retired old" scripts/nope.sh "retired (gone)"
st_e L-0002 2026-01-01 "Active, later retired line" project-wide active "- Status: retired (quoted in the body)"
st_e L-0003 "$SD" "Fresh" project-wide
st_e L-0004 "$SD" "Prefix" project-wide activeXYZ
st_e L-0005 2026-01-01 "Retired first" project-wide "retired (x)" "- Status: active"
printf '\n### note without an id\n- Status: active\n- Scope: scripts/nope.sh\n' >> "$F"
sst
assert_eq "Q9 S2 AC4 retired never listed or counted; first Status line decides; '### note' ignored; A = 3 (L-0002, L-0003, L-0004)" "$(printf 'L-0002 · 2026-01-01 · Active, later retired line: 320 days old\nstale: 1 of 3 active entries listed (older than 180 days)')" "$SOUT"

echo "Q9 S2 AC5: not a git repository"
NG="$(mk_tmp)"; mkdir -p "$NG/.agents"
if [ "$(git -C "$NG" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  t_ok "Q9 S2 AC5 sanity: the temp dir is outside any git work tree"
  cd "$NG" || exit 3
  printf '# Learnings\n' > "$F"
  st_e L-0001 2026-01-01 "Old" scripts/nope.sh
  st_e L-0002 "$SD" "Fresh" src/nope.js
  SKIP="scope check skipped: not a git repository"
  sst
  assert_rc "Q9 S2 AC5 exit 0" 0
  assert_eq "Q9 S2 AC5 age only; one skipped line after the entry lines and before the summary" "$(printf 'L-0001 · 2026-01-01 · Old: 320 days old\n%s\nstale: 1 of 2 active entries listed (older than 180 days)' "$SKIP")" "$SOUT"
  assert_eq "Q9 S2 AC5 no git fatal on stderr" "" "$SERR"
  GIT_DIR="$SR/.git" sst
  assert_eq "Q9 S2 AC5 GIT_DIR pointing at another repo changes nothing" "$(printf 'L-0001 · 2026-01-01 · Old: 320 days old\n%s\nstale: 1 of 2 active entries listed (older than 180 days)' "$SKIP")" "$SOUT"
  printf '# Learnings\n' > "$F"
  st_e L-0001 "$SD" "A" project-wide
  st_e L-0002 "$SD" "B" project-wide
  st_e L-0003 "$SD" "C" "free text"
  sst
  assert_eq "Q9 S2 AC5 many entries, none path-like: still exactly one skipped line" "$(printf '%s\nstale: 0 of 3 active entries listed (older than 180 days)' "$SKIP")" "$SOUT"
  printf '# Learnings\n' > "$F"
  sst
  assert_eq "Q9 S2 AC5 no active entry: skipped line right before '0 of 0'" "$(printf '%s\nstale: 0 of 0 active entries listed (older than 180 days)' "$SKIP")" "$SOUT"
else
  t_skip 7 "the temp dir is inside a git work tree here: non-repo rows not testable"
fi

echo "Q9 S2 AC6: exit codes and argument checks"
st_fix
st_e L-0001 2026-01-01 "Old" project-wide
sst_at 2026-01-02 --fail
assert_eq "Q9 S2 AC6 nothing listed with --fail: exit 0" "0" "$SRC"
sst
assert_eq "Q9 S2 AC6 listed without --fail: exit 0" "0" "$SRC"
sst --fail
assert_eq "Q9 S2 AC6 listed with --fail: exit 1" "1" "$SRC"
assert_contains "Q9 S2 AC6 --fail still prints the entry line" "$SOUT" "320 days old"
sst --fail --fail
assert_eq "Q9 S2 AC6 --fail twice: same as once (exit 1)" "1" "$SRC"
sst --days 999999
assert_eq "Q9 S2 AC6 six digits are valid" "0" "$SRC"
sst --days 1
assert_eq "Q9 S2 AC6 --days 1 is valid" "0" "$SRC"
assert_contains "Q9 S2 AC6 --days 1 lists the 320-day entry" "$SOUT" "older than 1 days"
st_bad() { # NAME ARGS...: exit 2, one stderr line 'error: ...', empty stdout
  local n="$1"; shift
  sst "$@"
  assert_eq "Q9 S2 AC6 $n: exit 2" "2" "$SRC"
  assert_eq "Q9 S2 AC6 $n: stdout empty" "" "$SOUT"
  assert_eq "Q9 S2 AC6 $n: one stderr line starting 'error: '" "1" "$(printf '%s\n' "$SERR" | grep -c '^error: ')"
}
st_bad "--days 0" --days 0
st_bad "--days 05" --days 05
st_bad "--days +5" --days +5
st_bad "--days abc" --days abc
st_bad "--days 1234567" --days 1234567
st_bad "--days=30" --days=30
st_bad "--days without a value" --days
st_bad "--days followed by --fail" --days --fail
st_bad "--days empty value" --days ""
st_bad "unknown option" --bogus
st_bad "stray argument" extra
st_bad "unknown option after valid ones" --days 30 --fail --bogus
mv "$F" "$F.gone"
sst
assert_eq "Q9 S2 AC6 missing file: exit 2" "2" "$SRC"
assert_contains "Q9 S2 AC6 missing file: '<REL> not found' on stderr" "$SERR" ".agents/LEARNINGS.md not found"
assert_eq "Q9 S2 AC6 missing file: stdout empty" "" "$SOUT"
sst --days abc
assert_eq "Q9 S2 AC6 usage error wins over a missing file: exit 2" "2" "$SRC"
assert_not_contains "Q9 S2 AC6 ... and does not say 'not found'" "$SERR" "not found"
sst_at 2026-02-30
assert_contains "Q9 S2 AC6 missing file wins over a bad PLAYBOOK_DATE" "$SERR" "not found"
assert_not_contains "Q9 S2 AC6 ... no 'invalid PLAYBOOK_DATE' then" "$SERR" "invalid PLAYBOOK_DATE"
mv "$F.gone" "$F"
# conf: learn_stale_days (project conf .agents/playbook.conf)
printf 'learn_stale_days=abc\n' > .agents/playbook.conf
sst
assert_eq "Q9 S2 AC6 learn_stale_days=abc without --days: exit 2" "2" "$SRC"
assert_eq "Q9 S2 AC6 ... stdout empty" "" "$SOUT"
assert_eq "Q9 S2 AC6 ... one stderr line" "1" "$(printf '%s\n' "$SERR" | grep -c '^error: ')"
sst_at 2026-02-30
assert_eq "Q9 S2 AC6 bad conf and bad PLAYBOOK_DATE: the conf is reported first" "0" "$(printf '%s\n' "$SERR" | grep -c 'invalid PLAYBOOK_DATE')"
assert_eq "Q9 S2 AC6 ... still exit 2" "2" "$SRC"
sst --days 30
assert_eq "Q9 S2 AC6 --days given: the bad conf is not read (exit 0)" "0" "$SRC"
assert_contains "Q9 S2 AC6 ... and --days 30 is used" "$SOUT" "older than 30 days"
sst_at 2026-02-30 --days 30
assert_contains "Q9 S2 AC6 --days given, bad conf, bad date: the date error shows (conf not read)" "$SERR" "invalid PLAYBOOK_DATE"
printf 'learn_stale_days=30\n' > .agents/playbook.conf
printf '# Learnings\n' > "$F"
st_e L-0001 2026-10-01 "Age 47" project-wide
sst
assert_eq "Q9 S2 AC6 learn_stale_days=30 changes the threshold (47 > 30)" "$(printf 'L-0001 · 2026-10-01 · Age 47: 47 days old\nstale: 1 of 1 active entries listed (older than 30 days)')" "$SOUT"
sst --days 100
assert_eq "Q9 S2 AC6 --days beats the conf" "stale: 0 of 1 active entries listed (older than 100 days)" "$SOUT"
rm -f .agents/playbook.conf
printf '# Learnings\n' > "$F"
st_e L-0001 2026-11-02 "Age 15" project-wide
sst --days 10 --days 20
assert_eq "Q9 S2 AC6 repeated --days: the last one wins (20: age 15 not listed)" "stale: 0 of 1 active entries listed (older than 20 days)" "$SOUT"
sst --days 20 --days 10
assert_eq "Q9 S2 AC6 repeated --days: the last one wins (10: age 15 listed)" "$(printf 'L-0001 · 2026-11-02 · Age 15: 15 days old\nstale: 1 of 1 active entries listed (older than 10 days)')" "$SOUT"
for BADD in 2026-02-30 abc 2026-1-1 2026-13-01 "2026-11-17x"; do
  sst_at "$BADD"
  assert_eq "Q9 S2 AC6 PLAYBOOK_DATE=$BADD: exit 2" "2" "$SRC"
  assert_contains "Q9 S2 AC6 PLAYBOOK_DATE=$BADD: 'invalid PLAYBOOK_DATE' on stderr" "$SERR" "invalid PLAYBOOK_DATE"
  assert_eq "Q9 S2 AC6 PLAYBOOK_DATE=$BADD: stdout empty" "" "$SOUT"
done

echo "Q9 S2 AC7: read-only"
st_fix
st_e L-0001 2026-01-01 "Old" scripts/nope.sh
st_e L-0002 "$SD" "Fresh" scripts/a.sh
st_snap() { find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r f; do cksum "$f"; done; git ls-files -s; cksum .git/index; }
SNAP_B="$(st_snap)"
sst --fail
assert_eq "Q9 S2 AC7 sanity: the --fail run listed something (exit 1)" "1" "$SRC"
SNAP_A="$(st_snap)"
assert_eq "Q9 S2 AC7 file hashes, file list, git ls-files -s and the index are unchanged" "$SNAP_B" "$SNAP_A"
sst
assert_eq "Q9 S2 AC7 ... also after a plain run" "$SNAP_B" "$(st_snap)"

echo "Q9 S2 AC8: dates, headings, CRLF, scope lines"
st_fix
st_e L-0001 2026-13-40 "Bad month" scripts/nope.sh
st_e L-0002 2026-02-29 "Bad day" scripts/nope.sh
st_e L-0003 2024-02-29 "Leap day" project-wide
printf '\n### L-0004 · bad heading text\n- Status: active\n- Rule: r\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: scripts/nope.sh\n' >> "$F"
sst_at 2024-03-02 --days 1
assert_eq "Q9 S2 AC8 bad dates: no age check, scope check still runs; 2024-02-29 is valid (2 days); raw heading text is printed" "$(printf 'L-0001 · 2026-13-40 · Bad month: %s\nL-0002 · 2026-02-29 · Bad day: %s\nL-0003 · 2024-02-29 · Leap day: 2 days old\nL-0004 · bad heading text: %s\nstale: 4 of 4 active entries listed (older than 1 days)' "$NOSCOPE" "$NOSCOPE" "$NOSCOPE")" "$SOUT"
assert_eq "Q9 S2 AC8 ... exit code 0" "0" "$SRC"
st_fix
st_e L-0001 2026-01-01 "Old ok" scripts/a.sh
st_e L-0002 "$SD" "Fresh ok" scripts/a.sh
st_e L-0003 2026-01-01 "Old bad" scripts/nope.sh
WANT_CR="$(printf 'L-0001 · 2026-01-01 · Old ok: 320 days old\nL-0003 · 2026-01-01 · Old bad: 320 days old; %s\nstale: 2 of 3 active entries listed (older than 180 days)' "$NOSCOPE")"
sst
assert_eq "Q9 S2 AC8 LF baseline" "$WANT_CR" "$SOUT"
awk '{ printf "%s\r\n", $0 }' "$F" > "$F.crlf" && mv "$F.crlf" "$F"
sst
assert_eq "Q9 S2 AC8 CRLF file: same result as LF (scope matches, no false flag)" "$WANT_CR" "$SOUT"
assert_eq "Q9 S2 AC8 CRLF file: no CR in stdout" "0" "$(printf '%s' "$SOUT" | tr -cd '\r' | wc -c | tr -d ' ')"
st_fix
st_e L-0001 "$SD" "First wins ok" scripts/a.sh active "- Scope: scripts/nope.sh"
st_e L-0002 "$SD" "First wins bad" scripts/nope.sh active "- Scope: scripts/a.sh"
st_e L-0003 "$SD" "Trailing space" "scripts/a.sh "
sst
assert_eq "Q9 S2 AC8 two Scope lines: the first wins; a scope with a trailing space is not a path (not flagged)" "$(printf 'L-0002 · %s · First wins bad: %s\nstale: 1 of 3 active entries listed (older than 180 days)' "$SD" "$NOSCOPE")" "$SOUT"

echo "Q9 S2 AC9: usage line and untouched assertions"
run bash "$LEARN" frobnicate
assert_rc "Q9 S2 AC9 an unknown command exits 2" 2
assert_contains "Q9 S2 AC9 the usage line names stale" "$OUT" "stale"
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  assert_eq "Q9 S2 AC9 no existing line of tests/test-learn.sh is changed or removed (diff against HEAD only adds)" "0" "$(git -C "$PB_ROOT" diff -U0 HEAD -- tests/test-learn.sh | grep -c '^-[^-]')"
else
  t_skip 1 "not a git checkout: diff row not testable"
fi

echo "Q9 S2 AC10: order of listed entries"
st_fix
st_e L-0005 2026-01-01 "Fifth first" project-wide
st_e L-0003 "$SD" "Fresh between" project-wide
st_e L-0001 2026-02-01 "First last" project-wide
sst
assert_eq "Q9 S2 AC10 file order (L-0005 before L-0001); the fresh entry in between is absent (Feb 1 to Nov 17 is 289 days)" "$(printf 'L-0005 · 2026-01-01 · Fifth first: 320 days old\nL-0001 · 2026-02-01 · First last: 289 days old\nstale: 2 of 3 active entries listed (older than 180 days)')" "$SOUT"
cd "$PB_ROOT" || exit 3

t_summary
