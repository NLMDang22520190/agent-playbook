#!/usr/bin/env node
// Step A2 of the evaluation of billion-context (history compression): how much of what a Claude Code workload costs is the RE-READING of
// OLD conversation history, and how much is cold restarts? Uses only the usage fields of Claude Code transcripts (.jsonl, also the
// subagents/ ones) and the timestamps. Prints AGGREGATES only (no message text). UNTESTED on your transcripts: run only on one cloud
// transcript by its author.
//
//   node history-share.js <file-or-dir>... [--json out.json] [--read-mult 0.1] [--write-mult 1.25] [--out-mult 5]
//
// Cost model (input-token equivalents, ASSUMPTIONS you can change): fresh input 1, cache read --read-mult (0.1; the docs say 0.05 for some
// models), cache write --write-mult (1.25 for the 5-minute cache, 2 for the 1-hour cache), output --out-mult (5). It is an API-price
// proxy, not what a subscription plan counts.
//
// Method. Each transcript file is its own context, split into segments at compactions. In a segment, the first call's input side P
// is the static prefix (system prompt, tools, first messages). Later growth over P is accumulated history. History that is OLDER than
// N calls at call k is the growth already present at call k-N: that is what a history compressor could shrink (it cannot shrink the
// static prefix and not the newest N calls). A cold restart is a call after a gap of more than 60 minutes whose cache write is over
// 50K tokens and whose cache read is under 20% of its input side.
//
// Pre-registered reading (set before looking at any data) of the headline "cost share of re-reading history older than 50 calls":
//   under 10%  : a history compressor cannot matter much. Stop.
//   25% or more: worth a paired test with a throwaway key (the compressor's own overhead and risks still have to be paid back).
//   10% to 25% : gray zone.
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let jsonOut = null, rm = 0.1, wm = 1.25, om = 5;
const inputs = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--json') { jsonOut = args[++i]; } else if (args[i] === '--read-mult') { rm = Number(args[++i]); }
  else if (args[i] === '--write-mult') { wm = Number(args[++i]); } else if (args[i] === '--out-mult') { om = Number(args[++i]); }
  else inputs.push(args[i]);
}
if (!inputs.length) { console.error('usage: node history-share.js <file-or-dir>... [--json out.json] [--read-mult X] [--write-mult X] [--out-mult X]'); process.exit(2); }
const listFiles = (p) => {
  const st = fs.statSync(p);
  if (st.isFile()) return p.endsWith('.jsonl') ? [p] : [];
  return fs.readdirSync(p).flatMap((n) => listFiles(path.join(p, n)));
};
const files = inputs.flatMap(listFiles);
if (!files.length) { console.error('no .jsonl files found'); process.exit(2); }

const NS = [10, 25, 50, 100];
const T = { files: 0, calls: 0, segments: 0, input: 0, read: 0, write: 0, out: 0, prefixReadTok: 0, histReadTok: 0, oldReadCost: Object.fromEntries(NS.map((n) => [n, 0])),
  cold: 0, coldWrite: 0, coldCost: 0, compactions: 0, over100k: 0 };

for (const file of files) {
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch (e) { continue; }
  T.files += 1;
  const byId = new Map(), calls = [], segStarts = new Set([0]);
  for (const line of text.split('\n')) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch (e) { continue; }
    if ((o.type === 'system' && o.subtype === 'compact_boundary') || o.isCompactSummary) { segStarts.add(calls.length); T.compactions += 1; continue; }
    const m = o.message;
    if (!m || m.role !== 'assistant' || !m.usage || !m.id) continue;
    const u = m.usage;
    const rec = { ts: o.timestamp ? Date.parse(o.timestamp) : NaN, input: u.input_tokens || 0, read: u.cache_read_input_tokens || 0, write: u.cache_creation_input_tokens || 0, out: u.output_tokens || 0 };
    if (byId.has(m.id)) { const r = byId.get(m.id); for (const k of ['input', 'read', 'write', 'out']) r[k] = Math.max(r[k], rec[k]); continue; }
    byId.set(m.id, rec); calls.push(rec);
  }
  calls.forEach((c) => { c.side = c.input + c.read + c.write; });
  const starts = [...segStarts].filter((s) => s < calls.length).sort((a, b) => a - b);
  starts.forEach((s, si) => {
    const e = si + 1 < starts.length ? starts[si + 1] : calls.length, seg = calls.slice(s, e);
    if (!seg.length) return;
    T.segments += 1;
    const P = seg[0].side, cum = seg.map((c) => Math.max(c.side - P, 0));
    seg.forEach((c, k) => {
      T.calls += 1; T.input += c.input; T.read += c.read; T.write += c.write; T.out += c.out;
      if (c.side > 100000) T.over100k += 1;
      const prefixShare = c.side ? Math.min(P, c.side) / c.side : 0;
      T.prefixReadTok += c.read * prefixShare; T.histReadTok += c.read * (1 - prefixShare);
      for (const n of NS) if (k >= n && c.side) T.oldReadCost[n] += rm * c.read * (cum[k - n] / c.side);
      const prev = k > 0 ? seg[k - 1] : (s > 0 ? calls[s - 1] : null);
      if (k > 0 && prev && Number.isFinite(c.ts) && Number.isFinite(prev.ts) && c.ts - prev.ts > 3600000 && c.write > 50000 && c.read < 0.2 * c.side) {
        T.cold += 1; T.coldWrite += c.write; T.coldCost += wm * c.write;
      }
    });
  });
}
const total = T.input + rm * T.read + wm * T.write + om * T.out;
const pct = (a) => (total ? (100 * a / total).toFixed(1) + '%' : 'n/a');
const L = [];
L.push('# Share of cost from re-reading old history and from cold restarts (aggregates only)\n');
L.push(`Transcript files: ${T.files}; segments (split at compactions): ${T.segments}; API calls: ${T.calls}; compactions: ${T.compactions}; calls with input side over 100K: ${T.over100k}.`);
L.push(`Assumed multipliers (input-token equivalents): read ${rm}, write ${wm}, output ${om}. Total weighted cost: ${Math.round(total).toLocaleString('en-US')} units.\n`);
L.push('| Part of the cost | Units | Share |');
L.push('|---|---|---|');
L.push(`| Fresh input | ${Math.round(T.input).toLocaleString('en-US')} | ${pct(T.input)} |`);
L.push(`| Cache reads (all) | ${Math.round(rm * T.read).toLocaleString('en-US')} | ${pct(rm * T.read)} |`);
L.push(`|   of which the static prefix (first call of a segment) | ${Math.round(rm * T.prefixReadTok).toLocaleString('en-US')} | ${pct(rm * T.prefixReadTok)} |`);
L.push(`|   of which accumulated history | ${Math.round(rm * T.histReadTok).toLocaleString('en-US')} | ${pct(rm * T.histReadTok)} |`);
L.push(`| Cache writes (all) | ${Math.round(wm * T.write).toLocaleString('en-US')} | ${pct(wm * T.write)} |`);
L.push(`|   of which cold restarts (${T.cold}) | ${Math.round(T.coldCost).toLocaleString('en-US')} | ${pct(T.coldCost)} |`);
L.push(`| Output | ${Math.round(om * T.out).toLocaleString('en-US')} | ${pct(om * T.out)} |\n`);
L.push('Re-reading of history OLDER than N calls (what a history compressor could shrink):\n');
L.push('| N calls | Units | Share of total cost |');
L.push('|---|---|---|');
for (const n of NS) L.push(`| ${n} | ${Math.round(T.oldReadCost[n]).toLocaleString('en-US')} | ${pct(T.oldReadCost[n])} |`);
const h = total ? 100 * T.oldReadCost[50] / total : 0;
L.push(`\n**Headline: cost share of re-reading history older than 50 calls: ${h.toFixed(1)}%.**`);
for (const r of [0.5, 0.8]) L.push(`- If that old history were shrunk by ${Math.round(r * 100)}% (ignoring the compressor's own cost and any cache it breaks): at most ${(h * r).toFixed(1)}% of the total cost saved.`);
L.push(`\nPre-registered reading: ${h < 10 ? 'UNDER 10%: a history compressor cannot matter much. Stop.' : h >= 25 ? '25% OR MORE: worth a paired test with a throwaway key.' : '10% TO 25%: gray zone.'}`);
L.push('\nLimits: usage fields are per API call as Claude Code logged them (duplicates by message id removed); growth over the first call is treated as history (it also holds new tool results and your messages); the multipliers are assumptions; a compressor also writes summaries and can break the cache, which this bound ignores; one person, one workload.');
console.log(L.join('\n'));
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ T, multipliers: { rm, wm, om }, total, headlineOldShare50: h }, null, 2));
