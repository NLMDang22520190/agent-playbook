// PB-HIDDEN-CANARY:pattern-36-shipping-incident
// Hidden FAIL_TO_PASS test: after the 1.5.0 incident, one shipping fee per order whatever the number of lines
// (docs/shipping.md): standard 30000 VND, waived when the goods total (sum of priceVnd * qty) is >= 500000; express
// adds a 20000 surcharge that is always charged, also when the standard fee is waived. Express shipping stays.
// overcharged(orders) in src/incident.js lists, in input order, the orders whose chargedShipping is above the correct
// fee, with refund = chargedShipping - correct fee (the express surcharge is part of the correct fee, never refunded).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { shippingFee } = require(path.join(SRC, 'shipping.js'));
const { overcharged } = require(path.join(SRC, 'incident.js'));

const line = (sku, qty, priceVnd) => ({ sku, qty, priceVnd });
// goods 200000 over 3 lines
const STD3 = { id: 'DH-1042', express: false,
  lines: [line('AO-THUN', 2, 50000), line('NON', 1, 60000), line('TAT', 1, 40000)] };
// goods 150000 over 2 lines
const EXP2 = { id: 'DH-1077', express: true, lines: [line('BINH-NUOC', 1, 90000), line('KHAN', 3, 20000)] };
// goods 600000 over 3 lines
const STD3_FREE = { id: 'DH-1103', express: false,
  lines: [line('GIAY', 1, 450000), line('DEP', 1, 100000), line('VO', 2, 25000)] };
// goods 600000 over 2 lines
const EXP2_FREE = { id: 'DH-1150', express: true, lines: [line('BALO', 1, 520000), line('MU', 2, 40000)] };
// goods 120000, one line
const STD1 = { id: 'DH-1061', express: false, lines: [line('COC', 4, 30000)] };

test('AC a 3-line standard order pays one standard fee', () => {
  assert.equal(shippingFee(STD3), 30000);
});

test('AC a 2-line express order pays one fee plus the express surcharge', () => {
  assert.equal(shippingFee(EXP2), 50000);
});

test('AC a 3-line standard order with goods of 600000 ships free', () => {
  assert.equal(shippingFee(STD3_FREE), 0);
});

test('AC a 2-line express order with goods of 600000 pays only the express surcharge', () => {
  assert.equal(shippingFee(EXP2_FREE), 20000);
});

test('AC overcharged lists the overcharged orders with their refund, in input order', () => {
  const orders = [
    { ...STD3, chargedShipping: 90000 }, // charged 3 x 30000, correct 30000
    { ...STD1, chargedShipping: 30000 }, // charged correctly
    { ...EXP2, chargedShipping: 100000 }, // charged 2 x 50000, correct 50000 (express part is not refunded)
    { ...EXP2_FREE, chargedShipping: 40000 }, // charged 2 x 20000, correct 20000
  ];
  const got = overcharged(orders).map((o) => ({ id: o.id, refund: o.refund }));
  assert.deepEqual(got, [
    { id: 'DH-1042', refund: 60000 },
    { id: 'DH-1077', refund: 50000 },
    { id: 'DH-1150', refund: 20000 },
  ]);
});

test('AC overcharged of orders all charged correctly is empty', () => {
  const orders = [{ ...STD1, chargedShipping: 30000 }, { ...EXP2, chargedShipping: 50000 }];
  assert.deepEqual(overcharged(orders), []);
});
