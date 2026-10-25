#!/usr/bin/env bash
# Builds the task repo in $1: order message views (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src/views tests docs

cat > package.json <<'EOF'
{
  "name": "order-messages",
  "version": "2.1.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > docs/ui.md <<'EOF'
# Message display

Orders carry a message thread: `{ author: { name } | null, text }`.

- A message from a person shows as `Name: text`, e.g. `Alice: hi`.
- A system message (author `null`, e.g. status updates written by the shop software) shows as the text in italics,
  written `_text_`, e.g. `_Order shipped_`.

Two screens show order messages: the order detail page (`src/views/orderDetail.js`) and the inbox preview
(`src/views/inbox.js`). Both follow these rules.
EOF

cat > src/views/orderDetail.js <<'EOF'
'use strict';

// Lines of the message thread on the order detail page (docs/ui.md).
function renderOrderMessages(messages) {
  return messages.map((m) => {
    const name = m.author ? m.author.name : '';
    return name ? `${name}: ${m.text}` : '';
  });
}

module.exports = { renderOrderMessages };
EOF

cat > src/views/inbox.js <<'EOF'
'use strict';

// Lines of the inbox preview of one order (docs/ui.md).
function renderInboxPreview(messages) {
  const lines = [];
  for (const m of messages) {
    lines.push(m.author ? m.author.name + ': ' + m.text : '');
  }
  return lines;
}

module.exports = { renderInboxPreview };
EOF

cat > tests/order-detail.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { renderOrderMessages } = require('../src/views/orderDetail');

test('order detail shows who wrote each message', () => {
  assert.deepEqual(
    renderOrderMessages([{ author: { name: 'Bob' }, text: 'is it ready?' }, { author: { name: 'Shop' }, text: 'yes' }]),
    ['Bob: is it ready?', 'Shop: yes'],
  );
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-07T09:00:00Z' GIT_COMMITTER_DATE='2026-01-07T09:00:00Z' git commit -q -m "Order detail and inbox message views"
