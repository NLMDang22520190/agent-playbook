#!/usr/bin/env node
// Step 3 of the evaluation of Context Mode: a trace-driven simulation of the NET effect on cost. It takes real Claude Code transcripts
// (.jsonl, also subagents/) and asks: if every tool result of 4 KB or more were cut by r, but the plugin adds O tokens to the input of
// EVERY call (its tool definitions and hook text) and makes the agent take p% more calls, what happens to the total cost?
// Prints AGGREGATES only (no message text). UNTESTED on your transcripts: run only on one cloud transcript by its author.
//
//   node net-savings-sim.js <file-or-dir>... [--json out.json] [--read-mult 0.1] [--write-mult 1.25] [--out-mult 5]
//
// Cost model (input-token equivalents; ASSUMPTIONS, change them): fresh input 1, cache read --read-mult, cache write --write-mult,
// output --out-mult. An API-price proxy, not what a subscription plan counts.
//
// Model. Baseline cost = sum over calls of input + rm*read + wm*write + om*out.
//  - Saving from the cut: at call k the live results of 4 KB or more are a fraction f_k of its input side (bytes/4 per result, an estimate),
//    so a cut of r saves r * f_k * rm * read_k on that call, plus r * (their size) * wm once when they were first written.
//  - Overhead O: every call reads O more tokens (rm * O per call), and O is written once per segment start and once per cold restart (wm * O).
//  - Extra calls p: p * (number of calls) more calls, each costing the average baseline cost per call.
// The grid at the end shows the net change in percent of the baseline cost (negative = cheaper). The break-even line says how large O
// may be before the plugin costs more than it saves. Measure O with plugin-overhead.sh; p comes from your own A/B (ServiceNow saw +5 to +9%).
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let jsonOut = null, rm = 0.1, wm = 1.25, om = 5;
const inputs = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--json') jsonOut = args[++i]; else if (args[i] === '--read-mult') rm = Number(args[++i]);
  else if (args[i] === '--write-mult') wm = Number(args[++i]); else if (args[i] === '--out-mult') om = Number(args[++i]);
  else inputs.push(args[i]);
}
if (!inputs.length) { console.error('usage: node net-savings-sim.js <file-or-dir>... [--json out.json] [--read-mult X] [--write-mult X] [--out-mult X]'); process.exit(2); }
const listFiles = (p) => { const st = fs.statSync(p); if (st.isFile()) return p.endsWith('.jsonl') ? [p] : []; return fs.readdirSync(p).flatMap((n) => listFiles(path.join(p, n))); };
const files = inputs.flatMap(listFiles);
if (!files.length) { console.error('no .jsonl files found'); process.exit(2); }

const BIG = 4096;
const sizeOf = (c) => {
  if (typeof c === 'string') return Buffer.byteLength(c);
  if (Array.isArray(c)) return c.reduce((s, x) => s + (typeof x === 'string' ? Buffer.byteLength(x) : Buffer.byteLength(x && x.text ? x.text : (x && x.type === 'image' ? '' : JSON.stringify(x || '')))), 0);
  return c == null ? 0 : Buffer.byteLength(JSON.stringify(c));
};
const A = { files: 0, calls: 0, segments: 0, cold: 0, base: 0, readSavePerR: 0, writeSavePerR: 0, bigTok: 0, readTok: 0 };

for (const file of files) {
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch (e) { continue; }
  A.files += 1;
  const byId = new Map(), calls = [], toolBig = new Map();
  let liveBig = 0;                 // tokens (bytes/4) of live results of 4 KB or more
  let pendingBigWrite = 0;         // size of big results not yet attributed to a call
  let segStart = true;
  const mark = () => { segStart = true; liveBig = 0; pendingBigWrite = 0; };
  for (const line of text.split('\n')) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch (e) { continue; }
    if ((o.type === 'system' && o.subtype === 'compact_boundary') || o.isCompactSummary) { mark(); continue; }
    const m = o.message;
    if (!m || typeof m !== 'object') continue;
    if (m.role === 'user' && Array.isArray(m.content)) {
      for (const b of m.content) {
        if (!b || b.type !== 'tool_result') continue;
        const bytes = sizeOf(b.content);
        if (bytes >= BIG) { liveBig += bytes / 4; pendingBigWrite += bytes / 4; }
      }
    } else if (m.role === 'assistant' && m.usage && m.id) {
      const u = m.usage;
      const rec = { ts: o.timestamp ? Date.parse(o.timestamp) : NaN, input: u.input_tokens || 0, read: u.cache_read_input_tokens || 0, write: u.cache_creation_input_tokens || 0, out: u.output_tokens || 0 };
      if (byId.has(m.id)) { const r = byId.get(m.id); for (const k of ['input', 'read', 'write', 'out']) r[k] = Math.max(r[k], rec[k]); continue; }
      rec.side = rec.input + rec.read + rec.write; rec.liveBig = liveBig; rec.newBig = pendingBigWrite; rec.segStart = segStart;
      pendingBigWrite = 0; segStart = false;
      byId.set(m.id, rec); calls.push(rec);
    }
  }
  calls.forEach((c, k) => {
    A.calls += 1;
    A.base += c.input + rm * c.read + wm * c.write + om * c.out;
    const f = c.side ? Math.min(c.liveBig / c.side, 1) : 0;
    A.readSavePerR += f * rm * c.read; A.readTok += c.read;
    A.writeSavePerR += wm * c.newBig; A.bigTok += c.newBig;
    if (c.segStart) A.segments += 1;
    const prev = k > 0 ? calls[k - 1] : null;
    if (prev && Number.isFinite(c.ts) && Number.isFinite(prev.ts) && c.ts - prev.ts > 3600000 && c.write > 50000 && c.read < 0.2 * c.side) A.cold += 1;
  });
}
const avgCall = A.calls ? A.base / A.calls : 0;
const net = (r, O, p) => {
  const save = r * (A.readSavePerR + A.writeSavePerR);
  const overhead = rm * O * A.calls + wm * O * (A.segments + A.cold);
  const extra = p * A.calls * avgCall;
  return A.base ? 100 * (overhead + extra - save) / A.base : 0;
};
const L = [];
L.push('# Net effect simulation of a tool-output cutter (aggregates only)\n');
L.push(`Transcript files: ${A.files}; API calls: ${A.calls}; segments: ${A.segments}; cold restarts: ${A.cold}. Multipliers: read ${rm}, write ${wm}, output ${om}. Baseline cost: ${Math.round(A.base).toLocaleString('en-US')} units; average per call: ${Math.round(avgCall).toLocaleString('en-US')}.\n`);
L.push(`Largest possible saving (r = 100%, no overhead, no extra calls): ${(100 * (A.readSavePerR + A.writeSavePerR) / A.base).toFixed(1)}% of the baseline cost.\n`);
for (const r of [0.5, 0.8]) {
  L.push(`Net change of total cost, percent (negative = cheaper), tool results of 4 KB or more cut by ${Math.round(r * 100)}%:\n`);
  L.push('| Overhead O per call | extra calls 0% | +5% | +9% |');
  L.push('|---|---|---|---|');
  for (const O of [0, 3000, 6000, 10000, 15000]) L.push(`| ${O} tokens | ${net(r, O, 0).toFixed(1)}% | ${net(r, O, 0.05).toFixed(1)}% | ${net(r, O, 0.09).toFixed(1)}% |`);
  L.push('');
}
const unit = rm * A.calls + wm * (A.segments + A.cold);
for (const r of [0.5, 0.8]) {
  const save = r * (A.readSavePerR + A.writeSavePerR);
  L.push(`Break-even overhead at r = ${Math.round(r * 100)}%, no extra calls: ${unit ? Math.round(save / unit).toLocaleString('en-US') : 'n/a'} tokens per call (the plugin must add less than this to save anything).`);
}
L.push('\nLimits: bytes/4 is not a tokenizer; f_k assumes the cut shrinks the cached context in proportion; the cut ignores what the model must ask again (that is what the extra-calls column stands for); the extra-call cost uses the average call; the multipliers are assumptions; O and p must come from measurements (plugin-overhead.sh and an A/B), not from this script; one person, one workload.');
console.log(L.join('\n'));
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ A, multipliers: { rm, wm, om }, grid: [0.5, 0.8].map((r) => ({ r, rows: [0, 3000, 6000, 10000, 15000].map((O) => ({ O, p0: net(r, O, 0), p5: net(r, O, 0.05), p9: net(r, O, 0.09) })) })) }, null, 2));
