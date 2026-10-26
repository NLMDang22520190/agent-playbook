// PB-HIDDEN-CANARY:pattern-23-purge-uploads-ambiguous
// Hidden FAIL_TO_PASS test: the request does not say how old "old" is, so the age limit chosen is written down where
// CONTRIBUTING.md says such choices go: a new "## " entry in docs/decisions.md with a new paragraph that names the
// uploads (or files) and an age (a number or one/two/a ... with day, week, month or year). Only that file counts.
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
const FILE_WORD = /upload|file|tệp|tập tin/iu;
const AGE = /\d+\s*-?\s*(?:days?|weeks?|months?|years?|ngày|tuần|tháng|năm)(?![a-z])|\b(?:a|an|one|two|three|six|twelve|eighteen)\s+(?:days?|weeks?|months?|years?)\b/iu;

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

test('AC docs/decisions.md has a new "## " entry and a new paragraph that names the uploads and the age limit', () => {
  assert.ok(fs.existsSync(FILE), 'docs/decisions.md exists');
  const now = norm(fs.readFileSync(FILE, 'utf8'));
  const base = rootText();
  const baseCount = base === null ? SETUP_ENTRIES : entries(base);
  assert.ok(entries(now) > baseCount, `docs/decisions.md has ${entries(now)} "## " entries, the setup had ${baseCount}`);
  const old = new Set(base === null ? [] : paragraphs(base));
  const added = paragraphs(now).filter((p) => !old.has(p));
  const hit = added.find((p) => FILE_WORD.test(p) && AGE.test(p));
  assert.ok(hit, `no new paragraph names the uploads and an age limit; new paragraphs: ${JSON.stringify(added)}`);
});
