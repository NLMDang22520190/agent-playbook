#!/usr/bin/env bash
# Tests of evals/run-checks.sh sections dupmax, sed, soh, the --only SECTION switch and the empty-glob report (split from test-run-checks.sh in v0.23.3).
# Each test runs run-checks.sh inside a fresh copy of the repository (tracked + untracked, non-ignored files), so mutations
# never touch the real tree. Shared setup: run-checks-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"

echo "v0.13.0 AC6.1 regex repeat bounds above 255 (BSD/macOS RE_DUP_MAX) are refused"
# The bound is built at run time: a literal one in this file would fail the real run-checks.
# bound_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
bound_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" dupmax
  if [ "$expect" = fail ]; then
    assert_rc "AC6.1 $name: exit 1" 1
    assert_contains "AC6.1 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC6.1 $name: exit 0" 0
    assert_not_contains "AC6.1 $name: the file is not named" "$OUT" "$rel"
  fi
}
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
# the message tells what is wrong, not only where
C="$(mk_copy)"; printf '#!/usr/bin/env bash\n# fixture\ngrep -E %s f\n' "'a{,${BIG}}'" > "$C/tools/zz-bound.sh"
checks "$C" dupmax
assert_contains "AC7.1 the failure mentions the repeat bound" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "bound"


echo "v0.21.0 AC2.1 GNU-only in-place sed (no attached suffix) is refused; BSD sed needs one"
# The commands are built at run time: a literal one in this file would fail the real run-checks.
SD=sed; FI=-i
# sed_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
sed_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" sed
  if [ "$expect" = fail ]; then
    assert_rc "AC2.1 $name: exit 1" 1
    assert_contains "AC2.1 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC2.1 $name: exit 0" 0
    assert_not_contains "AC2.1 $name: the file is not named" "$OUT" "$rel"
  fi
}
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
sed_case "grep -i is not in-place sed"                tests/zz-sed.sh "grep $FI x f" pass
sed_case "sed -e script, no -i at all"           tests/zz-sed.sh "$SD -e 's/a/b/' f" pass
# the message tells what is wrong, not only where
C="$(mk_copy)"; printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$SD $FI 's/a/b/' f" > "$C/tests/zz-sed.sh"
checks "$C" sed
assert_contains "AC2.1 the failure mentions sed" "$OUT" "$SD"
# the repository itself stays clean and says so
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC2.1 the real tree passes run-checks" 0
assert_contains "AC2.1 the ok line is printed" "$OUT" "  ok   $SD $FI has a suffix (BSD sed)"

# AC8.2: the default run (no --only) still contains the dupmax group
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
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

C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only gnu on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
assert_contains "AC8.1 --only gnu on a flagged fixture: names the construct" "$OUT" "$G2 $P2"
assert_contains "AC8.1 --only gnu on a flagged fixture: ends with the problem count" "$OUT" "run-checks: 1 problem(s)"
other_groups_absent "AC8.1 --only gnu (flagged)"
assert_not_contains "AC8.1 --only gnu (flagged): no sed line" "$OUT" "has a suffix (BSD sed)"
assert_not_contains "AC8.1 --only gnu (flagged): no dupmax line" "$OUT" "regex repeat bounds"

C="$(mk_copy)"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only gnu on a clean fixture: the gnu ok line" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"
assert_contains "AC8.1 --only gnu on a clean fixture: run-checks: all ok" "$OUT" "run-checks: all ok"
other_groups_absent "AC8.1 --only gnu (clean)"

C="$(mk_copy)"
only_run "$C" bogus
assert_rc "AC8.1 --only bogus: exit 2" 2
assert_not_contains "AC8.1 --only bogus: no check ran (no ok line)" "$OUT" "  ok   "
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only
assert_rc "AC8.1 --only without a section: exit 2" 2

C="$(mk_copy)"; fixture_sed "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only sed on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only sed (flagged)"
assert_not_contains "AC8.1 --only sed (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only sed on a clean fixture: the sed ok line" "$OUT" "has a suffix (BSD sed)"

C="$(mk_copy)"; fixture_big "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only dupmax on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only dupmax (flagged)"
assert_not_contains "AC8.1 --only dupmax (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only dupmax on a clean fixture: the dupmax ok line" "$OUT" "regex repeat bounds <= 255"

echo "AC8.1 a section runs only its own rule: the other rules' flagged files are not reported"
C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed ignores a gnu-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_sed "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a sed-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_big "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a repeat-bound-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax ignores a gnu-flagged file: exit 0" 0

echo "AC8.1 the other sections: skills, scenarios, shellcheck"
C="$(mk_copy)"
only_run "$C" skills
assert_rc "AC8.1 --only skills on the real tree: exit 0" 0
assert_contains "AC8.1 --only skills: the skills lines are there" "$OUT" "name matches directory"
assert_not_contains "AC8.1 --only skills: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC8.1 --only skills: no scenarios line" "$OUT" "scenarios each have"
C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
only_run "$C" skills
assert_rc "AC8.1 --only skills on a bad description: exit 1" 1
assert_contains "AC8.1 --only skills on a bad description: names the SKILL.md" "$OUT" "$SKILL"
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
C="$(mk_copy)"; fixture_gnu "$C"
run bash "$C/evals/run-checks.sh"
assert_rc "AC8.1 no --only: a gnu-flagged file fails the full run" 1
for want in "name matches directory" "always-on block" "regex repeat bounds <= 255" "has a suffix (BSD sed)" "GNU-only options (BSD/macOS lacks them" "scenarios each have Prompt:" "syntax:"; do
  assert_contains "AC8.1 no --only: the full output has [$want]" "$OUT" "$want"
done

# ---- v0.23.0 AC4.3: the control byte SOH (octal 1) in scripts is refused in every spelling (bash 3.2 on macOS) ----
# New check group: `evals/run-checks.sh --only soh`. Every construct is built from pieces (B = one backslash, Q = a single
# quote), so this file does not trip its own check. The message names file:line.
echo "v0.23.0 AC4.3 the SOH byte in any spelling (section soh)"
B='\'; Q="'"
# soh_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
soh_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" soh
  if [ "$expect" = fail ]; then
    assert_rc "AC4.3 $name: exit 1" 1
    assert_contains "AC4.3 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC4.3 $name: exit 0" 0
    assert_not_contains "AC4.3 $name: the file is not named" "$OUT" "$rel"
  fi
}
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
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC4.3 the full run on the real tree: exit 0" 0
assert_eq "AC4.3 the full run has the soh ok line (001)" "1" "$(printf '%s\n' "$OUT" | grep '^  ok   ' | grep -c '001')"
C="$(mk_copy)"
printf '#!/usr/bin/env bash\n# fixture\n%s\n' "printf ${Q}${B}001${Q}" > "$C/tests/zz-soh.sh"
run bash "$C/evals/run-checks.sh" --only gnu
assert_rc "AC4.3 --only gnu ignores a soh-flagged file: exit 0" 0
run bash "$C/evals/run-checks.sh" --only sed
assert_rc "AC4.3 --only sed ignores a soh-flagged file: exit 0" 0

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
# glob_case SECTION DIR GLOB -> in a copy whose DIR is renamed, run-checks --only SECTION says "no files match GLOB" and exits 1
glob_case() {
  local sec="$1" dir="$2" glob="$3"
  C="$(mk_copy)"
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
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh" --only gnu
assert_not_contains "AC16.1 only the empty glob is named (scripts/*.sh matches, so it is not reported)" "$OUT" "no files match scripts/*.sh"
assert_not_contains "AC16.1 only the empty glob is named (tests/*.sh matches, so it is not reported)" "$OUT" "no files match tests/*.sh"
# a section that does not read the glob does not fail for it
run bash "$C/evals/run-checks.sh" --only scenarios
assert_rc "AC16.1 --only scenarios does not read tools/*.sh: exit 0" 0
# skills
C="$(mk_copy)"; mv "$C/skills" "$C/skills-renamed"
run bash "$C/evals/run-checks.sh" --only skills
assert_rc "AC16.1 [skills] skills/ renamed: exit 1" 1
assert_contains "AC16.1 [skills] skills/ renamed: reports no files match skills/*" "$OUT" "no files match skills/*"
# shellcheck, where it is installed
if command -v shellcheck >/dev/null 2>&1; then
  glob_case shellcheck tools   'tools/*.sh'
  glob_case shellcheck scripts 'scripts/*.sh'
else
  t_skip 4 "AC16.1 [shellcheck] needs shellcheck installed"
fi
# the full run: the files group loops over the same globs
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh"
assert_rc "AC16.1 [full run] tools/ renamed: exit 1" 1
assert_contains "AC16.1 [full run] tools/ renamed: reports no files match tools/*.sh" "$OUT" "no files match tools/*.sh"
C="$(mk_copy)"; mv "$C/scripts" "$C/scripts-renamed"
run bash "$C/evals/run-checks.sh"
assert_rc "AC16.1 [full run] scripts/ renamed: exit 1" 1
assert_contains "AC16.1 [full run] scripts/ renamed: reports no files match scripts/*.sh" "$OUT" "no files match scripts/*.sh"


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

t_summary
