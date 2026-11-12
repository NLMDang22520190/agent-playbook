#!/usr/bin/env node
// Read-only. Usage: node cm-transcript-timeline.js <stream-json log> ...
// Prints, in order: tool calls (Bash command cut to 200 chars, Read/Edit/Write path), tool_result size in bytes,
// gap in seconds to the previous timestamped event, hook messages, api_retry and permission_denied events.
"use strict";
const fs = require("fs");
const bytes = (c) => typeof c === "string" ? Buffer.byteLength(c) : Buffer.byteLength(JSON.stringify(c));
for (const file of process.argv.slice(2)) {
  console.log("=== " + file);
  const ev = fs.readFileSync(file, "utf8").split("\n").filter(Boolean).map((x) => { try { return JSON.parse(x); } catch (e) { return null; } }).filter(Boolean);
  const calls = new Map(); let prev = null, n = 0, tests = [], touched = new Set(), maxGap = { s: 0, what: "" };
  for (const o of ev) {
    const t = o.timestamp ? Date.parse(o.timestamp) : null;
    let gap = "";
    if (t !== null) { if (prev !== null) { const g = (t - prev) / 1000; gap = " +" + g.toFixed(1) + "s"; } }
    if (o.type === "system" && o.subtype === "hook_response") console.log("HOOK_RESPONSE " + o.hook_event + " outcome=" + o.outcome + " out_bytes=" + bytes(o.output || o.stdout || ""));
    if (o.type === "system" && o.subtype === "api_retry") console.log("API_RETRY attempt=" + o.attempt + " delay_ms=" + o.retry_delay_ms + " err=" + (o.error || o.error_status || ""));
    if (o.type === "system" && o.subtype === "permission_denied") console.log("PERMISSION_DENIED " + JSON.stringify(o).slice(0, 300));
    if (o.type === "rate_limit_event") console.log("RATE_LIMIT " + JSON.stringify(o.rate_limit_info || o).slice(0, 200));
    if (o.type === "assistant") for (const b of o.message.content || []) {
      if (b.type === "tool_use") {
        const i = b.input || {}; let d = b.name;
        if (b.name === "Bash" || b.name === "PowerShell") { d += " " + String(i.command || "").slice(0, 200).replace(/\s+/g, " "); if (/npm test|node --test|npm run test/.test(i.command || "")) d += "   <== TEST RUN"; }
        else if (i.file_path || i.path) { d += " " + (i.file_path || i.path); touched.add(b.name + ":" + (i.file_path || i.path)); }
        else d += " " + JSON.stringify(i).slice(0, 120);
        calls.set(b.id, { d, t, name: b.name, cmd: i.command || "" });
        console.log(String(++n).padStart(2) + " CALL " + d + gap);
      }
    }
    if (o.type === "user") for (const b of (o.message && o.message.content) || []) {
      if (b.type === "tool_result") {
        const c = calls.get(b.tool_use_id); const sz = bytes(b.content);
        console.log("   RESULT " + sz + " B" + (b.is_error ? " ERROR" : "") + gap);
        if (c && /npm test|node --test/.test(c.cmd)) tests.push(sz);
        if (c && c.t !== null && t !== null && (t - c.t) / 1000 > maxGap.s) maxGap = { s: (t - c.t) / 1000, what: "tool " + c.d.slice(0, 80) };
      }
    }
    if (t !== null) { if (prev !== null && (t - prev) / 1000 > maxGap.s) maxGap = { s: (t - prev) / 1000, what: "between events before type=" + o.type + (o.subtype ? "/" + o.subtype : "") }; prev = t; }
  }
  console.log("TEST_RUNS " + tests.length + " sizes=" + JSON.stringify(tests));
  console.log("TOUCHED_invoice " + [...touched].filter((x) => /invoice|invoicing/.test(x)).join(", "));
  console.log("MAX_GAP " + maxGap.s.toFixed(1) + "s " + maxGap.what);
}
