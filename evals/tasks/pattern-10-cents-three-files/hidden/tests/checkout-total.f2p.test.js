// PB-HIDDEN-CANARY:pattern-10-cents-three-files
// Hidden FAIL_TO_PASS test: whole-order totals. The prompt's example order (49.99, SAVE5, 8% tax, 4.90 flat, free from
// 50.00) totals 53.49; shipping is measured on the goods subtotal after the coupon and tax is charged on the discounted
// goods subtotal, not on shipping (docs/money.md).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { checkoutTotal } = require(path.join(__dirname, '..', 'src', 'checkout.js'));

const CONFIG = {
  coupons: {
    SAVE5: { type: 'fixed', amount: '5.00' },
    WELCOME10: { type: 'percent', percent: 10 },
  },
  shipping: { flat: '4.90', free_over: '50.00' },
  taxPct: 8,
};

function cart(unitCents, coupon) {
  return { lines: [{ sku: 'LAMP-01', unitCents, qty: 1 }], coupon };
}

test('the example order: 49.99 with SAVE5 totals 53.49', () => {
  assert.deepEqual(checkoutTotal(cart(4999, 'SAVE5'), CONFIG), {
    subtotal: 4999, discount: 500, shipping: 490, tax: 360, total: 5349,
  });
});

test('55.00 with SAVE5 leaves 50.00 of goods: free shipping, tax on 50.00', () => {
  assert.deepEqual(checkoutTotal(cart(5500, 'SAVE5'), CONFIG), {
    subtotal: 5500, discount: 500, shipping: 0, tax: 400, total: 5400,
  });
});

test('52.00 with SAVE5 drops below 50.00 after the coupon: shipping is charged', () => {
  assert.deepEqual(checkoutTotal(cart(5200, 'SAVE5'), CONFIG), {
    subtotal: 5200, discount: 500, shipping: 490, tax: 376, total: 5566,
  });
});

test('two lines without a coupon: 2 x 12.00 pays shipping and tax on 24.00', () => {
  const c = { lines: [{ sku: 'MUG-02', unitCents: 1200, qty: 2 }], coupon: undefined };
  assert.deepEqual(checkoutTotal(c, CONFIG), {
    subtotal: 2400, discount: 0, shipping: 490, tax: 192, total: 3082,
  });
});
