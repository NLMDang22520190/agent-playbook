#!/usr/bin/env node
// Splits a hidden test that a run failed into "surfaced" and "missed", from the run's final reply (maintainers; reads only).
//   evals/tasks-project/outcome-classes.js RESULT.json [--json]
// RESULT.json is the pb-evals/1 file of evals/run-outcome.sh; the final reply of each run is read from
// <RESULT stem>.runs/<label>.log.result (the runner writes it next to the transcript). Each task may have a surface.json:
//   { "checks": [ { "name": "...", "test": "tests/x.f2p.test.js", "pattern": "<regex, case-insensitive>" } ] }
// For every run and every such check: FIXED when the runner graded the hidden test PASS; else SURFACED when the final reply matches
// the pattern (the problem was named, left for the user); else MISSED. The match is a heuristic on text: the matching line is printed
// so that a reader can confirm it, and a reply that says it fixed the thing yet fails the test is still counted as SURFACED.
// ERROR and SKIPPED runs are left out. Exit: 0 ok, 2 usage, 3 unreadable file or no surface.json found.
"use strict";
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const json = args.indexOf("--json") >= 0;
const file = args.find(a => !a.startsWith("--"));
if (!file) { console.error("usage: evals/tasks-project/outcome-classes.js RESULT.json [--json]"); process.exit(2); }

let res;
try { res = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { console.error("outcome-classes: cannot read " + file); process.exit(3); }
const runsDir = file.replace(/\.json$/, "") + ".runs";

const surfaceOf = {};
function surfaceFor(run) {
  if (run.scenario in surfaceOf) return surfaceOf[run.scenario];
  let found = null;
  for (const n of run.notes || []) {
    const m = /^tasks_dir=(.*)$/.exec(n);
    if (!m) continue;
    try { found = JSON.parse(fs.readFileSync(path.join(m[1], run.scenario, "surface.json"), "utf8")); } catch (e) { /* none */ }
  }
  surfaceOf[run.scenario] = found;
  return found;
}

const rows = [];
let anySurface = false;
for (const run of res.runs || []) {
  if (run.status !== "graded") continue;
  const sf = surfaceFor(run);
  if (!sf || !Array.isArray(sf.checks)) continue;
  anySurface = true;
  let reply = "";
  try { reply = fs.readFileSync(path.join(runsDir, run.label + ".log.result"), "utf8"); } catch (e) { /* no reply file */ }
  for (const c of sf.checks) {
    const hit = (run.checks || []).find(k => (k.name || "") === "FAIL_TO_PASS " + c.test);
    if (!hit) continue;
    let cls = "FIXED", line = "";
    if (hit.result !== "PASS") {
      const re = new RegExp(c.pattern, "i");
      const m = reply.split("\n").find(l => re.test(l));
      cls = m ? "SURFACED" : "MISSED";
      line = m ? m.trim().slice(0, 200) : "";
    }
    rows.push({ scenario: run.scenario, arm: run.arm, label: run.label, check: c.name, cls, line });
  }
}
if (!anySurface) { console.error("outcome-classes: no surface.json for the tasks in " + file); process.exit(3); }

const sum = {};
for (const r of rows) {
  const k = r.scenario + "|" + r.check + "|" + r.arm;
  (sum[k] = sum[k] || { FIXED: 0, SURFACED: 0, MISSED: 0 })[r.cls]++;
}
if (json) { console.log(JSON.stringify({ rows, summary: sum })); process.exit(0); }

const out = ["| task | check | arm | fixed | surfaced | missed |", "|---|---|---|---|---|---|"];
for (const k of Object.keys(sum).sort()) {
  const [sc, ch, arm] = k.split("|");
  out.push(`| ${sc} | ${ch} | ${arm} | ${sum[k].FIXED} | ${sum[k].SURFACED} | ${sum[k].MISSED} |`);
}
out.push("", "Surfaced runs (confirm the line):");
for (const r of rows.filter(x => x.cls === "SURFACED")) out.push(`- ${r.label}: ${r.line}`);
console.log(out.join("\n"));
