// Usage: node cm-sanitize-timeline.js <label> <timeline.txt> <outfile>. Drops personal temp paths and rate-limit lines.
const fs = require("fs");
const [label, inp, out] = process.argv.slice(2);
let s = fs.readFileSync(inp, "utf8");
s = s.split("\\").join("/").replace(/C:\/Users\/Lenovo\/AppData\/Local\/Temp\/tmp\.[A-Za-z0-9]+\/(project-05-tax-exempt-noisy\.without\.1\/)?/g, "<WORK>/");
s = s.split("\n").filter((x) => !x.startsWith("RATE_LIMIT")).map((x) => (x.startsWith("=== ") ? "=== " + label : x)).join("\n");
fs.writeFileSync(out, s);
