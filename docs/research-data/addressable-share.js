#!/usr/bin/env node
// Step A of the Context Mode evaluation: how much of the context that a Claude Code session carries is large tool output that a tool
// like Context Mode could shrink? Reads Claude Code transcripts (.jsonl, also the subagents/ ones) and prints AGGREGATES only (no
// message text, no paths of your files). UNTESTED on your transcripts: it was run only on one cloud transcript by its author.
//
//   node addressable-share.js <file-or-dir> [more files or dirs] [--json out.json]
//   e.g. node addressable-share.js ~/.claude/projects/<your-project>        (Windows: C:/Users/<you>/.claude/projects/<your-project>)
//
// Method. Every API call re-reads the whole live context. A tool result of S tokens that stays in the context for N later calls costs
// S x N token-reads. "Exposure" = sum of S x N. The denominator is the real input side of all calls (input + cache read + cache
// write, from the usage fields). Tool result size is estimated as bytes / 4 (a rough rule, not a tokenizer). A compaction (a
// compact boundary or a compact summary message) removes the older results from the live context. Each transcript file is its own
// context (main session and every subagent separately).
//
// Pre-registered reading of the headline number "share of >4 KB results" (set before looking at any data):
//   under 10%  : Context Mode cannot matter much for this workload. Stop.
//   20% or more: worth a paired best-case run (step B).
//   10% to 20% : gray zone, decide with the cost at stake.
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let jsonOut = null;
const inputs = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--json') { jsonOut = args[i + 1]; i += 1; } else inputs.push(args[i]);
}
if (!inputs.length) { console.error('usage: node addressable-share.js <file-or-dir>... [--json out.json]'); process.exit(2); }

function listFiles(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return p.endsWith('.jsonl') ? [p] : [];
  const out = [];
  for (const name of fs.readdirSync(p)) out.push(...listFiles(path.join(p, name)));
  return out;
}
const files = inputs.flatMap(listFiles);
if (!files.length) { console.error('no .jsonl files found'); process.exit(2); }

const KB = 1024;
const BUCKETS = [['<4KB', 0, 4 * KB], ['4-16KB', 4 * KB, 16 * KB], ['>=16KB', 16 * KB, Infinity]];
const bucketOf = (b) => BUCKETS.find(([, lo, hi]) => b >= lo && b < hi)[0];
const sizeOf = (c) => {
  if (typeof c === 'string') return Buffer.byteLength(c);
  if (Array.isArray(c)) return c.reduce((s, x) => s + (typeof x === 'string' ? Buffer.byteLength(x) : Buffer.byteLength(x && x.text ? x.text : (x && x.type === 'image' ? '' : JSON.stringify(x || '')))), 0);
  return c == null ? 0 : Buffer.byteLength(JSON.stringify(c));
};

const total = { files: 0, calls: 0, inputSide: 0, results: 0, resultBytes: 0, exposure: 0, peaks: [], over100k: 0, compactions: 0 };
const byBucket = Object.fromEntries(BUCKETS.map(([n]) => [n, { n: 0, bytes: 0, exposure: 0 }]));
const byTool = new Map();

for (const file of files) {
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { continue; }
  total.files += 1;
  const toolOf = new Map();   // tool_use_id -> tool name
  const seen = new Map();     // message.id -> input side tokens (max)
  let calls = 0, peak = 0;
  let live = [];              // { tool, bytes, bucket, start }
  const finalize = (end) => {
    for (const it of live) {
      const n = Math.max(0, end - it.start), expo = (it.bytes / 4) * n;
      total.exposure += expo; byBucket[it.bucket].exposure += expo;
      const t = byTool.get(it.tool) || { n: 0, bytes: 0, exposure: 0, big: 0, bigExposure: 0 };
      t.exposure += expo; if (it.bytes >= 4 * KB) t.bigExposure += expo; byTool.set(it.tool, t);
    }
    live = [];
  };
  for (const line of text.split('\n')) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch (e) { continue; }
    if (o.type === 'system' && o.subtype === 'compact_boundary') { finalize(calls); total.compactions += 1; continue; }
    const m = o.message;
    if (!m || typeof m !== 'object') continue;
    if (o.isCompactSummary) { finalize(calls); total.compactions += 1; }
    if (m.role === 'assistant') {
      if (Array.isArray(m.content)) for (const b of m.content) if (b && b.type === 'tool_use') toolOf.set(b.id, b.name || '?');
      const u = m.usage;
      if (u && m.id) {
        const side = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
        if (!seen.has(m.id)) { calls += 1; total.calls += 1; }
        seen.set(m.id, Math.max(seen.get(m.id) || 0, side));
      }
    } else if (m.role === 'user' && Array.isArray(m.content)) {
      for (const b of m.content) {
        if (!b || b.type !== 'tool_result') continue;
        const bytes = sizeOf(b.content), tool = toolOf.get(b.tool_use_id) || '?', bucket = bucketOf(bytes);
        total.results += 1; total.resultBytes += bytes;
        byBucket[bucket].n += 1; byBucket[bucket].bytes += bytes;
        const t = byTool.get(tool) || { n: 0, bytes: 0, exposure: 0, big: 0, bigExposure: 0 };
        t.n += 1; t.bytes += bytes; if (bytes >= 4 * KB) t.big += 1; byTool.set(tool, t);
        live.push({ tool, bytes, bucket, start: calls });
      }
    }
  }
  finalize(calls);
  for (const side of seen.values()) { total.inputSide += side; if (side > peak) peak = side; if (side > 100000) total.over100k += 1; }
  total.peaks.push(peak);
}

const pct = (a, b) => (b ? (100 * a / b).toFixed(1) + '%' : 'n/a');
const big4 = byBucket['4-16KB'].exposure + byBucket['>=16KB'].exposure;
const big16 = byBucket['>=16KB'].exposure;
const peaks = total.peaks.filter((x) => x > 0).sort((a, b) => a - b);
const med = peaks.length ? peaks[peaks.length >> 1] : 0;
const out = [];
out.push('# Addressable share of context (aggregates only)\n');
out.push(`Transcript files: ${total.files}; API calls: ${total.calls}; tool results: ${total.results} (${(total.resultBytes / KB).toFixed(0)} KB); compactions seen: ${total.compactions}.`);
out.push(`Peak input side per file: median ${med}, max ${peaks.length ? peaks[peaks.length - 1] : 0}; calls with input side above 100K: ${total.over100k} (${pct(total.over100k, total.calls)}).\n`);
out.push('Exposure = tool result tokens (bytes/4) x later calls that re-read them. Total input side of all calls (real usage): ' + total.inputSide.toLocaleString('en-US') + ' tokens.\n');
out.push('| Result size | Results | KB | Exposure (token-reads) | Share of all input-side reads |');
out.push('|---|---|---|---|---|');
for (const [n] of BUCKETS) out.push(`| ${n} | ${byBucket[n].n} | ${(byBucket[n].bytes / KB).toFixed(0)} | ${Math.round(byBucket[n].exposure).toLocaleString('en-US')} | ${pct(byBucket[n].exposure, total.inputSide)} |`);
out.push(`| all results | ${total.results} | ${(total.resultBytes / KB).toFixed(0)} | ${Math.round(total.exposure).toLocaleString('en-US')} | ${pct(total.exposure, total.inputSide)} |\n`);
out.push(`**Headline: share of results of 4 KB or more: ${pct(big4, total.inputSide)}** (16 KB or more: ${pct(big16, total.inputSide)}).`);
for (const r of [0.5, 0.8, 0.95]) out.push(`- If every result of 4 KB or more were cut by ${Math.round(r * 100)}%: at most ${pct(big4 * r, total.inputSide)} of all input-side reads saved.`);
const h = total.inputSide ? 100 * big4 / total.inputSide : 0;
out.push(`\nPre-registered reading: ${h < 10 ? 'UNDER 10%: Context Mode cannot matter much for this workload. Stop.' : h >= 20 ? '20% OR MORE: worth a paired best-case run (step B).' : '10% TO 20%: gray zone.'}\n`);
out.push('By tool (results of 4 KB or more first):\n');
out.push('| Tool | Results | of which 4 KB+ | KB | Exposure share (all) | Exposure share (4 KB+) |');
out.push('|---|---|---|---|---|---|');
for (const [name, t] of [...byTool.entries()].sort((a, b) => b[1].bigExposure - a[1].bigExposure).slice(0, 15))
  out.push(`| ${name} | ${t.n} | ${t.big} | ${(t.bytes / KB).toFixed(0)} | ${pct(t.exposure, total.inputSide)} | ${pct(t.bigExposure, total.inputSide)} |`);
out.push('\nLimits: bytes/4 is not a tokenizer; the ideal cut ignores what the model would have to ask again; cache pricing makes a read cheaper than a write, so token-reads are not dollars; one workload, one person.');
console.log(out.join('\n'));
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ total, byBucket, byTool: Object.fromEntries(byTool), headline4KBShare: h }, null, 2));
