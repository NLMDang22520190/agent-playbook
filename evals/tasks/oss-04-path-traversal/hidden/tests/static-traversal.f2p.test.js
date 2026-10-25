// PB-HIDDEN-CANARY:oss-04-path-traversal
// Hidden FAIL_TO_PASS test: any URL path that leaves the public root, plain or URL-encoded, resolves to null.
// Expected paths are built with path.join on a resolved temp root (spec "Test-portability rules": node uses win32 path on Git Bash).
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
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'index.html'), 'index\n');
  fs.writeFileSync(path.join(base, 'secret.txt'), 'secret\n');
  fs.mkdirSync(path.join(base, path.basename(root) + '2'));
  fs.writeFileSync(path.join(base, path.basename(root) + '2', 'x'), 'x\n');
});

after(() => {
  if (base) fs.rmSync(base, { recursive: true, force: true });
});

test('a parent segment leaves the root', () => {
  assert.equal(resolvePublic(root, '/../secret.txt'), null);
});

test('URL-encoded dots leave the root', () => {
  assert.equal(resolvePublic(root, '/%2e%2e/secret.txt'), null);
});

test('upper-case URL-encoded dots leave the root', () => {
  assert.equal(resolvePublic(root, '/%2E%2E/secret.txt'), null);
});

test('an encoded slash after encoded dots leaves the root', () => {
  assert.equal(resolvePublic(root, '/%2e%2e%2fsecret.txt'), null);
});

test('a nested parent segment leaves the root', () => {
  assert.equal(resolvePublic(root, '/a/../../secret.txt'), null);
});

test('a sibling directory whose name starts with the root name is outside', () => {
  assert.equal(resolvePublic(root, '/../' + path.basename(root) + '2/x'), null);
});
