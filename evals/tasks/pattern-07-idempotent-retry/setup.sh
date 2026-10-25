#!/usr/bin/env bash
# Builds the task repo in $1: a payment webhook handler (offline, fixed author and date). Refuses an existing non-empty $1.
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
  "name": "wallet-webhooks",
  "version": "0.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# wallet-webhooks

Receives payment webhooks from the payment provider and credits customer wallets.

An event is `{ id, account, amount }`; `id` is the provider's event id. `createStore()` makes the wallet store
(`store.balance[account]` holds the balance) and `handlePayment(store, event)` applies one delivered event.
EOF

cat > src/webhook.js <<'EOF'
'use strict';

// The wallet store: balance per account.
function createStore() {
  return { balance: {} };
}

// Applies one payment event delivered by the provider's webhook: credits event.amount to event.account.
function handlePayment(store, event) {
  if (!event || !event.id) throw new Error('payment event without id');
  store.balance[event.account] = (store.balance[event.account] || 0) + event.amount;
}

module.exports = { createStore, handlePayment };
EOF

cat > tests/webhook.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createStore, handlePayment } = require('../src/webhook');

test('a payment credits the account', () => {
  const store = createStore();
  handlePayment(store, { id: 'evt_9', account: 'acc_z', amount: 25 });
  assert.equal(store.balance.acc_z, 25);
});

test('payments to different accounts stay apart', () => {
  const store = createStore();
  handlePayment(store, { id: 'evt_1', account: 'acc_x', amount: 5 });
  handlePayment(store, { id: 'evt_2', account: 'acc_y', amount: 7 });
  assert.deepEqual(store.balance, { acc_x: 5, acc_y: 7 });
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-11T09:00:00Z' GIT_COMMITTER_DATE='2026-01-11T09:00:00Z' git commit -q -m "Credit wallets from payment webhooks"
