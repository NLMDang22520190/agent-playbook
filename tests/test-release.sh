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
  echo "  skip AC4 static check: PyYAML not available"
fi

t_summary
