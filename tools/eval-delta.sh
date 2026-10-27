#!/usr/bin/env bash
# Prints the delta per check between the with and the without arm of a pinned eval run (v0.26.0), with 95% intervals (v0.29.0).
#   tools/eval-delta.sh [--per-arm] FILE.json [FILE2.json ...]
# FILE.json is the pb-evals/1 results file of evals/run-evals.sh (${OUT%.md}.json): one file with both arms, or one file per
# arm. Several files are pooled: runs of the same scenario, check and arm add up (k=3 runs from different days give n=6),
# so give every file of the same model, harness and playbook commit. Only runs[] is read, never summary, so the tables
# can be rebuilt from the runs alone. It prints a markdown table with
# one row per (scenario, check key) and the columns Scenario, Check, with pass@1 (n), without pass@1 (n), delta and Flag.
# n counts the PASS and FAIL results of graded runs (ERROR runs are left out of n and listed after the table as
# "errors: <labels>"); delta = with - without pass@1, two decimals; rows sorted by scenario, then check. Flag
# "non-discriminating": both arms pass at least 2/3 of their runs, or both pass none (the check cannot tell the arms apart).
# A check graded in one arm only (such as the without-arm isolation check) is listed under "## One arm only".
# Statistics (v0.29.0), printed after those lines and sections, which stay as they were:
#   "## Per arm: passes/n and Wilson 95% interval": one row per scenario, check and arm with passes/n (pooled n), pass@1
#     and the Wilson score interval (z = 1.96), three decimals.
#   "## Δ with a 95% interval (Newcombe hybrid score)": Δ = with - without pass@1 and its interval, built from the two Wilson
#     intervals (Newcombe 1998, method 10), with the verdict "Δ>0 (interval excludes 0)", "Δ<0 (excludes 0)" or
#     "inconclusive". With k=3 per arm most intervals include 0: pool more runs before calling a Δ.
#   "## Cost and time per passed run": per scenario and arm, the runs (ERROR runs too), the passed runs (graded, at least
#     one PASS and no FAIL), the mean cost_usd and seconds of all runs, and the mean divided by the pass rate (n/a when
#     none passed): a cost and lead-time proxy.
# --per-arm prints only the per-arm and the cost sections; it accepts runs of one arm only (no Δ is computed).
# The files must agree on model (never null: pass --model to run-evals.sh), playbook_commit and harness, and each scenario
# must have one fixture_tree and one prompt_sha across its runs.
# Exit: 0 ok | 1 an isolation check FAILed in a without run (its scenario's delta is not valid) | 2 usage or invalid input |
#       3 node missing.
set -u

usage() { sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "${1:-}" in "" | -h | --help) usage ;; esac
PER_ARM=0 nf=0
for f in "$@"; do
  case "$f" in
    -h | --help) usage ;;
    --per-arm) PER_ARM=1 ;;
    *) [ -f "$f" ] || { printf 'error: no such file: %s\n' "$f" >&2; exit 2; }; nf=$((nf + 1)) ;;
  esac
done
[ "$nf" -ge 1 ] || usage
for f in "$@"; do shift; [ "$f" = --per-arm ] || set -- "$@" "$f"; done
command -v node >/dev/null 2>&1 || { printf 'error: node (>= 18) is required\n' >&2; exit 3; }

PB_EVAL_DELTA_PER_ARM="$PER_ARM" exec node -e '
const fs = require("fs"), perArm = process.env.PB_EVAL_DELTA_PER_ARM === "1";
const files = process.argv.slice(1);
const ISO = "without arm: no playbook file read and no playbook Skill call";
const die = m => { process.stderr.write("error: " + m + "\n"); process.exit(2); };
const docs = files.map(f => {
  let j;
  try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch (e) { die(f + " is not JSON (" + e.message + ")"); }
  if (!j || typeof j !== "object" || Array.isArray(j)) die(f + " is not a pb-evals/1 document");
  if (j.schema !== "pb-evals/1") die(f + ": schema is " + JSON.stringify(j.schema) + ", not pb-evals/1");
  if (j.model === null || j.model === undefined || j.model === "") die(f + ": model is null (an unpinned run; run evals/run-evals.sh with --model)");
  if (!Array.isArray(j.runs)) die(f + ": runs is not a list");
  return j;
});
for (const k of ["model", "playbook_commit", "harness"]) {
  if (docs.some(d => d[k] !== docs[0][k])) die("the files differ in " + k + ": " + docs.map(d => JSON.stringify(d[k])).join(" vs "));
}
const runs = [].concat(...docs.map(d => d.runs));
const arms = new Set(runs.map(r => r.arm));
if (!perArm && (!arms.has("with") || !arms.has("without"))) die("only one arm present (" + [...arms].join(", ") + "); the delta needs runs of both arms, with and without");
const scen = new Map();
for (const r of runs) {
  if (!scen.has(r.scenario)) scen.set(r.scenario, { fixture_tree: new Set(), prompt_sha: new Set() });
  for (const f of ["fixture_tree", "prompt_sha"]) if (r[f] !== null && r[f] !== undefined) scen.get(r.scenario)[f].add(r[f]);
}
for (const [s, v] of scen) for (const f of ["fixture_tree", "prompt_sha"]) {
  if (v[f].size > 1) die("scenario " + s + ": the runs have different " + f + " values; the arms did not run the same fixture and prompt");
}
const g = new Map(), errors = [], isoFail = [], rs = new Map();
let dropped = 0;
for (const r of runs) {
  if (r.arm === "without" && typeof r.dropped_user_lines === "number" && r.dropped_user_lines > dropped) dropped = r.dropped_user_lines;
  if (r.arm === "with" || r.arm === "without") {
    const id = r.scenario + "\u0000" + r.arm;
    if (!rs.has(id)) rs.set(id, { scenario: r.scenario, arm: r.arm, runs: 0, passed: 0, cost: 0, costN: 0, sec: 0, secN: 0 });
    const x = rs.get(id), cks = Array.isArray(r.checks) ? r.checks : [];
    x.runs++;
    if (r.status === "graded" && cks.some(c => c.result === "PASS") && !cks.some(c => c.result === "FAIL")) x.passed++;
    if (typeof r.cost_usd === "number" && isFinite(r.cost_usd)) { x.cost += r.cost_usd; x.costN++; }
    if (typeof r.seconds === "number" && isFinite(r.seconds)) { x.sec += r.seconds; x.secN++; }
  }
  if (r.status === "error") { errors.push(r.label); continue; }
  if (r.status !== "graded" || (r.arm !== "with" && r.arm !== "without")) continue;
  for (const c of (Array.isArray(r.checks) ? r.checks : [])) {
    const key = (c.key === null || c.key === undefined) ? c.name : c.key;
    if (r.arm === "without" && c.result === "FAIL" && (key === ISO || String(c.name).indexOf(ISO) === 0)) { if (isoFail.indexOf(r.label) < 0) isoFail.push(r.label); }
    const id = r.scenario + "\u0000" + key;
    if (!g.has(id)) g.set(id, { scenario: r.scenario, key: key, with: { seen: false, n: 0, p: 0 }, without: { seen: false, n: 0, p: 0 } });
    const a = g.get(id)[r.arm];
    a.seen = true;
    if (c.result === "PASS") { a.n++; a.p++; } else if (c.result === "FAIL") a.n++;
  }
}
const num = s => { const m = /^E(\d+)/.exec(String(s)); return m ? Number(m[1]) : Infinity; };
const cmp = (x, y) => x < y ? -1 : x > y ? 1 : 0;
const ents = [...g.values()].sort((x, y) => (num(x.scenario) - num(y.scenario)) || cmp(String(x.scenario), String(y.scenario)) || cmp(String(x.key), String(y.key)));
const cell = s => String(s).replace(/\|/g, "\\|");
const rate = a => (a.p / a.n).toFixed(2) + " (" + a.n + ")";
const Z = 1.959963984540054;
const wilson = (p, n) => { const a = p / n, z2 = Z * Z, d = 1 + z2 / n, c = (a + z2 / (2 * n)) / d, h = Z * Math.sqrt(a * (1 - a) / n + z2 / (4 * n * n)) / d; return [Math.max(0, c - h), Math.min(1, c + h)]; };
const f3 = x => Math.abs(x) < 0.0005 ? "0.000" : x.toFixed(3);
const iv = (l, u) => "[" + f3(l) + ", " + f3(u) + "]";
const stats = () => {
  const s = [], nf = files.length;
  s.push("", "## Per arm: passes/n and Wilson 95% interval", "",
    "Runs pooled from " + nf + " file" + (nf === 1 ? "" : "s") + "; n counts the PASS and FAIL results of every graded run of the same scenario, check and arm.", "",
    "| Scenario | Check | Arm | passes/n | pass@1 | Wilson 95% |", "|---|---|---|---|---|---|");
  for (const e of ents) for (const a of ["with", "without"]) {
    const x = e[a];
    if (!x.n) continue;
    const w = wilson(x.p, x.n);
    s.push("| " + e.scenario + " | " + cell(e.key) + " | " + a + " | " + x.p + "/" + x.n + " | " + (x.p / x.n).toFixed(2) + " | " + iv(w[0], w[1]) + " |");
  }
  if (!perArm) {
    s.push("", "## Δ with a 95% interval (Newcombe hybrid score)", "",
      "| Scenario | Check | Δ | 95% interval | Verdict |", "|---|---|---|---|---|");
    for (const e of ents) {
      const w = e.with, wo = e.without;
      if (!w.seen || !wo.seen || !w.n || !wo.n) continue;
      const a = w.p / w.n, b = wo.p / wo.n, d = a - b, A = wilson(w.p, w.n), B = wilson(wo.p, wo.n);
      const lo = d - Math.sqrt((a - A[0]) ** 2 + (B[1] - b) ** 2), hi = d + Math.sqrt((A[1] - a) ** 2 + (b - B[0]) ** 2);
      const v = lo > 0 ? "Δ>0 (interval excludes 0)" : hi < 0 ? "Δ<0 (excludes 0)" : "inconclusive";
      s.push("| " + e.scenario + " | " + cell(e.key) + " | " + f3(d) + " | " + iv(lo, hi) + " | " + v + " |");
    }
  }
  s.push("", "## Cost and time per passed run", "",
    "A run passes when it is graded, with at least one PASS and no FAIL; per passed run = the mean of all runs / the pass rate.", "",
    "| Scenario | Arm | runs | passed | mean cost (USD) | cost per passed run (USD) | mean seconds | seconds per passed run |",
    "|---|---|---|---|---|---|---|---|");
  const armN = a => a === "with" ? 0 : 1;
  const rows = [...rs.values()].sort((x, y) => (num(x.scenario) - num(y.scenario)) || cmp(String(x.scenario), String(y.scenario)) || (armN(x.arm) - armN(y.arm)));
  for (const x of rows) {
    const mc = x.costN ? x.cost / x.costN : null, ms = x.secN ? x.sec / x.secN : null, pr = x.passed / x.runs;
    const per = (m, dp) => (m === null || !x.passed) ? "n/a" : (m / pr).toFixed(dp);
    s.push("| " + x.scenario + " | " + x.arm + " | " + x.runs + " | " + x.passed + " | " + (mc === null ? "n/a" : mc.toFixed(4)) + " | " + per(mc, 4) +
      " | " + (ms === null ? "n/a" : ms.toFixed(1)) + " | " + per(ms, 1) + " |");
  }
  return s;
};
if (perArm) {
  const p = ["# Per arm statistics (--per-arm: no Δ)", "",
    "Model: " + docs[0].model + ", harness: " + docs[0].harness + ", playbook commit: " + docs[0].playbook_commit];
  if (errors.length) p.push("", "errors: " + errors.join(", "));
  p.push(...stats());
  if (isoFail.length) p.push("", "isolation: FAIL in " + isoFail.join(", ") + "; the Δ of these scenarios is not valid");
  process.stdout.write(p.join("\n") + "\n");
  process.exit(isoFail.length ? 1 : 0);
}
const o = ["# Delta per check: with minus without pass@1", "",
  "Model: " + docs[0].model + ", harness: " + docs[0].harness + ", playbook commit: " + docs[0].playbook_commit, "",
  "| Scenario | Check | with pass@1 (n) | without pass@1 (n) | Δ | Flag |", "|---|---|---|---|---|---|"];
const one = [], ungraded = [];
for (const e of ents) {
  const w = e.with, wo = e.without;
  if (w.seen !== wo.seen) { const a = w.seen ? "with" : "without", x = w.seen ? w : wo; one.push("- " + e.scenario + " " + a + ": " + e.key + (x.n ? " (pass@1 " + rate(x) + ")" : " (MANUAL only)")); continue; }
  if (!w.n || !wo.n) { ungraded.push("- " + e.scenario + ": " + e.key); continue; }
  const r = Math.round((w.p * wo.n - wo.p * w.n) * 100 / (w.n * wo.n));
  const d = r === 0 ? "0.00" : (r / 100).toFixed(2);
  const flag = ((w.p * 3 >= w.n * 2 && wo.p * 3 >= wo.n * 2) || (w.p === 0 && wo.p === 0)) ? "non-discriminating" : "";
  o.push("| " + e.scenario + " | " + cell(e.key) + " | " + rate(w) + " | " + rate(wo) + " | " + d + " | " + flag + " |");
}
o.push("");
if (errors.length) o.push("errors: " + errors.join(", "));
if (dropped > 0) o.push("note: the without arm also dropped " + dropped + " non-playbook lines of ~/.claude/CLAUDE.md");
if (one.length) o.push("", "## One arm only", "", ...one);
if (ungraded.length) o.push("", "## Not auto-graded in both arms (MANUAL)", "", ...ungraded);
o.push(...stats());
if (isoFail.length) o.push("", "isolation: FAIL in " + isoFail.join(", ") + "; the Δ of these scenarios is not valid");
process.stdout.write(o.join("\n") + "\n");
process.exit(isoFail.length ? 1 : 0);' "$@"
