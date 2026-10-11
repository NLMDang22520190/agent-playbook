#!/usr/bin/env node
// Reads one eval transcript once and prints what the graders need, as KEY=VALUE lines:
//   json=1|0  result_ok=1|0  cost=<usd or empty>  subagent=1|0  tdd_order=ok|bad|na
//   feedback_captured=1|0|na  full_named=1|0|na  untested_label=1|0|na
// and writes the final reply (the last stream-json "result" field) to <log>.result.
// Usage: node evals/transcript.js <log>
"use strict";
const fs = require("fs");
const log = process.argv[2];
if (!log) { console.error("usage: node evals/transcript.js <log>"); process.exit(2); }
let text;
try { text = fs.readFileSync(log, "utf8"); } catch (e) { console.error("cannot read " + log); process.exit(3); }

let json = false, result = null, i = 0, skill = -1, write = -1, subagent = false, captured = false;
// a real `feedback.sh capture` call: quoted text (echo "...", -m '...') is removed before matching
const unquote = s => s.replace(/"(?:[^"\\]|\\[\s\S])*"|'[^']*'/g, "");
// `bash -c "..."`, `bash -lc '...'`, `bash -ec`, `bash -l -c`, `bash --login -c`, `zsh -c`, `sh -c`: the quoted
// script is the command, so grade what is inside it; repeat for nested wrappers until nothing changes
const WRAP = /\b(?:ba|z)?sh((?:\s+--?[a-z]+)+)\s+(?:"((?:[^"\\]|\\[\s\S])*)"|'([^']*)')/g;
const unwrap1 = s => s.replace(WRAP, (m, f, d, q) => (!/(?:^|\s)-[a-z]*c/.test(f) ? m : d !== undefined ? d.replace(/\\(["\\$`])/g, "$1") : q));
const unwrap = s => { for (let i = 0; i < 10; i++) { const u = unwrap1(s); if (u === s) break; s = u; } return s; };
for (const line of text.split(/\r?\n/)) {
  let o;
  try { o = JSON.parse(line); } catch (e) { continue; }
  if (!o || typeof o !== "object" || !o.type) continue;
  json = true;
  if (o.type === "result") result = o;
  const blocks = o.message && Array.isArray(o.message.content) ? o.message.content : (o.type === "tool_use" ? [o] : []);
  for (const b of blocks) {
    if (!b || b.type !== "tool_use") continue;
    i++;
    const inp = b.input || {};
    const fp = String(inp.file_path || "");
    if (b.name === "Agent" || b.name === "Task") subagent = true;
    const loads = (b.name === "Skill" && /^([^:]+:)?playbook-tdd$/.test(String(inp.skill || ""))) ||
      (b.name === "Read" && /[\\/]playbook-tdd[\\/]SKILL\.md$/.test(fp));
    if (loads && skill < 0) skill = i;
    if ((b.name === "Write" || b.name === "Edit") && /(^|[\\/])tests[\\/]/.test(fp) && write < 0) write = i;
    if (b.name === "Bash" && /feedback\.sh\s+capture/.test(unquote(unwrap(String(inp.command || ""))))) captured = true;
  }
}

const out = log + ".result";
let reply = null;
if (result && typeof result.result === "string") { reply = result.result; fs.writeFileSync(out, reply); }
else { try { fs.unlinkSync(out); } catch (e) {} }

const st = result ? String(result.subtype || "") : "";
const resultOk = !!result && result.is_error !== true && (st === "success" || (st === "" && result.is_error === false));
const cost = result && typeof result.total_cost_usd === "number" ? String(result.total_cost_usd) : "";

function fullNamed(s) {   // Full as a word, not negated ("not Full", "isn't Full", "without Full", ...)
  const re = /\bFull\b/g; let m;
  while ((m = re.exec(s))) if (!/\b(not|no|never|without|isn't|is not)\s+$/i.test(s.slice(0, m.index))) return true;
  return false;
}
const untested = s => /\buntested\b|\b(has no|without( a)?) tests?\b(?![ \t]*(failing|that (are|were) failing|that fail))|\bno tests? (covers|covering)\b|\bnot covered by (a )?tests?\b/i.test(s);

const b = v => (v ? "1" : "0");
process.stdout.write([
  "json=" + b(json),
  "result_ok=" + b(resultOk),
  "cost=" + cost,
  "subagent=" + b(subagent),
  "tdd_order=" + (!json ? "na" : (skill > 0 && (write < 0 || skill < write) ? "ok" : "bad")),
  "feedback_captured=" + (!json ? "na" : b(captured)),
  "full_named=" + (reply === null ? "na" : b(fullNamed(reply))),
  "untested_label=" + (reply === null ? "na" : b(untested(reply))),
].join("\n") + "\n");
