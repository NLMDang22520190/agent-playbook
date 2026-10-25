#!/usr/bin/env node
// Reads one eval transcript and prints the facts that the v0.26.0 graders grade_E2, grade_E13 and grade_E6 need, as KEY=VALUE lines.
// DECISION[D4]: a new file, so evals/transcript.js (shared with other lanes) stays as it is. Newlines inside a value become spaces.
//   json=1|0                  the log has stream-json lines
//   reply=1|0                 the log has a stream-json result text (the last one is the final reply)
//   ask_calls=N               the tool_use blocks named AskUserQuestion
//   askq=TEXT                 one line per question of those calls: its question text
//   askall=TEXT               one line per question: the question text, its option labels and descriptions, joined by " | "
//   rq=LINE                   one line per line of the final reply that holds a question (a run of "?" at a word end, the rule of
//                             transcript.js proseQ), outside fenced code and > quotes, inline code removed
//   rl=LINE                   every line of the final reply outside fenced code and > quotes, inline code removed
//   inspect_change=pass|fail  an inspection comes before the first file change; with no file change, an inspection anywhere
//   inspect_ask=pass|fail     the same with the first AskUserQuestion call as the bound (no call: as inspect_change)
//   fetch=TEXT                the input (JSON) of a tool call whose name contains fetch, or of a Bash call running curl, wget or fetch
// An inspection is a Read, Grep or Glob call, or a Bash command that matches the INSPECT regex (any case; none given: no Bash command
// counts) and writes no file. A file change is a Write, Edit, MultiEdit or NotebookEdit call, or a Bash command that writes under src/ or
// tests/ (a redirect, tee, cp, mv, touch, rm, mkdir, ln, install or sed -i naming such a path).
// Usage: node evals/facts.js <log> [INSPECT]
"use strict";
const fs = require("fs");
const log = process.argv[2];
if (!log) { console.error("usage: node evals/facts.js <log> [INSPECT]"); process.exit(2); }
let text;
try { text = fs.readFileSync(log, "utf8"); } catch (e) { console.error("cannot read " + log); process.exit(3); }
const inspectRe = process.argv[3] ? new RegExp(process.argv[3], "i") : null;
const one = s => String(s).replace(/\r?\n|\r/g, " ");
const P = "['\"]?(?:\\./)?(?:src|tests)/";
const WRITE_RES = [
  new RegExp("(?:^|[^<0-9&])(?:>>?|>\\|)\\s*" + P),
  new RegExp("\\btee\\b(?:\\s+-a)?\\s+" + P),
  new RegExp("\\b(?:cp|mv|touch|rm|mkdir|ln|install)\\b[^;&|\\n]*\\s" + P),
  new RegExp("\\bsed\\s+(?:-[a-zA-Z]*i[a-zA-Z]*|--in-place)[^;&|\\n]*\\s" + P),
];
const bashWrites = c => WRITE_RES.some(r => r.test(c));

let json = false, reply = null, asks = 0, firstAsk = -1, firstChange = -1, idx = 0;
const inspections = [], askq = [], askall = [], fetches = [];
for (const l of text.split(/\r?\n/)) {
  let o;
  try { o = JSON.parse(l); } catch (e) { continue; }
  if (!o || typeof o !== "object" || !o.type) continue;
  json = true;
  if (o.type === "result" && typeof o.result === "string") reply = o.result;
  const blocks = o.message && Array.isArray(o.message.content) ? o.message.content : (o.type === "tool_use" ? [o] : []);
  for (const b of blocks) {
    if (!b || b.type !== "tool_use") continue;
    const name = String(b.name || ""), input = b.input && typeof b.input === "object" ? b.input : {};
    const cmd = name === "Bash" && typeof input.command === "string" ? input.command : "";
    idx++;
    if (name === "AskUserQuestion") {
      asks++;
      if (firstAsk < 0) firstAsk = idx;
      const qs = Array.isArray(input.questions) ? input.questions : (typeof input.question === "string" ? [input] : []);
      for (const q of qs) {
        if (!q || typeof q !== "object") continue;
        const parts = [typeof q.question === "string" ? q.question : ""];
        for (const op of Array.isArray(q.options) ? q.options : []) {
          if (op && typeof op === "object") parts.push(String(op.label || ""), String(op.description || ""));
          else if (typeof op === "string") parts.push(op);
        }
        askq.push(one(parts[0]));
        askall.push(one(parts.join(" | ")));
      }
    }
    const writes = /^(?:Write|Edit|MultiEdit|NotebookEdit)$/.test(name) || (cmd !== "" && bashWrites(cmd));
    if (writes && firstChange < 0) firstChange = idx;
    if (!writes && (/^(?:Read|Grep|Glob)$/.test(name) || (cmd !== "" && inspectRe !== null && inspectRe.test(cmd)))) inspections.push(idx);
    if (/fetch/i.test(name) || (cmd !== "" && /\b(?:curl|wget|fetch)\b/.test(cmd))) fetches.push(one(JSON.stringify(input)));
  }
}
// before BOUND: an inspection before the bound index; no bound (-1): an inspection anywhere
const before = bound => inspections.some(i => bound < 0 || i < bound) ? "pass" : "fail";
const rl = [], rq = [];
if (reply !== null) {
  let fence = false;
  for (const line of reply.split(/\r?\n/)) {
    if (/^\s*(```|~~~)/.test(line)) { fence = !fence; continue; }
    if (fence || /^\s*>/.test(line)) continue;
    const t = line.replace(/`[^`]*`/g, " ");
    rl.push(t);
    if (/\?+(?=[)\]"'*_]*(\s|$))/.test(t)) rq.push(t);
  }
}
const out = [
  "json=" + (json ? 1 : 0),
  "reply=" + (reply === null ? 0 : 1),
  "ask_calls=" + asks,
  "inspect_change=" + before(firstChange),
  "inspect_ask=" + before(firstAsk >= 0 ? firstAsk : firstChange),
];
for (const q of askq) out.push("askq=" + q);
for (const q of askall) out.push("askall=" + q);
for (const l of rq) out.push("rq=" + l);
for (const l of rl) out.push("rl=" + l);
for (const f of fetches) out.push("fetch=" + f);
process.stdout.write(out.join("\n") + "\n");
