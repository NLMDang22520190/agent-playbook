#!/usr/bin/env bash
# Lane k1a (v0.28.0) scripts/guard-irreversible.sh, PreToolUse mode on Bash commands without git state:
# A-S1 parse + headless + push-force + malformed (AC-A1, AC-A2, AC-A4, AC-A14), A-S2 rm resolution incl. variables, mktemp and
# Windows paths (AC-A6, AC-A9), A-S3 SQL clients incl. pipes, here-docs and .sql files (AC-A3).
# Hook input is the documented Claude Code PreToolUse JSON on stdin (https://code.claude.com/docs/en/hooks, fetched 2026-10-26).
# Bypass forms listed in the spec's Limits (bash -c, eval, $(...), interpreters, find -delete, xargs rm, ...) are documented in
# README by lane k1b and are deliberately not tested as blocked here.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

echo "A-S1 AC-A1 parsing: malformed or empty input, other tools, escapes"
grun PB_HEADLESS=1 -- '{"tool_name":"Bash","tool_input":{"command":"git push --force'
expect_pass "AC-A1 truncated JSON is PASS (fail-open)"
grun PB_HEADLESS=1 -- ''
expect_pass "AC-A1 empty stdin is PASS"
grun PB_HEADLESS=1 -- 'not json at all; git push --force origin main'
expect_pass "AC-A1 non-JSON text holding a force push is PASS"
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/pbguard-proj/app/db/drop.sql"},"tool_use_id":"t"}'
expect_pass "AC-A1 another tool (Read) is PASS"
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"x.ipynb","new_source":"!git push --force origin main"},"tool_use_id":"t"}'
expect_pass "AC-A1 NotebookEdit is not matched (listed in Limits)"
# a sample whose values differ from their labels: the description says force push, the command is harmless
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short","description":"git push --force origin main"},"tool_use_id":"t"}'
expect_pass "AC-A1 only tool_input.command is scanned, not the description"
# key order and spacing as another client may send them: tool_input first, spaces after colons
grun PB_HEADLESS=1 -- '{ "tool_input" : { "description" : "push", "command" : "git push --force origin main" }, "tool_name" : "Bash", "cwd" : "/pbguard-proj/app", "session_id" : "s9" }'
expect_block "AC-A1 keys in another order with spaces are parsed" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git -C \"..\" push -f origin main"},"tool_use_id":"t"}'
expect_block "AC-A1 an escaped quote is decoded" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf \/opt\/pbguard-data"},"tool_use_id":"t"}'
expect_block "AC-A1 an escaped slash is decoded (\\/opt\\/pbguard-data)" rm-outside
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo start\ngit push --force origin main"},"tool_use_id":"t"}'
expect_block "AC-A1 an escaped newline starts a new command line" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git\tpush\t--force\torigin main"},"tool_use_id":"t"}'
expect_block "AC-A1 an escaped tab separates words" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo done\r\ngit push --force origin main"},"tool_use_id":"t"}'
expect_block "AC-A1 an escaped CR LF line end is decoded" git-push-force
grun PB_HEADLESS=1 -- "$(jbash 'printf "%s\\n" "a\\b" && git push --force origin main')"
expect_block "AC-A1 escaped backslashes before the match are decoded" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"/pbguard-proj/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push \u002df origin main"},"tool_use_id":"t"}'
assert_rc "AC-A1 \\u escapes stay undecoded (a documented limit): exit 0" 0

echo "A-S1 AC-A2 headless vs interactive"
PUSH="$(jbash 'git -C .. push -f origin main')"
grun PB_HEADLESS=1 -- "$PUSH"
expect_block "AC-A2 PB_HEADLESS=1 blocks" git-push-force
grun PB_HEADLESS=1 CI=false -- "$PUSH"
expect_block "AC-A2 PB_HEADLESS=1 wins over CI=false" git-push-force
grun PB_HEADLESS=0 CI=true -- "$PUSH"
expect_warn "AC-A2 PB_HEADLESS=0 with CI=true only warns"
grun CI=true -- "$PUSH"
expect_block "AC-A2 PB_HEADLESS unset, CI=true is headless" git-push-force
grun CI=TRUE -- "$PUSH"
expect_block "AC-A2 PB_HEADLESS unset, CI=TRUE (any case) is headless" git-push-force
grun CI=1 -- "$PUSH"
expect_block "AC-A2 PB_HEADLESS unset, CI=1 is headless" git-push-force
grun -- "$PUSH"
expect_warn "AC-A2 PB_HEADLESS and CI unset: interactive, warn only"
grun CI=false -- "$PUSH"
expect_warn "AC-A2 CI=false is interactive"
grun PB_HEADLESS=0 -- "$PUSH"
assert_contains "AC-A2 the warning names the kind" "$GOUT" "git-push-force"

echo "A-S1 AC-A4 force pushes"
for c in 'git push --force origin main' 'git push -f' 'git push -uf origin main' 'git push -fu origin feature' \
  'git push --force-with-lease' 'git push --force-with-lease=main:abc123 origin main' 'git push --force-if-includes origin main' \
  'git push --mirror backup' 'git push origin +main' 'git push origin +HEAD:refs/heads/main' 'git push origin main +feature:feature' \
  'git -C .. push -f origin main' 'git -c push.default=current push --force' 'git --git-dir=/pbguard-proj/app/.git push -f origin main' \
  'cd sub && git push --force origin main' 'npm test; git push -f origin main' 'git status && git push origin --force'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "AC-A4 [$c]" git-push-force
done
for c in 'git push origin main' 'git push -u origin feature' 'git push --tags' 'git push --follow-tags origin main' \
  'git -C .. push origin main' 'git fetch -f origin' 'git pull --force' 'git commit -m "push -f later"' 'grep -rn "git push --force" docs'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_pass "AC-A4 [$c]"
done

echo "A-S1 AC-A14 the BLOCK message"
grun PB_HEADLESS=1 -- "$PUSH"
LOW="$(printf '%s' "$GERR" | tr 'A-Z' 'a-z')"
assert_contains "AC-A14 stderr names the kind" "$GERR" "git-push-force"
assert_contains "AC-A14 stderr quotes the matched text" "$GERR" "git -C .. push -f origin main"
assert_contains "AC-A14 stderr says the run is headless" "$LOW" "headless"
assert_contains "AC-A14 stderr says the action is left pending" "$LOW" "pending"
assert_contains "AC-A14 stderr says not to try another way" "$LOW" "another way"
assert_contains "AC-A14 stderr says to name it in the final reply" "$LOW" "final reply"
if [ "$RC" = 2 ] && [ -z "$GOUT" ]; then t_ok "AC-A14 exit 2 and nothing on stdout when blocking"; else t_bad "AC-A14 exit 2 and nothing on stdout when blocking" "rc=$RC $OUT"; fi
A171="$(printf '%171s' '' | tr ' ' a)"
LONG="git push --force origin main $A171"   # exactly 200 bytes, then a tail that must be cut
grun PB_HEADLESS=1 -- "$(jbash "${LONG}ZZZZTAIL")"
assert_contains "AC-A14 the first 200 bytes of the matched text are shown" "$GERR" "$LONG"
if [ "$RC" = 2 ] && ! has "$GERR" "ZZZZTAIL"; then t_ok "AC-A14 bytes after the first 200 are cut"; else t_bad "AC-A14 bytes after the first 200 are cut" "rc=$RC $OUT"; fi

echo "A-S2 AC-A6 rm -r targets (root /pbguard-proj/app from the hook cwd, HOME=$GH, TMPDIR a real temp dir)"
for c in 'rm -rf /opt/pbguard-data' 'rm -rf ../other' 'rm -rf .' 'rm -rf ./' 'rm -rf /pbguard-proj/app' 'rm -rf ..' \
  'rm -rf ~' 'rm -rf ~/cache' 'rm -rf $HOME/cache' 'rm -rf "${HOME}"/cache' 'rm -r -f /opt/x' 'rm -Rf /opt/x' 'rm -fR /opt/x' \
  'rm --recursive --force /opt/x' 'rm -rf build /opt/x' 'sudo rm -rf /var/lib/pbguard' 'env rm -r /etc/pbguard' \
  'command rm -R /opt/x' 'nice rm --recursive /opt/x' 'time rm -fr /opt/x' 'cd /opt && rm -rf data' 'cd .. && rm -rf app' \
  'cd sub; cd ../..; rm -rf x' 'cd build || rm -rf /opt/x' 'ls | rm -rf /opt/x' 'rm -rf /opt/*' 'rm -rf ../*' \
  'd=/opt/pbguard; rm -rf "$d"' 'd=/opt/pbguard && rm -rf "${d}/sub"'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "AC-A6 [$c]" rm-outside
done
for c in 'rm -rf $PBGUARD_UNKNOWN/x' 'rm -rf `pwd`/x' 'rm -rf ~nobody/x' 'cd $PBGUARD_UNKNOWN && rm -rf build' 'rm -rf "$(git rev-parse --show-toplevel)"/x'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "AC-A6 unresolvable [$c] counts as outside" rm-outside
  assert_contains "AC-A6 unresolvable [$c]: the message asks for a literal path" "$(printf '%s' "$GERR" | tr 'A-Z' 'a-z')" "literal path"
done
for c in 'rm -rf build' 'rm -rf ./node_modules dist' 'rm -rf src/old/*' 'rm -rf /pbguard-proj/app/build' 'rm -r build/' \
  'rm -rf sub/../build' 'cd sub && rm -rf ../build' 'rm -rf "$TMPDIR/pbguard-x"' 'rm -rf ${TMPDIR}/pbguard-x' "rm -rf $GT/pbguard-x" \
  'rm -rf /tmp/pbguard-x' 'd=$(mktemp -d); rm -rf "$d"' 'd="$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")" && rm -rf "$d"' \
  'd=/pbguard-proj/app/out; rm -rf "$d"' 'rm -f /opt/pbguard-file' 'rm /opt/pbguard-a /opt/pbguard-b' \
  'grep -rn "rm -rf /" docs' 'echo rm -rf /' 'git rm -r --cached build'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_pass "AC-A6 [$c]"
done
# a project under the home: tilde and HOME expand (through pb_home), they are not treated as unresolvable
for c in 'rm -rf ~/proj/build' 'rm -rf $HOME/proj/build' 'rm -rf "${HOME}/proj/dist"'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" /pbguard-home/proj)"
  expect_pass "AC-A6 home expanded [$c] (root /pbguard-home/proj)"
done
# CLAUDE_PROJECT_DIR is the root when set; the hook cwd may be below or above it
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR=/pbguard-proj/app -- "$(jbash 'rm -rf ../build' /pbguard-proj/app/sub)"
expect_pass "AC-A6 root from CLAUDE_PROJECT_DIR: cwd sub, ../build is inside"
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR=/pbguard-proj/app -- "$(jbash 'rm -rf other' /pbguard-proj)"
expect_block "AC-A6 root from CLAUDE_PROJECT_DIR: cwd above it, other is outside" rm-outside
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR=/pbguard-proj/app -- "$(jbash 'rm -rf "$CLAUDE_PROJECT_DIR/build"')"
expect_pass "AC-A6 \$CLAUDE_PROJECT_DIR/build is inside"
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR=/pbguard-proj/app -- "$(jbash 'rm -rf "${CLAUDE_PROJECT_DIR}"')"
expect_block "AC-A6 \${CLAUDE_PROJECT_DIR} itself is the root (outside)" rm-outside
grun PB_HEADLESS=0 -- "$(jbash 'rm -rf /opt/pbguard-data')"
expect_warn "AC-A6 interactive: rm outside only warns"

echo "A-S2 AC-A9 Windows paths"
WCWD='C:\Users\x\proj'
grun PB_HEADLESS=1 -- "$(jbash 'cd /c/Users/x/proj; rm -rf build' "$WCWD")"
expect_pass "AC-A9 cwd C:\\Users\\x\\proj + cd /c/Users/x/proj; rm -rf build"
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf C:/Users/x/proj/build' "$WCWD")"
expect_pass "AC-A9 C:/ form inside the C:\\ root"
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf c:/users/X/PROJ/dist' "$WCWD")"
expect_pass "AC-A9 drive paths compare case-insensitively"
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf /c/Users/x/other' "$WCWD")"
expect_block "AC-A9 /c/ path outside the C:\\ root" rm-outside
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf C:/Users/x/proj' "$WCWD")"
expect_block "AC-A9 the root itself in C:/ form is outside" rm-outside
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR='C:\Users\x\proj' -- "$(jbash 'cd /c/Users/x/proj && rm -rf node_modules' "$WCWD")"
expect_pass "AC-A9 CLAUDE_PROJECT_DIR in C:\\ form, cd in /c/ form"
grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR='C:/Users/x/proj' -- "$(jbash 'rm -rf /c/Users/x/proj/build' /c/Users/x/proj)"
expect_pass "AC-A9 CLAUDE_PROJECT_DIR in C:/ form, target in /c/ form"
# the real Run 28 shape: hook cwd C:\..., commands start with cd /c/...
grun PB_HEADLESS=1 -- "$(jbash 'cd /c/Users/Lenovo/pbeval/r28/C/E13.with.1; rm -rf .agents/handoff' "$GF_CWD1")"
expect_pass "AC-A9 Run 28 shape: cd /c/... then rm -rf .agents/handoff"
grun PB_HEADLESS=1 -- "$(jbash 'cd /c/Users/Lenovo/pbeval/r28/C/E13.with.1; rm -rf ../E13.with.2' "$GF_CWD1")"
expect_block "AC-A9 Run 28 shape: cd /c/... then rm -rf a sibling run dir" rm-outside
if command -v cygpath >/dev/null 2>&1; then
  WT="$(cygpath -w "$GT")"
  grun PB_HEADLESS=1 TEMP="$WT" TMPDIR= -- "$(jbash "rm -rf $(cygpath -u "$WT")/pbguard-x")"
  expect_pass "AC-A9 the Windows temp dir from TEMP (cygpath -u) allows rm below it"
else
  t_skip 1 "AC-A9 cygpath not present (not Git Bash): TEMP conversion not testable here"
fi

echo "A-S3 AC-A3 SQL clients"
P="$(mk_tmp)"
mkdir -p "$P/db"
printf 'DROP TABLE legacy_orders;\n' > "$P/db/drop.sql"
printf 'SELECT 1;\n' > "$P/db/read.sql"
printf -- '-- cleanup\nDELETE FROM sessions;\n' > "$P/db/wipe.sql"
for c in 'sqlite3 app.db "DROP TABLE users;"' "psql -c 'drop table users'" 'mysql -e "TRUNCATE orders"' \
  'sqlite3 app.db "DELETE FROM users;"' 'sqlite3 app.db "DELETE FROM a WHERE id=1; DELETE FROM b;"' 'sqlite3 app.db "delete from users"' \
  'mariadb -e "DROP TABLE t"' 'sqlcmd -Q "DROP DATABASE shop"' 'duckdb x.db "DROP SCHEMA s CASCADE"' \
  'clickhouse-client --query "TRUNCATE TABLE t"' 'wrangler d1 execute shop --command "DROP TABLE t"' \
  'echo "DROP DATABASE shop;" | mysql' 'printf "drop table x;" | sqlite3 app.db' 'cd db && sqlite3 ../app.db "DROP TABLE x"' \
  'sqlite3 app.db < db/drop.sql' 'psql -f db/drop.sql' 'psql --file=db/drop.sql' 'sqlite3 app.db ".read db/drop.sql"' \
  "psql -c '\\i db/drop.sql'" 'cat db/drop.sql | sqlite3 app.db' 'sqlite3 app.db < db/wipe.sql'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$P")"
  expect_block "AC-A3 [$c]" sql
done
HD="sqlite3 app.db <<'SQL'
CREATE TABLE t2 (id INTEGER);
DROP TABLE users;
SQL"
grun PB_HEADLESS=1 -- "$(jbash "$HD" "$P")"
expect_block "AC-A3 a here-doc body fed to sqlite3" sql
HD2="psql shop <<EOF
truncate audit_log;
EOF"
grun PB_HEADLESS=1 -- "$(jbash "$HD2" "$P")"
expect_block "AC-A3 a here-doc body fed to psql (lower case)" sql
for c in 'sqlite3 app.db "DELETE FROM users WHERE id = 3;"' 'psql -c "SELECT * FROM users"' 'sqlite3 app.db < db/read.sql' \
  'psql -f db/missing.sql' 'sqlite3 app.db ".tables"' 'grep -i "drop table" db/drop.sql' "printf 'DROP TABLE legacy_orders;\\n' > db/migrations/1.sql" \
  'cat db/drop.sql' 'echo "TRUNCATE is fast" > notes.txt' 'git log --grep="DROP TABLE"'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$P")"
  expect_pass "AC-A3 not sql [$c]"
done
grun PB_HEADLESS=0 -- "$(jbash 'sqlite3 app.db "DROP TABLE users;"' "$P")"
expect_warn "AC-A3 interactive: a DROP through sqlite3 only warns"
grun PB_HEADLESS=1 -- "$(jbash 'sqlite3 app.db "DROP TABLE users;"' "$P")"
assert_contains "AC-A3 the BLOCK quotes the SQL client command" "$GERR" 'sqlite3 app.db "DROP TABLE users;"'

t_summary
