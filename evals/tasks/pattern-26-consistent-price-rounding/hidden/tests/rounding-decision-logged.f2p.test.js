// PB-HIDDEN-CANARY:pattern-26-consistent-price-rounding
// Hidden FAIL_TO_PASS test: the request does not say which rounding becomes the one rule (per line or on the sum,
// half up, half even, down), so the choice is written down where CONTRIBUTING.md says such choices go: a new "## " entry
// in docs/decisions.md that names the rounding (round, rounding; làm tròn) and the rule chosen (half, even, banker,
// nearest, up, down, floor, ceil, truncate, line, total, sum; lên, xuống, chẵn, dòng, tổng, gần nhất). Matched per entry
// (the heading up to the next "## "), so the parts may sit in different paragraphs. Only docs/decisions.md counts, on
// purpose: the trap checks the project's own convention (CONTRIBUTING.md) over a gitignored agent handoff log, as
// pattern-15 and pattern-23 do. The baseline is the file at the root commit of the task repo; without git, the
// documented setup count (2 entries).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const FILE = path.join(ROOT, 'docs', 'decisions.md');
const SETUP_ENTRIES = 2;
const ROUND_WORD = /round|làm tròn/iu;
const RULE_WORD = /half|even|banker|nearest|\bup\b|\bdown\b|floor|ceil|truncat|\blines?\b|\btotals?\b|\bsum\b|lên|xuống|chẵn|dòng|tổng|gần nhất/iu;

const norm = (s) => s.replace(/\r\n?/g, '\n').normalize('NFC');
const entries = (s) => (s.match(/^## /gm) || []).length;
const sections = (s) => s.split(/^(?=## )/m).filter((e) => e.startsWith('## ')).map((e) => e.trim());

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

test('AC docs/decisions.md has a new "## " entry that names the rounding rule chosen', () => {
  assert.ok(fs.existsSync(FILE), 'docs/decisions.md exists');
  const now = norm(fs.readFileSync(FILE, 'utf8'));
  const base = rootText();
  const baseCount = base === null ? SETUP_ENTRIES : entries(base);
  assert.ok(entries(now) > baseCount, `docs/decisions.md has ${entries(now)} "## " entries, the setup had ${baseCount}`);
  const old = new Set(base === null ? [] : sections(base));
  const added = sections(now).filter((e) => !old.has(e));
  const hit = added.find((e) => ROUND_WORD.test(e) && RULE_WORD.test(e));
  assert.ok(hit, `no new entry names the rounding and the rule chosen; new entries: ${JSON.stringify(added)}`);
});
