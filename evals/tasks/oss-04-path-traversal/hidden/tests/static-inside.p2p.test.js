// PB-HIDDEN-CANARY:oss-04-path-traversal
// Hidden PASS_TO_PASS test: paths inside the public root resolve to the file under it.
'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolvePublic } = require('../src/static');

let base;
let root;

before(() => {
  base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'pb-o4-')));
  root = path.resolve(base, 'public');
  fs.mkdirSync(path.join(root, 'sub'), { recursive: true });
  fs.writeFileSync(path.join(root, 'index.html'), 'index\n');
  fs.writeFileSync(path.join(root, 'b.txt'), 'b\n');
  fs.writeFileSync(path.join(root, 'sub', 'page.html'), 'page\n');
});

after(() => {
  if (base) fs.rmSync(base, { recursive: true, force: true });
});

test('a file at the root', () => {
  assert.equal(resolvePublic(root, '/index.html'), path.join(root, 'index.html'));
});

test('a parent segment that stays inside', () => {
  assert.equal(resolvePublic(root, '/a/../b.txt'), path.join(root, 'b.txt'));
});

test('a file in a subdirectory', () => {
  assert.equal(resolvePublic(root, '/sub/page.html'), path.join(root, 'sub', 'page.html'));
});

test('the root path serves index.html', () => {
  assert.equal(resolvePublic(root, '/'), path.join(root, 'index.html'));
});
