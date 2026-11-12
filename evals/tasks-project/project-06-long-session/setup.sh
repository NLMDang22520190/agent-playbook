#!/usr/bin/env bash
# Builds the task repo in $1 for a LONG session: project-05-tax-exempt-noisy (shop, invoice module, 400-case matrix test, tax history,
# sample orders) plus a payment-gateway log of about 2000 events (offline, fixed author and date). The prompt holds three tickets to be
# done one after the other in ONE session: company tax exemption (project-02), returns (project-01) and a duplicate-charge incident
# found in logs/payments.log. Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../project-05-tax-exempt-noisy/setup.sh" "$dest"
cd "$dest"
mkdir -p logs

cat > docs/payments.md <<'PB_TASK_EOF'
# Payment gateway log

`logs/payments.log` has one event per line: `<time> order=<id> event=<EVENT> amount=<cents> gw=<gateway>`.

Events: `AUTHORIZED` (the card was reserved, nothing is charged), `VOIDED` (a reservation was released), `CAPTURED` (the customer was
charged), `REFUNDED` (the charge was paid back in full). A customer is charged only by `CAPTURED`. An order is charged twice when it has
a `CAPTURED` that is not followed by a `REFUNDED` before the next `CAPTURED` of the same order.
PB_TASK_EOF

node -e '
const fs = require("fs");
let seed = 4242;
const next = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const ids = [];
for (let i = 0; i < 600; i += 1) ids.push("SH-" + (200000 + i * 3 + next(3)));
const dup = new Set();
while (dup.size < 7) dup.add(ids[next(ids.length)]);
const events = [];
let t = Date.UTC(2026, 2, 1, 0, 0, 0);
const stamp = () => { t += 20000 + next(60000); return new Date(t).toISOString().replace(".000Z", "Z"); };
const gws = ["g1", "g2", "g3"];
for (const id of ids) {
  const amount = 990 + next(40000), gw = gws[next(3)];
  const kind = dup.has(id) ? "dup" : ["plain", "plain", "plain", "void", "refund", "recharge"][next(6)];
  const ev = (e) => events.push({ at: 0, id, e, amount, gw });
  ev("AUTHORIZED");
  if (kind === "void") { ev("VOIDED"); ev("AUTHORIZED"); ev("CAPTURED"); }
  else if (kind === "refund") { ev("CAPTURED"); ev("REFUNDED"); }
  else if (kind === "recharge") { ev("CAPTURED"); ev("REFUNDED"); ev("AUTHORIZED"); ev("CAPTURED"); }
  else if (kind === "dup") { ev("CAPTURED"); ev("CAPTURED"); }
  else ev("CAPTURED");
}
// interleave orders: shuffle by a stable sort on a random key per order, but keep each order events in sequence
const byOrder = new Map();
for (const e of events) { if (!byOrder.has(e.id)) byOrder.set(e.id, []); byOrder.get(e.id).push(e); }
const queues = [...byOrder.values()];
const lines = [];
while (queues.length) {
  const k = next(queues.length), q = queues[k], e = q.shift();
  lines.push("" + stamp() + " order=" + e.id + " event=" + e.e + " amount=" + e.amount + " gw=" + e.gw);
  if (!q.length) queues.splice(k, 1);
}
fs.writeFileSync("logs/payments.log", lines.join("\n") + "\n");
if (process.env.PB_PRINT_DUP) console.log([...dup].sort().join(","));
'

printf '\nPayment events: `logs/payments.log` (see `docs/payments.md`).\n' >> README.md
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-13T10:00:00Z' GIT_COMMITTER_DATE='2026-02-13T10:00:00Z' git commit -q -m "Add payment gateway log and docs"
