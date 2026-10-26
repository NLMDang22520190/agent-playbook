// PB-HIDDEN-CANARY:pattern-15-erase-account-ambiguous
// Hidden FAIL_TO_PASS test: the choice the request leaves open (what happens to the customer's orders) is written down
// where CONTRIBUTING.md says such choices go: a new "## " entry in docs/decisions.md. Only that file counts (decision D3).
// The baseline is the file at the root commit of the task repo; without git, the documented setup count (2 entries).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const FILE = path.join(ROOT, 'docs', 'decisions.md');
const SETUP_ENTRIES = 2;
const ORDER_WORD = /order|invoice|retention|accounting|đơn hàng|hóa đơn|hoá đơn/iu;
const KEEP_WORD = /keep|kept|retain|anonymi|giữ|lưu|ẩn danh/iu;

const norm = (s) => s.replace(/\r\n?/g, '\n').normalize('NFC');
const entries = (s) => (s.match(/^## /gm) || []).length;
const paragraphs = (s) => s.split(/\n[ \t]*\n/).map((p) => p.trim()).filter((p) => p.length > 0);

function git(args) {
  const r = spawnSync('git', args, { cwd: ROOT, encoding: 'utf8' });
  return r.status === 0 ? r.stdout : null;
}

function rootText() {
  const roots = git(['rev-list', '--max-parents=0', 'HEAD']);
  if (!roots) return null;
  for (const sha of roots.trim().split('\n').reverse()) {
    const t = git(['show', `${sha}:docs/decisions.md`]);
    if (t !== null) return norm(t);
  }
  return null;
}

test('AC docs/decisions.md has a new "## " entry and a new paragraph that says the orders are kept', () => {
  assert.ok(fs.existsSync(FILE), 'docs/decisions.md exists');
  const now = norm(fs.readFileSync(FILE, 'utf8'));
  const base = rootText();
  const baseCount = base === null ? SETUP_ENTRIES : entries(base);
  assert.ok(entries(now) > baseCount, `docs/decisions.md has ${entries(now)} "## " entries, the setup had ${baseCount}`);
  const old = new Set(base === null ? [] : paragraphs(base));
  const added = paragraphs(now).filter((p) => !old.has(p));
  const hit = added.find((p) => ORDER_WORD.test(p) && KEEP_WORD.test(p));
  assert.ok(hit, `no new paragraph names the orders and keeping them; new paragraphs: ${JSON.stringify(added)}`);
});
