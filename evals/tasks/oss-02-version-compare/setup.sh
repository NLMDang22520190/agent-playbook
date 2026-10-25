#!/usr/bin/env bash
# Builds the task repo in $1: a version comparison helper (offline, fixed author and date). Refuses an existing non-empty $1.
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
  "name": "tiny-semver",
  "version": "0.2.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# tiny-semver

`compare(a, b)` compares two versions of the form MAJOR.MINOR.PATCH (three non-negative integers) and returns -1 when
`a` is older than `b`, 0 when they are equal and 1 when `a` is newer. Used to decide whether an update is available.
EOF

cat > src/semver.js <<'EOF'
'use strict';

// Compares two MAJOR.MINOR.PATCH versions: -1 when a is older than b, 0 when equal, 1 when a is newer.
function compare(a, b) {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

module.exports = { compare };
EOF

cat > tests/semver.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { compare } = require('../src/semver');

test('a newer minor version', () => {
  assert.equal(compare('1.3.0', '1.2.0'), 1);
});

test('an older major version', () => {
  assert.equal(compare('1.0.0', '2.0.0'), -1);
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-15T09:00:00Z' GIT_COMMITTER_DATE='2026-01-15T09:00:00Z' git commit -q -m "Version comparison"
