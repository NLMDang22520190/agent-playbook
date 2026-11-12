// Summarize run-ab.sh output: node summarize.js OUT_DIR. Reads the runner JSON files (baseline-N.json, cm-N.json) and the stream-json
// transcripts in baseline-N.runs/<label>.log; prints a markdown table per task and arm. UNTESTED by the author.
const fs = require("fs"), path = require("path");
const dir = process.argv[2];
if (!dir) { console.error("usage: node summarize.js OUT_DIR"); process.exit(2); }
const med = a => { const s = a.filter(x => typeof x === "number").sort((x, y) => x - y); if (!s.length) return null; const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const fmt = (x, d = 3) => x == null ? "n/a" : Number(x).toFixed(d);
function transcript(jsonPath, label) {
  const log = path.join(jsonPath.replace(/\.json$/, ".runs"), label + ".log");
  const out = { toolKB: null, tokens: null, cw: null, cr: null, outTok: null, turns: null, ctxCalls: 0, loaded: false };
  let txt; try { txt = fs.readFileSync(log, "utf8"); } catch (e) { return out; }
  for (const line of txt.split("\n")) {
    let o; try { o = JSON.parse(line); } catch (e) { continue; }
    if (o.type === "system" && o.subtype === "init" && JSON.stringify(o.mcp_servers || o.tools || "").includes("context-mode")) out.loaded = true;
    if (o.type === "assistant" && o.message && Array.isArray(o.message.content))
      for (const b of o.message.content) if (b.type === "tool_use" && /context-mode|ctx_/.test(b.name || "")) out.ctxCalls++;
    if (o.type === "user" && o.message && Array.isArray(o.message.content))
      for (const b of o.message.content) if (b.type === "tool_result") {
        const c = b.content; const n = typeof c === "string" ? Buffer.byteLength(c) : Array.isArray(c) ? c.reduce((s, x) => s + Buffer.byteLength(typeof x === "string" ? x : (x.text || "")), 0) : 0;
        out.toolKB = (out.toolKB || 0) + n / 1024;
      }
    if (o.type === "result") {
      const u = o.usage || {};
      out.cr = u.cache_read_input_tokens; out.cw = u.cache_creation_input_tokens; out.outTok = u.output_tokens;
      out.tokens = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
      out.turns = o.num_turns;
    }
  }
  return out;
}
const rows = [];
for (const f of fs.readdirSync(dir).filter(x => x.endsWith(".json"))) {
  const arm = f.startsWith("cm-") ? "context-mode" : f.startsWith("baseline-") ? "baseline" : null; if (!arm) continue;
  let d; try { d = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); } catch (e) { continue; }
  for (const r of d.runs || []) {
    const hp = (r.checks || []).find(c => c.name === "hidden tests pass");
    const t = transcript(path.join(dir, f), r.label);
    rows.push({ arm, task: r.scenario, status: r.status, pass: r.status === "graded" && hp ? hp.result === "PASS" : null, cost: r.cost_usd, secs: r.seconds, ...t });
  }
}
console.log("# Context Mode A/B (without playbook)\n");
console.log("| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median tool-result KB | Median turns | Plugin loaded (runs) | ctx tool calls (total) |");
console.log("|---|---|---|---|---|---|---|---|---|---|---|---|---|");
const tasks = [...new Set(rows.map(r => r.task))].sort();
for (const t of tasks) for (const a of ["baseline", "context-mode"]) {
  const g = rows.filter(r => r.task === t && r.arm === a), ok = g.filter(r => r.status === "graded");
  console.log(`| ${t} | ${a} | ${ok.length} | ${g.length - ok.length} | ${ok.filter(r => r.pass).length}/${ok.length} | ${fmt(med(ok.map(r => r.cost)))} | ${fmt(med(ok.map(r => r.secs)), 0)} | ${fmt(med(ok.map(r => r.tokens)), 0)} | ${fmt(med(ok.map(r => r.cw)), 0)} | ${fmt(med(ok.map(r => r.toolKB)), 1)} | ${fmt(med(ok.map(r => r.turns)), 1)} | ${g.filter(r => r.loaded).length} | ${g.reduce((s, r) => s + r.ctxCalls, 0)} |`);
}
console.log("\nTotal cost_usd of all runs: " + rows.reduce((s, r) => s + (r.cost || 0), 0).toFixed(3));
console.log("\nRead with care: k is small, the transcript parser is untested, and 'Plugin loaded' 0 in the context-mode arm means the plugin did not load (then the arm measures nothing).");
