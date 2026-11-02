#!/usr/bin/env bash
# Lane k1a (v0.28.0) scripts/guard-irreversible.sh, PreToolUse mode where the repo state decides:
# A-S4 git-discard family (AC-A5), A-S6 Write/Edit pending and migration runners (AC-A7, AC-A8).
# Each case runs in its own throwaway repo under the suite's temp dirs; the guard only reads them (git status), the test never
# runs the discard commands it shows to the guard.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

# fresh -> a new repo in R (mk_repo layout), the guard starts there
fresh() { R="$(mk_tmp)/repo"; mk_repo "$R" >/dev/null; GRUNDIR="$R"; }
# gb CMD [ENV...] -> the guard on a Bash call in R, headless unless ENV says otherwise
gb() { local c="$1"; shift; grun PB_HEADLESS=1 "$@" -- "$(jbash "$c" "$R")"; }

echo "A-S4 AC-A5 git discard: nothing to lose -> PASS"
fresh
for c in 'git reset --hard' 'git reset --hard HEAD~0' 'git checkout -- .' 'git checkout .' 'git restore src/app.js' 'git clean -fd' 'git clean -fdx'; do
  gb "$c"; expect_pass "AC-A5 clean tree [$c]"
done
printf 'scratch\n' > "$R/notes.txt"
for c in 'git reset --hard' 'git checkout -- src/app.js' 'git restore .'; do
  gb "$c"; expect_pass "AC-A5 only an untracked file, tracked-only discard [$c]"
done
gb 'git clean -n'; expect_pass "AC-A5 git clean -n (dry run, no -f) with an untracked file"

echo "A-S4 AC-A5 git discard: tracked changes would be lost -> git-discard"
fresh
printf 'module.exports = 2;\n' > "$R/src/app.js"
for c in 'git reset --hard' 'git reset --hard HEAD' 'git checkout -- src/app.js' 'git checkout .' 'git checkout -- .' \
  'git restore src/app.js' 'git restore .' 'git -C . reset --hard' 'git stash list && git reset --hard origin/main'; do
  gb "$c"; expect_block "AC-A5 unstaged change [$c]" git-discard
done
gb 'git reset --hard'
assert_contains "AC-A5 the message suggests git stash -u first" "$GERR" "git stash -u"
gb 'git restore --staged src/app.js'; expect_pass "AC-A5 git restore --staged keeps the work tree"
gb 'git reset --soft HEAD'; expect_pass "AC-A5 git reset --soft"
gb 'git checkout -b feature'; expect_pass "AC-A5 git checkout -b (no paths)"
gb 'git reset --hard' PB_HEADLESS=0
expect_warn "AC-A5 interactive: reset --hard with changes only warns"
fresh
printf 'module.exports = 3;\n' > "$R/src/app.js"
git -C "$R" add src/app.js
gb 'git reset --hard'; expect_block "AC-A5 a staged change is lost by reset --hard" git-discard

echo "A-S4 AC-A5 git clean: untracked and ignored entries"
fresh
printf 'tmp\n' > "$R/scratch.txt"
for c in 'git clean -fd' 'git clean -f' 'git clean -df' 'git clean -ffdx'; do
  gb "$c"; expect_block "AC-A5 untracked file [$c]" git-discard
done
fresh
printf '*.log\n' > "$R/.gitignore"
fxg "$R" add .gitignore && fxg "$R" commit -qm ignore
printf 'log\n' > "$R/debug.log"
gb 'git clean -fd'; expect_pass "AC-A5 only an ignored file: git clean -fd keeps it"
gb 'git clean -fdx'; expect_block "AC-A5 only an ignored file: git clean -fdx loses it (--ignored probe)" git-discard
gb 'git clean -fX'; expect_block "AC-A5 only an ignored file: git clean -fX loses it" git-discard

echo "A-S6 AC-A8 Write/Edit of contract SQL -> PENDING (both modes)"
fresh
P_CHECK() { # NAME : PENDING = exit 0, JSON with the pending text, no permissionDecision, nothing on stderr
  local low; low="$(printf '%s' "$GOUT" | tr 'A-Z' 'a-z')"
  if [ "$RC" = 0 ] && [ -z "$GERR" ] && has "$GOUTN" '"hookEventName":"PreToolUse"' && has "$GOUTN" '"additionalContext":"agent-playbook guard: ' &&
    has "$low" pending && has "$low" "not run" && ! has "$GOUT" permissionDecision; then t_ok "$1 (PENDING)"; else t_bad "$1 (PENDING)" "rc=$RC $OUT"; fi
}
grun PB_HEADLESS=1 -- "$(jwrite "$R/db/migrations/003_drop_legacy.sql" 'DROP TABLE legacy_orders;' "$R")"
P_CHECK "AC-A8 headless Write of a DROP TABLE migration"
grun PB_HEADLESS=0 -- "$(jwrite "$R/db/migrations/003_drop_legacy.sql" 'DROP TABLE legacy_orders;' "$R")"
P_CHECK "AC-A8 interactive Write of a DROP TABLE migration"
grun PB_HEADLESS=1 -- "$(jwrite "$R/db/cleanup.sql" 'TRUNCATE orders;' "$R")"
P_CHECK "AC-A8 Write of TRUNCATE in a .sql file outside migrations"
grun PB_HEADLESS=1 -- "$(jwrite "$R/src/migrations/0004.ts" 'await db.raw("ALTER TABLE users DROP COLUMN age");' "$R")"
P_CHECK "AC-A8 Write under a migrations path, not .sql"
grun PB_HEADLESS=1 -- "$(jedit "$R/db/migrations/005.sql" '-- todo' 'ALTER TABLE orders DROP COLUMN total_cents;' "$R")"
P_CHECK "AC-A8 Edit whose new_string drops a column"
grun PB_HEADLESS=1 -- "$(jwrite 'C:\proj\db\migrations\006_drop.sql' 'drop database shop;' 'C:\proj')"
P_CHECK "AC-A8 Windows file_path with backslashes, lower-case SQL"
grun PB_HEADLESS=1 -- "$(jwrite "$R/db/migrations/007_add.sql" 'CREATE TABLE audit (id INTEGER);' "$R")"
expect_pass "AC-A8 an additive migration"
grun PB_HEADLESS=1 -- "$(jwrite "$R/src/repo.js" 'const q = "DROP TABLE x"; module.exports = q;' "$R")"
expect_warn "AC-A8 (superseded by R2-1, fix round R2) contract text in a .js file outside migrations now warns (code-contract)"
grun PB_HEADLESS=1 -- "$(jwrite "$R/README.md" 'Never DROP TABLE in production.' "$R")"
expect_warn "AC-A8 (superseded by R2-1 and D11, fix round R2) contract text in README.md outside .agents/ now warns (code-contract)"
grun PB_HEADLESS=1 -- "$(jedit "$R/db/schema.sql" 'CREATE TABLE legacy_orders (id INTEGER);' '' "$R")"
expect_pass "AC-A8 Edit removing a CREATE TABLE from the schema (judged by the Stop check)"
grun PB_HEADLESS=1 -- "$(jedit "$R/db/migrations/008.sql" 'DROP TABLE x;' '-- removed' "$R")"
expect_pass "AC-A8 Edit whose old_string (not new_string) holds the DROP"

echo "A-S6 AC-A7 migration runners"
mig_repo() { # a repo whose work tree holds an untracked contract migration (new since any baseline)
  fresh; mkdir -p "$R/db/migrations"; printf -- '-- 002\nDROP TABLE legacy_orders;\n' > "$R/db/migrations/002_drop_legacy.sql"
}
mig_repo
for c in 'npm run migrate' 'npm run db:migrate' 'pnpm run migrate:up' 'yarn run migrations' 'bun run migrate' 'npx knex migrate:latest' \
  'knex migrate:up' 'npx prisma migrate deploy' 'npx prisma migrate dev' 'rails db:migrate' 'bundle exec rake db:migrate' \
  'alembic upgrade head' 'flyway migrate' 'goose up' 'dbmate up' 'npx sequelize db:migrate' 'npx typeorm migration:run' \
  'wrangler d1 migrations apply shop' 'supabase db push' 'npm test && npm run migrate'; do
  gb "$c"; expect_block "AC-A7 untracked contract migration + [$c]" migration-run
done
for c in 'npm run build' 'npm test' 'git status' 'npm run lint'; do
  gb "$c"; expect_pass "AC-A7 untracked contract migration + a non-runner [$c]"
done
gb 'npm run migrate' PB_HEADLESS=0
expect_warn "AC-A7 interactive: running the migration only warns"
fresh; mkdir -p "$R/db/migrations"; printf 'CREATE TABLE audit (id INTEGER);\n' > "$R/db/migrations/003_add.sql"
gb 'npm run migrate'; expect_pass "AC-A7 an additive migration may run"
fresh
gb 'npm run migrate'; expect_pass "AC-A7 no migration files at all"
fresh; mkdir -p "$R/db/Migrations"; printf 'TRUNCATE sessions;\n' > "$R/db/Migrations/004.sql"
gb 'npx knex migrate:latest'; expect_block "AC-A7 a Migrations path in another case, TRUNCATE" migration-run
fresh; mkdir -p "$R/migrations/versions"; printf 'def upgrade():\n    op.execute("ALTER TABLE users DROP COLUMN age")\n' > "$R/migrations/versions/0005.py"
gb 'alembic upgrade head'; expect_block "AC-A7 a Python migration with ALTER TABLE ... DROP" migration-run
# a tracked file changed (unstaged / staged) counts too
fresh; mkdir -p "$R/db/migrations"; printf -- '-- 001\nCREATE TABLE t (id INTEGER);\n' > "$R/db/migrations/001.sql"
fxg "$R" add -A && fxg "$R" commit -qm mig
printf 'DROP TABLE t;\n' >> "$R/db/migrations/001.sql"
gb 'npm run migrate'; expect_block "AC-A7 an unstaged change adds a DROP to a tracked migration" migration-run
git -C "$R" add -A
gb 'npm run migrate'; expect_block "AC-A7 a staged change adds a DROP to a tracked migration" migration-run
# against the session baseline (AC-A10): a contract migration committed before the session is old; one committed after it is new
fresh; mkdir -p "$R/db/migrations"; printf 'DROP TABLE old_cache;\n' > "$R/db/migrations/001_drop_cache.sql"
fxg "$R" add -A && fxg "$R" commit -qm "old contract migration"
grun PB_HEADLESS=1 -- "$(jstart "$R" sm1)" --session-start
grun PB_HEADLESS=1 -- "$(jbash 'npm run migrate' "$R" sm1)"
expect_pass "AC-A7 a contract migration committed before the session baseline may run"
printf 'DROP TABLE legacy_orders;\n' > "$R/db/migrations/002_drop_legacy.sql"
fxg "$R" add -A && fxg "$R" commit -qm "new contract migration"
grun PB_HEADLESS=1 -- "$(jbash 'npm run migrate' "$R" sm1)"
expect_block "AC-A7 a contract migration committed after the session baseline" migration-run

echo "A-S6 AC-A7 always-irreversible database commands (no migration files needed)"
fresh
for c in 'npx prisma migrate reset' 'npx prisma migrate reset --force' 'npx prisma db push --accept-data-loss' 'rails db:drop' \
  'rake db:reset' 'bin/rails db:reset' 'dropdb shop'; do
  gb "$c"; expect_block "AC-A7 [$c]" migration-run
done
gb 'npx prisma db push'; expect_pass "AC-A7 prisma db push without --accept-data-loss"
gb 'npx prisma generate'; expect_pass "AC-A7 prisma generate"

t_summary
