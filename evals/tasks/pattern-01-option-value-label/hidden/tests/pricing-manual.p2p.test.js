// PB-HIDDEN-CANARY:pattern-01-option-value-label
// Hidden PASS_TO_PASS test: manual quote for unknown choices, base price without options.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceOrder } = require('../src/pricing');

test('an unknown choice goes to manual quote', () => {
  const product = { base: 10000, options: [
    { name: 'finish', choices: [{ value: 'matte', label: 'Matte finish', surcharge: 2000 }] },
  ] };
  assert.deepEqual(priceOrder(product, { finish: 'foil' }), { manual: true, total: null });
});

test('a product without options costs its base price', () => {
  assert.deepEqual(priceOrder({ base: 5000, options: [] }, {}), { manual: false, total: 5000 });
});
