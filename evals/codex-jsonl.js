"use strict";
// Codex JSONL support of the eval transcript readers (v0.29.0 lane cx). `codex exec --json` (codex-cli 0.164.0) prints one JSON
// event per line: thread.started, turn.started, turn.completed {usage}, turn.failed {error}, error {message}, and item.started /
// item.completed of agent_message {text}, command_execution {command, aggregated_output, exit_code}, file_change
// {changes: [{path, kind: add|update|delete}]}, web_search {query, action: {type: open_page, url} | {type: search}} and
// mcp_tool_call {server, tool, arguments}; other item types (reasoning, todo_list, error) are not tool calls.
// normalize(text) -> { format, text, usage }:
//   format "codex" when a line is a thread./turn./item. event, no line is a Claude Code stream-json event (system, assistant,
//   user, result, tool_use, stream_event), and more than half of the non-empty lines are JSON events (a text that quotes one
//   event line is not a Codex log); then text is the transcript rewritten as stream-json lines that the readers already
//   understand. Any other transcript (Claude stream-json, plain text, mixed) comes back unchanged with format "" and usage
//   null, so the readers read it exactly as before.
// The rewrite: every item.completed becomes one assistant line (item.started is skipped):
//   agent_message      -> a text block
//   command_execution  -> Bash {command}: the script inside `/bin/bash -lc '...'` (or "..."), else the command as it is;
//                         a file argument <dir>/playbook-<name>/SKILL.md of a read-type command (cat, head, tail, less, more,
//                         nl, bat; sed, awk, grep, egrep, fgrep, rg after their script or pattern) also gives Read {file_path}
//                         and Skill {skill: playbook-<name>} (Codex loads a skill by reading its SKILL.md). A mention elsewhere
//                         (ls, test -f, a search pattern, an echo, a redirect target) is no read; the without-arm isolation
//                         check still fails on it, because it reads the Bash command itself.
//   file_change        -> Write {file_path} for an added path, Edit {file_path} for an updated or deleted one, in order
//   web_search         -> WebFetch {url} for action open_page, else WebSearch {query}
//   mcp_tool_call      -> mcp__<server>__<tool> {arguments}
// and the end of the last turn becomes a result line: subtype success when it ended with turn.completed, error after
// turn.failed; result = the last agent_message of that turn, only when it succeeded (a failed turn has no reply);
// usage = the sum of every turn.completed usage (numeric fields). An error event does not end a turn (Codex prints transient
// "Reconnecting" errors), so it changes nothing. No result line when the last turn never ended.
const CLAUDE = { system: 1, assistant: 1, user: 1, result: 1, tool_use: 1, stream_event: 1 };

// shellWord(s) -> s read as exactly one shell word ('...', "..." with \ escapes, bare characters), or null
function shellWord(s) {
  let i = 0, out = "";
  const n = s.length;
  while (i < n && !/\s/.test(s[i])) {
    const c = s[i];
    if (c === "'") {
      const j = s.indexOf("'", i + 1);
      if (j < 0) return null;
      out += s.slice(i + 1, j); i = j + 1;
    } else if (c === '"') {
      i++;
      while (i < n && s[i] !== '"') {
        if (s[i] === "\\" && i + 1 < n && '\\"$`\n'.indexOf(s[i + 1]) >= 0) { if (s[i + 1] !== "\n") out += s[i + 1]; i += 2; }
        else { out += s[i]; i++; }
      }
      if (i >= n) return null;
      i++;
    } else if (c === "\\") {
      if (i + 1 < n && s[i + 1] !== "\n") out += s[i + 1];
      i += 2;
    } else { out += c; i++; }
  }
  return s.slice(i).trim() === "" ? out : null;
}
// the script of a codex shell call: `/bin/bash -lc SCRIPT`, `bash -c SCRIPT` (also zsh, sh), or an argv array of that shape
function script(cmd) {
  if (Array.isArray(cmd)) {
    const a = cmd.map(String);
    if (a.length === 3 && /(^|\/)(?:ba|z)?sh$/.test(a[0]) && /^-l?c$/.test(a[1])) return a[2];
    return a.join(" ");
  }
  const c = String(cmd == null ? "" : cmd);
  const m = /^\s*(?:\/[\w./-]*\/)?(?:ba|z)?sh\s+-l?c\s+([\s\S]*)$/.exec(c);
  if (!m) return c;
  const w = shellWord(m[1]);
  return w === null ? c : w;
}

// commands(s) -> the simple commands of a shell script, each a list of words (quotes removed) and {redir: OP} markers.
// Split at ; & | ( ) and newlines outside quotes; a digit word right before > or < is its fd; >&N and 2>&1 name no file.
function commands(s) {
  const cmds = [];
  let words = [], w = null, i = 0;
  const n = s.length;
  const endWord = () => { if (w !== null) { words.push(w); w = null; } };
  const endCmd = () => { endWord(); if (words.length) cmds.push(words); words = []; };
  while (i < n) {
    const c = s[i];
    if (c === "'") { const j = s.indexOf("'", i + 1), e = j < 0 ? n : j; w = (w || "") + s.slice(i + 1, e); i = e + 1; continue; }
    if (c === '"') {
      let t = ""; i++;
      while (i < n && s[i] !== '"') { if (s[i] === "\\" && i + 1 < n) { t += s[i + 1]; i += 2; } else { t += s[i]; i++; } }
      i++; w = (w || "") + t; continue;
    }
    if (c === "\\") { w = (w || "") + (s[i + 1] || ""); i += 2; continue; }
    if (c === "\n") { endCmd(); i++; continue; }
    if (/\s/.test(c)) { endWord(); i++; continue; }
    if (c === ">" || c === "<") {
      if (w !== null && /^\d+$/.test(w)) w = null; else endWord();
      let j = i;
      while (j < n && /[<>&|]/.test(s[j])) j++;
      const op = s.slice(i, j);
      i = j;
      if (/&$/.test(op)) { while (i < n && /[\d-]/.test(s[i])) i++; continue; }
      words.push({ redir: op });
      continue;
    }
    if (";&|()".indexOf(c) >= 0) { endCmd(); i++; continue; }
    w = (w || "") + c; i++;
  }
  endCmd();
  return cmds;
}
const READ_ALL = /^(?:cat|head|tail|less|more|nl|bat)$/;
const READ_PAT = /^(?:sed|awk|grep|egrep|fgrep|rg)$/;
// flags that take the next word as their value, per verb (an attached value, -n20 or --regexp=x, is one word)
const VALUE_FLAG = {
  head: /^-[nc]$/, tail: /^-[nc]$/, bat: /^-[lr]$/, sed: /^-[ef]$/, awk: /^-[fvF]$/,
  grep: /^-[efmABCD]$/, egrep: /^-[efmABCD]$/, fgrep: /^-[efmABCD]$/, rg: /^-[efmABCgtT]$|^--(?:glob|type)$/,
};
// a flag that gives the script or pattern, so no positional word is it
const PAT_FLAG = { sed: /^-[ef]|^--(?:expression|file)/, awk: /^-f|^--file/, grep: /^-[ef]|^--(?:regexp|file)/,
  egrep: /^-[ef]|^--(?:regexp|file)/, fgrep: /^-[ef]|^--(?:regexp|file)/, rg: /^-[ef]|^--(?:regexp|file)/ };
const SKILL_PATH = /(?:^|\/)(playbook-[A-Za-z0-9_-]+)\/SKILL\.md$/;
// skillReads(script) -> [[path, skill]...]: the playbook SKILL.md files that read-type commands of the script read
function skillReads(s) {
  const out = [];
  for (const cw of commands(s)) {
    const words = [];
    let redir = null;
    for (const x of cw) {
      if (typeof x === "object") { redir = x.redir; continue; }
      if (redir !== null) { if (redir === "<") words.push({ input: x }); redir = null; continue; }   // a > target is a write, << a heredoc word
      words.push(x);
    }
    let k = 0;
    while (k < words.length && typeof words[k] === "string" &&
      (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k]) || /^(?:sudo|env|command|exec|nohup|time)$/.test(words[k].replace(/^.*\//, "")))) {
      k++;
      while (k < words.length && typeof words[k] === "string" && /^-/.test(words[k])) k++;
    }
    if (k >= words.length || typeof words[k] !== "string") continue;
    const verb = words[k].replace(/^.*\//, "");
    if (!READ_ALL.test(verb) && !READ_PAT.test(verb)) continue;
    const pos = [], inputs = [];
    let patByFlag = false, dd = false;
    for (let j = k + 1; j < words.length; j++) {
      const t = words[j];
      if (typeof t === "object") { inputs.push(t.input); continue; }
      if (!dd && t === "--") { dd = true; continue; }
      if (!dd && /^-./.test(t)) {
        if (PAT_FLAG[verb] && PAT_FLAG[verb].test(t)) patByFlag = true;
        if (VALUE_FLAG[verb] && VALUE_FLAG[verb].test(t)) j++;
        continue;
      }
      pos.push(t);
    }
    if (READ_PAT.test(verb) && !patByFlag) pos.shift();   // the script or pattern
    for (const p of pos.concat(inputs)) { const m = SKILL_PATH.exec(p); if (m) out.push([p, m[1]]); }
  }
  return out;
}

function normalize(text) {
  const objs = [];
  let codex = false, claude = false, lines = 0;
  for (const line of String(text).split(/\r?\n/)) {
    if (line.trim() === "") continue;
    lines++;
    let o;
    try { o = JSON.parse(line); } catch (e) { continue; }
    if (!o || typeof o !== "object" || typeof o.type !== "string") continue;
    if (/^(?:thread|turn|item)\./.test(o.type)) codex = true;
    else if (CLAUDE[o.type]) claude = true;
    objs.push(o);
  }
  if (!codex || claude || objs.length * 2 <= lines) return { format: "", text, usage: null };
  const out = [], usage = {};
  let reply = null, ended = null, anyUsage = false, n = 0;
  const tool = (name, input) => out.push({ type: "assistant", message: { role: "assistant", content: [{ type: "tool_use", id: "cx" + (++n), name, input }] } });
  for (const o of objs) {
    if (o.type === "turn.started") { reply = null; ended = null; continue; }
    if (o.type === "turn.completed") {
      ended = "success";
      const u = o.usage && typeof o.usage === "object" ? o.usage : {};
      for (const k of Object.keys(u)) if (typeof u[k] === "number" && /^[A-Za-z0-9_]+$/.test(k)) { usage[k] = (usage[k] || 0) + u[k]; anyUsage = true; }
      continue;
    }
    if (o.type === "turn.failed") { ended = "error"; continue; }
    if (o.type !== "item.completed" || !o.item || typeof o.item !== "object") continue;
    const it = o.item;
    if (it.type === "agent_message" && typeof it.text === "string") {
      reply = it.text;
      out.push({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text: it.text }] } });
    } else if (it.type === "command_execution") {
      const s = script(it.command);
      tool("Bash", { command: s });
      for (const r of skillReads(s)) { tool("Read", { file_path: r[0] }); tool("Skill", { skill: r[1] }); }
    } else if (it.type === "file_change" && Array.isArray(it.changes)) {
      for (const ch of it.changes) if (ch && typeof ch.path === "string") tool(ch.kind === "add" ? "Write" : "Edit", { file_path: ch.path });
    } else if (it.type === "web_search") {
      const a = it.action && typeof it.action === "object" ? it.action : {};
      if (a.type === "open_page" && typeof a.url === "string") tool("WebFetch", { url: a.url });
      else tool("WebSearch", { query: String(it.query == null ? a.query || "" : it.query) });
    } else if (it.type === "mcp_tool_call") {
      tool("mcp__" + String(it.server || "") + "__" + String(it.tool || ""), it.arguments && typeof it.arguments === "object" ? it.arguments : {});
    }
  }
  if (ended !== null) {
    const r = { type: "result", subtype: ended, is_error: ended !== "success" };
    if (ended === "success" && reply !== null) r.result = reply;
    if (anyUsage) r.usage = usage;
    out.push(r);
  }
  return { format: "codex", text: out.map(x => JSON.stringify(x)).join("\n") + "\n", usage: anyUsage ? usage : null };
}
module.exports = { normalize, script, skillReads };
