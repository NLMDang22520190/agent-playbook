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


echo "PR release check in CI (AC6, static)"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  run python3 - "$WF" <<'EOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
CMD = 'bash tools/release-pr-check.sh "$BASE_SHA"'
hits = []
for jn, job in (wf.get("jobs") or {}).items():
    for i, s in enumerate(job.get("steps") or []):
        if CMD in str(s.get("run", "")):
            hits.append((jn, i, s))
print("pr-check steps total: %d" % len(hits))
for jn, i, s in hits:
    cond = str(s.get("if", ""))
    print("pr-check job: %s" % jn)
    print("pr-check env BASE_SHA: %s" % (s.get("env") or {}).get("BASE_SHA"))
    print("pr-check if: %s" % cond)
    print("pr-check if mentions docs_only: %s" % ("docs_only" in cond))
    print("pr-check if exact: %s" % (cond.strip() == "${{ github.event_name == 'pull_request' && matrix.os == 'ubuntu-latest' }}"))
    print("pr-check step continue-on-error: %s" % ("present" if "continue-on-error" in s else "absent"))
steps = ((wf.get("jobs") or {}).get("test") or {}).get("steps") or []
idx = [i for i, s in enumerate(steps) if CMD in str(s.get("run", ""))]
tix = [i for i, s in enumerate(steps) if s.get("name") == "Tests and static checks"]
print("test job continue-on-error: %s" % ("present" if "continue-on-error" in ((wf.get("jobs") or {}).get("test") or {}) else "absent"))
print("tests step found: %s" % bool(tix))
print("pr-check before tests step: %s" % (bool(idx) and bool(tix) and idx[0] < tix[0]))
EOF
  assert_contains "AC6 exactly one workflow step runs tools/release-pr-check.sh" "$OUT" "pr-check steps total: 1"
  assert_contains "AC6 that step is in the test job (not windows-shard)" "$OUT" "pr-check job: test"
  assert_contains "AC6 step passes BASE_SHA from the PR base sha" "$OUT" 'pr-check env BASE_SHA: ${{ github.event.pull_request.base.sha }}'
  PRIF="$(printf '%s\n' "$OUT" | grep '^pr-check if: ')"
  assert_contains "AC6 step only runs for pull_request events" "$PRIF" "github.event_name == 'pull_request'"
  assert_contains "AC6 step only runs on ubuntu-latest" "$PRIF" "matrix.os == 'ubuntu-latest'"
  assert_contains "AC6 step is not skipped for docs-only PRs" "$OUT" "pr-check if mentions docs_only: False"
  assert_contains "AC6 step runs before Tests and static checks" "$OUT" "pr-check before tests step: True"
  assert_contains "AC6 step if is exactly pull_request AND ubuntu-latest" "$OUT" "pr-check if exact: True"
  assert_contains "AC6 step cannot be made non-blocking (no continue-on-error on the step)" "$OUT" "pr-check step continue-on-error: absent"
  assert_contains "AC6 test job has no job-level continue-on-error" "$OUT" "test job continue-on-error: absent"
else
  t_skip 10 "AC6 static check of .github/workflows/test.yml: PyYAML not available"
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

echo "release PR check (v0.24.16 AC1-AC5, AC7)"
RPC="$PB_ROOT/tools/release-pr-check.sh"
RPC_CL3="$CL"
RPC_CL4='# Changelog

## 1.2.4 - 2026-10-20
- new release

## 1.2.3 - 2026-10-09
- first line
'
# rpc_mk VERSION CHANGELOG -> git repo with tools/, VERSION, CHANGELOG.md committed (this commit is BASE)
rpc_mk() {
  local d; d="$(mk_tmp)"
  mkdir -p "$d/tools"
  cp -p "$PB_ROOT/tools/check-release.sh" "$d/tools/check-release.sh"
  [ -f "$RPC" ] && cp -p "$RPC" "$d/tools/release-pr-check.sh"
  [ -n "$1" ] && printf '%s\n' "$1" > "$d/VERSION"
  printf '%s' "$2" > "$d/CHANGELOG.md"
  ( cd "$d" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
    git config commit.gpgsign false && git add -A && git commit -q -m base )
  printf '%s\n' "$d"
}
rpc_commit() { ( cd "$1" && git add -A && git commit -q --allow-empty -m "${2:-head}" ); }
rpc_sha() { ( cd "$1" && git rev-parse HEAD ); }
# rpc DIR BASE -> runs the tool inside DIR
rpc() { run_in "$1" bash tools/release-pr-check.sh "$2"; }

assert_file "AC7 tools/release-pr-check.sh exists" "$RPC"
if [ -x "$RPC" ]; then t_ok "AC7 tools/release-pr-check.sh is executable"; else t_bad "AC7 tools/release-pr-check.sh is executable" "not executable or missing: $RPC"; fi

# AC1: a bumped VERSION with a valid release passes
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC1 VERSION 1.2.3 -> 1.2.4 with a CHANGELOG entry: exit 0" 0
assert_contains "AC1 success prints the pinned line" "$OUT" "release PR check passed"
assert_not_contains "AC1 success does not print the failure line" "$OUT" "release PR check failed"

# AC1: check-release exit 1 (missing CHANGELOG entry) maps to 1 and its message is passed through
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC1 VERSION bumped, no '## 1.2.4 ' entry: exit 1" 1
assert_contains "AC1 check-release's CHANGELOG message is passed through" "$OUT" "CHANGELOG"
assert_contains "AC1 failure prints the pinned line" "$OUT" "release PR check failed"
assert_not_contains "AC1 a failure never prints the success line" "$OUT" "release PR check passed"

# AC1: check-release exit 3 (CHANGELOG.md unreadable) also maps to 1, not 3
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; rm -f "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC1 check-release exit 3 (no CHANGELOG.md) maps to exit 1" 1
assert_contains "AC1 exit-3 case prints the pinned failure line" "$OUT" "release PR check failed"

# AC1: the check runs on several commits between BASE and HEAD (HEAD is what counts)
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; rpc_commit "$D" one
printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"; rpc_commit "$D" two
rpc "$D" "$B"
assert_rc "AC1 VERSION and CHANGELOG fixed in different commits: judged at HEAD, exit 0" 0

# AC1: whitespace / CRLF only edits of VERSION are not a release PR (same trim as check-release.sh)
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.3\r\n' > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC1 CRLF-only VERSION edit: not a release PR, exit 0" 0
assert_contains "AC1 CRLF-only VERSION edit prints VERSION unchanged" "$OUT" "VERSION unchanged"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '  1.2.3 \t\n\n' > "$D/VERSION"; rm -f "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC1 spaces/tabs/blank-line VERSION edit (CHANGELOG gone): exit 0" 0
assert_contains "AC1 whitespace-only VERSION edit prints VERSION unchanged" "$OUT" "VERSION unchanged"
assert_not_contains "AC1 whitespace-only edit does not run check-release" "$OUT" "CHANGELOG"

# AC2: VERSION identical at BASE and HEAD: not a release PR, check-release is not run
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf 'other\n' > "$D/notes.txt"; printf 'changed\n' >> "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC2 other files changed, VERSION same: exit 0" 0
assert_contains "AC2 prints VERSION unchanged" "$OUT" "VERSION unchanged"
assert_not_contains "AC2 no failure line" "$OUT" "release PR check failed"
assert_not_contains "AC2 no success line (check-release was not run)" "$OUT" "release PR check passed"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
rpc "$D" "$B"
assert_rc "AC2 BASE equals HEAD (no changes at all): exit 0" 0
assert_contains "AC2 BASE equals HEAD prints VERSION unchanged" "$OUT" "VERSION unchanged"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf 'garbage\n' > "$D/CHANGELOG.md"; printf '![v](https://img.shields.io/badge/version-9.9.9)\n' > "$D/README.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC2 broken CHANGELOG and stale README but VERSION same: still exit 0" 0

# AC3: VERSION at HEAD that is not X.Y.Z digits, on a changed VERSION
for bad in 0.25 v0.25.0 0.25.0.1 0.25.0-rc1 abc; do
  D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
  printf '%s\n' "$bad" > "$D/VERSION"; rpc_commit "$D"
  rpc "$D" "$B"
  assert_rc "AC3 VERSION '$bad' at HEAD: exit 1 (not 0, not usage 2)" 1
  assert_contains "AC3 VERSION '$bad' is named in the message" "$OUT" "$bad"
done
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
: > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 empty VERSION at HEAD: exit 1" 1
assert_contains "AC3 empty VERSION message names VERSION" "$OUT" "VERSION"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '   \r\n' > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 whitespace-only VERSION at HEAD (empty once trimmed): exit 1" 1
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
rm -f "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 VERSION deleted at HEAD, present at BASE: exit 1" 1
assert_contains "AC3 deleted VERSION message names VERSION" "$OUT" "VERSION"
D="$(rpc_mk '' "$RPC_CL3")"; B="$(rpc_sha "$D")"
assert_no_path "fixture: BASE has no VERSION" "$D/VERSION"
printf '1.2.4\n' > "$D/VERSION"; printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 VERSION absent at BASE, valid at HEAD with CHANGELOG entry: counts as changed, exit 0" 0
assert_contains "AC3 added VERSION is checked (success line)" "$OUT" "release PR check passed"
D="$(rpc_mk '' "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 VERSION absent at BASE, added without a CHANGELOG entry: check-release runs, exit 1" 1
assert_contains "AC3 added VERSION without entry names CHANGELOG" "$OUT" "CHANGELOG"
D="$(rpc_mk '' "$RPC_CL3")"; B="$(rpc_sha "$D")"
printf 'v1\n' > "$D/VERSION"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC3 VERSION absent at BASE, added with a bad value: exit 1" 1
assert_contains "AC3 added bad VERSION value is named" "$OUT" "v1"

# AC4: usage and environment errors
D="$(rpc_mk 1.2.3 "$RPC_CL3")"; B="$(rpc_sha "$D")"
run_in "$D" bash tools/release-pr-check.sh
assert_rc "AC4 no argument: exit 2" 2
assert_contains "AC4 no argument prints a usage line" "$OUT" "usage"
run_in "$D" bash tools/release-pr-check.sh "$B" "$B"
assert_rc "AC4 two arguments: exit 2" 2
assert_contains "AC4 two arguments print a usage line" "$OUT" "usage"
rpc "$D" 0123456789abcdef0123456789abcdef01234567
assert_rc "AC4 BASE is a sha that does not exist: exit 3" 3
rpc "$D" no-such-branch
assert_rc "AC4 BASE is an unknown ref name: exit 3" 3
TREE="$(cd "$D" && git rev-parse 'HEAD^{tree}')"
rpc "$D" "$TREE"
assert_rc "AC4 BASE is a tree, not a commit: exit 3" 3
D2="$(mk_tmp)"; mkdir -p "$D2/tools"
cp -p "$PB_ROOT/tools/check-release.sh" "$D2/tools/check-release.sh"
[ -f "$RPC" ] && cp -p "$RPC" "$D2/tools/release-pr-check.sh"
printf '1.2.3\n' > "$D2/VERSION"
run_in "$D2" env GIT_CEILING_DIRECTORIES="$PB_TMPBASE" bash tools/release-pr-check.sh "$B"
assert_rc "AC4 not inside a git repository: exit 3" 3

# AC5 regression (v0.24.10): VERSION bumped, CHANGELOG entry present, README always-on row stale
rpc_agents() { awk -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%-79s\n", "rule " i }' > "$1/AGENTS.global.md"; }
RPC_BADGE() { printf '![version](https://img.shields.io/badge/version-%s-4F5BD5)\n| Always-on block | %s / 60 lines · %s / 5,000 bytes | `wc -l -c AGENTS.global.md` |\n' "$1" "$2" "$3"; }
D="$(rpc_mk 1.2.3 "$RPC_CL3")"
rpc_agents "$D" 20; RPC_BADGE 1.2.3 20 1,600 > "$D/README.md"; rpc_commit "$D" base2; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"
rpc_agents "$D" 40; RPC_BADGE 1.2.4 20 1,600 > "$D/README.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC5 stale README always-on row after a VERSION bump: exit 1" 1
assert_contains "AC5 the output names README.md" "$OUT" "README.md"
assert_contains "AC5 the output names the Always-on block row" "$OUT" "Always-on block"
assert_contains "AC5 failure prints the pinned line" "$OUT" "release PR check failed"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"
rpc_agents "$D" 20; RPC_BADGE 1.2.3 20 1,600 > "$D/README.md"; rpc_commit "$D" base2; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"
rpc_agents "$D" 40; RPC_BADGE 1.2.4 40 3,200 > "$D/README.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC5 control: same bump with the README row updated: exit 0" 0
assert_contains "AC5 control prints the success line" "$OUT" "release PR check passed"
D="$(rpc_mk 1.2.3 "$RPC_CL3")"
printf '![version](https://img.shields.io/badge/version-1.2.3-4F5BD5)\n' > "$D/README.md"; rpc_commit "$D" base2; B="$(rpc_sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; printf '%s' "$RPC_CL4" > "$D/CHANGELOG.md"; rpc_commit "$D"
rpc "$D" "$B"
assert_rc "AC5 README version badge left at 1.2.3 after the bump: exit 1" 1
assert_contains "AC5 stale badge output names README.md" "$OUT" "README.md"

echo "release PR check --gate BASE (v0.32.0 S3: AC5, AC5', AC7)"
if command -v node >/dev/null 2>&1; then
  . "$(dirname "$0")/release-gate-fixture.sh"
  rpcg() { run_in "$1" bash tools/release-pr-check.sh --gate "$2"; }
  # gmk -> a repo at VERSION 1.2.3 that ships the real gate tools (not sealed); the caller takes BASE from it
  gmk() { local d; d="$(rpc_mk 1.2.3 "$RPC_CL3")"; rgf_prepare "$d"; rpc_commit "$d" gate-tools; printf '%s\n' "$d"; }
  # gmk_stub RC -> as gmk, but tools/release-gate.sh is a stub that logs its arguments to "<repo>.args" and exits RC
  gmk_stub() {
    local d; d="$(gmk)"
    printf '#!/usr/bin/env bash\nprintf "%%s\n" "$*" >> "%s.args"\nprintf "stub reason one\n"\nexit %s\n' "$d" "$1" > "$d/tools/release-gate.sh"
    rpc_commit "$d" gate-stub; printf '%s\n' "$d"
  }
  gcalls() { if [ -f "$1.args" ]; then wc -l < "$1.args" | tr -d ' '; else echo 0; fi; }
  rel_bump() { printf '1.2.4\n' > "$1/VERSION"; printf '%s' "$RPC_CL4" > "$1/CHANGELOG.md"; rpc_commit "$1" release; }

  # AC5: a PR that does not change VERSION is not a release PR; the gate is not called
  D="$(gmk_stub 1)"; B="$(rpc_sha "$D")"
  printf 'other\n' > "$D/notes.txt"; rpc_commit "$D" notes
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a non-release PR (VERSION unchanged), gate stub would fail: exit 0" 0
  assert_contains "AC5 --gate non-release: says VERSION unchanged" "$OUT" "VERSION unchanged"
  assert_eq "AC5 --gate non-release: the gate was not called" "0" "$(gcalls "$D")"
  assert_not_contains "AC5 --gate non-release: no failure line" "$OUT" "release PR check failed"
  D="$(gmk)"; B="$(rpc_sha "$D")"
  printf 'other\n' > "$D/notes.txt"; rpc_commit "$D" notes
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a non-release PR with no committed gate at all: exit 0" 0

  # AC5: a release PR calls tools/release-gate.sh --check HEAD and maps its exit code
  D="$(gmk_stub 0)"; B="$(rpc_sha "$D")"; rel_bump "$D"
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a release PR, gate exits 0: exit 0" 0
  assert_eq "AC5 --gate release PR: the gate was called once" "1" "$(gcalls "$D")"
  assert_contains "AC5 --gate release PR: called as 'release-gate.sh --check HEAD'" "$(cat "$D.args" 2>/dev/null)" "--check HEAD"
  assert_not_contains "AC5 --gate release PR with a passing gate: no failure line" "$OUT" "release PR check failed"
  D="$(gmk_stub 1)"; B="$(rpc_sha "$D")"; rel_bump "$D"
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a release PR, gate exits 1: exit 1" 1
  assert_contains "AC5 --gate failure prints the pinned line" "$OUT" "release PR check failed: release gate"
  assert_eq "AC5 --gate failure: the gate was called" "1" "$(gcalls "$D")"
  assert_not_contains "AC5 --gate failure: no success line" "$OUT" "release PR check passed"

  # AC5': plain `release-pr-check.sh BASE` keeps today's behaviour: it never calls the gate
  D="$(gmk_stub 1)"; B="$(rpc_sha "$D")"; rel_bump "$D"
  rpc "$D" "$B"
  assert_rc "AC5' plain release-pr-check.sh BASE on a release PR with a failing gate stub: exit 0 (as before)" 0
  assert_contains "AC5' plain: the success line" "$OUT" "release PR check passed"
  assert_eq "AC5' plain: the gate was not called" "0" "$(gcalls "$D")"
  D="$(gmk)"; B="$(rpc_sha "$D")"; rel_bump "$D"
  rpc "$D" "$B"
  assert_rc "AC5' plain: a release PR without any gate: exit 0 (the gate is the separate --gate step)" 0

  # AC5 + AC7: the real gate tool and a synthetic committed gate
  D="$(gmk)"; B="$(rpc_sha "$D")"; rel_bump "$D"; rgf_seal "$D"
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a release PR with a committed passing gate: exit 0" 0
  assert_not_contains "AC5 passing gate: no failure line" "$OUT" "release PR check failed"
  D="$(gmk)"; B="$(rpc_sha "$D")"; rel_bump "$D"
  rpcg "$D" "$B"
  assert_rc "AC5 --gate on a release PR without a gate: exit 1" 1
  assert_contains "AC5 no gate: the pinned failure line" "$OUT" "release PR check failed: release gate"
  assert_contains "AC5 no gate: the gate's reason is shown" "$OUT" "no gate result under evals/results/gate-*/ at REV"
  assert_not_contains "AC5 no gate: no success line" "$OUT" "release PR check passed"
  D="$(gmk)"; B="$(rpc_sha "$D")"; rel_bump "$D"; rgf_seal "$D"
  printf 'late\n' > "$D/notes.txt"; rpc_commit "$D" late-change
  rpcg "$D" "$B"
  assert_rc "AC5 --gate: a change outside evals/results after the gate commit: exit 1" 1
  assert_contains "AC5 stale gate: the pinned failure line" "$OUT" "release PR check failed: release gate"
  D="$(gmk)"; B="$(rpc_sha "$D")"; rel_bump "$D"; rgf_seal "$D" E2
  rpcg "$D" "$B"
  assert_rc "AC5 --gate: a committed gate whose verdict is fail: exit 1" 1
  assert_contains "AC5 failing verdict: the pinned failure line" "$OUT" "release PR check failed: release gate"
  assert_contains "AC5 failing verdict: the failing item is named" "$OUT" "E2"

  # usage and environment errors keep their codes with --gate
  D="$(gmk)"; B="$(rpc_sha "$D")"
  run_in "$D" bash tools/release-pr-check.sh --gate
  assert_rc "AC5 --gate without BASE: exit 2" 2
  assert_contains "AC5 --gate without BASE prints a usage line" "$OUT" "usage"
  rpcg "$D" no-such-branch
  assert_rc "AC5 --gate with an unknown BASE: exit 3" 3
else
  # 31 assertions in the block above (real run 231 total, node forced missing 200 + this skip)
  t_skip 31 "AC5 release-pr-check.sh --gate cases: node missing (the synthetic release gate needs it)"
fi

echo "release gate steps in CI (v0.32.0 S3: AC5', AC6, static)"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  run python3 - "$WF" <<'EOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf.get("jobs") or {}
test = jobs.get("test") or {}
steps = test.get("steps") or []
GATE = "tools/release-pr-check.sh --gate"
hits = [(i, s) for i, s in enumerate(steps) if GATE in str(s.get("run", ""))]
print("gate-pr steps in test job: %d" % len(hits))
print("gate-pr steps in all jobs: %d" % sum(1 for j in jobs.values() for s in (j.get("steps") or []) if GATE in str(s.get("run", ""))))
tix = [i for i, s in enumerate(steps) if s.get("name") == "Tests and static checks"]
old = [i for i, s in enumerate(steps) if 'bash tools/release-pr-check.sh "$BASE_SHA"' in str(s.get("run", ""))]
if hits:
    i, s = hits[0]
    print("gate-pr if: %s" % str(s.get("if", "")))
    print("gate-pr env BASE_SHA: %s" % (s.get("env") or {}).get("BASE_SHA"))
    print("gate-pr run passes BASE_SHA: %s" % ('--gate "$BASE_SHA"' in str(s.get("run", ""))))
    print("gate-pr after tests step: %s" % (bool(tix) and i > tix[0]))
    print("gate-pr step continue-on-error: %s" % ("present" if "continue-on-error" in s else "absent"))
    print("gate-pr is not the old step: %s" % (not old or old[0] != i))
print("old release PR check step still there: %s" % (len(old) == 1))
if old:
    o = steps[old[0]]
    print("old step if exact: %s" % (str(o.get("if", "")).strip() == "${{ github.event_name == 'pull_request' && matrix.os == 'ubuntu-latest' }}"))
    print("old step runs exactly: %s" % (str(o.get("run", "")).strip() == 'bash tools/release-pr-check.sh "$BASE_SHA"'))
rel = jobs.get("release") or {}
rs = rel.get("steps") or []
co = [i for i, s in enumerate(rs) if str(s.get("uses", "")).startswith("actions/checkout")]
print("release job checkout steps: %d" % len(co))
if co:
    print("release checkout fetch-depth: %s" % str((rs[co[0]].get("with") or {}).get("fetch-depth")))
CHK = "bash tools/release-gate.sh --check HEAD"
gi = [i for i, s in enumerate(rs) if CHK in str(s.get("run", ""))]
cr = [i for i, s in enumerate(rs) if "gh release create" in str(s.get("run", ""))]
print("release job gate steps: %d" % len(gi))
print("gate steps in all jobs: %d" % sum(1 for j in jobs.values() for s in (j.get("steps") or []) if CHK in str(s.get("run", ""))))
print("release job create steps: %d" % len(cr))
print("gate check after checkout: %s" % (bool(gi) and bool(co) and gi[0] > co[0]))
print("gate check before gh release create: %s" % (bool(gi) and bool(cr) and gi[0] < cr[0]))
if gi:
    print("gate check step continue-on-error: %s" % ("present" if "continue-on-error" in rs[gi[0]] else "absent"))
    print("gate check step if: %s" % rs[gi[0]].get("if", "none"))
print("release job continue-on-error: %s" % ("present" if "continue-on-error" in rel else "absent"))
EOF
  assert_contains "AC5' exactly one step of the test job runs tools/release-pr-check.sh --gate" "$OUT" "gate-pr steps in test job: 1"
  assert_contains "AC5' no other job runs it" "$OUT" "gate-pr steps in all jobs: 1"
  assert_contains "AC5' that step runs after 'Tests and static checks'" "$OUT" "gate-pr after tests step: True"
  GPIF="$(printf '%s\n' "$OUT" | grep '^gate-pr if: ')"
  assert_contains "AC5' that step only runs for pull_request events" "$GPIF" "github.event_name == 'pull_request'"
  assert_contains "AC5' that step gets BASE_SHA from the PR base sha" "$OUT" 'gate-pr env BASE_SHA: ${{ github.event.pull_request.base.sha }}'
  assert_contains "AC5' that step passes the base to --gate" "$OUT" "gate-pr run passes BASE_SHA: True"
  assert_contains "AC5' that step cannot be made non-blocking" "$OUT" "gate-pr step continue-on-error: absent"
  assert_contains "AC5' it is a separate step from the existing Release PR check" "$OUT" "gate-pr is not the old step: True"
  assert_contains "AC5' the existing Release PR check step is still there" "$OUT" "old release PR check step still there: True"
  assert_contains "AC5' the existing step keeps its condition" "$OUT" "old step if exact: True"
  assert_contains "AC5' the existing step keeps its command (no --gate)" "$OUT" "old step runs exactly: True"
  assert_contains "AC6 the release job has one checkout step" "$OUT" "release job checkout steps: 1"
  assert_contains "AC6 the release job checks out with fetch-depth 0" "$OUT" "release checkout fetch-depth: 0"
  assert_contains "AC6 the release job has one step running 'bash tools/release-gate.sh --check HEAD'" "$OUT" "release job gate steps: 1"
  assert_contains "AC6 no other job runs that command" "$OUT" "gate steps in all jobs: 1"
  assert_contains "AC6 the gate check runs after the checkout" "$OUT" "gate check after checkout: True"
  assert_contains "AC6 the gate check runs before gh release create" "$OUT" "gate check before gh release create: True"
  assert_contains "AC6 the release job still has its gh release create step" "$OUT" "release job create steps: 1"
  assert_contains "AC6 the gate check step cannot be made non-blocking" "$OUT" "gate check step continue-on-error: absent"
  assert_contains "AC6 the gate check step has no condition of its own" "$OUT" "gate check step if: none"
  assert_contains "AC6 the release job has no job-level continue-on-error" "$OUT" "release job continue-on-error: absent"
else
  t_skip 19 "AC5'/AC6 static check of .github/workflows/test.yml: PyYAML not available"
fi


t_summary
