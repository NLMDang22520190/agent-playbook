"use strict";
// Codex JSONL support of the eval transcript readers (v0.29.0 lane cx). `codex exec --json` (codex-cli 0.164.0) prints one JSON
// event per line: thread.started, turn.started, turn.completed {usage}, turn.failed {error}, error, and item.started /
// item.completed of agent_message {text}, command_execution {command, aggregated_output, exit_code}, file_change
// {changes: [{path, kind: add|update|delete}]}, web_search {query, action: {type: open_page, url} | {type: search}} and
// mcp_tool_call {server, tool, arguments}; other item types (reasoning, todo_list, error) are not tool calls.
// normalize(text) -> { format, text, usage }:
//   format "codex" when a line is a thread./turn./item. event and no line is a Claude Code stream-json event (system,
//   assistant, user, result, tool_use, stream_event); then text is the transcript rewritten as stream-json lines that the
//   readers already understand. Any other transcript (Claude stream-json, plain text, mixed) comes back unchanged with
//   format "" and usage null, so the readers read it exactly as before.
// The rewrite: every item.completed becomes one assistant line (item.started is skipped):
//   agent_message      -> a text block
//   command_execution  -> Bash {command}: the script inside `/bin/bash -lc '...'` (or "..."), else the command as it is;
//                         a path <dir>/playbook-<name>/SKILL.md named in the command also gives Read {file_path} and
//                         Skill {skill: playbook-<name>} (Codex loads a skill by reading its SKILL.md)
//   file_change        -> Write {file_path} for an added path, Edit {file_path} for an updated or deleted one, in order
//   web_search         -> WebFetch {url} for action open_page, else WebSearch {query}
//   mcp_tool_call      -> mcp__<server>__<tool> {arguments}
// and the end of the last turn becomes a result line: subtype success when it ended with turn.completed (error after
// turn.failed or a later error event), result = the last agent_message of that turn (absent when the turn has none),
// usage = the sum of every turn.completed usage (numeric fields). No result line when the last turn never ended.
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
const SKILL_RE = /(?:^|[\s"'=:(<])((?:[^\s"'`;|&<>()]*\/)?(playbook-[A-Za-z0-9_-]+)\/SKILL\.md)(?=$|[\s"'`;|&<>)])/g;

function normalize(text) {
  const objs = [];
  let codex = false, claude = false;
  for (const line of String(text).split(/\r?\n/)) {
    let o;
    try { o = JSON.parse(line); } catch (e) { continue; }
    if (!o || typeof o !== "object" || typeof o.type !== "string") continue;
    if (/^(?:thread|turn|item)\./.test(o.type)) codex = true;
    else if (CLAUDE[o.type]) claude = true;
    objs.push(o);
  }
  if (!codex || claude) return { format: "", text, usage: null };
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
    if (o.type === "turn.failed" || o.type === "error") { ended = "error"; continue; }
    if (o.type !== "item.completed" || !o.item || typeof o.item !== "object") continue;
    const it = o.item;
    if (it.type === "agent_message" && typeof it.text === "string") {
      reply = it.text;
      out.push({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text: it.text }] } });
    } else if (it.type === "command_execution") {
      const s = script(it.command);
      tool("Bash", { command: s });
      let m;
      SKILL_RE.lastIndex = 0;
      while ((m = SKILL_RE.exec(s))) { tool("Read", { file_path: m[1] }); tool("Skill", { skill: m[2] }); }
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
    if (reply !== null) r.result = reply;
    if (anyUsage) r.usage = usage;
    out.push(r);
  }
  return { format: "codex", text: out.map(x => JSON.stringify(x)).join("\n") + "\n", usage: anyUsage ? usage : null };
}
module.exports = { normalize, script };
