#!/usr/bin/env bash
# Prints the delta per check between the with and the without arm of a pinned eval run (v0.26.0).
#   tools/eval-delta.sh FILE.json [FILE2.json]
# FILE.json is the pb-evals/1 results file of evals/run-evals.sh (${OUT%.md}.json): one file with both arms, or one file per
# arm. Only runs[] is read, never summary, so the table can be rebuilt from the runs alone. It prints a markdown table with
# one row per (scenario, check key) and the columns Scenario, Check, with pass@1 (n), without pass@1 (n), delta and Flag.
# n counts the PASS and FAIL results of graded runs (ERROR runs are left out of n and listed after the table as
# "errors: <labels>"); delta = with - without pass@1, two decimals; rows sorted by scenario, then check. Flag
# "non-discriminating": both arms pass at least 2/3 of their runs, or both pass none (the check cannot tell the arms apart).
# A check graded in one arm only (such as the without-arm isolation check) is listed under "## One arm only".
# The files must agree on model (never null: pass --model to run-evals.sh), playbook_commit and harness, and each scenario
# must have one fixture_tree and one prompt_sha across its runs.
# Exit: 0 ok | 1 an isolation check FAILed in a without run (its scenario's delta is not valid) | 2 usage or invalid input |
#       3 node missing.
set -u

usage() { sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "${1:-}" in "" | -h | --help) usage ;; esac
[ $# -le 2 ] || usage
for f in "$@"; do [ -f "$f" ] || { printf 'error: no such file: %s\n' "$f" >&2; exit 2; }; done
command -v node >/dev/null 2>&1 || { printf 'error: node (>= 18) is required\n' >&2; exit 3; }

exec node -e '
const fs = require("fs"), files = process.argv.slice(1);
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
if (!arms.has("with") || !arms.has("without")) die("only one arm present (" + [...arms].join(", ") + "); the delta needs runs of both arms, with and without");
const scen = new Map();
for (const r of runs) {
  if (!scen.has(r.scenario)) scen.set(r.scenario, { fixture_tree: new Set(), prompt_sha: new Set() });
  for (const f of ["fixture_tree", "prompt_sha"]) if (r[f] !== null && r[f] !== undefined) scen.get(r.scenario)[f].add(r[f]);
}
for (const [s, v] of scen) for (const f of ["fixture_tree", "prompt_sha"]) {
  if (v[f].size > 1) die("scenario " + s + ": the runs have different " + f + " values; the arms did not run the same fixture and prompt");
}
const g = new Map(), errors = [], isoFail = [];
let dropped = 0;
for (const r of runs) {
  if (r.arm === "without" && typeof r.dropped_user_lines === "number" && r.dropped_user_lines > dropped) dropped = r.dropped_user_lines;
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
if (isoFail.length) o.push("", "isolation: FAIL in " + isoFail.join(", ") + "; the Δ of these scenarios is not valid");
process.stdout.write(o.join("\n") + "\n");
process.exit(isoFail.length ? 1 : 0);' "$@"
