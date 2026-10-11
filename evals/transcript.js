#!/usr/bin/env node
// Reads one eval transcript once and prints what the graders need, as KEY=VALUE lines:
//   json=1|0  result_ok=1|0  cost=<usd or empty>  subagent=1|0  tdd_order=ok|bad|na
//   feedback_captured=1|0|na  full_named=1|0|na  untested_label=1|0|na  ran_tests=1|0|na  spec_first=1|0|na
// and writes the final reply (the last stream-json "result" field) to <log>.result.
// Usage: node evals/transcript.js <log>
"use strict";
const fs = require("fs");
const log = process.argv[2];
if (!log) { console.error("usage: node evals/transcript.js <log>"); process.exit(2); }
let text;
try { text = fs.readFileSync(log, "utf8"); } catch (e) { console.error("cannot read " + log); process.exit(3); }

let json = false, result = null, i = 0, skill = -1, write = -1, subagent = false, captured = false, ran = false, specw = -1, srcw = -1;
// a real `feedback.sh capture` call: quoted text (echo "...", -m '...') is removed before matching
const unquote = s => s.replace(/"(?:[^"\\]|\\[\s\S])*"|'[^']*'/g, "");
// like unquote, but the command substitutions inside a double-quoted string are kept as commands of their own (appended
// at the end, so the words around the string stay as they were): out="$(bash proof-run.sh)", [ -n "$(bash proof-run.sh)" ]
// and "$(bash proof-run.sh)"x run it; echo "bash proof-run.sh" does not
const unquoteRun = s => {
  const subs = [];
  const r = s.replace(/"(?:[^"\\]|\\[\s\S])*"|'[^']*'/g, m => {
    if (m[0] === '"') for (const x of m.match(/\$\([^()]{0,200}\)/g) || []) subs.push(x.slice(2, -1));
    return "";
  });
  return subs.length ? r + ";" + subs.join(";") : r;
};
// `bash -c "..."`, `bash -lc '...'`, `bash -ec`, `bash -l -c`, `bash --login -c`, `zsh -c`, `sh -c`, and options
// that take a value (`-o pipefail`, `+o histexpand`, `-O extglob`, `--rcfile F`, `--init-file F`): the quoted
// script is the command, so grade what is inside it; repeat for nested wrappers until nothing changes
const WRAP = /\b(?:ba|z)?sh((?:\s+(?:[-+][a-zA-Z]*[oO]\s+[a-z_]+|--(?:rcfile|init-file)\s+[^\s"'-][^\s"']*|--?[a-zA-Z][a-zA-Z-]*))+)\s+(?:"((?:[^"\\]|\\[\s\S])*)"|'([^']*)')/g;
const unwrap1 = s => s.replace(WRAP, (m, f, d, q) => (!/(?:^|\s)-[a-z]*c/.test(f) ? m : d !== undefined ? d.replace(/\\(["\\$`])/g, "$1") : q));
const unwrap = s => { for (let i = 0; i < 10; i++) { const u = unwrap1(s); if (u === s) break; s = u; } return s; };
// a path under src/ (not under node_modules/)
const isSrc = p => /(^|\/)src\//.test(p) && !/(^|\/)node_modules\//.test(p);
// does a shell command write under src/? Quote-aware tokens (linear: no nested unbounded quantifiers), split into
// simple commands at ; & | and newlines; redirects, tee, mv/cp targets and sed/perl in-place edits count
function bashWritesSrc(cmd) {
  const toks = cmd.match(/"(?:[^"\\]|\\.)*"|'[^']*'|&&|\|\||>>|[;&|>\n]|[^\s;&|<>"']+/g) || [];
  const bare = t => t.replace(/^["']|["']$/g, "");
  let words = [];
  const done = () => {
    const w = words; words = [];
    if (!w.length) return false;
    const verb = bare(w[0]).replace(/^.*\//, ""), args = w.slice(1), plain = args.filter(a => !/^-/.test(a));
    const flags = args.filter(a => /^-/.test(a));
    if (verb === "tee") return plain.some(a => isSrc(bare(a)));
    if (verb === "mv" || verb === "cp") return plain.length > 0 && isSrc(bare(plain[plain.length - 1]));
    if (verb === "sed") return flags.some(f => /^-[a-zA-Z]*i|^--in-place/.test(f)) && plain.some(a => isSrc(bare(a)));
    if (verb === "perl") return flags.some(f => /^-[a-zA-Z]*i/.test(f)) && plain.some(a => isSrc(bare(a)));
    return false;
  };
  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    if (t === ">" || t === ">>") { if (k + 1 < toks.length && isSrc(bare(toks[k + 1]))) return true; k++; continue; }
    if (/^(&&|\|\||[;&|\n])$/.test(t)) { if (done()) return true; continue; }
    words.push(t);
  }
  return done();
}
// does a shell command run proof-run.sh? Split into simple commands at ; & | ( ) { } backticks and newlines (linear), then skip
// reserved words, env assignments and the prefixes sudo/env/nice/timeout/time/nohup/exec with their flags and arguments;
// the command word is proof-run.sh, or a shell whose first non-flag word is
function runsProof(cmd) {
  const isP = t => /(^|\/)proof-run\.sh$/.test(t);
  const RESERVED = /^(if|then|do|else|elif|while|until|!)$/;
  const PREFIX = /^(sudo|env|nice|timeout|time|nohup|exec)$/;
  const FLAGARG = { sudo: /^-[ugphCDRTU]$/, env: /^-[uCS]$/, nice: /^-n$/, timeout: /^-[sk]$/ };
  // a substitution that is part of a word (${X}, or $(..) and `..` touching other characters) becomes one word character, so
  // "cat $(dirname x)/proof-run.sh" stays one token; a standalone $(..) or `..` is still split open (bounded: linear)
  const SEP = "[^\\s;&|(){}`]";
  const inword = new RegExp("\\$\\{[^}]{0,200}\\}|(?<=" + SEP + ")\\$\\([^()]{0,200}\\)|\\$\\([^()]{0,200}\\)(?=" + SEP + ")|(?<=" + SEP + ")`[^`]{0,200}`|`[^`]{0,200}`(?=" + SEP + ")", "g");
  // the command inside a substitution that touches word characters runs whatever surrounds it: check it on its own
  const inner = [];
  const masked = cmd.replace(inword, m => { if (m[0] === "`") inner.push(m.slice(1, -1)); else if (m[0] === "$" && m[1] === "(") inner.push(m.slice(2, -1)); return "X"; });
  if (inner.some(runsProof)) return true;
  for (const seg of masked.split(/[;&|(){}`\n]+/)) {
    const w = seg.trim().split(/\s+/).map(t => t.replace(/^["']|["']$/g, "")).filter(t => t !== "");
    let k = 0;
    while (k < w.length) {
      const base = w[k].replace(/^.*\//, "");
      if (RESERVED.test(w[k]) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(w[k])) { k++; continue; }
      if (PREFIX.test(base)) {
        k++;
        while (k < w.length && /^-/.test(w[k])) k += FLAGARG[base] && FLAGARG[base].test(w[k]) ? 2 : 1;
        if (base === "timeout") k++;   // the duration
        continue;
      }
      break;
    }
    if (k >= w.length) continue;
    if (isP(w[k])) return true;
    if (/(^|\/)(ba|z)?sh$/.test(w[k])) {
      let j = k + 1;
      while (j < w.length && /^-/.test(w[j])) j++;
      if (j < w.length && isP(w[j])) return true;
    }
  }
  return false;
}
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
    if (b.name === "Write" || b.name === "Edit" || b.name === "MultiEdit" || b.name === "NotebookEdit") {   // the spec file, and the first write under src/
      const p = String(b.name === "NotebookEdit" ? inp.notebook_path || "" : fp).replace(/\\/g, "/");
      if (b.name !== "NotebookEdit" && /(^|\/)\.agents\/handoff\/01-spec\.md$/.test(p) && specw < 0) specw = i;
      if (isSrc(p) && srcw < 0) srcw = i;
    }
    if (b.name === "Bash" && srcw < 0 && bashWritesSrc(unwrap(String(inp.command || "")))) srcw = i;
    const cmd = b.name === "Bash" ? unquote(unwrap(String(inp.command || ""))) : "";
    if (/feedback\.sh\s+capture/.test(cmd)) captured = true;
    // a test run, not a mention: proof-run.sh only as the command (or the script of a shell); ls, cat, head, diff of it are reads
    if (/\bnode\s+--test\b|\bnpm\s+(?:run\s+)?test\b/.test(cmd) || runsProof(b.name === "Bash" ? unquoteRun(unwrap(String(inp.command || ""))) : "")) ran = true;
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
  "ran_tests=" + (!json ? "na" : b(ran)),
  "spec_first=" + (!json ? "na" : b(specw > 0 && (srcw < 0 || specw < srcw))),
].join("\n") + "\n");
