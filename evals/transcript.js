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
// heredoc bodies are data: drop every line after a line with <<WORD, <<'WORD', <<"WORD" or <<-WORD up to and including the
// terminator line (tabs allowed before it with <<-); an unterminated heredoc swallows the rest. One pass over the lines.
// A heredoc that is fed to a bare shell (bash, sh or zsh with flags only, no script file) is its stdin, which the shell runs
// as commands: its body is kept (the terminator line is dropped), so the graders read it like any other command text.
const feedsShell = prefix => {
  const segs = prefix.split(/[;&|(){}`]+/);
  const w = segs[segs.length - 1].trim().split(/\s+/).filter(t => t !== "");
  let k = 0;
  while (k < w.length && /^(?:[A-Za-z_][A-Za-z0-9_]*=.*|if|then|do|else|elif|while|until|!|sudo|env|nice|time|nohup|exec|command)$/.test(w[k])) k++;
  if (k >= w.length || !/^(?:ba|z)?sh$/.test(w[k].replace(/^.*\//, ""))) return false;
  for (let j = k + 1; j < w.length; j++) {
    if (/^-[a-zA-Z]*c/.test(w[j])) return false;   // -c, -ec, -xc: the shell runs the -c string; the heredoc is that script's stdin, not commands
    if (/^[-+][a-zA-Z]*[oO]$/.test(w[j])) j++;   // an option that takes a value (-o pipefail)
    else if (!/^[-+]/.test(w[j])) return false;   // a script file or other word: the body is input to it
  }
  return true;
};
const stripHeredocs = s => {
  const out = [];
  const pending = [];
  for (const line of s.split("\n")) {
    if (pending.length) {
      const t = pending[0].dash ? line.replace(/^\t+/, "") : line;
      if (t.replace(/\r$/, "") === pending[0].word) pending.shift();
      else if (pending[0].keep) out.push(line);
      continue;
    }
    out.push(line);
    // not a here-string (<<<); the word may be quoted ('W' or "W") or backslash-quoted (\W)
    const re = /(?<!<)<<(?!<)(-?)[ \t]*(?:(["'])([A-Za-z_][A-Za-z0-9_]*)\2|\\?([A-Za-z_][A-Za-z0-9_]*))/g;
    let m;
    // only in code: a << inside a quoted string or an arithmetic $(( )) is no heredoc (a $( ) inside double quotes is code)
    const v = shellView(line), view = v.out + (v.subs.length ? ";" + v.subs.join(";") : "");
    // Linear: the start of the current simple command is tracked while scanning (no slice from 0 per heredoc), and a second
    // heredoc in the same simple command is never fed to a bare shell (its prefix holds the first <<WORD, a non-flag word).
    let scanned = 0, cmdStart = 0, prevStart = -1;
    while ((m = re.exec(view))) {
      for (; scanned < m.index; scanned++) if (";&|(){}`".indexOf(view[scanned]) >= 0) cmdStart = scanned + 1;
      scanned = re.lastIndex;
      pending.push({ dash: m[1] === "-", word: m[3] || m[4], keep: cmdStart !== prevStart && feedsShell(view.slice(cmdStart, m.index)) });
      prevStart = cmdStart;
    }
  }
  return out.join("\n");
};
// like unquote, but the command substitutions inside a double-quoted string are kept as commands of their own (appended
// at the end, so the words around the string stay as they were): out="$(bash proof-run.sh)", [ -n "$(bash proof-run.sh)" ]
// and "$(bash proof-run.sh)"x run it; echo "bash proof-run.sh" does not
// One quote-aware scan (single pass, explicit stack, no recursion): `out` is the text outside every quoted string and every $(( )); `subs`
// are the bodies of the $( ) found inside double quotes, matched with their own nested quotes and parentheses, so
// out="$(bash proof-run.sh --label "red")" keeps the run. An arithmetic $(( ... )) holds no command and no heredoc.
const shellView = s => {
  const n = s.length, subs = [];
  let budget = 4 * n + 1000;   // total size of the collected bodies: deep nesting would otherwise copy the text once per level
  const keep = (a, b) => { if (b - a <= budget) { budget -= b - a; subs.push(s.slice(a, b)); } };
  const arith = i => { let d = 2; i += 3; while (i < n && d > 0) { if (s[i] === "(") d++; else if (s[i] === ")") d--; i++; } return i; };   // i at "$((": the index after its "))"
  const HD = /<<(?!<)-?[ \t]*(?:(["'])[A-Za-z_][A-Za-z0-9_]*\1|\\?[A-Za-z_][A-Za-z0-9_]*)/y;   // a heredoc word, quoted or not, stays as it is
  // An explicit stack instead of recursion (a deeply nested input must not overflow the call stack): a frame is
  // { d: true } for a double-quoted string, or { start, depth } for a $( ) body.
  const st = [];
  let out = "", i = 0;
  while (i < n) {
    const c = s[i], top = st.length ? st[st.length - 1] : null;
    if (top === null) {
      HD.lastIndex = i;
      const h = c === "<" && s[i - 1] !== "<" ? HD.exec(s) : null;
      if (h) { out += h[0]; i += h[0].length; }
      else if (c === "\\") { out += s.slice(i, i + 2); i += 2; }
      else if (c === "'" && s.indexOf("'", i + 1) > 0) i = s.indexOf("'", i + 1) + 1;
      else if (c === '"') { st.push({ d: true }); i++; }
      else if (c === "$" && s[i + 1] === "(" && s[i + 2] === "(") i = arith(i);
      else { out += c; i++; }
    } else if (top.d) {   // inside double quotes: hidden, except a command substitution
      if (c === "\\") i += 2;
      else if (c === '"') { st.pop(); i++; }
      else if (c === "$" && s[i + 1] === "(") {
        if (s[i + 2] === "(") i = arith(i);
        else { st.push({ start: i + 2, depth: 1 }); i += 2; }
      } else i++;
    } else {   // inside $( ): quotes are skipped, parentheses counted
      if (c === "\\") i += 2;
      else if (c === "'") { const e = s.indexOf("'", i + 1); i = e < 0 ? n : e + 1; }
      else if (c === '"') { st.push({ d: true }); i++; }
      else if (c === "(") { top.depth++; i++; }
      else if (c === ")" && --top.depth === 0) { keep(top.start, i); st.pop(); i++; }
      else i++;
    }
  }
  for (let k = st.length - 1; k >= 0; k--) if (!st[k].d) keep(st[k].start, n);   // unclosed $( ): the rest of the text is its body
  return { out, subs };
};
const unquoteRun = s => {
  const r = shellView(s);
  return r.subs.length ? r.out + ";" + r.subs.join(";") : r.out;
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
// simple commands at ; & | and newlines; redirects, tee, mv/cp/git mv targets, sed/perl in-place edits and node
// writeFileSync/appendFileSync calls count. After a `cd src` (or ./src, or <abs>/src) a relative path is inside src until
// a later cd that leaves it.
function bashWrites(cmd) {
  const toks = cmd.match(/"(?:[^"\\]|\\.)*"|'[^']*'|&&|\|\||>>|[;&|>\n()]|[^\s;&|<>()"']+/g) || [];
  const bare = t => t.replace(/^["']|["']$/g, "");
  let words = [], inSrc = false, inHand = false;
  let sawSrc = false, sawSpec = false;
  const saved = [];   // [inSrc, inHand] at each open "(": a subshell's cd does not leak out of it
  const rel = p => p !== "" && !/^(\/|~|\.\.|-)/.test(p);
  const src = p => isSrc(p) || (inSrc && rel(p));
  // the spec file: the same path rule as a Write/Edit call; a bare 01-spec.md only after a cd into .agents/handoff still in effect
  const spec = p => /(^|\/)\.agents\/handoff\/01-spec\.md$/.test(p.replace(/\\/g, "/")) || (inHand && /^(\.\/)?01-spec\.md$/.test(p));
  // a write target: an src write ends the scan (nothing after it can put the spec first); a spec write before it is noted
  // one simple command that writes both counts the src write first: a spec write noted in the same command is taken back
  let specAtStart = false;
  const hit = p => { if (src(p)) { sawSrc = true; sawSpec = specAtStart; } else if (spec(p)) sawSpec = true; return sawSrc; };
  const hits = list => { for (const p of list) if (hit(p)) return true; return false; };
  const done = () => { const r = done0(); specAtStart = sawSpec; return r; };
  const done0 = () => {
    const w = words; words = [];
    if (!w.length) return false;
    const verb = bare(w[0]).replace(/^.*\//, ""), args = w.slice(1), plain = args.filter(a => !/^-/.test(a));
    const flags = args.filter(a => /^-/.test(a));
    if (verb === "cd") {
      const d = plain.length ? bare(plain[0]) : "";
      inSrc = (inSrc && rel(d)) || isSrc(d + "/");
      inHand = /(^|\/)\.agents\/handoff\/?$/.test(d.replace(/\\/g, "/"));
      return false;
    }
    if (verb === "tee") return hits(plain.map(bare));
    if (verb === "mv" || verb === "cp") return plain.length > 0 && hit(bare(plain[plain.length - 1]));
    if (verb === "git") {
      let j = 0;
      while (j + 1 < args.length && bare(args[j]) === "-C") j += 2;   // git -C DIR mv ... (an index walk: linear)
      const q = args.slice(j).filter(x => !/^-/.test(x));
      return q[0] === "mv" && q.length > 2 && hit(bare(q[q.length - 1]));
    }
    if (verb === "sed") return flags.some(f => /^-[a-zA-Z]*i|^--in-place/.test(f)) && hits(plain.map(bare));
    if (verb === "perl") return flags.some(f => /^-[a-zA-Z]*i/.test(f)) && hits(plain.map(bare));
    if (verb === "node" || verb === "nodejs") {
      const re = /\b(?:writeFileSync|appendFileSync)\s*\(\s*\x5c?["'`]([^"'`\x5c]*)/g;
      for (const a of plain) { let m; while ((m = re.exec(a))) if (hit(m[1])) return true; }
    }
    return false;
  };
  const result = () => ({ src: sawSrc, spec: sawSpec });
  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    if (t === ">" || t === ">>") { if (k + 1 < toks.length && hit(bare(toks[k + 1]))) return result(); k++; continue; }
    if (t === "(") { if (done()) return result(); saved.push([inSrc, inHand]); continue; }
    if (t === ")") { if (done()) return result(); if (saved.length) [inSrc, inHand] = saved.pop(); continue; }
    if (/^(&&|\|\||[;&|\n])$/.test(t)) { if (done()) return result(); continue; }
    words.push(t);
  }
  done();
  return result();
}
// does a shell command run proof-run.sh? Split into simple commands at ; & | ( ) { } backticks and newlines (linear), then skip
// reserved words, env assignments and the prefixes sudo/env/nice/timeout/time/nohup/exec/command with their flags (command -v and -V are lookups) and arguments;
// the command word is proof-run.sh, or a shell whose first non-flag word is
function runsProof(cmd) {
  const isP = t => /(^|\/)proof-run\.sh$/.test(t);
  const RESERVED = /^(if|then|do|else|elif|while|until|!)$/;
  const PREFIX = /^(sudo|env|nice|timeout|time|nohup|exec|command)$/;
  const FLAGARG = { sudo: /^-[ugphCDRTU]$/, env: /^-[uCS]$/, nice: /^-n$/, timeout: /^-[sk]$/ };
  // a substitution that is part of a word (${X}, or $(..) and `..` touching other characters) becomes one word character, so
  // "cat $(dirname x)/proof-run.sh" stays one token; a standalone $(..) or `..` is still split open (bounded: linear)
  const SEP = "[^\\s;&|(){}`=]";   // = is not in the class: x=$(..) is a captured run, not a word
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
        if (base === "command" && /^-[vV]$/.test(w[k + 1] || "")) break;
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
    const cmdText = b.name === "Bash" ? stripHeredocs(String(inp.command || "")) : "";
    if (b.name === "Bash" && (srcw < 0 || specw < 0)) {
      // heredoc bodies are data unless a shell reads them (cmdText); a Bash write of the spec is the spec write, ordered inside the call
      const w = bashWrites(unwrap(cmdText));
      if (w.spec && specw < 0) specw = i - 0.5;
      if (w.src && srcw < 0) srcw = i;
    }
    const cmd = b.name === "Bash" ? unquote(unwrap(cmdText)) : "";
    if (/feedback\.sh\s+capture/.test(cmd)) captured = true;
    // a test run, not a mention: proof-run.sh only as the command (or the script of a shell); ls, cat, head, diff of it are reads
    if (/\bnode\s+--test\b|\bnpm\s+(?:run\s+)?test\b/.test(cmd) || runsProof(b.name === "Bash" ? unquoteRun(unwrap(cmdText)) : "")) ran = true;
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
const untested = s => /\buntested\b|\b(has no|added no|without( (a|any))?) tests?\b(?![ \t]*(failing|that (are|were) failing|that fail))|\bno tests? (covers|covering)\b|\bno automated (test )?coverage\b|\bnot covered by (a )?tests?\b/i.test(s);

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
