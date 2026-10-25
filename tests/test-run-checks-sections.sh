#!/usr/bin/env bash
# Tests of evals/run-checks.sh sections dupmax, sed, soh, the --only SECTION switch and the empty-glob report (split from test-run-checks.sh in v0.23.3).
# Each test runs run-checks.sh inside a fresh copy of the repository (tracked + untracked, non-ignored files), so mutations
# never touch the real tree. Shared setup: run-checks-fixture.sh.
# Cases whose findings come only from their own fixture file run in mk_min_copy (run-checks-fixture.sh); the real-tree runs, and the
# sections that read skills/, evals/scenarios.md or the installed shellcheck, use mk_copy.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"

# ---- v0.24.13: the min-tree cases of the dupmax, sed and soh families are batched (a case cost ~1.1 s on Windows: a cp -a, a run-checks, the rest) ----
# bound_case / sed_case / soh_case NAME FILE BODY-LINE EXPECT(fail|pass) only queue a case; bq_flush FAMILY then writes every fixture of the family
# as its own file (zz-FAMILY-NNN.sh, one per case, so a finding names exactly one case) into ONE min tree per expectation, runs the section once on
# the "fail" tree and once on the "pass" tree, and asserts per case on the shared output: a fail case has its own FILE:LINE named, a pass case has its
# FILE not named (the fixed-width NNN keeps one file name from being a prefix of another). Several cases on install.sh (the one fixed name) share that file
# on different lines (3, 4, ...). The rc is one assertion per tree: the fail tree exits 1 and the all-pass tree exits 0.
BQ_FAM=(); BQ_NAME=(); BQ_REL=(); BQ_LINE=(); BQ_EXP=()
bq_add() { # FAMILY NAME FILE BODY-LINE EXPECT
  local n="${#BQ_FAM[@]}"
  BQ_FAM[$n]="$1"; BQ_NAME[$n]="$2"; BQ_REL[$n]="$3"; BQ_LINE[$n]="$4"; BQ_EXP[$n]="$5"
}
# bq_flush FAMILY ACID SECTION
bq_flush() {
  local fam="$1" ac="$2" sec="$3" exp i n d f ln rc_fail=1 rc_pass=0 out_fail="" out_pass="" ninst
  local BQ_FILE=() BQ_FLN=()
  for exp in fail pass; do
    C="$(mk_min_copy)"; ninst=0; n=0
    for ((i = 0; i < ${#BQ_FAM[@]}; i++)); do
      [ "${BQ_FAM[$i]}" = "$fam" ] && [ "${BQ_EXP[$i]}" = "$exp" ] || continue
      n=$((n + 1))
      if [ "${BQ_REL[$i]}" = install.sh ]; then
        f=install.sh; ln=$((3 + ninst))
        if [ "$ninst" = 0 ]; then printf '#!/usr/bin/env bash\n# fixture\n%s\n' "${BQ_LINE[$i]}" > "$C/$f"
        else printf '%s\n' "${BQ_LINE[$i]}" >> "$C/$f"; fi || t_bad "$ac ${BQ_NAME[$i]}: fixture written" "could not write $C/$f"
        ninst=$((ninst + 1))
      else
        d="$(dirname "${BQ_REL[$i]}")"; f="$d/zz-$fam-$(printf '%03d' "$i").sh"; ln=3
        mkdir -p "$C/$d" && printf '#!/usr/bin/env bash\n# fixture\n%s\n' "${BQ_LINE[$i]}" > "$C/$f" ||
          t_bad "$ac ${BQ_NAME[$i]}: fixture written" "could not write $C/$f"
      fi
      # a case whose line is not in its fixture would pass vacuously (its file is never named)
      grep -qxF -- "${BQ_LINE[$i]}" "$C/$f" 2>/dev/null || t_bad "$ac ${BQ_NAME[$i]}: fixture holds its line" "line not found in $C/$f"
      BQ_FILE[$i]="$f"; BQ_FLN[$i]="$ln"
    done
    [ "$n" -gt 0 ] || continue
    checks "$C" "$sec"
    if [ "$exp" = fail ]; then out_fail="$OUT"; rc_fail="$RC"; else out_pass="$OUT"; rc_pass="$RC"; fi
  done
  OUT="$out_fail"; RC="$rc_fail"; assert_rc "$ac batched: the fixtures that must fail exit 1" 1
  OUT="$out_pass"; RC="$rc_pass"; assert_rc "$ac batched: the all-pass fixtures exit 0" 0
  for ((i = 0; i < ${#BQ_FAM[@]}; i++)); do
    [ "${BQ_FAM[$i]}" = "$fam" ] || continue
    if [ "${BQ_EXP[$i]}" = fail ]; then
      # exit 1 for this case: the tree exited 1 AND this case's own file:line is among the findings
      case "$out_fail" in *"${BQ_FILE[$i]}:${BQ_FLN[$i]}"*) [ "$rc_fail" = 1 ] && t_ok "$ac ${BQ_NAME[$i]}: exit 1" || t_bad "$ac ${BQ_NAME[$i]}: exit 1" "tree exit $rc_fail" ;;
        *) t_bad "$ac ${BQ_NAME[$i]}: exit 1" "no finding for ${BQ_FILE[$i]}:${BQ_FLN[$i]} (tree exit $rc_fail)" ;; esac
      assert_contains "$ac ${BQ_NAME[$i]}: names file:line" "$out_fail" "${BQ_FILE[$i]}:${BQ_FLN[$i]}"
    else
      if [ "$rc_pass" = 0 ]; then t_ok "$ac ${BQ_NAME[$i]}: exit 0"; else t_bad "$ac ${BQ_NAME[$i]}: exit 0" "all-pass tree exit $rc_pass; output: $out_pass"; fi
      assert_not_contains "$ac ${BQ_NAME[$i]}: the file is not named" "$out_pass" "${BQ_FILE[$i]}"
    fi
  done
}

echo "v0.13.0 AC6.1 regex repeat bounds above 255 (BSD/macOS RE_DUP_MAX) are refused"
# The bound is built at run time: a literal one in this file would fail the real run-checks.
# bound_case NAME FILE BODY-LINE EXPECT(fail|pass): queued, run by bq_flush bound (batched, v0.24.13)
bound_case() { bq_add bound "$@"; }
BIG=$((255 + 45)); EDGE=$((255 + 1)); TOP=255
bound_case "tests/ file, upper bound over the limit" tests/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "evals/ file, upper bound over the limit" evals/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "single bound over the limit" tests/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "just above the limit 256"  tests/zz-bound.sh "grep -E 'a{0,${EDGE}}' f" fail
bound_case "four-digit bound"          tests/zz-bound.sh "grep -E 'a{0,${TOP}0}' f" fail
bound_case "both numbers high"         tests/zz-bound.sh "grep -E 'a{${BIG},$((BIG + 100))}' f" fail
bound_case "exactly 255 passes"        tests/zz-bound.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "single {255} passes"       tests/zz-bound.sh "grep -E 'a{${TOP}}' f" pass
bound_case "small bounds pass"         tests/zz-bound.sh "grep -E 'a{1,100}b{3}' f" pass
bound_case "a bash brace list is not a bound" tests/zz-bound.sh "echo {1,2,3} {a,b}" pass

echo "v0.14.0 AC7.1 every shell script is scanned: scripts/, tools/, install.sh; and the {,n} form"
bound_case "scripts/ file, upper bound over the limit" scripts/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "scripts/ file, single bound over the limit" scripts/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "tools/ file, upper bound over the limit" tools/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "tools/ file, single bound over the limit" tools/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "install.sh, upper bound over the limit" install.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "install.sh, just above the limit 256" install.sh "grep -E 'a{0,${EDGE}}' f" fail
bound_case "{,n} form with n over the limit (tests/)" tests/zz-bound.sh "grep -E 'a{,${BIG}}' f" fail
bound_case "{,n} form with n over the limit (scripts/)" scripts/zz-bound.sh "grep -E 'a{,${BIG}}' f" fail
bound_case "{,n} form with n = 256" tests/zz-bound.sh "grep -E 'a{,${EDGE}}' f" fail
bound_case "{,255} passes" tests/zz-bound.sh "grep -E 'a{,${TOP}}' f" pass
bound_case "{,n} with a small n passes" scripts/zz-bound.sh "grep -E 'a{,10}' f" pass
bound_case "scripts/ file, exactly 255 passes" scripts/zz-bound.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "tools/ file, small bounds pass" tools/zz-bound.sh "grep -E 'a{1,100}b{3}' f" pass
bound_case "install.sh, exactly 255 passes" install.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "a bash brace list in scripts/ is not a bound" scripts/zz-bound.sh "echo {1,2,3} {a,b}" pass
echo "v0.13.0/v0.14.0 AC6.1 AC7.1 the bound cases above, one run per expectation"
bq_flush bound AC6.1 dupmax
# the message tells what is wrong, not only where
C="$(mk_min_copy)"; printf '#!/usr/bin/env bash\n# fixture\ngrep -E %s f\n' "'a{,${BIG}}'" > "$C/tools/zz-bound.sh"
checks "$C" dupmax
assert_contains "AC7.1 the failure mentions the repeat bound" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "bound"


echo "v0.21.0 AC2.1 GNU-only in-place sed (no attached suffix) is refused; BSD sed needs one"
# The commands are built at run time: a literal one in this file would fail the real run-checks.
SD=sed; FI=-i
# sed_case NAME FILE BODY-LINE EXPECT(fail|pass): queued, run by bq_flush sed (batched, v0.24.13)
sed_case() { bq_add sed "$@"; }
sed_case "double-quoted script, no suffix"        tests/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "single-quoted script, no suffix"        tests/zz-sed.sh "$SD $FI 's/a/b/' f" fail
sed_case "-E before -i"                           tests/zz-sed.sh "$SD -E $FI 's/a/b/' f" fail
sed_case "long form --in-place"                  tests/zz-sed.sh "$SD --in-place 's/a/b/' f" fail
sed_case "combined flags -Ei"                    tests/zz-sed.sh "$SD -E${FI#-} 's/a/b/' f" fail
sed_case "-n before -i"                           tests/zz-sed.sh "$SD -n $FI 's/a/b/p' f" fail
sed_case "mid-line after a semicolon"             tests/zz-sed.sh "x=1; $SD $FI \"s/a/b/\" f" fail
sed_case "script quoted right after -i (double)"  tests/zz-sed.sh "$SD $FI\"s/a/b/\" f" fail
sed_case "script quoted right after -i (single)"  tests/zz-sed.sh "$SD $FI's/a/b/' f" fail
sed_case "in a pipeline"                          tests/zz-sed.sh "cat f | $SD $FI 's/a/b/' g" fail
sed_case "evals/ file"                            evals/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "scripts/ file"                          scripts/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "tools/ file"                            tools/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "install.sh"                             install.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "attached suffix .bak"                   tests/zz-sed.sh "$SD $FI.bak 's/a/b/' f" pass
sed_case "attached suffix .bak, -E before"        tests/zz-sed.sh "$SD -E $FI.bak 's/a/b/' f" pass
sed_case "a comment line mentioning it"           tests/zz-sed.sh "# do not use $SD $FI \"s/...\"" pass
sed_case "a trailing comment mentioning it"       tests/zz-sed.sh "foo   # node, not $SD $FI: BSD" pass
sed_case "sed without -i"                         tests/zz-sed.sh "$SD -n 's/a/b/p' f" pass
sed_case "review F3 a (#1) inside double quotes is not a comment, the in-place sed after it is flagged" tests/zz-sed.sh "echo \"(#1)\"; $SD $FI s/a/b/ f" fail
sed_case "review F3 a ;# inside single quotes is not a comment, the in-place sed after it is flagged" tests/zz-sed.sh "echo 'a;#b'; $SD $FI s/a/b/ f" fail
sed_case "review F3 control: a real comment after the quoted text still hides it" tests/zz-sed.sh "echo \"(#1)\" # not $SD $FI s/a/b/ f" pass
sed_case "grep -i is not in-place sed"                tests/zz-sed.sh "grep $FI x f" pass
sed_case "sed -e script, no -i at all"           tests/zz-sed.sh "$SD -e 's/a/b/' f" pass
# the message tells what is wrong, not only where
C="$(mk_min_copy)"; printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$SD $FI 's/a/b/' f" > "$C/tests/zz-sed.sh"
checks "$C" sed
assert_contains "AC2.1 the failure mentions sed" "$OUT" "$SD"
# the repository itself stays clean and says so
# One real-tree full run feeds AC2.1, AC8.2 and AC4.3 (the same run on an unmodified copy gives the same output).
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
FULL_OUT="$OUT"; FULL_RC="$RC"
assert_rc "AC2.1 the real tree passes run-checks" 0
assert_contains "AC2.1 the ok line is printed" "$OUT" "  ok   $SD $FI has a suffix (BSD sed)"

# AC8.2: the default run (no --only) still contains the dupmax group (the real-tree full run from AC2.1)
OUT="$FULL_OUT"; RC="$FULL_RC"
assert_rc "AC8.2 the real tree passes a full run-checks" 0
assert_contains "AC8.2 the full run has the dupmax ok line" "$OUT" "  ok   regex repeat bounds <= 255 (BSD RE_DUP_MAX)"

# ---- v0.22.2 AC8.1: run-checks.sh --only SECTION ----
echo "v0.22.2 AC8.1 run-checks.sh --only SECTION runs one check group"
# the fixtures are built from variables, so this file does not trip its own checks
G2=grep; P2=-P; S3=sed; I3=-i; BIG2=$((255 + 45))
# fixture_gnu DIR / fixture_sed DIR / fixture_big DIR -> a flagged line 3 of tests/zz-only.sh
fixture_gnu() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$G2 $P2 'a' f >/dev/null" > "$1/tests/zz-only.sh"; }
fixture_sed() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$S3 $I3 's/a/b/' f" > "$1/tests/zz-only.sh"; }
fixture_big() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "grep -E 'a{0,${BIG2}}' f" > "$1/tests/zz-only.sh"; }
only_run() { run bash "$1/evals/run-checks.sh" --only "$2"; }
# other_groups_absent LABEL -> assert that OUT has no line of the other check groups
other_groups_absent() {
  assert_not_contains "$1: no skills line (name matches directory)" "$OUT" "name matches directory"
  assert_not_contains "$1: no eval scenarios line" "$OUT" "scenarios each have"
  assert_not_contains "$1: no always-on block heading" "$OUT" "always-on block"
  assert_not_contains "$1: no syntax line from the files group" "$OUT" "  ok   syntax:"
}

C="$(mk_min_copy)"; fixture_gnu "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only gnu on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
assert_contains "AC8.1 --only gnu on a flagged fixture: names the construct" "$OUT" "$G2 $P2"
assert_contains "AC8.1 --only gnu on a flagged fixture: ends with the problem count" "$OUT" "run-checks: 1 problem(s)"
other_groups_absent "AC8.1 --only gnu (flagged)"
assert_not_contains "AC8.1 --only gnu (flagged): no sed line" "$OUT" "has a suffix (BSD sed)"
assert_not_contains "AC8.1 --only gnu (flagged): no dupmax line" "$OUT" "regex repeat bounds"

C="$(mk_min_copy)"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only gnu on a clean fixture: the gnu ok line" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"
assert_contains "AC8.1 --only gnu on a clean fixture: run-checks: all ok" "$OUT" "run-checks: all ok"
other_groups_absent "AC8.1 --only gnu (clean)"

C="$(mk_min_copy)"
only_run "$C" bogus
assert_rc "AC8.1 --only bogus: exit 2" 2
assert_not_contains "AC8.1 --only bogus: no check ran (no ok line)" "$OUT" "  ok   "
C="$(mk_min_copy)"
run bash "$C/evals/run-checks.sh" --only
assert_rc "AC8.1 --only without a section: exit 2" 2

C="$(mk_min_copy)"; fixture_sed "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only sed on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only sed (flagged)"
assert_not_contains "AC8.1 --only sed (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_min_copy)"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only sed on a clean fixture: the sed ok line" "$OUT" "has a suffix (BSD sed)"

C="$(mk_min_copy)"; fixture_big "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only dupmax on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only dupmax (flagged)"
assert_not_contains "AC8.1 --only dupmax (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_min_copy)"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only dupmax on a clean fixture: the dupmax ok line" "$OUT" "regex repeat bounds <= 255"

echo "AC8.1 a section runs only its own rule: the other rules' flagged files are not reported"
C="$(mk_min_copy)"; fixture_gnu "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed ignores a gnu-flagged file: exit 0" 0
C="$(mk_min_copy)"; fixture_sed "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a sed-flagged file: exit 0" 0
C="$(mk_min_copy)"; fixture_big "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a repeat-bound-flagged file: exit 0" 0
C="$(mk_min_copy)"; fixture_gnu "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax ignores a gnu-flagged file: exit 0" 0

echo "AC8.1 the other sections: skills, scenarios, shellcheck"
C="$(mk_copy)"
only_run "$C" skills
assert_rc "AC8.1 --only skills on the real tree: exit 0" 0
assert_contains "AC8.1 --only skills: the skills lines are there" "$OUT" "name matches directory"
assert_not_contains "AC8.1 --only skills: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC8.1 --only skills: no scenarios line" "$OUT" "scenarios each have"
SKILLS_ONLY_OUT="$OUT"
C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
# the same tree also carries a stale word-budgets entry: the skills group's own wbstale call must name it (no extra run)
printf 'skills/gone/SKILL.md 100\n' >> "$C/evals/word-budgets"
only_run "$C" skills
assert_rc "AC8.1 --only skills on a bad description: exit 1" 1
assert_contains "AC8.1 --only skills on a bad description: names the SKILL.md" "$OUT" "$SKILL"
assert_contains "R1 --only skills: a stale word-budgets entry is named (skills group runs wbstale)" "$OUT" "skills/gone/SKILL.md: in evals/word-budgets but missing"
C="$(mk_copy)"
only_run "$C" scenarios
assert_rc "AC8.1 --only scenarios on the real tree: exit 0" 0
assert_contains "AC8.1 --only scenarios: the scenario lines are there" "$OUT" "scenarios each have Prompt:"
assert_not_contains "AC8.1 --only scenarios: no skills line" "$OUT" "name matches directory"
assert_not_contains "AC8.1 --only scenarios: no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" shellcheck
assert_rc "AC8.1 --only shellcheck on the real tree: exit 0" 0
assert_contains "AC8.1 --only shellcheck: a shellcheck line (ok or skip)" "$OUT" "shellcheck"
assert_not_contains "AC8.1 --only shellcheck: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC8.1 --only shellcheck: no skills line" "$OUT" "name matches directory"

echo "AC8.1 without --only every group runs"
# every group's lines come from the real-tree full run of AC2.1 (FULL_OUT); only the flagged-file exit code needs its own run, on the
# minimal tree (its run-checks fails anyway for what the minimal tree lacks, so the flagged file's own finding is asserted too)
OUT="$FULL_OUT"
for want in "name matches directory" "always-on block" "regex repeat bounds <= 255" "has a suffix (BSD sed)" "scenarios each have Prompt:" "syntax:"; do
  assert_contains "AC8.1 no --only: the full output has [$want]" "$OUT" "$want"
done
C="$(mk_min_copy)"
run bash "$C/evals/run-checks.sh"
n0="$(printf '%s\n' "$OUT" | sed -n 's/^run-checks: \([0-9][0-9]*\) problem.*/\1/p')"
C="$(mk_min_copy)"; fixture_gnu "$C"
run bash "$C/evals/run-checks.sh"
n1="$(printf '%s\n' "$OUT" | sed -n 's/^run-checks: \([0-9][0-9]*\) problem.*/\1/p')"
assert_eq "AC8.1 no --only: a gnu-flagged file adds exactly one problem to the same min-tree full run" "$((n0 + 1))" "$n1"
assert_contains "AC8.1 no --only: the full output has [GNU-only options (BSD/macOS lacks them]" "$OUT" "GNU-only options (BSD/macOS lacks them"
assert_contains "AC8.1 no --only: the flagged file:line is named" "$OUT" "tests/zz-only.sh:3"
# the word budgets run exactly once in a full run (always-on block for AGENTS.global.md, skills group for the skills): no line doubled, none lost
OUT="$FULL_OUT"
assert_eq "AC8.1 no --only: AGENTS.global.md's budget is checked once" "1" "$(printf '%s\n' "$OUT" | grep -c '^  ok   AGENTS.global.md: .* words (budget [0-9]*)$')"
assert_eq "AC8.1 no --only: each skill's budget is checked once" "$(ls "$PB_ROOT"/skills/*/SKILL.md | wc -l | tr -d ' ')" "$(printf '%s\n' "$OUT" | grep -c '^  ok   skills/.*/SKILL.md: .* words (budget [0-9]*)$')"
assert_contains "AC8.1 --only skills still includes the skills budget lines" "$SKILLS_ONLY_OUT" "  ok   $SKILL: "

# ---- v0.23.0 AC4.3: the control byte SOH (octal 1) in scripts is refused in every spelling (bash 3.2 on macOS) ----
# New check group: `evals/run-checks.sh --only soh`. Every construct is built from pieces (B = one backslash, Q = a single
# quote), so this file does not trip its own check. The message names file:line.
echo "v0.23.0 AC4.3 the SOH byte in any spelling (section soh)"
B='\'; Q="'"
# soh_case NAME FILE BODY-LINE EXPECT(fail|pass): queued, run by bq_flush soh (batched, v0.24.13)
soh_case() { bq_add soh "$@"; }
# every spelling is flagged
soh_case "printf with the octal escape"          tests/zz-soh.sh "printf ${Q}${B}001${Q}" fail
soh_case "ANSI-C quote with the octal escape"    tests/zz-soh.sh "x=\$${Q}${B}001${Q}" fail
soh_case "hex escape"                            tests/zz-soh.sh "printf ${Q}${B}x01${Q}" fail
soh_case "ANSI-C quote with the hex escape"      tests/zz-soh.sh "x=\$${Q}${B}x01${Q}" fail
soh_case "short octal escape"                    tests/zz-soh.sh "printf ${Q}${B}01${Q}" fail
soh_case "printf %b with the octal escape"       tests/zz-soh.sh "printf ${Q}%b${Q} ${Q}${B}001${Q}" fail
soh_case "tr with the octal escape"              tests/zz-soh.sh "tr ${Q}${B}001${Q} x" fail
soh_case "awk string with the octal escape"      tests/zz-soh.sh "awk ${Q}BEGIN { printf \"${B}001\" }${Q}" fail
soh_case "three backslashes: the last one escapes" tests/zz-soh.sh "printf ${Q}${B}${B}${B}001${Q}" fail
soh_case "inside double quotes"                  tests/zz-soh.sh "echo \"a${B}001b\"" fail
soh_case "mid-line after a semicolon"            tests/zz-soh.sh "x=1; printf ${Q}${B}001${Q}" fail
soh_case "no gnu-ok exemption"                   tests/zz-soh.sh "printf ${Q}${B}001${Q}   # gnu-ok: legacy fixture" fail
# in every scanned location
soh_case "evals/ file"       evals/zz-soh.sh   "printf ${Q}${B}001${Q}" fail
soh_case "scripts/ file"     scripts/zz-soh.sh "printf ${Q}${B}001${Q}" fail
soh_case "tools/ file"       tools/zz-soh.sh   "printf ${Q}${B}001${Q}" fail
soh_case "install.sh"        install.sh        "printf ${Q}${B}001${Q}" fail
soh_case "hex spelling in scripts/"  scripts/zz-soh.sh "printf ${Q}${B}x01${Q}" fail
soh_case "tr spelling in tools/"     tools/zz-soh.sh   "tr ${Q}${B}001${Q} x" fail
# not flagged
soh_case "a comment line mentioning it"      tests/zz-soh.sh "# uses ${B}001 and printf ${Q}${B}x01${Q} here" pass
soh_case "an indented comment line"          tests/zz-soh.sh "   # ${B}001 is CTLESC" pass
soh_case "a trailing comment mentioning it (as scripts/mutate.sh does)" tests/zz-soh.sh "soh=\"\$(printf ${Q}${B}034${Q})\"   # ASCII field separator: bash 3.2 uses ${B}001 internally" pass
soh_case "an escaped backslash before 01 (as tests/test-evals-grade5.sh does)" tests/zz-soh.sh "x=${Q}handoff${B}${B}01-spec.md${Q}" pass
soh_case "an escaped backslash before 01 in double quotes" tests/zz-soh.sh "echo \"handoff${B}${B}01-spec.md\"" pass
soh_case "an escaped backslash before 001"   tests/zz-soh.sh "printf ${Q}${B}${B}001${Q}" pass
soh_case "the field separator 034"           tests/zz-soh.sh "printf ${Q}${B}034${Q}" pass
soh_case "another escape (newline)" tests/zz-soh.sh "printf ${Q}${B}n${Q}" pass
soh_case "a path with 001 and no backslash"  tests/zz-soh.sh "cat tests/fixture-001.txt" pass

echo "v0.23.0 AC4.3 the real tree passes and says so"
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only soh
assert_rc "AC4.3 --only soh on the real tree: exit 0" 0
assert_contains "AC4.3 --only soh: run-checks: all ok" "$OUT" "run-checks: all ok"
assert_eq "AC4.3 --only soh prints exactly one ok line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  ok   ')"
assert_contains "AC4.3 the ok line names 001" "$(printf '%s\n' "$OUT" | grep '^  ok   ')" "001"
assert_not_contains "AC4.3 --only soh: no gnu line" "$OUT" "GNU-only options"
OUT="$FULL_OUT"; RC="$FULL_RC"   # the real-tree full run from AC2.1
assert_rc "AC4.3 the full run on the real tree: exit 0" 0
assert_eq "AC4.3 the full run has the soh ok line (001)" "1" "$(printf '%s\n' "$OUT" | grep '^  ok   ' | grep -c '001')"
C="$(mk_min_copy)"
printf '#!/usr/bin/env bash\n# fixture\n%s\n' "printf ${Q}${B}001${Q}" > "$C/tests/zz-soh.sh"
run bash "$C/evals/run-checks.sh" --only gnu
assert_rc "AC4.3 --only gnu ignores a soh-flagged file: exit 0" 0
run bash "$C/evals/run-checks.sh" --only sed
assert_rc "AC4.3 --only sed ignores a soh-flagged file: exit 0" 0

# ---- v0.24.25: the soh scan under a UTF-8 locale (macOS awk is multibyte aware; its per-character split failed on a UTF-8 script) ----
echo "v0.24.25 the soh scan runs under LC_ALL=C and explains its own failure"
# (1) a scanned script with a UTF-8 multibyte character (U+2019) right before a backslash escape: still exit 0 under a UTF-8 locale
UTFLOC=""
for l in en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
  if LC_ALL="$l" bash -c 'exit 0' 2>/dev/null && locale -a 2>/dev/null | grep -q -x -e "$l" -e "$(printf '%s' "$l" | tr 'A-Z' 'a-z')"; then UTFLOC="$l"; break; fi
done
if [ -n "$UTFLOC" ]; then
  C="$(mk_min_copy)"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "echo it$(printf '\342\200\231')s ${B}n ${B}${B}01" > "$C/tests/zz-soh-utf.sh"
  run env LC_ALL="$UTFLOC" bash "$C/evals/run-checks.sh" --only soh
  assert_rc "v0.24.25 --only soh with a UTF-8 character beside a backslash escape ($UTFLOC): exit 0" 0
  assert_contains "v0.24.25 the same run prints the ok line" "$OUT" "  ok   no SOH byte"
else
  t_ok "v0.24.25 no UTF-8 locale installed: the multibyte case is skipped"
fi
# (2) a failing awk: the reason (its stderr) is printed after the FAIL line
C="$(mk_min_copy)"; SHIM="$(mk_tmp)"
printf '#!/bin/sh\necho "shim-awk: boom on stderr" >&2\nexit 2\n' > "$SHIM/awk"; chmod +x "$SHIM/awk"
run env PATH="$SHIM:$PATH" bash "$C/evals/run-checks.sh" --only soh
assert_contains "v0.24.25 a failing awk is reported as SOH scan failed" "$OUT" "SOH scan failed (awk exit 2"
assert_contains "v0.24.25 the awk stderr is shown after the failure" "$OUT" "shim-awk: boom on stderr"
# (3) static pins: the soh awk and the gnu awk run byte-wise (LC_ALL=C); SOH is one ASCII byte, so the findings do not change
RCSRC="$(cat "$PB_ROOT/evals/run-checks.sh")"
assert_contains "v0.24.25 the soh awk runs under LC_ALL=C" "$RCSRC" 'gsoh="$(LC_ALL=C awk "$AWKSTRIP"'
assert_contains "v0.24.25 the gnu awk runs under LC_ALL=C" "$RCSRC" "ggnu=\"\$(LC_ALL=C awk '"

# ---- v0.23.0 review: four-digit octal, what the soh check documents as not covered, executable bits ----
echo "v0.23.0 review: AC4.3 four digits"
soh_case "printf %b with a four-digit octal escape" tests/zz-soh.sh "printf ${Q}%b${Q} ${Q}${B}0001${Q}" fail
soh_case "four-digit octal escape in a plain printf" tests/zz-soh.sh "printf ${Q}${B}0001${Q}" fail

echo "v0.23.0 review: the soh block documents what it does not cover"
SOHBLK="$(awk '/^if want soh; then/ { f = 1 } f && /^#/ { print } f && /^fi$/ { exit }' "$PB_ROOT/evals/run-checks.sh")"
if [ -n "$SOHBLK" ]; then t_ok "the soh block in evals/run-checks.sh has comment lines"; else t_bad "the soh block in evals/run-checks.sh has comment lines" "no '# ' lines between 'if want soh' and 'fi'"; fi
assert_contains "the soh comment mentions the short escape (backslash 1)" "$SOHBLK" "${B}1"
assert_contains "the soh comment mentions the short hex escape (backslash x1)" "$SOHBLK" "${B}x1"
assert_contains "the soh comment mentions the control escape (backslash cA)" "$SOHBLK" "${B}cA"
assert_contains "the soh comment says these are not covered" "$(printf '%s' "$SOHBLK" | tr 'A-Z' 'a-z')" "not covered"

# ---- v0.23.2 AC16.1: a file glob that matches nothing fails its section (a renamed directory is not a silent pass) ----
# Sections covered: dupmax, sed, gnu, soh (globs tests/*.sh, scripts/*.sh, tools/*.sh), skills (skills/*/), shellcheck (scripts/*.sh,
# tools/*.sh; only where shellcheck is installed) and the full run (the files group loops over the same globs).
# evals/*.sh is not emptied: evals/run-checks.sh itself always matches it. A directory is renamed, never globbed away.
echo "v0.23.2 AC16.1 a glob that matches no file is reported and fails the section"
# glob_case SECTION DIR GLOB [full] -> in a copy whose DIR is renamed, run-checks --only SECTION says "no files match GLOB" and exits 1
# (the minimal tree has a stub for every glob; "full" uses the whole tree, which the shellcheck section needs)
glob_case() {
  local sec="$1" dir="$2" glob="$3"
  if [ "${4:-}" = full ]; then C="$(mk_copy)"; else C="$(mk_min_copy)"; fi
  mv "$C/$dir" "$C/$dir-renamed"
  run bash "$C/evals/run-checks.sh" --only "$sec"
  assert_rc "AC16.1 [$sec] $dir/ renamed: exit 1" 1
  assert_contains "AC16.1 [$sec] $dir/ renamed: reports no files match $glob" "$OUT" "no files match $glob"
}
# corpus first: the real tree has files for every glob, so each section passes and never says it
C="$(mk_copy)"
for sec in dupmax sed gnu soh; do
  run bash "$C/evals/run-checks.sh" --only "$sec"
  assert_rc "AC16.1 the real tree passes --only $sec" 0
  assert_not_contains "AC16.1 the real tree: --only $sec never says no files match" "$OUT" "no files match"
done
for sec in dupmax sed gnu soh; do
  glob_case "$sec" tools   'tools/*.sh'
  glob_case "$sec" scripts 'scripts/*.sh'
  glob_case "$sec" tests   'tests/*.sh'
done
# only the empty glob is named
C="$(mk_min_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh" --only gnu
assert_not_contains "AC16.1 only the empty glob is named (scripts/*.sh matches, so it is not reported)" "$OUT" "no files match scripts/*.sh"
assert_not_contains "AC16.1 only the empty glob is named (tests/*.sh matches, so it is not reported)" "$OUT" "no files match tests/*.sh"
# a section that does not read the glob does not fail for it
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh" --only scenarios
assert_rc "AC16.1 --only scenarios does not read tools/*.sh: exit 0" 0
# skills
C="$(mk_copy)"; mv "$C/skills" "$C/skills-renamed"
run bash "$C/evals/run-checks.sh" --only skills
assert_rc "AC16.1 [skills] skills/ renamed: exit 1" 1
assert_contains "AC16.1 [skills] skills/ renamed: reports no files match skills/*" "$OUT" "no files match skills/*"
# the section named for that tool, run only where it is installed
if command -v shellcheck >/dev/null 2>&1; then
  glob_case shellcheck tools   'tools/*.sh' full
  glob_case shellcheck scripts 'scripts/*.sh' full
else
  t_skip 4 "AC16.1 [shellcheck] needs shellcheck installed"
fi
# the files group (the one the full run takes these messages from) loops over the same globs
# one run renames both directories and feeds both groups of assertions
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"; mv "$C/scripts" "$C/scripts-renamed"
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC16.1 [--only files] tools/ renamed: exit 1" 1
assert_contains "AC16.1 [--only files] tools/ renamed: reports no files match tools/*.sh" "$OUT" "no files match tools/*.sh"
assert_rc "AC16.1 [--only files] scripts/ renamed: exit 1" 1
assert_contains "AC16.1 [--only files] scripts/ renamed: reports no files match scripts/*.sh" "$OUT" "no files match scripts/*.sh"


# ---- v0.23.3 AC7.3: a # right after ; & | ( ) starts a comment in the sed check too ----
echo "v0.23.3 AC7.3 the sed check strips a comment that starts right after an operator"
sed_case "a comment right after ';' mentioning it" tests/zz-sed.sh "true;# $SD $FI x f" pass
sed_case "a comment right after '|' mentioning it" tests/zz-sed.sh "a|# $SD $FI x f" pass
sed_case "a comment right after '&' mentioning it" tests/zz-sed.sh "true &# $SD $FI x f" pass
sed_case "a comment right after '(' mentioning it" tests/zz-sed.sh "(# $SD $FI x f" pass
sed_case "a comment right after ')' mentioning it" tests/zz-sed.sh "( true )# $SD $FI x f" pass
sed_case "a comment right after '&&' mentioning it" tests/zz-sed.sh "true &&# $SD $FI x f" pass
sed_case "control: code after ';' is still flagged" tests/zz-sed.sh "true;$SD $FI x f" fail
sed_case "control: code before a comment after ';' is still flagged" tests/zz-sed.sh "$SD $FI x f;# done" fail
sed_case "control: a # inside a word is not a comment" tests/zz-sed.sh "echo a#b; $SD $FI x f" fail

echo "v0.21.0/v0.23.3 AC2.1 AC7.3 the in-place sed cases above, one run per expectation"
bq_flush sed AC2.1 sed

# ---- v0.23.3 AC7.3: strip() starts a comment after ; & | ( ) as scan() does ----
echo "v0.23.3 AC7.3 the soh check strips a comment that starts right after an operator"
soh_case "a comment right after ';' mentioning the escape" tests/zz-soh.sh "true;# ${B}001" pass
soh_case "a comment right after '|' mentioning the escape" tests/zz-soh.sh "a|# ${B}001" pass
soh_case "a comment right after '&' mentioning the escape" tests/zz-soh.sh "true &# ${B}001" pass
soh_case "a comment right after '(' mentioning the escape" tests/zz-soh.sh "(# ${B}001" pass
soh_case "a comment right after ')' mentioning the escape" tests/zz-soh.sh "( true )# ${B}001" pass
soh_case "control: the escape in code after ';' is still flagged" tests/zz-soh.sh "true;printf ${Q}${B}001${Q}" fail
soh_case "control: the escape in code before a comment after ';' is still flagged" tests/zz-soh.sh "printf ${Q}${B}001${Q};# done" fail
soh_case "control: a # inside a word is not a comment" tests/zz-soh.sh "echo a#b; printf ${Q}${B}001${Q}" fail
soh_case "control: a # inside quotes after ';' is not a comment" tests/zz-soh.sh "true; echo ${Q}a#${B}001${Q}" fail

echo "v0.23.0/v0.23.3 AC4.3 the SOH cases above, one run per expectation"
bq_flush soh AC4.3 soh


echo "v0.24.10 AC4 run-checks: references/quick.md is no longer required and its section has no word cap"
# a tree without references/quick.md passes the skills group; a stray quick.md is not checked (the v0.24.0 cap of 250 words is gone)
words_of() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "w%d%s", i, (i % 12 == 0 ? "\n" : " "); printf "\n" }'; }
C="$(mk_copy)"; rm -f "$C/skills/playbook-tdd/references/quick.md"
checks "$C" skills
assert_rc "v24.10 AC4 a tree without references/quick.md passes the skills section" 0
assert_not_contains "v24.10 AC4 a tree without references/quick.md: no output names quick.md" "$OUT" "quick.md"
C="$(mk_copy)"; q="$C/skills/playbook-tdd/references/quick.md"; mkdir -p "$(dirname "$q")"
{ printf '# Quick\n\n## Quick workflow\n'; words_of 400; } > "$q"
checks "$C" skills
assert_rc "v24.10 AC4 a stray quick.md with a 400-word Quick workflow section is not checked: exit 0" 0
assert_not_contains "v24.10 AC4 a stray quick.md: no word-cap failure" "$OUT" "Quick workflow"
C="$(mk_copy)"
checks "$C" skills
assert_not_contains "v24.10 AC4 the real tree: no failure about quick.md" "$OUT" "quick.md"
assert_rc "v24.10 AC4 the real tree passes the skills section" 0

echo "v0.24.4 AC6 dupmax, sed and soh fail closed: a missing file in the scanned list is a FAIL, never an ok"
# install.sh is named in each scan list; when it is missing awk or grep reads nothing of it, and the section used to print ok and exit 0.
for sec in dupmax sed soh; do
  C="$(mk_min_copy)"
  rm -f "$C/install.sh"
  only_run "$C" "$sec"
  assert_rc "AC6 --only $sec, install.sh missing: exit 1" 1
  assert_contains "AC6 --only $sec, install.sh missing: a FAIL line" "$OUT" "FAIL"
  assert_contains "AC6 --only $sec, install.sh missing: names the missing file" "$OUT" "missing file install.sh"
  assert_not_contains "AC6 --only $sec, install.sh missing: no ok line" "$OUT" "  ok   "
  C="$(mk_copy)"
  only_run "$C" "$sec"
  assert_rc "AC6 --only $sec, real tree: exit 0" 0
  assert_not_contains "AC6 --only $sec, real tree: no missing-file line" "$OUT" "missing file"
done

echo "v0.24.4 review F3 dupmax, sed and soh fail closed on a scanned file that cannot be read"
# a stub in tests/ with no read permission: grep or awk exits non-zero on it, and the section must say FAIL, never ok (mutant M5: soh 'elif false')
for sec in dupmax sed soh; do
  C="$(mk_min_copy)"
  printf '#!/usr/bin/env bash\n# fixture\n' > "$C/tests/zz.sh"
  chmod 000 "$C/tests/zz.sh"
  if [ "$(id -u)" = 0 ] || [ -r "$C/tests/zz.sh" ]; then
    chmod 644 "$C/tests/zz.sh"
    t_skip 3 "F3 --only $sec, unreadable tests/zz.sh (running as root, or chmod 000 leaves the file readable here)"
    continue
  fi
  only_run "$C" "$sec"
  chmod 644 "$C/tests/zz.sh"
  assert_rc "F3 --only $sec, tests/zz.sh unreadable: exit 1" 1
  assert_contains "F3 --only $sec, tests/zz.sh unreadable: a FAIL line" "$OUT" "FAIL"
  assert_not_contains "F3 --only $sec, tests/zz.sh unreadable: no ok line" "$OUT" "  ok   "
done

echo "v0.24.8 word budgets: evals/word-budgets holds one budget per skills/*/SKILL.md and one for AGENTS.global.md; run-checks fails a file over its budget"
# wc output is space-padded on BSD, so every count goes through tr -d ' '. The cases write their own budget table into the copy (file + slack), so they
# do not depend on today's sizes; the real table is checked as itself in the last cases.
WB_SLACK=10
# The budget cases run `--only budgets` (v0.24.12), which reads only AGENTS.global.md, skills/*/SKILL.md, evals/word-budgets and the script itself:
# WBMASTER holds exactly those (each case then rewrites the table and one file), so a case costs a fraction of a second instead of a tree copy plus a group run.
WBMASTER="$(mk_tmp)"
mkdir -p "$WBMASTER/evals"
cp "$MASTER/evals/run-checks.sh" "$MASTER/evals/word-budgets" "$WBMASTER/evals/"
cp "$MASTER/AGENTS.global.md" "$WBMASTER/"
for f in "$MASTER"/skills/*/SKILL.md; do
  d="$WBMASTER/skills/$(basename "$(dirname "$f")")"; mkdir -p "$d"; cp -a "$f" "$d/"
done
mk_wb_copy() { local d; d="$(mk_tmp)"; cp -a "$WBMASTER/." "$d/"; printf '%s\n' "$d"; }
wcw() { wc -w < "$1" | tr -d ' '; }
# wb_table DIR -> evals/word-budgets in DIR: AGENTS.global.md and every skills/*/SKILL.md at its current words + WB_SLACK
wb_table() {
  local d="$1" f
  {
    printf '# fixture budgets\n\n'
    for f in AGENTS.global.md "$d"/skills/*/SKILL.md; do
      case "$f" in "$d"/*) f="${f#"$d"/}" ;; esac
      printf '%s %s\n' "$f" "$(( $(wcw "$d/$f") + WB_SLACK ))"
    done
  } > "$d/evals/word-budgets"
}
# wb_pad DIR FILE N -> append one line of N words to FILE
wb_pad() { { printf '\n'; words_of "$3"; } >> "$1/$2"; }
# the real table exists and names every skill and the always-on block
assert_file "AC1 evals/word-budgets exists" "$PB_ROOT/evals/word-budgets"
for f in AGENTS.global.md "$PB_ROOT"/skills/*/SKILL.md; do
  f="${f#"$PB_ROOT"/}"
  if grep -Eq "^${f}[[:space:]]+[0-9]+" "$PB_ROOT/evals/word-budgets" 2>/dev/null; then t_ok "AC1 evals/word-budgets has an entry for $f"; else t_bad "AC1 evals/word-budgets has an entry for $f"; fi
done
if grep -qi 'raising a budget needs a CHANGELOG line' "$PB_ROOT/evals/word-budgets" 2>/dev/null; then t_ok "AC1 the table header carries the rule (a budget raise needs a CHANGELOG line)"; else t_bad "AC1 the table header carries the rule (a budget raise needs a CHANGELOG line)"; fi


# --only budgets prints only budget lines (v0.24.12): the heading, one ok line per budgeted file, the summary
C="$(mk_wb_copy)"
run bash "$C/evals/run-checks.sh" --only budgets
nskills="$(ls "$C"/skills/*/SKILL.md | wc -l | tr -d ' ')"
assert_rc "AC2 --only budgets on the real table: exit 0" 0
assert_contains "AC2 --only budgets: run-checks: all ok" "$OUT" "run-checks: all ok"
assert_contains "AC2 --only budgets: the AGENTS.global.md budget line" "$OUT" "  ok   AGENTS.global.md: "
assert_contains "AC2 --only budgets: a skill budget line" "$OUT" "  ok   $SKILL: "
assert_eq "AC2 --only budgets: one ok line per budgeted file" "$((nskills + 1))" "$(printf '%s\n' "$OUT" | grep -c '^  ok   ')"
assert_eq "AC2 --only budgets: every ok line is a budget line" "$((nskills + 1))" "$(printf '%s\n' "$OUT" | grep -c '^  ok   .* words (budget [0-9]*)$')"
assert_not_contains "AC2 --only budgets: no skills line (name matches directory)" "$OUT" "name matches directory"
assert_not_contains "AC2 --only budgets: no always-on block heading" "$OUT" "always-on block"
assert_not_contains "AC2 --only budgets: no clarify-sentence line" "$OUT" "clarify sentence"
assert_not_contains "AC2 --only budgets: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC2 --only budgets: no scenarios line" "$OUT" "scenarios each have"
assert_not_contains "AC2 --only budgets: no syntax line" "$OUT" "  ok   syntax:"
assert_not_contains "AC2 --only budgets: no description-length line" "$OUT" "description "
# the usage and unknown-section messages name it
run bash "$C/evals/run-checks.sh" --only bogus
assert_rc "AC2 --only bogus: exit 2" 2
assert_contains "AC2 the unknown-section message names budgets" "$OUT" "budgets"
run bash "$C/evals/run-checks.sh" --only
assert_contains "AC2 the usage message names budgets" "$OUT" "budgets"
# the real tree passes the skills group
C="$(mk_wb_copy)"
checks "$C" budgets
assert_rc "AC2 the real tree passes the word budgets (--only budgets)" 0
assert_not_contains "AC2 the real tree: no budget failure" "$OUT" "over its budget"

# a skill 1 word over its budget fails and the output names file, count and budget
C="$(mk_wb_copy)"; wb_table "$C"
b="$(( $(wcw "$C/$SKILL") + WB_SLACK ))"
wb_pad "$C" "$SKILL" $((WB_SLACK + 1))
checks "$C" budgets
assert_rc "AC3 a SKILL.md 1 word over its budget: exit 1" 1
assert_contains "AC3 names the file" "$OUT" "$SKILL"
assert_contains "AC3 says over its budget" "$OUT" "over its budget"
assert_contains "AC3 names its count" "$OUT" "$((b + 1)) words"
assert_contains "AC3 names its budget" "$OUT" "budget of $b"

# exactly at its budget passes
C="$(mk_wb_copy)"; wb_table "$C"
wb_pad "$C" "$SKILL" "$WB_SLACK"
checks "$C" budgets
assert_rc "AC4 a SKILL.md exactly at its budget: exit 0" 0
assert_not_contains "AC4 no budget failure" "$OUT" "over its budget"

# every skill is checked, not only one: the largest skill over its budget by 1 fails
C="$(mk_wb_copy)"; wb_table "$C"
big=skills/playbook-tdd/SKILL.md
wb_pad "$C" "$big" $((WB_SLACK + 1))
checks "$C" budgets
assert_rc "AC3 playbook-tdd 1 over: exit 1" 1
assert_contains "AC3 playbook-tdd 1 over: names it" "$OUT" "$big"

# a skill with no budget entry fails with a clear message
C="$(mk_wb_copy)"; wb_table "$C"
grep -v "^$SKILL " "$C/evals/word-budgets" > "$C/evals/word-budgets.new" && mv "$C/evals/word-budgets.new" "$C/evals/word-budgets"
checks "$C" budgets
assert_rc "AC5 a skill without a budget entry: exit 1" 1
assert_contains "AC5 names the skill file" "$OUT" "$SKILL"
assert_contains "AC5 says it has no word budget" "$OUT" "no word budget"

# a missing table fails closed
C="$(mk_wb_copy)"; rm -f "$C/evals/word-budgets"
checks "$C" budgets
assert_rc "AC5 evals/word-budgets missing: exit 1" 1
assert_contains "AC5 evals/word-budgets missing: names the file" "$OUT" "word-budgets"

# AGENTS.global.md has its own budget (checked through --only budgets)
C="$(mk_wb_copy)"; wb_table "$C"
b="$(( $(wcw "$C/AGENTS.global.md") + WB_SLACK ))"
wb_pad "$C" AGENTS.global.md $((WB_SLACK + 1))
checks "$C" budgets
assert_rc "AC3 AGENTS.global.md 1 word over its budget: exit 1" 1
assert_contains "AC3 AGENTS.global.md: names the file and the overrun" "$OUT" "AGENTS.global.md: $((b + 1)) words, over its budget of $b"
C="$(mk_wb_copy)"; wb_table "$C"
wb_pad "$C" AGENTS.global.md "$WB_SLACK"
checks "$C" budgets
assert_not_contains "AC4 AGENTS.global.md exactly at its budget: no budget failure" "$OUT" "over its budget"
C="$(mk_wb_copy)"; wb_table "$C"
grep -v '^AGENTS.global.md ' "$C/evals/word-budgets" > "$C/evals/word-budgets.new" && mv "$C/evals/word-budgets.new" "$C/evals/word-budgets"
checks "$C" budgets
assert_contains "AC5 AGENTS.global.md without a budget entry: says no word budget" "$OUT" "no word budget"

# review 1 (v0.24.8): CRLF table without comments, a missing file, a stale table entry
# a CRLF table whose lines carry no trailing comment still parses (the \r is not part of the number)
C="$(mk_wb_copy)"; wb_table "$C"; to_crlf "$C/evals/word-budgets"
checks "$C" budgets
assert_rc "R1 a CRLF budget table without comments, counts within budget: exit 0" 0
assert_not_contains "R1 a CRLF table without comments: no 'no word budget' failure" "$OUT" "no word budget"
C="$(mk_wb_copy)"; wb_table "$C"; to_crlf "$C/evals/word-budgets"
b="$(( $(wcw "$C/$SKILL") + WB_SLACK ))"
wb_pad "$C" "$SKILL" $((WB_SLACK + 1))
checks "$C" budgets
assert_rc "R1 a CRLF budget table, 1 word over: exit 1" 1
assert_contains "R1 a CRLF budget table, 1 word over: says over its budget with the budget" "$OUT" "over its budget of $b"

# a missing file is "missing, no word count", never "over its budget"
C="$(mk_wb_copy)"; wb_table "$C"; rm -f "$C/AGENTS.global.md"
checks "$C" budgets
assert_rc "R1 AGENTS.global.md deleted: exit 1" 1
assert_contains "R1 a missing file says missing, no word count" "$OUT" "AGENTS.global.md: missing, no word count"
assert_not_contains "R1 a missing file is not reported as over its budget" "$OUT" "over its budget"

# a table entry for a file that does not exist is a failure
C="$(mk_wb_copy)"; wb_table "$C"
printf 'skills/gone/SKILL.md 100\n' >> "$C/evals/word-budgets"
checks "$C" budgets
assert_rc "R1 a stale table entry: exit 1" 1
assert_contains "R1 a stale entry names the path and says in evals/word-budgets but missing" "$OUT" "skills/gone/SKILL.md: in evals/word-budgets but missing"
C="$(mk_wb_copy)"; wb_table "$C"
checks "$C" budgets
assert_not_contains "R1 no stale entry in a table of existing files" "$OUT" "in evals/word-budgets but missing"

t_summary
