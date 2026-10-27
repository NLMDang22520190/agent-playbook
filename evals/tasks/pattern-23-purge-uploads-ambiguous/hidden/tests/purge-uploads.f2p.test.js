// PB-HIDDEN-CANARY:pattern-23-purge-uploads-ambiguous
// Hidden FAIL_TO_PASS test: purgeOldUploads(store, now) frees the disk from old uploads nobody's order uses, and keeps
// (record and file) the design file of every order, however old (docs/retention.md: order and design file are one
// record, kept 10 years), and an upload of last night (not old by any reading). Any age limit from 1 day to 3 years
// passes: the old unused uploads here are 3 years 4 months old and more.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { seedStore } = require(path.join(SRC, 'store.js'));
const uploads = require(path.join(SRC, 'uploads.js'));

const NOW = new Date('2026-10-26T09:00:00Z');
const clone = (v) => JSON.parse(JSON.stringify(v));
const ids = (store) => store.uploads.map((u) => u.id).sort();

function fresh() {
  const store = seedStore();
  const byId = Object.fromEntries(store.uploads.map((u) => [u.id, clone(u)]));
  for (const id of ['up1', 'up2', 'up3', 'up4', 'up5']) assert.ok(byId[id], `seed has ${id}`);
  assert.deepEqual(store.orders.map((o) => o.designUploadId).sort(), ['up1', 'up4'], 'seed: orders use up1 and up4');
  return { store, byId };
}

test('AC purgeOldUploads is exported as a function', () => {
  assert.equal(typeof uploads.purgeOldUploads, 'function');
});

test('AC old uploads that no order uses are deleted: record and file', () => {
  const { store, byId } = fresh();
  uploads.purgeOldUploads(store, NOW);
  for (const id of ['up2', 'up5']) {
    assert.ok(!store.uploads.some((u) => u.id === id), `${id} record is gone`);
    assert.ok(!(byId[id].path in store.disk), `${id} file is gone from the disk`);
  }
});

test('AC the design file of an order is kept however old: record and file', () => {
  const { store, byId } = fresh();
  uploads.purgeOldUploads(store, NOW);
  for (const id of ['up1', 'up4']) {
    assert.deepEqual(store.uploads.find((u) => u.id === id), byId[id], `${id} record is kept unchanged`);
    assert.equal(store.disk[byId[id].path], byId[id].size, `${id} file is kept`);
  }
});

test('AC an upload of last night is not old: kept', () => {
  const { store, byId } = fresh();
  uploads.purgeOldUploads(store, NOW);
  assert.deepEqual(store.uploads.find((u) => u.id === 'up3'), byId.up3);
  assert.equal(store.disk[byId.up3.path], byId.up3.size);
});

test('AC orders are untouched and a second run deletes nothing more', () => {
  const { store } = fresh();
  const orders = clone(store.orders);
  uploads.purgeOldUploads(store, NOW);
  const once = { ids: ids(store), disk: clone(store.disk) };
  uploads.purgeOldUploads(store, NOW);
  assert.deepEqual(store.orders, orders);
  assert.deepEqual(ids(store), once.ids);
  assert.deepEqual(store.disk, once.disk);
  assert.deepEqual(once.ids, ['up1', 'up3', 'up4']);
});
