// PB-HIDDEN-CANARY:oss-05-slug-separators
// Hidden PASS_TO_PASS test: names that already give a valid slug keep it, and the other links are unchanged.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { slugify } = require(path.join(__dirname, '..', 'src', 'slug.js'));
const { productPath, categoryPath } = require(path.join(__dirname, '..', 'src', 'links.js'));

test('one word, upper case lowered', () => {
  assert.equal(slugify('Notebook'), 'notebook');
  assert.equal(slugify('PENCILS'), 'pencils');
});

test('digits and existing single hyphens stay', () => {
  assert.equal(slugify('2026'), '2026');
  assert.equal(slugify('t-shirt'), 't-shirt');
});

test('surrounding spaces are dropped', () => {
  assert.equal(slugify('  Stapler '), 'stapler');
});

test('links', () => {
  assert.equal(productPath({ name: 'Notebook' }), '/p/notebook');
  assert.equal(categoryPath({ code: 'paper' }, 2), '/c/paper?page=2');
});
