#!/usr/bin/env bash
# Tests for tools/shard-weights.sh (v0.16.0 AC2.1): refresh tests/shard-weights from the logs of a CI run.
# Never calls the real gh: a fake `gh` first on PATH answers from the files in $GH_DIR and records its calls.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/shard-weights.sh"
TAB=$'\t'; CR=$'\r'
RW0="$(cksum < "$PB_ROOT/tests/shard-weights" 2>/dev/null)"

BIN="$(mk_tmp)"; GD="$(mk_tmp)"
cat > "$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
# fake gh: `gh run view RUN [--repo R] --json jobs` and `gh run view --job ID [--repo R] --log`
printf '%s\n' "$*" >> "$GH_DIR/calls"
if [ -n "${GH_FAIL:-}" ]; then echo "gh: simulated failure" >&2; exit 1; fi
[ "$1" = auth ] && exit 0
if [ "$1" = api ]; then   # gh api repos/OWNER/NAME/actions/jobs/ID/logs
  id="$(printf '%s' "$2" | sed -n 's#^repos/[^/]*/[^/]*/actions/jobs/\([0-9][0-9]*\)/logs$#\1#p')"
  [ -n "$id" ] || { echo "fake gh: unsupported api path $2" >&2; exit 64; }
  cat "$GH_DIR/apilog-$id.txt" 2>/dev/null || { echo "gh: HTTP 404" >&2; exit 1; }
  exit 0
fi
if [ "$1" != run ] || [ "$2" != view ]; then echo "fake gh: unsupported: $*" >&2; exit 64; fi
shift 2
job=""; json=""; run=""
while [ $# -gt 0 ]; do
  case "$1" in
    --job) job="$2"; shift 2 ;;
    --json) json="$2"; shift 2 ;;
    --repo) shift 2 ;;
    --log) shift ;;
    -*) echo "fake gh: unsupported option $1" >&2; exit 64 ;;
    *) run="$1"; shift ;;
  esac
done
if [ -n "$job" ]; then
  cat "$GH_DIR/log-$job.txt" 2>/dev/null || { echo "gh: log not found for job $job" >&2; exit 1; }
  exit 0
fi
if [ "$json" != jobs ]; then echo "fake gh: unsupported (need --json jobs): $*" >&2; exit 64; fi
cat "$GH_DIR/jobs-$run.json" 2>/dev/null || { echo "gh: could not find run $run" >&2; exit 1; }
FAKE
chmod +x "$BIN/gh"

# runt CMD... -> runs CMD with the fake gh first on PATH; clears the call record; sets OUT and RC
runt() { rm -f "$GD/calls"; run env PATH="$BIN:$PATH" GH_DIR="$GD" "$@"; }
# data FILE -> the weights lines (no # comments, no blank lines)
data() { grep -v '^#' "$1" 2>/dev/null | grep -v '^$'; }
# job ID NAME -> one entry of the `gh run view --json jobs` array
job() { printf '{"databaseId":%s,"name":"%s","status":"completed","conclusion":"success","steps":[{"name":"Set up job","number":1}]}' "$1" "$2"; }

# ---- run 5551: three shard jobs (901-903) plus decoys (904 ubuntu, 905 macos, 906 aggregate) ----
printf '{"jobs":[%s,%s,%s,%s,%s,%s]}\n' "$(job 901 'windows shard 1/3')" "$(job 902 'windows shard 2/3')" "$(job 903 'windows shard 3/3')" \
  "$(job 904 ubuntu-latest)" "$(job 905 macos-latest)" "$(job 906 'test (windows-latest)')" > "$GD/jobs-5551.json"
{
  echo "windows shard 1/3${TAB}Set up job${TAB}2026-10-11T10:00:00.1000000Z Current runner version: 2.320.0"
  echo "windows shard 1/3${TAB}Tests and static checks (shard)${TAB}2026-10-11T10:01:00.0000000Z == tests/test-big.sh (392 s)"
  echo "windows shard 1/3${TAB}Tests and static checks (shard)${TAB}2026-10-11T10:01:01.0000000Z   ok   AC1 something passed"
  echo "== tests/test-dup.sh (50 s)"
  echo "== tests/test-lex.sh (9 s)${CR}"
  echo "== tests/test-rev.sh (90 s)"
  echo "== evals/run-checks.sh (static skill checks)"
  echo "tests/test-nohead.sh (44 s)"
  echo "== tests/test-bad.sh (abc s)"
  echo "== tests/test-sec.sh (12 sec)"
  echo "ok test-fake.sh passed in 500 s"
} > "$GD/log-901.txt"
{
  echo "windows shard 2/3${TAB}Tests and static checks (shard)${TAB}2026-10-11T10:02:00.0000000Z == tests/test-dup.sh (80 s)"
  echo "== tests/test-rev.sh (20 s)"
  echo "== tests/test-nine.sh (9 s)"
  echo "some noise line == not a heading"
} > "$GD/log-902.txt"
{
  echo "== tests/test-lex.sh (85 s)"
  echo "== tests/test-same.sh (30 s)"
  echo "== tests/test-same.sh (31 s)${CR}"
  echo "== tests/test-small.sh (7 s)"
  echo "== tests/test-hund.sh (100 s)"
} > "$GD/log-903.txt"
echo "== tests/test-linuxonly.sh (777 s)" > "$GD/log-904.txt"
echo "== tests/test-macos.sh (888 s)" > "$GD/log-905.txt"
echo "== tests/test-agg.sh (999 s)" > "$GD/log-906.txt"
EXP="test-big.sh 392
test-hund.sh 100
test-rev.sh 90
test-lex.sh 85
test-dup.sh 80
test-same.sh 31
test-nine.sh 9
test-small.sh 7"

echo "AC2.1 the weights file: content, order, header"
D="$(mk_tmp)"; F="$D/weights"
printf '# old\ntest-gone.sh 999\n' > "$F"
runt bash "$TOOL" 5551 --repo acme/pb --out "$F"
assert_rc "AC2.1 a run with shard logs exits 0" 0
assert_eq "AC2.1 the weights are sorted by seconds descending, one 'test-x.sh N' line per suite" "$EXP" "$(data "$F")"
assert_eq "AC2.1 the first line is a # header" "#" "$(head -n 1 "$F" 2>/dev/null | cut -c1)"
if grep '^#' "$F" 2>/dev/null | grep -q '5551'; then t_ok "AC2.1 the # header names the run id"; else t_bad "AC2.1 the # header names the run id" "$(head -n 3 "$F" 2>/dev/null)"; fi
assert_eq "AC2.1 the header comes first: no # line after a weights line" "0" "$(awk '/^[^#]/ { d = 1 } d && /^#/ { n++ } END { print n + 0 }' "$F" 2>/dev/null)"
assert_eq "AC2.1 the file has no carriage returns (logs may carry CR)" "0" "$(grep -c "$CR" "$F" 2>/dev/null)"
assert_not_contains "AC2.1 the previous content of the file is replaced" "$(cat "$F" 2>/dev/null)" "test-gone"
assert_eq "AC2.1 the output directory holds only the weights file (no temp leftovers)" "weights" "$(ls -A "$D")"
assert_eq "AC2.1 a suite seen in two shards keeps the larger number (50 then 80)" "test-dup.sh 80" "$(data "$F" | grep '^test-dup.sh ')"
assert_eq "AC2.1 a suite seen in two shards keeps the larger number (90 then 20)" "test-rev.sh 90" "$(data "$F" | grep '^test-rev.sh ')"
assert_eq "AC2.1 the larger number wins numerically, not as text (9 vs 85)" "test-lex.sh 85" "$(data "$F" | grep '^test-lex.sh ')"
assert_eq "AC2.1 a suite seen twice in one job keeps the larger number (30, 31)" "test-same.sh 31" "$(data "$F" | grep '^test-same.sh ')"
assert_eq "AC2.1 seconds sort numerically (100 before 9 and 7)" "test-hund.sh 100" "$(data "$F" | sed -n 2p)"

echo "AC2.1 only the windows shard jobs are read"
assert_not_contains "AC2.1 headings of the ubuntu job are not used" "$(cat "$F" 2>/dev/null)" "linuxonly"
assert_not_contains "AC2.1 headings of the macos job are not used" "$(cat "$F" 2>/dev/null)" "test-macos"
assert_not_contains "AC2.1 headings of the 'test (windows-latest)' aggregate job are not used" "$(cat "$F" 2>/dev/null)" "test-agg"
assert_eq "AC2.1 exactly the three shard logs were fetched (--job 901, 902, 903)" "3" "$(grep -c -e '--job' "$GD/calls" 2>/dev/null)"
assert_eq "AC2.1 no log was fetched for the other jobs (904, 905, 906)" "0" "$(grep -c -E -e '--job[ =]90[456]' "$GD/calls" 2>/dev/null)"
assert_eq "AC2.1 the shard logs were fetched with --log" "3" "$(grep -e '--job' "$GD/calls" 2>/dev/null | grep -c -e '--log')"
assert_eq "AC2.1 the jobs list was fetched once: gh run view 5551 --json jobs" "1" "$(grep -c -e '--json jobs' "$GD/calls" 2>/dev/null)"
assert_eq "AC2.1 the jobs call names run 5551" "1" "$(grep -e '--json jobs' "$GD/calls" 2>/dev/null | grep -c '5551')"
echo "AC2.1 --repo is passed to every gh call"
assert_eq "AC2.1 --repo acme/pb on the jobs call" "1" "$(grep -e '--json jobs' "$GD/calls" 2>/dev/null | grep -c -e '--repo acme/pb')"
assert_eq "AC2.1 --repo acme/pb on every log call" "3" "$(grep -e '--job' "$GD/calls" 2>/dev/null | grep -c -e '--repo acme/pb')"

echo "AC2.1 option order, relative --out, default file"
D2="$(mk_tmp)"
runt bash "$TOOL" --out "$D2/w2" --repo acme/pb 5551
assert_rc "AC2.1 the run id may come after the options" 0
assert_eq "AC2.1 same weights when the run id comes last" "$EXP" "$(data "$D2/w2")"
runt bash "$TOOL" 5551 --out "$D2/w3"
assert_rc "AC2.1 --repo is optional (gh infers it)" 0
assert_eq "AC2.1 same weights without --repo" "$EXP" "$(data "$D2/w3")"
assert_eq "AC2.1 without --repo no --repo is passed to gh" "0" "$(grep -c -e '--repo' "$GD/calls" 2>/dev/null)"
D3="$(mk_tmp)"
OUT="$(cd "$D3" && env PATH="$BIN:$PATH" GH_DIR="$GD" bash "$TOOL" 5551 --out rel.txt 2>&1)"; RC=$?
assert_rc "AC2.1 a relative --out exits 0" 0
assert_eq "AC2.1 a relative --out is resolved from the caller's cwd" "$EXP" "$(data "$D3/rel.txt")"
C="$(mk_tmp)"; mkdir -p "$C/tests"; cp -R "$PB_ROOT/tools" "$PB_ROOT/scripts" "$C/"
printf '# old\ntest-gone.sh 999\n' > "$C/tests/shard-weights"
OUT="$(cd "$C" && env PATH="$BIN:$PATH" GH_DIR="$GD" bash tools/shard-weights.sh 5551 2>&1)"; RC=$?
assert_rc "AC2.1 without --out the run exits 0" 0
assert_eq "AC2.1 the default file is tests/shard-weights" "$EXP" "$(data "$C/tests/shard-weights")"
assert_not_contains "AC2.1 the default file is rewritten, not appended to" "$(cat "$C/tests/shard-weights" 2>/dev/null)" "test-gone"

echo "AC2.1 no headings found: exit 1, file untouched"
printf '{"jobs":[%s,%s]}\n' "$(job 921 'windows shard 1/3')" "$(job 922 'windows shard 2/3')" > "$GD/jobs-5552.json"
printf '%s\n' "windows shard 1/3${TAB}Run${TAB}2026-10-11T10:01:00.0000000Z all fine" "== evals/run-checks.sh (static skill checks)" "tests/test-nohead.sh (44 s)" "== tests/test-bad.sh (abc s)" > "$GD/log-921.txt"
echo "nothing to see" > "$GD/log-922.txt"
D4="$(mk_tmp)"; F4="$D4/weights"; printf '# keep\ntest-old.sh 5\n' > "$F4"; K4="$(cat "$F4")"
runt bash "$TOOL" 5552 --out "$F4"
assert_rc "AC2.1 shard logs without any heading exit 1" 1
assert_eq "AC2.1 the weights file is untouched when no heading is found" "$K4" "$(cat "$F4")"
assert_eq "AC2.1 no temp file is left next to it" "weights" "$(ls -A "$D4")"
F5="$D4/new-weights"
runt bash "$TOOL" 5552 --out "$F5"
assert_rc "AC2.1 no headings and no previous file: exit 1" 1
assert_no_path "AC2.1 no headings: a missing weights file is not created" "$F5"
printf '{"jobs":[%s]}\n' "$(job 931 ubuntu-latest)" > "$GD/jobs-5553.json"
echo "== tests/test-linuxonly.sh (777 s)" > "$GD/log-931.txt"
runt bash "$TOOL" 5553 --out "$F5"
assert_rc "AC2.1 a run without windows shard jobs (headings only elsewhere) exits 1" 1
assert_no_path "AC2.1 no shard jobs: the weights file is not created" "$F5"
assert_eq "AC2.1 no shard jobs: no log was fetched" "0" "$(grep -c -e '--job' "$GD/calls" 2>/dev/null)"

echo "AC2.1 usage errors exit 2 (before gh is called, file untouched)"
printf '# keep\ntest-old.sh 5\n' > "$C/tests/shard-weights"; K6="$(cat "$C/tests/shard-weights")"
usage_case() { # name args...
  local n="$1"; shift
  rm -f "$GD/calls"
  OUT="$(cd "$C" && env PATH="$BIN:$PATH" GH_DIR="$GD" bash tools/shard-weights.sh "$@" 2>&1)"; RC=$?
  assert_rc "AC2.1 $n exits 2" 2
  assert_no_path "AC2.1 $n: gh is not called" "$GD/calls"
  assert_eq "AC2.1 $n: the weights file is untouched" "$K6" "$(cat "$C/tests/shard-weights")"
  if printf '%s' "$OUT" | grep -qi usage; then t_ok "AC2.1 $n: the message shows the usage"; else t_bad "AC2.1 $n: the message shows the usage" "$OUT"; fi
}
usage_case "no arguments"
usage_case "a non-numeric run id (abc)" abc
usage_case "a run id with a suffix (12x)" 12x
usage_case "an empty run id" ""
usage_case "an unknown option after the run id" 5551 --bogus
usage_case "an unknown option before the run id" --bogus 5551
usage_case "--repo without a value" 5551 --repo
usage_case "--out without a value" 5551 --out
usage_case "options only, no run id" --repo acme/pb --out "$C/tests/shard-weights"

echo "AC2.1 gh failures exit 3, file untouched"
D7="$(mk_tmp)"; F7="$D7/weights"; printf '# keep\ntest-old.sh 5\n' > "$F7"; K7="$(cat "$F7")"
rm -f "$GD/calls"; OUT="$(env PATH="$BIN:$PATH" GH_DIR="$GD" GH_FAIL=1 bash "$TOOL" 5551 --out "$F7" 2>&1)"; RC=$?
assert_rc "AC2.1 gh failing on every call exits 3" 3
assert_eq "AC2.1 gh failing: the weights file is untouched" "$K7" "$(cat "$F7")"
runt bash "$TOOL" 9999 --out "$F7"
assert_rc "AC2.1 gh cannot find the run (no such run id): exit 3" 3
assert_eq "AC2.1 unknown run: the weights file is untouched" "$K7" "$(cat "$F7")"
printf '{"jobs":[%s,%s]}\n' "$(job 941 'windows shard 1/3')" "$(job 942 'windows shard 2/3')" > "$GD/jobs-5554.json"
echo "== tests/test-big.sh (392 s)" > "$GD/log-941.txt"     # no log-942.txt: that log fetch fails
runt bash "$TOOL" 5554 --out "$F7"
assert_rc "AC2.1 one shard log cannot be fetched: exit 3 (not 0 with a partial file)" 3
assert_eq "AC2.1 a failing shard log leaves the weights file untouched (no partial write)" "$K7" "$(cat "$F7")"
assert_eq "AC2.1 no temp file is left next to it" "weights" "$(ls -A "$D7")"

assert_eq "AC2.1 the real tests/shard-weights was never touched by these runs" "$RW0" "$(cksum < "$PB_ROOT/tests/shard-weights" 2>/dev/null)"

# ---- v0.16.0 (found on a real run): gh 2.45 prints an EMPTY log for `run view --job --log`;
# the tool then reads the job log through the API (repos/OWNER/NAME/actions/jobs/ID/logs) ----
echo "empty run-view log -> API fallback"
printf '{"jobs":[%s,%s]}\n' "$(job 971 'windows shard 1/2')" "$(job 972 'windows shard 2/2')" > "$GD/jobs-7771.json"
: > "$GD/log-971.txt"; : > "$GD/log-972.txt"
printf 'windows shard 1/2\tTests\t2026-10-11T10:00:00Z == tests/test-api-a.sh (61 s)\n' > "$GD/apilog-971.txt"
printf '== tests/test-api-b.sh (42 s)\n' > "$GD/apilog-972.txt"
OUTF="$(mk_tmp)/w"
runt bash "$TOOL" 7771 --repo acme/pb --out "$OUTF"
assert_rc "API fallback: exit 0" 0
assert_eq "API fallback: weights come from the API logs" "test-api-a.sh 61
test-api-b.sh 42" "$(data "$OUTF")"
assert_eq "API fallback: the API path names the repo and job" "2" "$(grep -c -E '^api repos/acme/pb/actions/jobs/97[12]/logs' "$GD/calls")"
OUTF2="$(mk_tmp)/w"
runt bash "$TOOL" 7771 --out "$OUTF2"
assert_eq "API fallback without --repo uses {owner}/{repo}" "2" "$(grep -c -F 'api repos/{owner}/{repo}/actions/jobs/' "$GD/calls")"
rm -f "$GD/apilog-972.txt"
OUTF3="$(mk_tmp)/w"; printf 'old\n' > "$OUTF3"
runt bash "$TOOL" 7771 --repo acme/pb --out "$OUTF3"
assert_rc "API fallback failing for one job -> exit 3" 3
assert_eq "API fallback failing: file untouched" "old" "$(cat "$OUTF3")"

# ---- v0.24.16 AC1-AC4: --check, every suite in the weights file's directory has exactly one weight line ----
echo "--check: suite coverage"
CK="$(mk_tmp)"
: > "$CK/test-a.sh"; : > "$CK/test-b.sh"; : > "$CK/test-c.sh"; : > "$CK/helper.sh"
printf '# header\n\ntest-a.sh 100\ntest-b.sh 50\ntest-c.sh 7\n' > "$CK/shard-weights"
run bash "$TOOL" --check "$CK/shard-weights"
assert_rc "AC1 all suites weighted: exit 0" 0
assert_contains "AC1 all suites weighted: says so with the count" "$OUT" "shard weights: 3 suites, all weighted"
printf 'test-a.sh 100\ntest-c.sh 7\n' > "$CK/shard-weights"
run bash "$TOOL" --check "$CK/shard-weights"
assert_rc "AC1 a suite without a weight line: exit 1" 1
assert_contains "AC1 names the suite without a weight" "$OUT" "no weight: test-b.sh"
assert_not_contains "AC1 a non-suite file (helper.sh) is not a suite" "$OUT" "helper.sh"
printf 'test-a.sh 100\ntest-b.sh 50\ntest-c.sh 7\ntest-gone.sh 300\n' > "$CK/shard-weights"
run bash "$TOOL" --check "$CK/shard-weights"
assert_rc "AC1 a line for a missing suite: exit 1" 1
assert_contains "AC1 names the stale weight" "$OUT" "stale weight: test-gone.sh"
printf 'test-a.sh 100\ntest-b.sh 50\ntest-c.sh 7\ntest-b.sh 60\n' > "$CK/shard-weights"
run bash "$TOOL" --check "$CK/shard-weights"
assert_rc "AC1 a suite listed twice: exit 1" 1
assert_contains "AC1 names the duplicate" "$OUT" "duplicate weight: test-b.sh"
printf '# c\r\ntest-a.sh 100\r\n\r\ntest-b.sh 50\r\ntest-c.sh 7\r\n' > "$CK/shard-weights"
run bash "$TOOL" --check "$CK/shard-weights"
assert_rc "AC2 CRLF lines, comments and blank lines: exit 0" 0
assert_not_contains "AC2 CRLF: no suite reported" "$OUT" "weight: "
run bash "$TOOL" --check "$CK/no-such-file"
assert_rc "AC3 unreadable weights file: exit 3" 3
run bash "$TOOL" --check 123
assert_rc "AC3 --check with a run id: exit 2 (usage)" 2
run bash "$TOOL" --check "$CK/shard-weights" --out "$CK/x"
assert_rc "AC3 --check with --out: exit 2 (usage)" 2
assert_no_path "AC3 --check never writes --out" "$CK/x"
run bash "$TOOL" --check
assert_rc "AC4 the real tests/shard-weights weights every suite exactly once" 0
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | sed 's/^/       /'

t_summary
