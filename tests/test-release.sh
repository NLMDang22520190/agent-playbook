#!/usr/bin/env bash
# Tests for tools/check-release.sh (AC3) and the release job in .github/workflows/test.yml (AC4).
# Contract: check-release.sh reads VERSION and CHANGELOG.md from the repository root, i.e. the
# parent of the directory the script lives in (same as evals/run-checks.sh). Each test copies the
# script into <tmp>/tools/ and writes <tmp>/VERSION and <tmp>/CHANGELOG.md next to it.
. "$(dirname "$0")/lib.sh"
SRC="$PB_ROOT/tools/check-release.sh"

CL='# Changelog

## 1.2.3 - 2026-10-09
- first line
- second line: with a colon
  continued

## 1.2.2 - 2026-10-01
- older entry
'

# mk_rel VERSION CHANGELOG -> prints a temp root holding tools/check-release.sh, VERSION, CHANGELOG.md
mk_rel() {
  local d; d="$(mk_tmp)"
  mkdir -p "$d/tools"
  [ -f "$SRC" ] && cp -p "$SRC" "$d/tools/check-release.sh"
  printf '%s\n' "$1" > "$d/VERSION"
  printf '%s' "$2" > "$d/CHANGELOG.md"
  printf '%s\n' "$d"
}

echo "check-release (AC3)"
assert_file "AC3 tools/check-release.sh exists" "$SRC"

D="$(mk_rel 1.2.3 "$CL")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC3 matching tag, VERSION and changelog entry: exit 0" 0

D="$(mk_rel 1.2.4 "$CL")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC3 VERSION 1.2.4 vs tag v1.2.3: exit 1" 1
assert_contains "AC3 version mismatch message names VERSION" "$OUT" "VERSION"

D="$(mk_rel 1.2.4 "$CL")"
run bash "$D/tools/check-release.sh" v1.2.4
assert_rc "AC3 no '## 1.2.4 ' in CHANGELOG.md: exit 1" 1
assert_contains "AC3 missing entry message names CHANGELOG" "$OUT" "CHANGELOG"

D="$(mk_rel 1.2.3 '# Changelog

## 1.2.30 - 2026-10-09
- not the same version
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC3 '## 1.2.30 ' does not count as the entry for 1.2.3: exit 1" 1
assert_contains "AC3 prefix-only entry is reported as missing CHANGELOG entry" "$OUT" "CHANGELOG"

D="$(mk_rel 1.2.3 "$CL")"
for tag in v1.2 1.2.3 vX v1.2.3-rc1; do
  run bash "$D/tools/check-release.sh" "$tag"
  assert_rc "AC3 tag '$tag' is not vX.Y.Z: exit 2" 2
done
run bash "$D/tools/check-release.sh"
assert_rc "AC3 no tag argument: exit 2" 2

echo "README version badge (v0.9.0 AC7.1)"
# mk_rel_readme VERSION README_TEXT -> like mk_rel, with a README.md next to VERSION (changelog has 1.2.3)
mk_rel_readme() {
  local d; d="$(mk_rel "$1" "$CL")"
  printf '%s' "$2" > "$d/README.md"
  printf '%s\n' "$d"
}
BADGE_OK='# demo
![version](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![tests](https://img.shields.io/badge/tests-5-1F9D63)
'
D="$(mk_rel_readme 1.2.3 "$BADGE_OK")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 README badge equals VERSION: exit 0" 0

D="$(mk_rel_readme 1.2.3 '![version](https://img.shields.io/badge/version-1.2.2-4F5BD5)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 README badge 1.2.2 vs VERSION 1.2.3: exit 1" 1
assert_contains "AC7.1 mismatch message names README" "$OUT" "README"
assert_contains "AC7.1 mismatch message names the badge version" "$OUT" "1.2.2"
assert_contains "AC7.1 mismatch message names VERSION's version" "$OUT" "1.2.3"

D="$(mk_rel_readme 1.2.3 '![version](https://img.shields.io/badge/version-1.2.30-4F5BD5)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 badge 1.2.30 is not 1.2.3 (no prefix match): exit 1" 1

D="$(mk_rel_readme 1.2.3 '![version](https://img.shields.io/badge/version-1.2.3)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 badge without a colour suffix and equal to VERSION: exit 0" 0

D="$(mk_rel_readme 1.2.3 '![version](https://img.shields.io/badge/version-0.1.0-4F5BD5)
')"
run bash "$D/tools/check-release.sh" --notes v1.2.3
assert_rc "AC7.1 --notes also refuses a stale README badge: exit 1" 1

D="$(mk_rel_readme 1.2.3 '# demo, no badge here. version 9.9.9 in prose does not count.
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 README without a version badge: no check, exit 0" 0

D="$(mk_rel 1.2.3 "$CL")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 no README.md at all: no check, exit 0" 0

D="$(mk_rel_readme 1.2.4 '![version](https://img.shields.io/badge/version-1.2.4-4F5BD5)
')"
run bash "$D/tools/check-release.sh" v1.2.4
assert_rc "AC7.1 matching badge does not hide a missing CHANGELOG entry: exit 1" 1
assert_contains "AC7.1 the CHANGELOG problem is still reported" "$OUT" "CHANGELOG"

echo "release notes (AC3 --notes)"
D="$(mk_rel 1.2.3 "$CL")"
NOTES="$(bash "$D/tools/check-release.sh" --notes v1.2.3 2>/dev/null)"; RC=$?
OUT="$NOTES"
assert_rc "AC3 --notes v1.2.3: exit 0" 0
assert_eq "AC3 --notes prints exactly the 1.2.3 section body" '- first line
- second line: with a colon
  continued' "$NOTES"

D="$(mk_rel 1.2.2 "$CL")"
NOTES="$(bash "$D/tools/check-release.sh" --notes v1.2.2 2>/dev/null)"; RC=$?
OUT="$NOTES"
assert_rc "AC3 --notes for the last section: exit 0" 0
assert_eq "AC3 --notes for the last section runs to end of file" '- older entry' "$NOTES"

echo "release job in CI (AC4, static)"
WF="$PB_ROOT/.github/workflows/test.yml"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  run python3 - "$WF" <<'EOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
top = (wf.get("permissions") or {}).get("contents")
print("top-level contents:", top)
for name, job in (wf.get("jobs") or {}).items():
    runs = " ".join(str(s.get("run", "")) for s in job.get("steps", []))
    perm = (job.get("permissions") or {}).get("contents")
    rel = "tools/check-release.sh" in runs
    print("job %s release=%s contents=%s notes=%s if=%s" % (
        name, rel, perm, "--notes" in runs, job.get("if", "")))
EOF
  assert_contains "AC4 workflow keeps top-level contents: read" "$OUT" "top-level contents: read"
  assert_contains "AC4 a job runs tools/check-release.sh with contents: write" "$OUT" "release=True contents=write notes=True"
  assert_not_contains "AC4 no other job gets contents: write" "$OUT" "release=False contents=write"
  REL_IF="$(printf '%s\n' "$OUT" | grep 'release=True' | sed 's/.* if=//')"
  assert_contains "AC4 release job only runs for tags" "$REL_IF" "tag"
  WFTEXT="$(grep -F check-release.sh "$WF")"
  assert_contains "AC4 release job checks the pushed tag" "$WFTEXT" 'tools/check-release.sh "$GITHUB_REF_NAME"'
else
  t_skip 5 "AC4 static check of .github/workflows/test.yml: PyYAML not available"
fi


echo "#12a a tag with a newline is a usage error"
run bash "$D/tools/check-release.sh" "$(printf 'v1.2.3\nx')"
assert_rc "AC12a.1 check-release: tag with a newline exits 2" 2


echo "v0.10.0 AC7.1 every version badge is checked"
B_OK='![version](https://img.shields.io/badge/version-1.2.3-4F5BD5)'
B_OLD='![old](https://img.shields.io/badge/version-1.2.2-4F5BD5)'
D="$(mk_rel_readme 1.2.3 "$B_OK $B_OLD
")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 second badge on the same line is stale (1.2.2): exit 1" 1
assert_contains "AC7.1 the stale second badge is named" "$OUT" "1.2.2"
D="$(mk_rel_readme 1.2.3 "# demo
$B_OK
text between
$B_OLD
")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 second badge on a later line is stale: exit 1" 1
assert_contains "AC7.1 the stale later badge is named" "$OUT" "1.2.2"
D="$(mk_rel_readme 1.2.3 "$B_OLD
$B_OK
")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 first badge stale, second fine: exit 1" 1
D="$(mk_rel_readme 1.2.3 "$B_OK
![again](https://img.shields.io/badge/version-1.2.3-orange) ![x](https://img.shields.io/badge/version-1.2.3)
")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 three correct badges (colour suffixes and none): exit 0" 0
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3--rc.1-orange)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 pre-release badge 1.2.3--rc.1 is a mismatch: exit 1" 1
assert_contains "AC7.1 the pre-release mismatch names README" "$OUT" "README"
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3.1-orange)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 badge 1.2.3.1 is a mismatch: exit 1" 1
D="$(mk_rel_readme 1.2.3 "$B_OK"'
![v](https://img.shields.io/badge/version-1.2.3--rc.1-orange)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 a good first badge does not hide a later pre-release badge: exit 1" 1
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3.1)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 badge 1.2.3.1 without a colour is also a mismatch: exit 1" 1
for tail in ')' '"' '?style=flat' ' ' '>'; do
  D="$(mk_rel_readme 1.2.3 "![v](https://img.shields.io/badge/version-1.2.3${tail}
")"
  run bash "$D/tools/check-release.sh" v1.2.3
  assert_rc "AC7.1 version followed by [$tail] (cannot continue a version): exit 0" 0
done
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5) and badge/tests-5 and a prose badge/version note
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.1 non-version badges and prose do not trip the check: exit 0" 0
D="$(mk_rel_readme 1.2.3 "$B_OLD
")"
run bash "$D/tools/check-release.sh" --notes v1.2.3
assert_rc "AC7.1 --notes also refuses a stale second-kind badge: exit 1" 1

echo "v0.10.0 AC7.2 the always-on badge equals the AGENTS.global.md line count"
# mk_rel_agents N_LINES README_TEXT -> like mk_rel_readme, plus an AGENTS.global.md with exactly N_LINES lines
mk_rel_agents() {
  local d; d="$(mk_rel_readme 1.2.3 "$2")"
  seq 1 "$1" | sed 's/^/rule /' > "$d/AGENTS.global.md"
  printf '%s\n' "$d"
}
AO() { printf '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![always-on](https://img.shields.io/badge/always--on_block-%s%%2F60_lines-C98A00)\n' "$1"; }
D="$(mk_rel_agents 37 "$(AO 37)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 37 equals the 37-line AGENTS.global.md: exit 0" 0
D="$(mk_rel_agents 41 "$(AO 37)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 37 vs 41 lines: exit 1" 1
assert_contains "AC7.2 the mismatch names the badge number" "$OUT" "37"
assert_contains "AC7.2 the mismatch names the real line count" "$OUT" "41"
D="$(mk_rel_agents 33 "$(AO 37)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 37 vs 33 lines (too high): exit 1" 1
assert_contains "AC7.2 too-high mismatch names 33" "$OUT" "33"
D="$(mk_rel_agents 44 "$(AO 4)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 4 is not a prefix match of 44 lines: exit 1" 1
D="$(mk_rel_agents 4 "$(AO 44)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 44 vs 4 lines: exit 1" 1
D="$(mk_rel_agents 60 "$(AO 60)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 60 equals a 60-line file: exit 0" 0
D="$(mk_rel_agents 41 "$(AO 37)")"
run bash "$D/tools/check-release.sh" --notes v1.2.3
assert_rc "AC7.2 --notes also refuses a stale always-on badge: exit 1" 1
D="$(mk_rel_agents 41 "$(AO 41)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 matching always-on badge with a good changelog: exit 0" 0
D="$(mk_rel_agents 41 '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![t](https://img.shields.io/badge/tests-5-1F9D63)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 no always-on badge: no line count check, exit 0" 0
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5)
Prose: the always-on block is 99 lines long.
')"
seq 1 5 > "$D/AGENTS.global.md"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 prose about the block is not a badge: exit 0" 0
D="$(mk_rel_agents 41 "$(AO 41)")"
printf '%s' "$(AO 37)" >> "$D/README.md"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 a second, stale always-on badge is also checked: exit 1" 1

echo "v0.10.0 AC7.2 round 2: no final newline, missing AGENTS.global.md"
D="$(mk_rel_agents 37 "$(AO 37)")"
printf '%s' "$(cat "$D/AGENTS.global.md")" > "$D/AGENTS.global.md"   # same 37 lines, no final newline
assert_eq "fixture: the file has no final newline" "36" "$(wc -l < "$D/AGENTS.global.md" | tr -d ' ')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 37 real lines without a final newline equal badge 37: exit 0" 0
D="$(mk_rel_agents 37 "$(AO 36)")"
printf '%s' "$(cat "$D/AGENTS.global.md")" > "$D/AGENTS.global.md"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 badge 36 vs 37 real lines (no final newline): exit 1" 1
D="$(mk_rel_readme 1.2.3 "$(AO 37)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC7.2 always-on badge but no AGENTS.global.md: exit 1" 1
assert_contains "AC7.2 the missing file is named" "$OUT" "AGENTS.global.md"
assert_not_contains "AC7.2 no raw shell error leaks" "$OUT" "No such file"

echo "v0.11.0 AC5.1: README metrics row 'Always-on block | L / 60 lines · B / 5,000 bytes'"
# mk_metrics NLINES WIDTH ROWTEXT [nofinalnl] -> release root whose AGENTS.global.md has NLINES lines of WIDTH bytes
# each (newline included) and whose README.md holds ROWTEXT after a valid version badge.
mk_metrics() {
  local d; d="$(mk_rel_readme 1.2.3 "![v](https://img.shields.io/badge/version-1.2.3-4F5BD5)
$3
")"
  awk -v n="$1" -v w="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%-" (w - 1) "s\n", "rule " i }' > "$d/AGENTS.global.md"
  if [ "${4:-}" = nofinalnl ]; then printf '%s' "$(cat "$d/AGENTS.global.md")" > "$d/AGENTS.global.md"; fi
  printf '%s\n' "$d"
}
# row L B -> the README table row with B shown the way the README prints it (thousands comma from 1,000)
row() {
  local b="$2"
  [ "$b" -ge 1000 ] && b="${b%???},${b: -3}"
  printf '| Always-on block | %s / 60 lines · %s / 5,000 bytes | `wc -l -c AGENTS.global.md` |' "$1" "$b"
}
rowplain() { printf '| Always-on block | %s / 60 lines · %s / 5,000 bytes | `wc -l -c AGENTS.global.md` |' "$1" "$2"; }

D="$(mk_metrics 20 80 "$(row 20 1600)")"
assert_eq "fixture: 1600 bytes" "1600" "$(wc -c < "$D/AGENTS.global.md" | tr -d ' ')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 matching L=20 and B=1,600 (thousands comma): exit 0" 0
D="$(mk_metrics 20 80 "$(rowplain 20 1600)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 matching L and B written without a comma (1600): exit 0" 0
D="$(mk_metrics 5 80 "$(row 5 400)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 matching L=5 and B=400 (under 1,000): exit 0" 0
D="$(mk_metrics 20 80 "$(row 21 1600)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 wrong L (row 21, real 20), matching B: exit 1" 1
assert_contains "AC5.1 wrong L names the README row" "$OUT" "Always-on block"
assert_contains "AC5.1 wrong L names the README number" "$OUT" "21"
assert_contains "AC5.1 wrong L names the real line count" "$OUT" "20"
D="$(mk_metrics 20 80 "$(row 20 1601)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 wrong B (row 1,601, real 1600), matching L: exit 1" 1
assert_contains "AC5.1 wrong B names the README row" "$OUT" "Always-on block"
assert_contains "AC5.1 wrong B names the README number" "$OUT" "1,601"
case "$OUT" in *1600*|*1,600*) t_ok "AC5.1 wrong B names the real byte count" ;; *) t_bad "AC5.1 wrong B names the real byte count" "output: $OUT" ;; esac
D="$(mk_metrics 20 80 "$(rowplain 20 1601)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 wrong B written without a comma: exit 1" 1
D="$(mk_metrics 20 80 "$(row 20 1500)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 B too low by 100: exit 1" 1
D="$(mk_metrics 20 80 "$(row 20 160)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 B=160 is not a prefix match of 1600: exit 1" 1
D="$(mk_metrics 20 80 "$(row 20 1600 | sed 's/1,600/16,000/')")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 B=16,000 is not a suffix match of 1,600: exit 1" 1
D="$(mk_metrics 20 80 "$(row 21 1601)")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 both numbers wrong: exit 1" 1
D="$(mk_metrics 20 80 "$(row 20 1600)" nofinalnl)"
assert_eq "fixture: no final newline" "19" "$(wc -l < "$D/AGENTS.global.md" | tr -d ' ')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 no final newline: B=1,600 would count a newline that is not there: exit 1" 1
D="$(mk_metrics 20 80 "$(row 20 1599)" nofinalnl)"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 no final newline: L=20 and B=1,599 match: exit 0" 0
D="$(mk_metrics 20 80 "$(row 19 1599)" nofinalnl)"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 no final newline: L=19 (wc -l style) is wrong: exit 1" 1
# review round 1: spacing around the numbers
D="$(mk_metrics 20 80 '| Always-on block |  99  / 60 lines · 9,999  /  5,000 bytes | x |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 extra spaces around wrong numbers are still checked: exit 1" 1
assert_contains "R1 extra spaces: names the row" "$OUT" "Always-on block"
D="$(mk_metrics 20 80 '| Always-on block |  20  / 60 lines · 1,600  /  5,000 bytes | x |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 extra spaces around matching numbers: exit 0" 0
D="$(mk_metrics 20 80 '|  Always-on block  |  99 /  60 lines · 1,600 / 5,000 bytes |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 extra spaces, wrong L only: exit 1" 1
D="$(mk_metrics 20 80 '| Always-on block | 20 / 60 lines · 9,999  / 5,000 bytes |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 two spaces before the slash, wrong B only: exit 1" 1
D="$(mk_metrics 20 80 '| Always-on block | many lines |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 a row whose numbers cannot be parsed: exit 1, not skipped" 1
assert_contains "R1 unparsable row: names the row" "$OUT" "Always-on block"
D="$(mk_metrics 20 80 '| Always-on block | 20 / 60 lines · lots of bytes |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 only the bytes cannot be parsed: exit 1" 1
D="$(mk_metrics 20 80 '| Always-on block | lots of lines · 1,600 / 5,000 bytes |')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "R1 only the lines cannot be parsed: exit 1" 1
D="$(mk_metrics 20 80 "| Other row | 99 / 60 lines · 1 / 5,000 bytes | x |")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 other rows are not checked: exit 0" 0
D="$(mk_metrics 20 80 "Prose: the Always-on block is 99 / 60 lines · 1 / 5,000 bytes today.")"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 prose that is not a table row is not checked: exit 0" 0
D="$(mk_rel_readme 1.2.3 '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5)
')"
run bash "$D/tools/check-release.sh" v1.2.3
assert_rc "AC5.1 no metrics row (and no AGENTS.global.md): no check, exit 0" 0
D="$(mk_metrics 20 80 "$(row 21 1601)")"
run bash "$D/tools/check-release.sh" --notes v1.2.3
assert_rc "AC5.1 --notes also refuses a stale metrics row: exit 1" 1

t_summary
