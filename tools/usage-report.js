#!/usr/bin/env node
// Token report for one Claude Code session transcript (maintainers; reads files, writes nothing).
//   tools/usage-report.js [--json] [--gap MIN] [--big TOKENS] [--prices FILE] TRANSCRIPT.jsonl
//   tools/usage-report.js --latest [...]     the newest transcript of this project under ~/.claude/projects
// TRANSCRIPT is a session .jsonl; its sub-agents are read from the sibling directory <session-id>/subagents/
// (agent-*.jsonl with agent-*.meta.json). Sub-agent files are optional: without them only the orchestrator is counted.
// Prints markdown tables: totals; by role (orchestrator, tester, implementer, reviewer, spec_reviewer, mechanical, other);
// by model; by segment (the main thread split wherever two calls are more than --gap minutes apart, default 60 = the
// 1-hour prompt-cache lifetime); and the cold restarts (a main-thread call after such a gap that writes more than --big
// tokens, default 100000 = the context was written again because the cache had expired).
// A role comes from the role file the Agent prompt names (skills/playbook-tdd/roles/<role>.md), else from a word in the
// Agent description (tester, implementer, spec review, review, mechanical), else "other".
// One API call is repeated once per content block in a transcript: calls are counted once per message id, taking the
// largest value of each usage field. The output column can be a floor: some transcripts store the count from the start
// of the response. Messages of model "<synthetic>" (rate-limit stubs) are skipped.
// --prices FILE: JSON {"<model>": {"input": N, "cache_write": N, "cache_read": N, "output": N}} in USD per million tokens;
// adds a USD column. The script has no built-in prices: a model without an entry is listed under "no price" and counted as 0.
// --json prints the same numbers as one JSON object (tokens, never rounded).
// Exit: 0 ok, 2 usage error, 3 no transcript or no usage found.
"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");

function usage(msg) {
  if (msg) console.error("usage-report: " + msg);
  console.error("usage: tools/usage-report.js [--json] [--gap MIN] [--big TOKENS] [--prices FILE] (TRANSCRIPT.jsonl | --latest)");
  process.exit(2);
}

let json = false, gapMin = 60, big = 100000, pricesFile = "", latest = false, file = "";
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const num = name => { const v = argv[++i]; if (!/^[0-9]+$/.test(v || "") || Number(v) < 1) usage(name + " needs a positive integer"); return Number(v); };
  if (a === "--json") json = true;
  else if (a === "--latest") latest = true;
  else if (a === "--gap") gapMin = num("--gap");
  else if (a === "--big") big = num("--big");
  else if (a === "--prices") { pricesFile = argv[++i] || ""; if (!pricesFile) usage("--prices needs a file"); }
  else if (a.startsWith("--")) usage("unknown option " + a);
  else if (file) usage("one transcript only");
  else file = a;
}
if (latest && file) usage("give a transcript or --latest, not both");
if (!latest && !file) usage("no transcript given");

if (latest) {
  // Claude Code names the project folder after the working directory with every non-alphanumeric character as "-".
  const dir = path.join(os.homedir(), ".claude", "projects", process.cwd().replace(/[^A-Za-z0-9]/g, "-"));
  let best = null;
  try {
    for (const n of fs.readdirSync(dir)) {
      if (!n.endsWith(".jsonl")) continue;
      const m = fs.statSync(path.join(dir, n)).mtimeMs;
      if (!best || m > best.m) best = { f: path.join(dir, n), m };
    }
  } catch (e) { /* handled below */ }
  if (!best) { console.error("usage-report: no transcript under " + dir); process.exit(3); }
  file = best.f;
}

let prices = null;
if (pricesFile) {
  try { prices = JSON.parse(fs.readFileSync(pricesFile, "utf8")); } catch (e) { usage("cannot read --prices " + pricesFile); }
  if (!prices || typeof prices !== "object" || Array.isArray(prices)) usage("--prices must hold a JSON object");
}

function readRows(f) {
  let text;
  try { text = fs.readFileSync(f, "utf8"); } catch (e) { return null; }
  const rows = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try { rows.push(JSON.parse(line)); } catch (e) { /* a torn last line */ }
  }
  return rows;
}

const n0 = v => (typeof v === "number" && isFinite(v) && v > 0 ? v : 0);

// Calls of one transcript, once per message id. Also the Agent tool_use blocks it contains.
function collect(rows) {
  const calls = new Map();
  const agents = new Map();
  for (const r of rows) {
    const m = r && r.message;
    if (!m || r.type !== "assistant" || !m.usage || !m.id || m.model === "<synthetic>") continue;
    const u = m.usage;
    let c = calls.get(m.id);
    if (!c) { c = { model: m.model || "unknown", ts: Date.parse(r.timestamp) || 0, w: 0, r: 0, o: 0, i: 0 }; calls.set(m.id, c); }
    c.w = Math.max(c.w, n0(u.cache_creation_input_tokens));
    c.r = Math.max(c.r, n0(u.cache_read_input_tokens));
    c.o = Math.max(c.o, n0(u.output_tokens));
    c.i = Math.max(c.i, n0(u.input_tokens));
    if (Array.isArray(m.content)) {
      for (const b of m.content) {
        if (b && b.type === "tool_use" && b.name === "Agent" && b.id && b.input) {
          agents.set(b.id, { desc: String(b.input.description || ""), prompt: String(b.input.prompt || ""), model: b.input.model || "" });
        }
      }
    }
  }
  return { calls: [...calls.values()], agents };
}

function roleOf(desc, prompt) {
  const p = /roles\/(spec-reviewer|tester|implementer|reviewer)\.md/.exec(prompt);
  if (p) return p[1] === "spec-reviewer" ? "spec_reviewer" : p[1];
  const s = desc.toLowerCase();
  if (s.indexOf("spec review") >= 0) return "spec_reviewer";
  if (s.indexOf("mechanical") === 0) return "mechanical";
  if (s.indexOf("tester") >= 0) return "tester";
  if (s.indexOf("implementer") >= 0) return "implementer";
  if (s.indexOf("review") >= 0) return "reviewer";
  return "other";
}

const mainRows = readRows(file);
if (!mainRows) { console.error("usage-report: cannot read " + file); process.exit(3); }
const main = collect(mainRows);

const sub = []; // { role, desc, model, calls }
const subDir = path.join(path.dirname(file), path.basename(file, ".jsonl"), "subagents");
let subFiles = [];
try { subFiles = fs.readdirSync(subDir).filter(n => /^agent-.*\.jsonl$/.test(n)).sort(); } catch (e) { /* no sub-agents */ }
for (const n of subFiles) {
  const rows = readRows(path.join(subDir, n));
  if (!rows) continue;
  let meta = {};
  try { meta = JSON.parse(fs.readFileSync(path.join(subDir, n.replace(/\.jsonl$/, ".meta.json")), "utf8")); } catch (e) { /* optional */ }
  const reg = main.agents.get(meta.toolUseId) || {};
  const first = rows.find(r => r && r.type === "user" && r.message);
  const firstText = first ? (typeof first.message.content === "string" ? first.message.content : JSON.stringify(first.message.content)) : "";
  const desc = meta.description || reg.desc || "";
  sub.push({ role: roleOf(desc, reg.prompt || firstText), desc, calls: collect(rows).calls });
}

if (main.calls.length === 0 && sub.every(s => s.calls.length === 0)) {
  console.error("usage-report: no assistant usage in " + file);
  process.exit(3);
}

// ---- aggregation
const zero = () => ({ calls: 0, w: 0, r: 0, o: 0, i: 0, agents: 0 });
const add = (t, c) => { t.calls++; t.w += c.w; t.r += c.r; t.o += c.o; t.i += c.i; };
const total = zero(), byRole = new Map(), byModel = new Map();
const bump = (m, k) => { if (!m.has(k)) m.set(k, zero()); return m.get(k); };
const addAll = (role, c) => { add(total, c); add(bump(byRole, role), c); add(bump(byModel, c.model), c); };
for (const c of main.calls) addAll("orchestrator", c);
for (const s of sub) { bump(byRole, s.role).agents++; for (const c of s.calls) addAll(s.role, c); }

// segments of the main thread, split on idle gaps
const mainSorted = main.calls.filter(c => c.ts).sort((a, b) => a.ts - b.ts);
const gapMs = gapMin * 60000;
const segs = [];
const cold = [];
for (let k = 0; k < mainSorted.length; k++) {
  const c = mainSorted[k];
  const idle = k > 0 ? c.ts - mainSorted[k - 1].ts : 0;
  if (k === 0 || idle > gapMs) {
    segs.push({ from: c.ts, to: c.ts, t: zero(), idleBefore: idle });
    if (k > 0 && c.w > big) cold.push({ ts: c.ts, w: c.w, r: c.r, idle });
  }
  const sg = segs[segs.length - 1];
  sg.to = c.ts; add(sg.t, c);
}
const coldW = cold.reduce((a, c) => a + c.w, 0);

const price = (model, t) => {
  const p = prices && prices[model];
  if (!p) return null;
  return (t.i * (p.input || 0) + t.w * (p.cache_write || 0) + t.r * (p.cache_read || 0) + t.o * (p.output || 0)) / 1e6;
};
const usd = m => { // total for a map of model -> totals; models without a price are listed
  let s = 0; const missing = [];
  for (const [k, t] of m) { const v = price(k, t); if (v === null) missing.push(k); else s += v; }
  return { usd: s, missing };
};

const iso = ms => new Date(ms).toISOString().replace(/:\d\d\.\d+Z$/, "Z").replace("T", " ");
const mean = (a, b) => (b ? Math.round(a / b) : 0);
const roleOrder = ["orchestrator", "tester", "implementer", "reviewer", "spec_reviewer", "mechanical", "other"];
const roles = roleOrder.filter(r => byRole.has(r)).concat([...byRole.keys()].filter(r => roleOrder.indexOf(r) < 0));

if (json) {
  const obj = t => ({ calls: t.calls, input: t.i, cache_write: t.w, cache_read: t.r, output: t.o });
  const out = {
    transcript: path.basename(file), gap_minutes: gapMin, big_write_tokens: big,
    total: obj(total),
    by_role: roles.map(r => Object.assign({ role: r, agents: byRole.get(r).agents }, obj(byRole.get(r)))),
    by_model: [...byModel.entries()].map(([k, t]) => Object.assign({ model: k }, obj(t))),
    segments: segs.map(s => Object.assign({ from: iso(s.from), to: iso(s.to), idle_before_minutes: Math.round(s.idleBefore / 60000) }, obj(s.t))),
    cold_restarts: { count: cold.length, cache_write: coldW, calls: cold.map(c => ({ at: iso(c.ts), cache_write: c.w, cache_read: c.r, idle_minutes: Math.round(c.idle / 60000) })) },
  };
  if (prices) { const u = usd(byModel); out.usd = u.usd; out.models_without_price = u.missing; }
  console.log(JSON.stringify(out));
  process.exit(0);
}

const M = n => (n / 1e6).toFixed(2) + "M";
const pct = (a, b) => (b ? Math.round(100 * a / b) + "%" : "-");
const L = [];
L.push("# Token report: " + path.basename(file));
L.push("");
L.push(`${total.calls} API calls (${main.calls.length} main, ${total.calls - main.calls.length} in ${sub.length} sub-agents). Cache write ${M(total.w)}, cache read ${M(total.r)}, output ${M(total.o)} (a floor), fresh input ${total.i}.`);
if (sub.length === 0) L.push("No sub-agent transcripts found next to this file: only the orchestrator is counted.");
if (prices) { const u = usd(byModel); L.push(`Priced total: ${u.usd.toFixed(2)} USD` + (u.missing.length ? `; no price for ${u.missing.join(", ")} (counted as 0)` : "") + "."); }
L.push("");
L.push("## By role");
L.push("");
L.push("| role | agents | calls | cache write | write % | cache read | read % | write / call | read / call |");
L.push("|---|---|---|---|---|---|---|---|---|");
for (const r of roles) {
  const t = byRole.get(r);
  L.push(`| ${r} | ${r === "orchestrator" ? "-" : t.agents} | ${t.calls} | ${M(t.w)} | ${pct(t.w, total.w)} | ${M(t.r)} | ${pct(t.r, total.r)} | ${mean(t.w, t.calls)} | ${mean(t.r, t.calls)} |`);
}
L.push("");
L.push("## By model");
L.push("");
L.push("| model | calls | cache write | cache read | output |" + (prices ? " USD |" : ""));
L.push("|---|---|---|---|---|" + (prices ? "---|" : ""));
for (const [k, t] of byModel) {
  const v = price(k, t);
  L.push(`| ${k} | ${t.calls} | ${M(t.w)} | ${M(t.r)} | ${M(t.o)} |` + (prices ? ` ${v === null ? "no price" : v.toFixed(2)} |` : ""));
}
L.push("");
L.push(`## Main-thread segments (split on idle gaps over ${gapMin} min)`);
L.push("");
L.push("| # | from (UTC) | to (UTC) | idle before | calls | cache write | cache read |");
L.push("|---|---|---|---|---|---|---|");
segs.forEach((s, k) => L.push(`| ${k + 1} | ${iso(s.from)} | ${iso(s.to)} | ${k ? Math.round(s.idleBefore / 60000) + " min" : "-"} | ${s.t.calls} | ${M(s.t.w)} | ${M(s.t.r)} |`));
L.push("");
L.push(`## Cold restarts (main call after an idle gap that writes over ${big} tokens)`);
L.push("");
if (cold.length === 0) L.push("None.");
else {
  L.push(`${cold.length} restarts wrote ${M(coldW)} cache tokens, ${pct(coldW, total.w)} of all cache write.`);
  L.push("");
  L.push("| at (UTC) | idle | cache write | cache read |");
  L.push("|---|---|---|---|");
  for (const c of cold) L.push(`| ${iso(c.ts)} | ${Math.round(c.idle / 60000)} min | ${c.w} | ${c.r} |`);
}
console.log(L.join("\n"));
