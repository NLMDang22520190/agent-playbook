#!/usr/bin/env bash
# Builds the task repo in $1: project-02-tax-exempt plus large generated noise (offline, fixed author and date): a 400-case visible
# matrix test whose `npm test` output is tens of KB, a long tax-history document and a sample orders CSV. The ticket, the
# hidden tests and the solution are those of project-02; the point of this variant is that a natural run puts large tool output
# into the context (test runs, file reads), which is what Context Mode claims to cut. Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../project-02-tax-exempt/setup.sh" "$dest"
cd "$dest"
mkdir -p data

cat > tests/matrix.test.js <<'PB_TASK_EOF'
'use strict';
// Consumer price matrix: 400 generated carts, each checked against the shop's arithmetic invariants.
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceOrder } = require('../src/pricing');
const { loadConfig } = require('../src/config');

const config = loadConfig();
let seed = 20260211;
function next(n) { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; }
const SKUS = ['A', 'B', 'C', 'D', 'E', 'F'];
const COUPONS = [null, 'SAVE5', 'WELCOME10'];

for (let i = 1; i <= 400; i += 1) {
  const lines = [];
  const count = 1 + next(4);
  for (let j = 0; j < count; j += 1) lines.push({ sku: SKUS[next(SKUS.length)], qty: 1 + next(5), unitCents: 99 + next(9000) });
  const coupon = COUPONS[next(COUPONS.length)];
  const label = `matrix case ${String(i).padStart(3, '0')}: ${lines.map((l) => `${l.sku} x${l.qty} @${l.unitCents}c`).join(', ')}, coupon ${coupon || 'none'}`;
  test(label, () => {
    const t = priceOrder({ lines, coupon }, config);
    assert.equal(t.goodsCents, lines.reduce((s, l) => s + l.unitCents * l.qty, 0));
    assert.equal(t.discountedCents, t.goodsCents - t.discountCents);
    assert.equal(t.taxCents, Math.floor((t.discountedCents * config.tax_percent + 50) / 100));
    assert.equal(t.totalCents, t.discountedCents + t.shippingCents + t.taxCents);
  });
}
PB_TASK_EOF

node -e '
const fs = require("fs");
let seed = 77;
const next = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const topics = ["rounding of the VAT line", "free-shipping threshold", "coupon stacking", "price display in the cart", "invoice numbering", "handling of cents on refunds", "regional rate tables", "rounding of percent coupons", "export orders", "gift cards"];
const verbs = ["was reviewed by finance and left unchanged", "was changed after a customer complaint", "was documented after an audit", "was discussed again at the quarterly meeting", "was clarified with the accountant"];
let out = "# Tax and pricing history\n\nA dated log of decisions about tax and pricing. The rules in force today are in `docs/policy.md` and `docs/money.md`; this file is history only and is kept for audits.\n";
for (let y = 2019; y <= 2026; y += 1) {
  out += "\n## " + y + "\n";
  for (let m = 1; m <= 12; m += 1) {
    const t = topics[next(topics.length)], v = verbs[next(verbs.length)];
    out += "\n- " + y + "-" + String(m).padStart(2, "0") + ": The " + t + " " + v + ". Ticket SHOP-" + (100 + next(900)) + " has the detail; the person on call was reachable at the usual channel, and the note was copied to the finance wiki so the next audit finds it. The figures quoted back then used the " + (18 + next(5)) + "% reference rate of that year and are not the rates in force today.";
    if (y === 2024 && m === 6) out += " Companies with a VAT number began ordering through the shop; accounting asked for tax lines of 0 for them (see docs/invoicing.md).";
  }
}
fs.writeFileSync("docs/tax-history.md", out);
let csv = "order_id,date,customer_type,goods_cents,discount_cents,shipping_cents,tax_cents,total_cents\n";
for (let i = 1; i <= 1200; i += 1) {
  const goods = 500 + next(60000), disc = next(3) === 0 ? Math.round(goods * 0.1) : 0, d = goods - disc, ship = d >= 5000 ? 0 : 490, tax = Math.floor((d * 20 + 50) / 100);
  csv += "SH-" + String(100000 + i) + ",2025-" + String(1 + next(12)).padStart(2, "0") + "-" + String(1 + next(28)).padStart(2, "0") + ",consumer," + goods + "," + disc + "," + ship + "," + tax + "," + (d + ship + tax) + "\n";
}
fs.writeFileSync("data/orders-2025.csv", csv);
'
printf '\nTax history for audits: `docs/tax-history.md`. Anonymised sample of last year'"'"'s orders: `data/orders-2025.csv`.\n' >> README.md

git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-12T10:00:00Z' GIT_COMMITTER_DATE='2026-02-12T10:00:00Z' git commit -q -m "Add price matrix test, tax history and sample orders"
