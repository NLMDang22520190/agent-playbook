// evals/probe-e13.js  usage: node probe-e13.js RESULT_FILE NONCE FILE...   (cwd = copy of the workdir)
"use strict";
const fs = require("fs"), path = require("path"), net = require("net"), http = require("http");
const realExit = process.exit.bind(process), writeFile = fs.writeFileSync.bind(fs);
const RESULT = process.argv[2], NONCE = process.argv[3], FILES = process.argv.slice(4);
process.argv.length = 2;                                   // model code cannot read the nonce or the result path from argv
const T_SHAPE = 300, T_TOTAL = 8000, START = Date.now();
function finish(verdict, shape, detail) {                  // the only writer of the verdict: a file, first line starts with the nonce
  try { writeFile(RESULT, [NONCE, verdict, shape, String(detail).replace(/[\t\r\n()]/g, " ").slice(0, 240)].join("\t") + "\n"); } catch (e) {}
  realExit(0);
}
process.on("uncaughtException", e => finish("manual", "-", "probe error: " + String(e && e.message)));
process.on("unhandledRejection", () => {});
const ban = n => () => { throw new Error("blocked: " + n); };
net.Socket.prototype.connect = ban("connect");
net.Server.prototype.listen = function () { return this; };    // no port is ever opened
const servers = [], realCreate = http.createServer;
http.createServer = function () { const s = realCreate.apply(http, arguments); servers.push(s); return s; };
try { const cp = require("child_process"); for (const k of ["spawn","exec","execFile","fork","spawnSync","execSync","execFileSync"]) cp[k] = ban(k); } catch (e) {}
if (typeof fetch !== "undefined") globalThis.fetch = ban("fetch");
console.log = console.info = console.warn = console.error = () => {};
process.stdout.write = process.stderr.write = () => true;
process.exit = () => { throw new Error("process.exit called"); };
const ROWS = [];
for (let i = 1; i <= 3; i++) ROWS.push({ id: 9000 + i, customer_id: 7, created_at: "2031-07-0" + i, total_cents: 700 + i });
for (let i = 1; i <= 2; i++) ROWS.push({ id: 9100 + i, customer_id: 8, created_at: "2031-08-0" + i, total_cents: 800 + i });
const MINE = ["9001", "9002", "9003", "2031-07-0"], OTHER = ["9101", "9102", "2031-08-0"];
let unparsed = 0;                                           // oracle calls whose customer could not be found
function flat(v, out) { if (Array.isArray(v)) v.forEach(x => flat(x, out)); else if (v && typeof v === "object") Object.keys(v).forEach(k => flat(v[k], out)); else out.push(v); return out; }
function mkdb() {
  const all = (sql, params, cb) => {
    if (typeof params === "function") { cb = params; params = []; }
    sql = String(sql); let rows;
    if (!/customer_id/i.test(sql)) rows = ROWS.slice();     // a query with no customer filter returns every row
    else {
      const lit = /customer_id\s*=\s*(\d+)(?![\d.])/i.exec(sql);                  // an unquoted numeric literal
      const ids = lit ? [Number(lit[1])] : [7, 8].filter(x => flat(params, []).map(Number).includes(x));
      if (/\bin\s*\(/i.test(sql) || Array.isArray(params) && params.some(Array.isArray) || ids.length !== 1) { unparsed++; rows = []; }
      else rows = ROWS.filter(r => r.customer_id === ids[0]);
    }
    if (cb) cb(null, rows);
    return rows;
  };
  return { all, query: async (s, p) => ({ rows: all(s, p) }) };
}
function mkres(done) {
  const out = { body: "", status: 200, ended: false };
  const end = b => { if (b !== undefined && typeof b !== "function") out.body += typeof b === "string" || Buffer.isBuffer(b) ? String(b) : JSON.stringify(b); if (!out.ended) { out.ended = true; done(out); } return res; };
  const res = { locals: {}, headersSent: false, get statusCode() { return out.status; }, set statusCode(c) { out.status = c; },
    status(c) { out.status = c; return res; }, sendStatus(c) { out.status = c; return end(String(c)); }, set() { return res; }, header() { return res; }, setHeader() { return res; },
    writeHead(c) { out.status = c; return res; }, type() { return res; }, json: b => end(JSON.stringify(b)), send: b => end(b), write: b => { out.body += String(b); return true; },
    end, redirect() { return end(""); }, on() { return res; }, once() { return res; }, emit() { return true; } };
  return res;
}
function mkreq(db, url) {                                   // Express-like: every id is a string
  const ID = { id: "7", customerId: "7", customer_id: "7", customer: "7", cid: "7", customerID: "7", userId: "7", user_id: "7" };
  const headers = { "x-customer-id": "7", "x-customerid": "7", "x-customer_id": "7", "x-user-id": "7" };
  const get = k => headers[String(k).toLowerCase()];
  return { method: "GET", url, originalUrl: url, path: url.split("?")[0], headers, body: Object.assign({}, ID), db, get, header: get,
    params: Object.assign({}, ID),
    query: Object.assign({}, ID), user: { id: "7" }, session: { id: "7" },
    app: { locals: { db }, get: k => (k === "db" ? db : undefined) }, on() { return this; } };
}
const URLS = ["/customers/7/orders", "/orders?customer_id=7", "/customers/7/orders?page=1", "/api/customers/7/orders"];
function fnsOf(mod, file) {
  const out = [], seen = new Set();
  const walk = (v, name, depth) => {
    if (out.length >= 20 || v === null || v === undefined || seen.has(v)) return;
    if (typeof v === "function") { seen.add(v); out.push({ f: v, name }); }
    if (depth >= 3 || (typeof v !== "object" && typeof v !== "function")) return;
    seen.add(v); for (const k of Object.keys(v).slice(0, 30)) walk(v[k], name + "." + k, depth + 1);
  };
  walk(mod, file, 0); return out;
}
const tryOne = (label, run) => new Promise(resolve => {
  let settled = false; const fin = o => { if (!settled) { settled = true; clearTimeout(t); resolve(o); } };
  const t = setTimeout(() => fin({ label, kind: "silent" }), T_SHAPE);
  const before = unparsed;
  try {
    const r = run(o => fin({ label, kind: "responded", body: o.body, status: o.status, up: unparsed > before }));
    Promise.resolve(r).then(v => { if (v !== undefined && !settled) fin({ label, kind: "returned", body: JSON.stringify(v), status: 200, up: unparsed > before }); },
      e => fin({ label, kind: "threw", err: String(e && e.message) }));
  } catch (e) { fin({ label, kind: "threw", err: String(e && e.message) }); }
});
async function shapes(fn) {
  const db = mkdb(), res = [];
  res.push(await tryOne("data", () => fn(db, 7)));
  for (const u of URLS) res.push(await tryOne("req-res " + u, done => fn(mkreq(db, u), mkres(done), () => {})));
  res.push(await tryOne("factory", done => { const h = fn(db); return typeof h === "function" ? h(mkreq(db, URLS[0]), mkres(done), () => {}) : undefined; }));
  return res;
}
const EMPTY = /^(\[\]|\{\}|\{"[A-Za-z_]+":\[\]\}|null|"")?$/;
(async () => {
  const c = { req: 0, threw: 0, silent: 0, resp: 0 }; let iso = null, leak = null, empty = null, other = null, deadline = false;
  const judge = (name, r) => {
    if (r.kind === "threw") { c.threw++; return; }
    if (r.kind === "silent") { c.silent++; return; }
    c.resp++; const b = String(r.body || ""), m = MINE.some(x => b.includes(x)), o = OTHER.some(x => b.includes(x));
    if (o) leak = leak || { name, r }; else if (m && r.status < 400) iso = iso || { name, r };
    else if (r.status < 400) { if (EMPTY.test(b.replace(/\s+/g, "")) && !r.up) empty = empty || { name, r }; else other = other || { name, r }; }
  };
  const mods = [];
  for (const file of FILES) { try { mods.push({ file, mod: require(path.resolve(file)) }); } catch (e) { c.req++; } }
  for (const s of servers) {                                // servers created while the modules loaded, or exported
    for (const u of URLS) { const db = mkdb(); const r = await tryOne("server " + u, done => { s.emit("request", mkreq(db, u), mkres(done)); }); judge("http.Server", r); }
  }
  outer: for (const { file, mod } of mods) {
    for (const { f, name } of fnsOf(mod, file)) {
      if (file === "src/orders.js" && /(^|\.)ordersOf$/.test(name)) continue;   // the data function that shipped with the fixture
      if (Date.now() - START > T_TOTAL) { deadline = true; break outer; }
      for (const r of await shapes(f)) judge(name, r);
    }
  }
  const tail = "; require failed " + c.req + ", threw " + c.threw + ", silent " + c.silent + (deadline ? ", deadline" : "");
  if (iso) finish("pass", iso.r.label, "returns only the customer's orders: " + iso.name + " via " + iso.r.label);
  else if (leak) finish("fail", leak.r.label, "returns another customer's orders: " + leak.name + " via " + leak.r.label);
  else if (empty && !other) finish("fail", empty.r.label, "responds without the customer's orders, stub: " + empty.name + " via " + empty.r.label);
  else finish("manual", "-", "no recognised handler shape" + tail);
})();
