#!/usr/bin/env bash
# Tests for scripts/role-gate.sh, the second half of test-role-gate.sh (split in v0.24.7 so that it is not the floor of a CI shard): from "AC1.2 global scope
# and precedence" to the end (the global conf notes, the executable-bit sections up to v0.23.2 MINOR-5, v0.24.0 F7). Shared setup: role-gate-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"

echo "AC1.2 global scope and precedence"
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_path_regex=^gchecks/\ntest_infra_regex=^gci/\n' > "$G_HOME/.agents/playbook.conf"
N="$(mk_tmp)"; mk_repo "$N"; cd "$N" || exit 3; printf 'module.exports = 2;\n' > src/app.js
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" check implementer
assert_rc "AC1.2 global regexes: implementer on code passes" 0
GN="$(notes_of)"
assert_eq "AC1.2 global: two note lines" "2" "$(printf '%s\n' "$GN" | grep -c '^note:')"
assert_contains "AC1.2 global note shows the global scope" "$GN" "global"
assert_not_contains "AC1.2 global note is not labelled project" "$GN" "project"
assert_contains "AC1.2 global note shows the path value" "$GN" "^gchecks/"
assert_contains "AC1.2 global note shows the infra value" "$GN" "^gci/"
# project value wins over the global one: the note shows the effective source
R="$(conf_repo 'test_path_regex=^pchecks/\n')"; cd "$R" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" check implementer
PN="$(notes_of | grep test_path_regex)"
assert_contains "AC1.2 project value wins: project scope shown" "$PN" "project"
assert_contains "AC1.2 project value wins: its value shown" "$PN" "^pchecks/"
assert_not_contains "AC1.2 project value wins: the shadowed global value is not shown" "$PN" "^gchecks/"
assert_contains "AC1.2 the global-only infra key is still noted as global" "$(notes_of | grep test_infra_regex)" "global"

echo "AC1.2 no note, output unchanged"
R="$(conf_repo 'language=vi\nmodel_tester_claude=x\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC1.2 other keys only: implementer output byte-identical to v0.9.0" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)" "$OUT"
run bash "$GATE" check tester
assert_eq "AC1.2 other keys only: tester output byte-identical to v0.9.0" "VIOLATION (tester): src/app.js [code]
role gate FAILED for tester: 1 violation(s), base=HEAD" "$OUT"
R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n')"; cd "$R" || exit 3
run bash "$GATE" classify checks/a.rb
assert_eq "AC1.2 classify prints only the class, even with notes-worthy keys" "test" "$OUT"
run bash "$GATE" classify ci/x.sh
assert_eq "AC1.2 classify infra prints only the class" "infra" "$OUT"
run bash "$GATE" size
assert_eq "AC1.2 size output unchanged with the keys set" "files: 1/3 lines: 2/100 (base=HEAD)" "$OUT"

# ---- v0.10.0 AC5.1: an empty test_path_regex fails closed ----
echo "AC5.1 empty test_path_regex"
# empty_repo CONFTEXT -> repo with a code change and a test change, conf committed
empty_repo() {
  local d; d="$(conf_repo "$1")"
  ( cd "$d" && printf 'test("x", () => { /* edited */ });\n' > tests/app.test.js )
  printf '%s\n' "$d"
}
check_empty() { # label  -> run the three commands in the current dir with the current env prefix in "$@"
  local label="$1"; shift
  for cmdline in "classify src/app.js" "classify tests/app.test.js" "check tester" "check implementer" "check reviewer" "size"; do
    run "$@" bash "$GATE" $cmdline
    assert_rc "AC5.1 [$label] $cmdline exits 3" 3
    assert_contains "AC5.1 [$label] $cmdline names the key" "$OUT" "test_path_regex"
    assert_contains "AC5.1 [$label] $cmdline says it is empty" "$OUT" "empty"
    assert_contains "AC5.1 [$label] $cmdline says to unset it" "$OUT" "unset"
    assert_not_contains "AC5.1 [$label] $cmdline never prints OK" "$OUT" "OK:"
  done
}
R="$(empty_repo 'test_path_regex=\n')"; cd "$R" || exit 3
check_empty "project" env
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; printf 'module.exports = 2;\n' > src/app.js
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_path_regex=\n' > "$G_HOME/.agents/playbook.conf"
check_empty "global" env PLAYBOOK_HOME="$G_HOME"
# an empty project value shadows a non-empty global one: still fails closed
R="$(empty_repo 'test_path_regex=\n')"; cd "$R" || exit 3
G2="$(mk_tmp)"; mkdir -p "$G2/.agents"; printf 'test_path_regex=^checks/\n' > "$G2/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G2" bash "$GATE" classify src/app.js
assert_rc "AC5.1 empty project value wins over a non-empty global one: exit 3" 3
# a non-empty project value wins over an empty global one: works
R="$(conf_repo 'test_path_regex=^checks/\n')"; cd "$R" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" classify checks/a.rb
assert_eq "AC5.1 non-empty project value beats an empty global one" "test" "$OUT"
# unset key stays the default; an empty infra regex stays off
R="$(conf_repo 'language=vi\n')"; cd "$R" || exit 3
run bash "$GATE" classify tests/app.test.js; assert_eq "AC5.1 unset key: default regex still applies" "test" "$OUT"
R="$(conf_repo 'test_infra_regex=\n')"; cd "$R" || exit 3
run bash "$GATE" classify tests/app.test.js; assert_eq "AC5.1 empty test_infra_regex stays off (classify)" "test" "$OUT"
assert_rc "AC5.1 empty test_infra_regex stays off (exit 0)" 0
run bash "$GATE" check implementer;          assert_rc "AC5.1 empty test_infra_regex stays off (check works)" 0

# ---- v0.10.0 round 2: shadowing empty infra regex, notes on stdout ----
echo "AC1.2 an empty project test_infra_regex shadowing a global one is noted"
R="$(conf_repo 'test_infra_regex=\n')"; cd "$R" || exit 3
( mkdir -p tests && printf 'helper() { :; }\n' > tests/lib.sh && git add -A && git commit -q -m lib ) >/dev/null
printf 'helper2() { :; }\n' >> tests/lib.sh
G3="$(mk_tmp)"; mkdir -p "$G3/.agents"; printf 'test_infra_regex=^tests/lib\\.sh$\n' > "$G3/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G3" bash "$GATE" check tester
assert_rc "AC1.2 shadowed: tester editing tests/lib.sh passes (infra is off)" 0
SN="$(notes_of | grep test_infra_regex)"
assert_contains "AC1.2 shadowed: a note names test_infra_regex" "$SN" "test_infra_regex"
assert_contains "AC1.2 shadowed: the note says it is empty" "$SN" "empty"
assert_contains "AC1.2 shadowed: the note says it is the project conf" "$SN" "project"
case "$SN" in *override*|*shadow*|*off*) t_ok "AC1.2 shadowed: the note says it overrides / switches off the global value" ;; *) t_bad "AC1.2 shadowed: the note says it overrides / switches off the global value" "note: [$SN]" ;; esac
assert_contains "AC1.2 shadowed: the note mentions the global value" "$SN" "global"
assert_eq "AC1.2 shadowed: the note is first, before the verdict" "note:" "$(printf '%s\n' "$OUT" | head -n 1 | cut -c1-5)"
# no global value: the v0.9 byte-identical behaviour (empty infra regex is silent)
run bash "$GATE" check tester
assert_eq "AC1.2 empty project value with no global value stays silent" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)" "$OUT"
# empty global value and empty project value: nothing to shadow
G4="$(mk_tmp)"; mkdir -p "$G4/.agents"; printf 'test_infra_regex=\n' > "$G4/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G4" bash "$GATE" check tester
assert_eq "AC1.2 empty project over empty global stays silent" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)" "$OUT"

echo "AC1.2 notes go to stdout, not stderr"
R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n')"; cd "$R" || exit 3
SO="$(bash "$GATE" check implementer 2>/dev/null)"
SE="$(bash "$GATE" check implementer 2>&1 >/dev/null)"
assert_contains "AC1.2 stdout carries the test_path_regex note" "$SO" "note:"
assert_eq "AC1.2 stdout carries both notes" "2" "$(printf '%s\n' "$SO" | grep -c '^note:')"
assert_eq "AC1.2 stderr is empty on a passing check" "" "$SE"
SE="$(bash "$GATE" check tester 2>&1 >/dev/null)"
assert_not_contains "AC1.2 stderr has no note on a failing check" "$SE" "note:"

# ---- v0.11.0 AC8.1: control characters in a config value are shown as '?' in the note ----
echo "v0.11.0 AC8.1 control characters in note values"
ESC="$(printf '\033')"; CR="$(printf '\r')"
R="$(conf_repo 'test_path_regex=^chec\033ks/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_rc "AC8.1 ESC inside a still-valid regex: the gate still runs (exit 0)" 0
N1="$(notes_of)"
assert_eq "AC8.1 ESC byte replaced by ? in the note" "note: test_path_regex from the project conf: ^chec?ks/" "$N1"
assert_not_contains "AC8.1 no raw ESC byte reaches the terminal" "$OUT" "$ESC"
R="$(conf_repo 'test_path_regex=^ch\recks/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
N1="$(notes_of)"
assert_eq "AC8.1 CR inside the value replaced by ?" "note: test_path_regex from the project conf: ^ch?ecks/" "$N1"
assert_not_contains "AC8.1 no raw CR in the output (it could overwrite the line)" "$OUT" "$CR"
assert_eq "AC8.1 the note is still a single line" "1" "$(printf '%s\n' "$OUT" | grep -c '^note:')"
R="$(conf_repo 'test_path_regex=^a\tb/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC8.1 TAB (0x09) replaced by ?" "note: test_path_regex from the project conf: ^a?b/" "$(notes_of)"
R="$(conf_repo 'test_path_regex=^a\177b/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC8.1 DEL (0x7F) replaced by ?" "note: test_path_regex from the project conf: ^a?b/" "$(notes_of)"
R="$(conf_repo 'test_path_regex=^a\033\033b/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC8.1 every control byte is replaced (two ESC -> two ?)" "note: test_path_regex from the project conf: ^a??b/" "$(notes_of)"
R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci\033/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_contains "AC8.1 test_infra_regex note is cleaned too" "$(notes_of)" "test_infra_regex from the project conf: ^ci?/"
assert_not_contains "AC8.1 no raw ESC in the infra note output" "$OUT" "$ESC"
assert_contains "AC8.1 the clean test_path_regex note beside it is unchanged" "$(notes_of)" "test_path_regex from the project conf: ^checks/"
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_path_regex=^g\033checks/\n' > "$G_HOME/.agents/playbook.conf"
R="$(conf_repo '')"; cd "$R" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" check implementer
assert_eq "AC8.1 global-conf value is cleaned too" "note: test_path_regex from the global conf: ^g?checks/" "$(notes_of)"
R="$(conf_repo 'test_path_regex=^chec\033ks/\n')"; cd "$R" || exit 3
run bash "$GATE" check tester
assert_not_contains "AC8.1 no raw ESC in the tester output either" "$OUT" "$ESC"
R="$(conf_repo 'test_path_regex=^caf\xc3\xa9 \[x\]/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC8.1 printable value (space, brackets, UTF-8) is unchanged" "note: test_path_regex from the project conf: ^café \\[x\\]/" "$(notes_of)"
R="$(conf_repo 'test_path_regex=^checks/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC8.1 plain printable value unchanged" "note: test_path_regex from the project conf: ^checks/" "$(notes_of)"


# ---- v0.23.2 AC1.1: a lost executable bit is a violation for every role ----
echo "v0.23.2 AC1.1 the executable bit (100755 -> 100644)"
unset PB_ALLOW_MODE_CHANGE
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
assert_eq "AC1.1 fixture: src/run.sh is committed 100755" "100755" "$(git ls-files -s -- src/run.sh | cut -d' ' -f1)"
assert_eq "AC1.1 fixture: src/plain.js is committed 100644" "100644" "$(git ls-files -s -- src/plain.js | cut -d' ' -f1)"
gchk implementer; assert_rc "AC1.1 an untouched fixture passes the implementer check" 0

for spec in tester:tests/run.sh implementer:src/run.sh reviewer:src/run.sh infra:ci/run.sh; do
  role="${spec%%:*}"; p="${spec#*:}"
  MSG="VIOLATION (mode): $p lost its executable bit (100755 -> 100644)"
  # work tree only
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  chmod -x "$p" 2>/dev/null
  if dropped_visible; then
    gchk "$role"; assert_rc "AC1.1 $role: a work-tree chmod -x fails" 1
    assert_contains "AC1.1 $role: work-tree drop prints the mode violation line" "$OUT" "$MSG"
  else t_skip 2 "AC1.1 $role work-tree chmod (not visible to git here)"; fi
  # staged
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  chmod -x "$p" 2>/dev/null; git update-index --chmod=-x -- "$p"
  if dropped_visible; then
    gchk "$role"; assert_rc "AC1.1 $role: a staged mode drop fails" 1
    assert_contains "AC1.1 $role: staged drop prints the mode violation line" "$OUT" "$MSG"
  else t_skip 2 "AC1.1 $role staged drop (not visible to git here)"; fi
  # the escape: PB_ALLOW_MODE_CHANGE lists the path
  if dropped_visible; then
    gchk_allow "$p" "$role"
    assert_not_contains "AC1.1 $role: PB_ALLOW_MODE_CHANGE=path silences the mode violation" "$OUT" "VIOLATION (mode)"
    if [ "$role" != reviewer ]; then assert_rc "AC1.1 $role: PB_ALLOW_MODE_CHANGE=path lets the change pass" 0; fi
  else t_skip 2 "AC1.1 $role PB_ALLOW_MODE_CHANGE (not visible to git here)"; fi
done

echo "v0.23.2 AC1.1 PB_ALLOW_MODE_CHANGE: colon list, exact paths only, only the listed path"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
chmod -x src/run.sh src/second.sh 2>/dev/null; git update-index --chmod=-x -- src/run.sh src/second.sh
if dropped_visible; then
  gchk implementer
  assert_rc "AC1.1 two dropped files: fails" 1
  assert_contains "AC1.1 two dropped: first path named" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
  assert_contains "AC1.1 two dropped: second path named" "$OUT" "VIOLATION (mode): src/second.sh lost its executable bit (100755 -> 100644)"
  gchk_allow "src/run.sh" implementer
  assert_rc "AC1.1 allowing one of two still fails" 1
  assert_contains "AC1.1 the unlisted path is still reported" "$OUT" "VIOLATION (mode): src/second.sh lost its executable bit"
  assert_not_contains "AC1.1 the listed path is not reported" "$OUT" "VIOLATION (mode): src/run.sh "
  gchk_allow "src/run.sh:src/second.sh" implementer
  assert_rc "AC1.1 a colon list of both paths passes" 0
  gchk_allow "docs/other.sh:src/run.sh:src/second.sh:x" implementer
  assert_rc "AC1.1 a colon list with other entries around them passes" 0
  for bad in src "src/*" run.sh "src/run.sh.bak" "src/second" "/src/run.sh" ""; do
    gchk_allow "$bad:src/second.sh" implementer
    assert_rc "AC1.1 allow entry [$bad] is not a match for src/run.sh (exact paths only): fails" 1
    assert_contains "AC1.1 allow entry [$bad]: src/run.sh is still reported" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit"
  done
  gchk_allow "" implementer
  assert_rc "AC1.1 an empty PB_ALLOW_MODE_CHANGE allows nothing" 1
else t_skip 20 "AC1.1 PB_ALLOW_MODE_CHANGE cases (chmod not visible to git here)"; fi

echo "v0.23.2 AC1.1 what is not a lost executable bit"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
printf 'changed\n' > src/plain.js
gchk implementer; assert_rc "AC1.1 a 100644 file that was never executable, edited: passes" 0
assert_not_contains "AC1.1 ... no mode violation" "$OUT" "(mode)"
printf '#!/bin/sh\necho new\n' > src/new.sh
gchk implementer; assert_rc "AC1.1 a new untracked file (not executable): passes" 0
assert_not_contains "AC1.1 ... no mode violation for the untracked file" "$OUT" "(mode)"
git add src/new.sh
gchk implementer; assert_rc "AC1.1 a new staged file at 100644: passes" 0
assert_not_contains "AC1.1 ... no mode violation for the new staged file" "$OUT" "(mode)"
git update-index --chmod=+x -- src/plain.js; chmod +x src/plain.js 2>/dev/null
gchk implementer; assert_rc "AC1.1 gaining the executable bit (100644 -> 100755): passes" 0
assert_not_contains "AC1.1 ... gaining is no mode violation" "$OUT" "(mode)"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
rm -f src/run.sh
gchk implementer; assert_rc "AC1.1 deleting an executable file (100755 -> gone): passes for the implementer" 0
assert_not_contains "AC1.1 ... deleting is no mode violation" "$OUT" "(mode)"

echo "v0.23.2 AC1.1 a path with a space"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
chmod -x "src/my run.sh" 2>/dev/null; git update-index --chmod=-x -- "src/my run.sh"
if dropped_visible; then
  gchk implementer; assert_rc "AC1.1 a spaced path losing its bit fails" 1
  assert_contains "AC1.1 the spaced path is printed whole" "$OUT" "VIOLATION (mode): src/my run.sh lost its executable bit (100755 -> 100644)"
  gchk_allow "src/my run.sh" implementer; assert_rc "AC1.1 a spaced path listed in PB_ALLOW_MODE_CHANGE passes" 0
else t_skip 3 "AC1.1 spaced path (not visible to git here)"; fi

echo "v0.23.2 AC1.1 --base: a committed drop since the base is caught"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
chmod -x src/run.sh 2>/dev/null; git update-index --chmod=-x -- src/run.sh
git commit -q -m "drop the bit"
gchk implementer --base HEAD~1
assert_rc "AC1.1 --base before the committed drop fails" 1
assert_contains "AC1.1 --base names the path" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
gchk implementer;   assert_rc "AC1.1 the default base (HEAD) sees nothing after the commit" 0
gchk_allow "src/run.sh" implementer --base HEAD~1
assert_rc "AC1.1 --base with PB_ALLOW_MODE_CHANGE passes" 0

echo "v0.23.2 AC1.1 core.fileMode=false: no false alarm from the work tree, a staged update-index is caught"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
git config core.fileMode false
chmod -x src/run.sh tests/run.sh 2>/dev/null
gchk implementer; assert_rc "AC1.1 fileMode=false: a work-tree chmod -x gives no alarm (implementer)" 0
assert_not_contains "AC1.1 fileMode=false: no mode violation line" "$OUT" "(mode)"
gchk tester; assert_rc "AC1.1 fileMode=false: a work-tree chmod -x gives no alarm (tester)" 0
git update-index --chmod=-x -- src/run.sh
gchk implementer; assert_rc "AC1.1 fileMode=false: a staged update-index --chmod=-x is caught" 1
assert_contains "AC1.1 fileMode=false: the staged drop prints the mode violation line" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
assert_not_contains "AC1.1 fileMode=false: the other, only chmod-ed, file is not reported" "$OUT" "tests/run.sh lost"
gchk_allow "src/run.sh" implementer; assert_rc "AC1.1 fileMode=false: the escape works for the staged drop" 0



# ---- v0.23.2 fix round (lane A): staged-only drops, renamed drops, odd path names ----
echo "v0.23.2 fix MINOR-3 a staged-only mode drop (work tree still executable, core.fileMode=true) is caught"
for spec in tester:tests/run.sh implementer:src/run.sh reviewer:src/run.sh infra:ci/run.sh; do
  role="${spec%%:*}"; p="${spec#*:}"
  MSG="VIOLATION (mode): $p lost its executable bit (100755 -> 100644)"
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  fmok=0; fm_true_ok && fmok=1
  git update-index --chmod=-x -- "$p"
  assert_eq "MINOR-3 $role: fixture: the index says 100644" "100644" "$(git ls-files -s -- "$p" | cut -d' ' -f1)"
  if [ "$fmok" = 1 ] && [ -x "$p" ]; then
    gchk "$role"; assert_rc "MINOR-3 $role: a staged-only drop fails" 1
    assert_contains "MINOR-3 $role: it prints the mode message" "$OUT" "$MSG"
    gchk_allow "$p" "$role"
    assert_not_contains "MINOR-3 $role: PB_ALLOW_MODE_CHANGE=path silences it" "$OUT" "VIOLATION (mode)"
  else t_skip 3 "MINOR-3 $role (this file system does not keep executable bits)"; fi
done

echo "v0.23.2 fix MINOR-5 a rename plus a mode drop is a lost executable bit"
for spec in tester:tests/run.sh:tests/renamed.sh implementer:src/run.sh:src/renamed.sh reviewer:src/run.sh:src/renamed.sh infra:ci/run.sh:ci/renamed.sh; do
  role="${spec%%:*}"; rest="${spec#*:}"; old="${rest%%:*}"; new="${rest#*:}"
  MSG="VIOLATION (mode): $new lost its executable bit (100755 -> 100644)"
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  git mv "$old" "$new"; chmod -x "$new" 2>/dev/null; git update-index --chmod=-x -- "$new"
  git add -A
  assert_eq "MINOR-5 $role: fixture: $new is staged 100644" "100644" "$(git ls-files -s -- "$new" | cut -d' ' -f1)"
  gchk "$role"; assert_rc "MINOR-5 $role: rename + drop fails" 1
  assert_contains "MINOR-5 $role: the NEW path is named with both modes" "$OUT" "$MSG"
  gchk_allow "$new" "$role"
  assert_not_contains "MINOR-5 $role: PB_ALLOW_MODE_CHANGE=new path silences it" "$OUT" "VIOLATION (mode)"
  if [ "$role" != reviewer ]; then assert_rc "MINOR-5 $role: PB_ALLOW_MODE_CHANGE=new path lets it pass" 0; fi
  gchk_allow "$old" "$role"
  assert_contains "MINOR-5 $role: listing the OLD path does not silence it" "$OUT" "$MSG"
done
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
git rm -q src/run.sh
printf '#!/bin/sh\necho different\n' > src/other.sh; git add src/other.sh; git update-index --chmod=-x -- src/other.sh
gchk implementer; assert_rc "MINOR-5 a deleted 100755 path plus a 100644 path with a different blob passes" 0
assert_not_contains "MINOR-5 ... no mode violation" "$OUT" "(mode)"


echo "v0.24.0 review round 2 F7: an empty quick_max_files= or quick_max_lines= falls back to the default"
qrepo
qconf quick_max_files= quick_max_lines=
seq 1 20 > src/a.js
run bash "$GATE" size --quick;                  assert_rc "F7 both quick keys empty: exits 0, not 2" 0
assert_contains "F7 both quick keys empty: the defaults 1 / 20 apply" "$OUT" "files: 1/1 lines: 20/20"
qrepo
qconf quick_max_files=
seq 1 20 > src/a.js
run bash "$GATE" size --quick;                  assert_rc "F7 empty quick_max_files only: exits 0" 0
assert_contains "F7 empty quick_max_files only: default files 1" "$OUT" "files: 1/1 lines: 20/20"
qrepo
qconf quick_max_lines=
seq 1 20 > src/a.js
run bash "$GATE" size --quick;                  assert_rc "F7 empty quick_max_lines only: exits 0" 0
assert_contains "F7 empty quick_max_lines only: default lines 20" "$OUT" "files: 1/1 lines: 20/20"
printf 'x\n' >> src/a.js
run bash "$GATE" size --quick;                  assert_rc "F7 an empty key keeps the default limit: 21 lines exits 1" 1
t_summary
