#!/usr/bin/env bash
# Builds the task repo in $1: product links built from a slug of the product name (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > README.md <<'PB_TASK_EOF'
# shop-links

Builds the public links of a small web shop.

- `src/slug.js` turns a product name into the slug used in its link.
- `src/links.js` builds the links themselves.

The URL rules are in `docs/urls.md`. Run the tests with `npm test`.
PB_TASK_EOF

cat > docs/urls.md <<'PB_TASK_EOF'
# Public URLs

A product page lives at `/p/<slug>`, where the slug comes from the product name.

## Slug rule

- A slug holds only lowercase ASCII letters `a-z`, digits `0-9` and hyphens `-`.
- Upper case becomes lower case.
- A letter with an accent or another mark loses the mark (`é` becomes `e`, `ơ` becomes `o`); `đ` becomes `d`.
- Any other character (spaces, punctuation, symbols) only separates words: each run of such characters becomes one
  hyphen, so a slug never holds two hyphens in a row.
- A slug never starts or ends with a hyphen.
- A name without any letter or digit gives the empty slug.

Old links are never redirected, so a product keeps the slug it got when it was created.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-links",
  "version": "1.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > src/slug.js <<'PB_TASK_EOF'
'use strict';

// The slug of a product name, used in its public link (rule: docs/urls.md).
function slugify(name) {
  return encodeURIComponent(String(name).trim().toLowerCase());
}

module.exports = { slugify };
PB_TASK_EOF

cat > src/links.js <<'PB_TASK_EOF'
'use strict';

const { slugify } = require('./slug');

// Path of a product page.
function productPath(product) {
  return `/p/${slugify(product.name)}`;
}

// Path of a category listing, page 1 when no page is given.
function categoryPath(category, page) {
  return page && page > 1 ? `/c/${category.code}?page=${page}` : `/c/${category.code}`;
}

module.exports = { productPath, categoryPath };
PB_TASK_EOF

cat > tests/links.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { productPath, categoryPath } = require('../src/links');

test('a one-word product name', () => {
  assert.equal(productPath({ name: 'Notebook' }), '/p/notebook');
});

test('category pages', () => {
  assert.equal(categoryPath({ code: 'paper' }), '/c/paper');
  assert.equal(categoryPath({ code: 'paper' }, 3), '/c/paper?page=3');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-04-02T10:30:00Z' GIT_COMMITTER_DATE='2026-04-02T10:30:00Z' git commit -q -m "Product and category links"
