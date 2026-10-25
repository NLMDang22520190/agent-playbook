#!/usr/bin/env bash
# Builds the task repo in $1: static file path resolution (offline, fixed author and date). Refuses an existing non-empty $1.
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
  "name": "mini-static",
  "version": "0.3.1",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# mini-static

A tiny static file server. `resolvePublic(root, urlPath)` maps the path of a request URL to the file to serve under the
public root directory (an absolute path); `/` serves `index.html`. It returns `null` when the request must be refused.
The HTTP layer answers 404 for `null`.
EOF

cat > src/static.js <<'EOF'
'use strict';
const path = require('path');

// Maps a request URL path (e.g. '/css/site.css', still URL-encoded) to a file under the public root.
// Returns the absolute file path, or null when the request must be refused.
function resolvePublic(root, urlPath) {
  const full = path.join(root, urlPath === '/' ? 'index.html' : urlPath);
  if (!full.startsWith(root)) return null;
  return decodeURIComponent(full);
}

module.exports = { resolvePublic };
EOF

cat > tests/static.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { resolvePublic } = require('../src/static');

const root = path.resolve('www');

test('a file under the root', () => {
  assert.equal(resolvePublic(root, '/css/site.css'), path.join(root, 'css', 'site.css'));
});

test('an encoded space in a file name', () => {
  assert.equal(resolvePublic(root, '/my%20page.html'), path.join(root, 'my page.html'));
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-17T09:00:00Z' GIT_COMMITTER_DATE='2026-01-17T09:00:00Z' git commit -q -m "Resolve static file paths"
