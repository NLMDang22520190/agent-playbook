#!/usr/bin/env bash
# Builds the task repo in $1: a box-size parser (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src tests

cat > package.json <<'EOF'
{
  "name": "box-quote",
  "version": "0.9.2",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# box-quote

Quotes custom printed boxes. Customers type the box size (length x width x height, in mm) into one free-text field;
`parseDims(text)` turns it into `{ l, w, h }` (numbers) or `null` when the text is not a valid size. Every size must be
greater than 0.
EOF

cat > src/dims.js <<'EOF'
'use strict';

const SIZE = /^\d+(\.\d+)?$/;

// Parses a box size typed by the customer, e.g. "150x100x50" (mm), into { l, w, h }.
// Returns null when the text is not three sizes greater than 0.
function parseDims(text) {
  const parts = String(text).split('x');
  if (parts.length !== 3) return null;
  if (!parts.every((p) => SIZE.test(p))) return null;
  const [l, w, h] = parts.map(Number);
  if (l <= 0 || w <= 0 || h <= 0) return null;
  return { l, w, h };
}

module.exports = { parseDims };
EOF

cat > tests/dims.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseDims } = require('../src/dims');

test('parses length x width x height', () => {
  assert.deepEqual(parseDims('200x120x80'), { l: 200, w: 120, h: 80 });
});

test('rejects text that is not a size', () => {
  assert.equal(parseDims('big box'), null);
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-06T09:00:00Z' GIT_COMMITTER_DATE='2026-01-06T09:00:00Z' git commit -q -m "Parse box sizes from the quote form"
