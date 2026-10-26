// PB-HIDDEN-CANARY:oss-05-slug-separators
// Hidden FAIL_TO_PASS test: every class of product name the slug rule of docs/urls.md covers (the prompt asks for
// "every product name, whatever characters it holds"): spaces, runs of separators, separators at either end, accents
// and marks, d-stroke, punctuation, and a name with no letter or digit.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { slugify } = require(path.join(__dirname, '..', 'src', 'slug.js'));
const { productPath } = require(path.join(__dirname, '..', 'src', 'links.js'));

test('spaces become hyphens (the reported name)', () => {
  assert.equal(slugify('Summer Sale 2026'), 'summer-sale-2026');
  assert.equal(productPath({ name: 'Summer Sale 2026' }), '/p/summer-sale-2026');
});

test('a run of separators becomes one hyphen', () => {
  assert.equal(slugify('Rock  &  Roll'), 'rock-roll');
  assert.equal(slugify('Pens, blue / black'), 'pens-blue-black');
});

test('no hyphen at either end', () => {
  assert.equal(slugify('  (New) Arrivals!  '), 'new-arrivals');
  assert.equal(slugify('--Clearance--'), 'clearance');
});

test('accents and other marks are dropped from the letter', () => {
  assert.equal(slugify('Crème Brûlée'), 'creme-brulee');
  assert.equal(slugify('Phở Bò Tái'), 'pho-bo-tai');
});

test('d-stroke becomes d, in both cases', () => {
  assert.equal(slugify('Đà Lạt Coffee'), 'da-lat-coffee');
  assert.equal(slugify('bánh đậu xanh'), 'banh-dau-xanh');
});

test('punctuation and symbols separate words', () => {
  assert.equal(slugify('tips_and_tricks'), 'tips-and-tricks');
  assert.equal(slugify('A4+A5 paper'), 'a4-a5-paper');
});

test('a name without a letter or digit gives the empty slug', () => {
  assert.equal(slugify('!!!'), '');
});
