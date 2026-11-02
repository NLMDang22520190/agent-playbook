// PB-HIDDEN-CANARY:pattern-34-discount-codes
// Hidden FAIL_TO_PASS test: discount codes SAVE10 (10 percent) and WELCOME5 (500 cents off), case-insensitive
// (docs/pricing.md): subtotal, then discount, then tax on the discounted subtotal; shipping on the subtotal before the
// discount; total = discounted subtotal + tax + shipping; percent discounts round half up to the cent; a fixed
// discount never takes the discounted subtotal below 0; an unknown code is rejected with HTTP 400 and body
// {error: "unknown_code"}. The receipt shows a `Discount -X.XX` line and the API response gains discountCents.
// handleCheckout(body) takes the same fields as checkout: {lines, ratePct, code}; it may return a promise.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { checkout } = require(path.join(SRC, 'checkout.js'));
const { receiptLines } = require(path.join(SRC, 'receipt.js'));
const { handleCheckout } = require(path.join(SRC, 'api.js'));

const pick = (r) => ({
  subtotalCents: r.subtotalCents, discountCents: r.discountCents, taxCents: r.taxCents,
  shippingCents: r.shippingCents, totalCents: r.totalCents,
});
const save10 = () => ({ lines: [{ unitCents: 1999, qty: 2 }], ratePct: 8, code: 'SAVE10' });

test('AC SAVE10: 10 percent off rounded half up, tax on the discounted subtotal', () => {
  // 3998 * 10% = 399.8 -> 400; tax (3998 - 400) * 8% = 287.84 -> 288; shipping 500 (3998 < 5000)
  assert.deepEqual(pick(checkout(save10())),
    { subtotalCents: 3998, discountCents: 400, taxCents: 288, shippingCents: 500, totalCents: 4386 });
});

test('AC welcome5 (lower case): 500 off never below 0, shipping on the subtotal before the discount', () => {
  const r = checkout({ lines: [{ unitCents: 300, qty: 1 }], ratePct: 10, code: 'welcome5' });
  assert.deepEqual(pick(r),
    { subtotalCents: 300, discountCents: 300, taxCents: 0, shippingCents: 500, totalCents: 500 });
});

test('AC D9 SAVE10 on a 5000 subtotal: shipping is free on the subtotal before the discount', () => {
  // subtotal 2500 * 2 = 5000; discount 5000 * 10% = 500; discounted 4500; tax 0 (rate 0);
  // shipping 0 because the subtotal before the discount (5000) reaches 5000, although the discounted 4500 does not
  const r = checkout({ lines: [{ unitCents: 2500, qty: 2 }], ratePct: 0, code: 'SAVE10' });
  assert.deepEqual(pick(r),
    { subtotalCents: 5000, discountCents: 500, taxCents: 0, shippingCents: 0, totalCents: 4500 });
});

test('AC the API rejects an unknown code with 400 unknown_code', async () => {
  const res = await handleCheckout({ lines: [{ unitCents: 1999, qty: 2 }], ratePct: 8, code: 'BOGUS' });
  assert.equal(res.status, 400);
  assert.equal(res.body && res.body.error, 'unknown_code');
});

test('AC the receipt shows a Discount line', () => {
  const lines = receiptLines(checkout(save10()));
  assert.ok(Array.isArray(lines), 'receiptLines returns an array');
  assert.ok(lines.some((l) => /^Discount -4\.00$/.test(l)), `a "Discount -4.00" line in ${JSON.stringify(lines)}`);
});

test('AC the API 200 response gains discountCents', async () => {
  const res = await handleCheckout(save10());
  assert.equal(res.status, 200);
  assert.equal(res.body.discountCents, 400);
  assert.equal(res.body.totalCents, 4386);
});
