#!/usr/bin/env bash
# Shared setup of the release suites (tests/test-release-tool.sh, tests/test-release.sh; v0.32.0 slice S3, AC7): a fixture repo that
# ships tools/release-gate.sh and tools/eval-delta.sh and can hold a synthetic, COMMITTED, passing release gate, so that the
# release tools (release.sh, release-pr-check.sh --gate) see a gate for the fixture commit. The gate files are pb-evals/1 files
# (a variant object with sha = the gate commit, 5 graded runs per arm and item) pooled by the real
# `tools/release-gate.sh --pool-only`, then committed (see tests/test-release-gate-check.sh). The fake runners fail if they are
# ever called: a release tool must never spend money. Source it after lib.sh (it needs mk_tmp, node and git). It is not a suite:
# run-all.sh only starts tests/test-*.sh.
RGF_TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
RGF_W="$(mk_tmp)"
mkdir -p "$RGF_W/home" "$RGF_W/tmp"
rgf_git() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false -c core.autocrlf=false "$@"; }
# rgf_gate_scen FILE LIST (v0.32.0 slice S6, AC7''): the fixture's copy of tools/release-gate.sh gets GATE_SCENARIOS="LIST", a subset of the
# fixture's fake AUTO. The line is replaced when the script has one, else inserted before the DEFAULT_TASKS line (a no-op for a script that
# does not read it yet, so the same fixture serves the script before and after the gate gains the line). The file keeps its mode.
rgf_gate_scen() {
  local f="$1" l="$2" t
  t="$(mktemp)" || return 1
  if grep -q '^GATE_SCENARIOS=' "$f"; then sed "s/^GATE_SCENARIOS=.*/GATE_SCENARIOS=\"$l\"/" "$f" > "$t"
  else awk -v l="$l" '/^DEFAULT_TASKS=/ && !d { print "GATE_SCENARIOS=\"" l "\""; d = 1 } { print }' "$f" > "$t"; fi
  cat "$t" > "$f"; rm -f "$t"
}
# rgf_prepare REPO: tools, task dirs and fake runners (AUTO="E1 E2 E3", GATE_SCENARIOS="E1 E2 E3"); nothing is committed
rgf_prepare() {
  local r="$1" t
  mkdir -p "$r/tools" "$r/evals/tasks"
  cp -p "$PB_ROOT/tools/release-gate.sh" "$r/tools/release-gate.sh"
  rgf_gate_scen "$r/tools/release-gate.sh" "E1 E2 E3"
  cp -p "$PB_ROOT/tools/eval-delta.sh" "$r/tools/eval-delta.sh"
  for t in $(printf '%s' "$RGF_TASKS" | tr ',' ' '); do mkdir -p "$r/evals/tasks/$t"; printf 'x\n' > "$r/evals/tasks/$t/prompt.md"; done
  printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3"\necho "fixture runner called: $0 $*" >&2\nexit 99\n' > "$r/evals/run-evals.sh"
  printf '#!/usr/bin/env bash\necho "fixture runner called: $0 $*" >&2\nexit 99\n' > "$r/evals/run-outcome.sh"
  chmod 755 "$r/evals/run-evals.sh" "$r/evals/run-outcome.sh"
}
# rgf_jfile OUT COMMIT MODEL ITEMS [INVERT]: a pb-evals/1 file; with passes, without fails (items in INVERT: the other way round)
rgf_jfile() {
  local out="$1" commit="$2" model="$3" list="$4" inv="${5:-}" runs="" sep="" s i arm r
  for s in $(printf '%s' "$list" | tr ',' ' '); do
    i=1
    while [ "$i" -le 5 ]; do
      for arm in with without; do
        r=PASS; [ "$arm" = without ] && r=FAIL
        case ",$inv," in *",$s,"*) if [ "$r" = PASS ]; then r=FAIL; else r=PASS; fi ;; esac
        runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$arm\",\"k\":$i,\"label\":\"$s.$arm.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"PASS\"}]}"
        sep=","
      done
      i=$((i + 1))
    done
  done
  printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"claude","model":"%s","arms":["with","without"],"repeat":5,"max_cost":null,"interactive":false,"hooks":true,"started":"2026-10-27T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.30.0","sha":"%s","end_check":"ok"},"runs":[%s],"summary":[]}\n' \
    "$commit" "$model" "$commit" "$runs" > "$out"
}
# rgf_seal REPO [INVERT]: a gate for the commit at HEAD of REPO, committed as one more commit (evals/results/gate-<12 hex> only).
# With INVERT (an item such as E2) that item has a negative delta, so the real verdict is fail. Does not push.
rgf_seal() {
  local r="$1" inv="${2:-}" c d items
  c="$(git -C "$r" rev-parse HEAD)" || return 1
  d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
  items="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$r/evals/run-evals.sh" | head -n 1 | tr -s ' ' ',')"
  rgf_jfile "$d/behaviour-m1.json" "$c" m1 "$items" "$inv"
  rgf_jfile "$d/outcome-m1.json" "$c" m1 "$RGF_TASKS" "$inv"
  # A passing verdict exits 0; a failing one (INVERT set) exits 1 and is still committed. Any other code is a fixture error.
  local rc=0
  ( cd "$r" && env HOME="$RGF_W/home" TMPDIR="$RGF_W/tmp" bash tools/release-gate.sh --harness claude --model m1 --pool-only --out-dir "evals/results/${d##*/}" >/dev/null 2>&1 ) || rc=$?
  if [ -n "$inv" ]; then [ "$rc" -eq 1 ] || return 1; else [ "$rc" -eq 0 ] || return 1; fi
  rgf_git -C "$r" add -- "evals/results/${d##*/}" && rgf_git -C "$r" commit -qm "gate results for ${c%"${c#????????????}"}"
}

# ---- v0.34.0 slice B1 (G1/G2): a fake `gh` for the real-run CI check of tools/release-gate.sh ---------------------------------------
# A real gate run reads the CI check runs of HEAD (`gh api --paginate repos/OWNER/REPO/commits/SHA/check-runs --jq '.check_runs[]'`, and
# `gh api repos/OWNER/REPO/actions/jobs/ID` for a red check run) before anything else. The fake serves REST payloads in the shape GitHub
# returns (snake_case; names, ids, statuses and step names are those of a captured payload, the repository is anonymised to acme/widgets)
# from DIR/data, logs every call to DIR/gh.log, and refuses any other command (exit 64: `gh pr checks` is never read). With no data
# set, every check run is green. Needs node (no jq: it may be missing on CI); a --jq that is a plain path (.check_runs[], .steps[], .a.b)
# is evaluated by node, anything else needs a jq binary.
#   rgf_gh_install DIR    install DIR/bin/gh and the default green data; the suite puts DIR/bin on PATH and sets PB_GATE_REPO=acme/widgets
#   rgf_gh_green          back to the default (all check runs green); removes failure switches and job files
#   rgf_gh_runs [--per-page N] "ID|NAME|STATUS|CONCLUSION"...   the check runs served (an empty CONCLUSION is null; --per-page splits the pages)
#   rgf_gh_job ID NAME CONCLUSION "NUMBER|STEP NAME|CONCLUSION"...   the Actions job ID (its steps), served at actions/jobs/ID
#   rgf_gh_sample_red_gate_only   the captured shape: `test (ubuntu-latest)` failed only in its "Release gate" step, the rest green or skipped
#   rgf_gh_fail checks|jobs|all   the call exits 1 with an HTTP error (an API error)
#   rgf_gh_clearlog       empty the call log (every rgf_gh_green does too)
#   rgf_gh_calls          the call log, one line per call, then rgf_gh_ncalls for its length
rgf_gh_install() {
  local d="$1"
  mkdir -p "$d/bin" "$d/data"
  cat > "$d/gen.js" <<'JS'
const fs = require("fs"), path = require("path");
const [kind, dir, ...a] = process.argv.slice(2);
const SHA = "7f9cdd89064a8a20f4debb19cfd4b9a7b194e3f0", REPO = "acme/widgets";
if (kind === "runs") {
  let per = 100;
  if (a[0] === "--per-page") { per = Number(a[1]); a.splice(0, 2); }
  const runs = a.map(s => { const p = s.split("|");
    return { id: Number(p[0]), name: p[1], node_id: "CR_" + p[0], head_sha: SHA, external_id: "ext-" + p[0],
      url: "https://api.github.com/repos/" + REPO + "/check-runs/" + p[0], html_url: "https://github.com/" + REPO + "/actions/runs/1/job/" + p[0],
      details_url: "https://github.com/" + REPO + "/actions/runs/1/job/" + p[0], status: p[2], conclusion: p[3] === "" ? null : p[3],
      started_at: "2026-11-01T12:36:35Z", completed_at: p[2] === "completed" ? "2026-11-01T12:50:01Z" : null,
      output: { title: null, summary: null, text: null, annotations_count: 0 },
      check_suite: { id: 1 }, app: { id: 15368, slug: "github-actions", name: "GitHub Actions" }, pull_requests: [] }; });
  for (const f of fs.readdirSync(dir)) if (/^check-runs-\d+\.json$/.test(f)) fs.unlinkSync(path.join(dir, f));
  const pages = Math.max(1, Math.ceil(runs.length / per));
  for (let i = 0; i < pages; i++)
    fs.writeFileSync(path.join(dir, "check-runs-" + (i + 1) + ".json"), JSON.stringify({ total_count: runs.length, check_runs: runs.slice(i * per, (i + 1) * per) }) + "\n");
} else if (kind === "job") {
  const [id, name, concl, ...steps] = a;
  const st = steps.map(s => { const p = s.split("|");
    return { name: p[1], status: "completed", conclusion: p[2], number: Number(p[0]), started_at: "2026-11-01T12:36:37Z", completed_at: "2026-11-01T12:36:38Z" }; });
  fs.writeFileSync(path.join(dir, "job-" + id + ".json"), JSON.stringify({ id: Number(id), run_id: 1, workflow_name: "test", head_branch: "feat/x", head_sha: SHA,
    url: "https://api.github.com/repos/" + REPO + "/actions/jobs/" + id, status: "completed", conclusion: concl, name, steps: st,
    check_run_url: "https://api.github.com/repos/" + REPO + "/check-runs/" + id, labels: ["ubuntu-latest"] }) + "\n");
}
JS
  cat > "$d/bin/gh" <<'SH'
#!/usr/bin/env bash
# fake gh (tests/release-gate-fixture.sh): only `gh api`; data and log next to bin/
D="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$*" >> "$D/gh.log"
[ "${1:-}" = api ] || { echo "fake gh: unexpected command: gh $*" >&2; exit 64; }
shift
pag=0; jq=""; ep=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) pag=1 ;;
    --jq | -q) jq="$2"; shift ;;
    -H | --header | -X | --method | -f | -F | --field | --raw-field | --hostname | --cache) shift ;;
    -*) ;;
    *) ep="$1" ;;
  esac
  shift
done
[ ! -e "$D/data/fail-all" ] || { echo "gh: HTTP 500: server error (fake)" >&2; exit 1; }
emit() { # FILE...: the files, or their --jq filter
  if [ -z "$jq" ]; then cat "$@"; return 0; fi
  local re='^\.[A-Za-z0-9_.]*(\[\])?[A-Za-z0-9_.]*(\[\])?$'
  if [[ "$jq" =~ $re ]]; then
    node -e '
const fs = require("fs");
const parts = process.argv[1].replace(/\[\]/g, ".[]").split(".").filter(Boolean);
for (const f of process.argv.slice(2)) {
  let vs = [JSON.parse(fs.readFileSync(f, "utf8"))];
  for (const p of parts) vs = p === "[]" ? vs.flatMap(v => Array.isArray(v) ? v : []) : vs.map(v => v == null ? null : v[p]);
  for (const v of vs) console.log(typeof v === "string" ? v : JSON.stringify(v));
}' "$jq" "$@"; return $?
  fi
  command -v jq >/dev/null 2>&1 || { echo "fake gh: unsupported --jq without a jq binary: $jq" >&2; exit 65; }
  local f; for f in "$@"; do jq -c "$jq" "$f"; done
}
case "$ep" in
  repos/*/commits/*/check-runs*)
    [ ! -e "$D/data/fail-checks" ] || { echo "gh: HTTP 403: rate limit exceeded (fake)" >&2; exit 1; }
    pages=( $(ls "$D"/data/check-runs-*.json 2>/dev/null | sort -t- -k3 -n) )
    [ "${#pages[@]}" -gt 0 ] || { echo "fake gh: no check-runs data" >&2; exit 66; }
    [ "$pag" = 1 ] || pages=( "${pages[0]}" )
    emit "${pages[@]}" ;;
  repos/*/actions/jobs/*)
    [ ! -e "$D/data/fail-jobs" ] || { echo "gh: HTTP 502: bad gateway (fake)" >&2; exit 1; }
    f="$D/data/job-${ep##*/jobs/}.json"
    [ -f "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    emit "$f" ;;
  *) echo "fake gh: unexpected endpoint: $ep" >&2; exit 64 ;;
esac
SH
  chmod 755 "$d/bin/gh"
  RGF_GH="$d"
  rgf_gh_green
}
rgf_gh_green() {
  rm -f "$RGF_GH"/data/job-*.json "$RGF_GH"/data/fail-* "$RGF_GH/gh.log"; : > "$RGF_GH/gh.log"
  rgf_gh_runs "124850217910|test (ubuntu-latest)|completed|success" "124854622507|test (windows-latest)|completed|success" \
    "124854646566|release|completed|skipped" "124850191813|changes|completed|success"
}
rgf_gh_runs() { node "$RGF_GH/gen.js" runs "$RGF_GH/data" "$@"; }
rgf_gh_job() { local id="$1" n="$2" c="$3"; shift 3; node "$RGF_GH/gen.js" job "$RGF_GH/data" "$id" "$n" "$c" "$@"; }
rgf_gh_sample_red_gate_only() {
  rgf_gh_runs "124854646566|release|completed|skipped" "124854622507|test (windows-latest)|completed|success" \
    "124853028073|test (macos-latest)|completed|success" "124850218254|windows shard 8/8|completed|success" \
    "124850217910|test (ubuntu-latest)|completed|failure" "124850217855|macos shard 1/2|completed|success" \
    "124850193197|main-ci|completed|skipped" "124850191813|changes|completed|success"
  rgf_gh_job 124850217910 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Run actions/checkout@v5|success" "3|Versions|success" \
    "4|Release PR check (VERSION changed -> tools/check-release.sh)|success" "5|Docs-only checks|skipped" "6|Tests and static checks|success" \
    "7|Release gate (a PR that changes VERSION needs a committed passing gate)|failure" "8|README test count (Linux only)|skipped" \
    "16|Post Run actions/checkout@v5|success" "17|Complete job|success"
}
rgf_gh_fail() { : > "$RGF_GH/data/fail-$1"; }
rgf_gh_clearlog() { : > "$RGF_GH/gh.log"; }
rgf_gh_calls() { cat "$RGF_GH/gh.log"; }
rgf_gh_ncalls() { grep -c . "$RGF_GH/gh.log" || true; }
