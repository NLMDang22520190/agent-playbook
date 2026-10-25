#!/usr/bin/env bash
# Tests for tools/report-usage.sh (v0.26.0): counts which report parts appear in merged PR bodies, numbers only.
# Never calls the real gh: a fake `gh` first on PATH prints $GH_DIR/prs.json and records its arguments in $GH_DIR/args.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/report-usage.sh"

BIN="$(mk_tmp)"; GD="$(mk_tmp)"
cat > "$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
# fake gh: records one argument per line, then prints the fixture (or fails on GH_FAIL)
printf '%s\n' "$@" > "$GH_DIR/args"
if [ -n "${GH_FAIL:-}" ]; then echo "gh: simulated failure" >&2; exit 1; fi
cat "$GH_DIR/prs.json"
FAKE
chmod +x "$BIN/gh"

# runt CMD... -> runs CMD with the fake gh first on PATH; clears the argument record; sets OUT and RC
runt() { rm -f "$GD/args"; run env PATH="$BIN:$PATH" GH_DIR="$GD" "$@"; }
# row LABEL -> the first output line that starts with LABEL, runs of spaces squeezed
row() { printf '%s\n' "$OUT" | awk -v l="$1" 'index($0, l) == 1 { print; exit }' | tr -s ' '; }
# arg_has WORD -> 1 when the fake gh got WORD as one argument, else 0
arg_has() { if [ -f "$GD/args" ] && grep -qxF -- "$1" "$GD/args"; then echo 1; else echo 0; fi; }

# Five merged PRs (gh prints compact JSON, keys sorted). PR 11 has every part; PR 12 uses **Weight:** and CRLF; PR 13 has
# only near misses (mid-line Weight:, plain "Not checked", an escaped backslash before n, no bold on Playbook feedback) and
# one [UNVERIFIED]; PR 14 is empty; PR 5 is older than 2026-10-09.
cat > "$GD/prs5.json" <<'EOF'
[{"body":"Intro SECRET-BODY-ONE \"quoted\"\nWeight: Lite (user said quick)\nClaims [VERIFIED] a, [INFERRED] b, [UNVERIFIED] c\n\n## Request coverage\n- x\n## Not checked\n- y\n## Pre-mortem\n- z\n**Models used:** m\n**Playbook feedback:** none","mergedAt":"2026-10-10T08:00:00Z","number":11,"title":"SECRET-TITLE-ONE"},{"body":"**Weight:** Full\r\nOnly [UNVERIFIED] here\r\n## Pre-mortem\r\n- r","mergedAt":"2026-10-11T09:00:00Z","number":12,"title":"t2"},{"body":"text with Weight: inline and see Not checked, [UNVERIFIED] once, path C:\\\\new\\\\x and foo\\n## Request coverage and Playbook feedback: none, SECRET-BODY-THREE","mergedAt":"2026-10-12T10:00:00Z","number":13,"title":"t3"},{"body":"","mergedAt":"2026-10-13T11:00:00Z","number":14,"title":"t4"},{"body":"Weight: Full\n[VERIFIED] old\n## Not checked\n- n","mergedAt":"2026-10-01T12:00:00Z","number":5,"title":"t5"}]
EOF
cp "$GD/prs5.json" "$GD/prs.json"

echo "AC1/AC2 counts over all merged PRs"
runt bash "$TOOL" acme/secret-repo
assert_rc "AC1 a valid run exits 0" 0
assert_eq "AC2 header names the PR count" "merged PRs: 5" "$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_eq "AC2 Weight line: PRs 11, 12, 5 (mid-line Weight: does not count)" "Weight: line 3/5 60%" "$(row 'Weight: line')"
assert_eq "AC2 [VERIFIED]: PRs 11, 5 ([UNVERIFIED] is not [VERIFIED])" "[VERIFIED] 2/5 40%" "$(row '[VERIFIED]')"
assert_eq "AC2 [INFERRED]: PR 11" "[INFERRED] 1/5 20%" "$(row '[INFERRED]')"
assert_eq "AC2 [UNVERIFIED]: PRs 11, 12, 13" "[UNVERIFIED] 3/5 60%" "$(row '[UNVERIFIED]')"
assert_eq "AC2 ## Not checked: heading lines only (PRs 11, 5)" "## Not checked 2/5 40%" "$(row '## Not checked')"
assert_eq "AC2 ## Pre-mortem: PRs 11, 12 (CRLF body)" "## Pre-mortem 2/5 40%" "$(row '## Pre-mortem')"
assert_eq "AC2 **Playbook feedback:**: bold form only (PR 11)" "**Playbook feedback:** 1/5 20%" "$(row '**Playbook feedback:**')"
assert_eq "AC2 ## Request coverage: an escaped backslash-n is not a line start (PR 11 only)" "## Request coverage 1/5 20%" "$(row '## Request coverage')"
assert_eq "AC2 **Models used:**: PR 11" "**Models used:** 1/5 20%" "$(row '**Models used:**')"

echo "AC1 the gh call"
for w in pr list --repo acme/secret-repo --state merged --limit 100 --json number,body,mergedAt; do
  assert_eq "AC1 gh got argument [$w]" "1" "$(arg_has "$w")"
done
assert_eq "AC1 without --since no --search is passed" "0" "$(arg_has --search)"
assert_eq "AC1 the arguments come in this order" "pr list --repo acme/secret-repo --state merged --limit 100 --json number,body,mergedAt" "$(tr '\n' ' ' < "$GD/args" 2>/dev/null | sed 's/ $//')"

echo "AC3 numbers only"
assert_not_contains "AC3 no body text (PR 11)" "$OUT" "SECRET-BODY-ONE"
assert_not_contains "AC3 no body text (PR 13)" "$OUT" "SECRET-BODY-THREE"
assert_not_contains "AC3 no title" "$OUT" "SECRET-TITLE"
assert_not_contains "AC3 no repo name" "$OUT" "secret-repo"
assert_not_contains "AC3 no owner name" "$OUT" "acme"
assert_eq "AC3 exactly the header and nine rows" "10" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "AC3 every row is a label and numbers" "0" "$(printf '%s\n' "$OUT" | sed 1d | grep -cvE ' [0-9]+/[0-9]+ +([0-9]+%|-)$')"

echo "AC1/AC2 --since and --limit"
runt bash "$TOOL" acme/secret-repo --since 2026-10-09 --limit 7
assert_rc "AC1 --since and --limit exit 0" 0
assert_eq "AC2 header names the date" "merged PRs: 4 (merged on or after 2026-10-09)" "$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_eq "AC1 --limit 7 is passed" "1" "$(arg_has 7)"
assert_eq "AC1 --since passes a merged: search" "1" "$(arg_has 'merged:>=2026-10-09')"
assert_eq "AC1 --since passes --search" "1" "$(arg_has --search)"
assert_eq "AC1 the older PR 5 is filtered out even when gh ignores the search: Weight" "Weight: line 2/4 50%" "$(row 'Weight: line')"
assert_eq "AC1 PR 5 filtered: [VERIFIED]" "[VERIFIED] 1/4 25%" "$(row '[VERIFIED]')"
assert_eq "AC1 PR 5 filtered: [UNVERIFIED]" "[UNVERIFIED] 3/4 75%" "$(row '[UNVERIFIED]')"
assert_eq "AC1 PR 5 filtered: ## Not checked" "## Not checked 1/4 25%" "$(row '## Not checked')"
assert_eq "AC1 PR 5 filtered: ## Pre-mortem" "## Pre-mortem 2/4 50%" "$(row '## Pre-mortem')"
runt bash "$TOOL" --limit 3 acme/secret-repo
assert_rc "AC1 options may come before the repo" 0
assert_eq "AC1 --limit 3 before the repo is passed" "1" "$(arg_has 3)"

echo "AC2 rounding and zero PRs"
printf '%s\n' '[{"body":"Weight: Lite\n[VERIFIED]","mergedAt":"2026-10-10T00:00:00Z","number":1},{"body":"Weight: Full","mergedAt":"2026-10-10T00:00:00Z","number":2},{"body":"none","mergedAt":"2026-10-10T00:00:00Z","number":3}]' > "$GD/prs.json"
runt bash "$TOOL" acme/r
assert_eq "AC2 2 of 3 rounds to 67%" "Weight: line 2/3 67%" "$(row 'Weight: line')"
assert_eq "AC2 1 of 3 rounds to 33%" "[VERIFIED] 1/3 33%" "$(row '[VERIFIED]')"
assert_eq "AC2 0 of 3 is 0%" "[INFERRED] 0/3 0%" "$(row '[INFERRED]')"
printf '[]\n' > "$GD/prs.json"
runt bash "$TOOL" acme/r
assert_rc "AC2 no merged PRs exits 0" 0
assert_eq "AC2 no merged PRs: header" "merged PRs: 0" "$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_eq "AC2 no merged PRs: a dash, not a division by zero" "Weight: line 0/0 -" "$(row 'Weight: line')"
awk '{ gsub(/\},\{/, "},\n  {"); print }' "$GD/prs5.json" > "$GD/prs.json"
runt bash "$TOOL" acme/r
assert_eq "AC2 pretty-printed JSON over several lines counts the same" "Weight: line 3/5 60%" "$(row 'Weight: line')"
cp "$GD/prs5.json" "$GD/prs.json"

echo "AC4 usage errors exit 2 and never call gh"
usage_case() { # name args...
  local n="$1"; shift
  runt bash "$TOOL" "$@"
  assert_rc "AC4 $n: exit 2" 2
  assert_contains "AC4 $n: usage on stderr" "$OUT" "usage:"
  assert_eq "AC4 $n: gh not called" "0" "$( [ -f "$GD/args" ] && echo 1 || echo 0)"
}
usage_case "no arguments"
usage_case "repo without a slash" acme
usage_case "repo with two slashes" acme/r/x
usage_case "two repos" acme/r acme/s
usage_case "--limit 0" acme/r --limit 0
usage_case "--limit not a number" acme/r --limit abc
usage_case "--limit without a value" acme/r --limit
usage_case "--since not YYYY-MM-DD" acme/r --since 2026-1-9
usage_case "--since without a value" acme/r --since
usage_case "unknown option" acme/r --foo
runt bash "$TOOL" --help
assert_rc "AC4 --help exits 0" 0
assert_contains "AC4 --help prints the usage" "$OUT" "usage:"

echo "AC5 gh missing, failing or odd"
OUT="$(env PATH="$BIN:$PATH" GH_DIR="$GD" PLAYBOOK_GH="$GD/no-such-gh" bash "$TOOL" acme/r 2>&1 >/dev/null)"; RC=$?
assert_rc "AC5 gh missing: exit 3" 3
assert_contains "AC5 gh missing: message on stderr" "$OUT" "gh"
OUT="$(env PATH="$BIN:$PATH" GH_DIR="$GD" GH_FAIL=1 bash "$TOOL" acme/r 2>&1 >/dev/null)"; RC=$?
assert_rc "AC5 gh fails: exit 3" 3
assert_contains "AC5 gh fails: message on stderr" "$OUT" "gh"
OUT="$(env PATH="$BIN:$PATH" GH_DIR="$GD" GH_FAIL=1 bash "$TOOL" acme/r 2>/dev/null)"
assert_eq "AC5 gh fails: nothing on stdout" "" "$OUT"
printf 'not json\n' > "$GD/prs.json"
runt bash "$TOOL" acme/r
assert_rc "AC5 output that is not a JSON array: exit 3" 3
cp "$GD/prs5.json" "$GD/prs.json"

t_summary
