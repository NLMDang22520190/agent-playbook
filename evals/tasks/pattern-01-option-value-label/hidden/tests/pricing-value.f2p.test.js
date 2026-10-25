// PB-HIDDEN-CANARY:pattern-01-option-value-label
// Hidden FAIL_TO_PASS test: a selection names the option VALUE, never its label.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceOrder } = require('../src/pricing');

function finishProduct() {
  return {
    base: 10000,
    options: [
      { name: 'finish', choices: [
        { value: 'matte', label: 'Matte finish', surcharge: 2000 },
        { value: 'gloss', label: 'Gloss finish', surcharge: 3000 },
      ] },
    ],
  };
}

test('a selected value whose label differs is priced, not sent to manual quote', () => {
  assert.deepEqual(priceOrder(finishProduct(), { finish: 'matte' }), { manual: false, total: 12000 });
});

test('two options, both value != label, add both surcharges', () => {
  const product = finishProduct();
  product.options.push({ name: 'corners', choices: [
    { value: 'square', label: 'Square corners', surcharge: 0 },
    { value: 'round', label: 'Rounded corners', surcharge: 500 },
  ] });
  assert.deepEqual(priceOrder(product, { finish: 'gloss', corners: 'round' }), { manual: false, total: 13500 });
});

test('the value is matched even when another choice has that text as its label', () => {
  const product = { base: 1000, options: [
    { name: 'size', choices: [
      { value: 's', label: 'm', surcharge: 100 },
      { value: 'm', label: 'l', surcharge: 200 },
    ] },
  ] };
  assert.deepEqual(priceOrder(product, { size: 'm' }), { manual: false, total: 1200 });
});

test('a label sent in place of a value is not a known choice', () => {
  assert.deepEqual(priceOrder(finishProduct(), { finish: 'Matte finish' }), { manual: true, total: null });
});
