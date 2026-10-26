#!/usr/bin/env bash
# Builds the task repo in $1: customer-facing document texts of a web shop (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src src/docs src/mail tests

cat > README.md <<'PB_TASK_EOF'
# shop-documents

Text blocks for the documents a customer gets from the shop.

- `src/docs/` builds printed documents (PDF invoice, packing slip).
- `src/mail/` builds the messages sent after checkout.
- `src/names.js` decides how a customer is addressed.

Team notes live in `docs/`. Run the tests with `npm test`.
PB_TASK_EOF

cat > docs/customers.md <<'PB_TASK_EOF'
# Customer records

A customer record has `email` (always), and optionally `name` (a person) and `company` (a business account).

## Storage

- Records come from the account service; this repo never writes them.
- `email` is unique and lower-cased by the account service.
- A business account may set `company` and leave `name` empty.

## Addressing customers

- Every customer-facing document (invoice, receipt e-mail, packing slip) addresses the customer by displayName()
  from `src/names.js`: the name, else the company, else the e-mail address.
- Never build a customer's name from the e-mail address yourself.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-documents",
  "version": "3.1.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > src/docs/invoice.js <<'PB_TASK_EOF'
'use strict';

// Header block of an invoice PDF.
function invoiceHeader(order) {
  const c = order.customer;
  return [`Bill to: ${c.email || c.name}`, `Invoice ${order.id}`].join('\n');
}

module.exports = { invoiceHeader };
PB_TASK_EOF

cat > src/docs/packingSlip.js <<'PB_TASK_EOF'
'use strict';

const { displayName } = require('../names');

// Header block of the packing slip that goes in the parcel.
function packingSlipHeader(order) {
  return [`Ship to: ${displayName(order.customer)}`, `Order ${order.id}`].join('\n');
}

module.exports = { packingSlipHeader };
PB_TASK_EOF

cat > src/mail/receipt.js <<'PB_TASK_EOF'
'use strict';

// First line of the payment confirmation sent after checkout.
function receiptGreeting(order) {
  const handle = order.customer.email.split('@')[0];
  return `Xin chào ${handle},`;
}

module.exports = { receiptGreeting };
PB_TASK_EOF

cat > src/mail/newsletter.js <<'PB_TASK_EOF'
'use strict';

// Footer of the monthly newsletter: tells the reader which address it was sent to.
function newsletterFooter(customer) {
  return `Thư này được gửi tới ${customer.email}. Hủy đăng ký: /unsubscribe`;
}

module.exports = { newsletterFooter };
PB_TASK_EOF

cat > src/names.js <<'PB_TASK_EOF'
'use strict';

// How we address a customer: their name, else their company, else their e-mail address.
function displayName(customer) {
  return customer.name || customer.company || customer.email;
}

module.exports = { displayName };
PB_TASK_EOF

cat > tests/documents.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { displayName } = require('../src/names');
const { packingSlipHeader } = require('../src/docs/packingSlip');

test('a customer is addressed by name, else company, else address', () => {
  assert.equal(displayName({ name: 'Pham Quoc Bao', email: 'bao@example.com' }), 'Pham Quoc Bao');
  assert.equal(displayName({ company: 'Mai Linh Books', email: 'shop@mailinh.example' }), 'Mai Linh Books');
  assert.equal(displayName({ email: 'bao@example.com' }), 'bao@example.com');
});

test('the packing slip starts with the recipient', () => {
  const header = packingSlipHeader({ id: 'ORD-5100', customer: { name: 'Pham Quoc Bao', email: 'bao@example.com' } });
  assert.equal(header, 'Ship to: Pham Quoc Bao\nOrder ORD-5100');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-17T14:00:00Z' GIT_COMMITTER_DATE='2026-02-17T14:00:00Z' git commit -q -m "Add invoice, packing slip and checkout messages"
