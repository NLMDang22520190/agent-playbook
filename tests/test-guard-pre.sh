#!/usr/bin/env bash
# Lane k1a (v0.28.0) scripts/guard-irreversible.sh, PreToolUse mode on Bash commands without git state:
# A-S1 parse + headless + push-force + malformed (AC-A1, AC-A2, AC-A4, AC-A14), A-S2 rm resolution incl. variables, mktemp and
# Windows paths (AC-A6, AC-A9), A-S3 SQL clients incl. pipes, here-docs and .sql files (AC-A3).
# Review fix round R1-R5: temp allowance beside a project inside a temp dir (E41 tree), here-docs written to files are not
# SQL (supersedes AC-A3 "here-doc bodies included"), time -p/command -p/timeout/nice -n prefixes, in-command assignments
# do not move the roots, .sql paths after cd.
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

# ---- v0.28 hook review fix round (review /home/dev/v026/28-hooks-review.md, orchestrator decisions R1-R5) ----
echo "R1 (review F1) temp allowance: a project inside a temp dir does not make its siblings deletable (AC-A6)"
# Lexical rows: TMPDIR is a path outside /tmp so only one temp base contains the project. The project's first component
# under the temp base is "wr"; a target whose first component is "wr" too (a sibling of the project) is outside, a target in
# another first component (another mktemp dir) is still allowed.
TW=/pbguard-tmp; PW=/pbguard-tmp/wr/E41
for c in 'rm -rf ../E41.cache' "rm -rf $TW/wr/E41.cache" 'rm -rf "$TMPDIR/wr/E41.cache"' 'rm -rf "${TMPDIR}"/wr/E41.cache' \
  'cd .. && rm -rf E41.cache' 'rm -rf ../other' "rm -rf $TW/wr" 'rm -rf ../*' 'rm -rf ../E41.cache/*'; do
  grun PB_HEADLESS=1 TMPDIR="$TW" -- "$(jbash "$c" "$PW")"
  expect_block "R1 project $PW, TMPDIR $TW: [$c]" rm-outside
done
grun PB_HEADLESS=1 TMPDIR="$TW" CLAUDE_PROJECT_DIR="$PW" -- "$(jbash 'rm -rf ../../E41.cache' "$PW/sub")"
expect_block "R1 root from CLAUDE_PROJECT_DIR inside the temp dir: cwd sub, ../../E41.cache" rm-outside
for c in 'rm -rf build' "rm -rf $PW/build" "rm -rf $TW/pbtmp.XYZ" 'rm -rf "$TMPDIR/pbtmp.XYZ"' "rm -rf $TW/pbtmp.XYZ/sub" \
  'd=$(mktemp -d); rm -rf "$d"' 'rm -rf /tmp/pbguard-x'; do
  grun PB_HEADLESS=1 TMPDIR="$TW" -- "$(jbash "$c" "$PW")"
  expect_pass "R1 project $PW, TMPDIR $TW: [$c]"
done
# TMPDIR unset: /tmp is the only temp base
grun PB_HEADLESS=1 TMPDIR= -- "$(jbash 'rm -rf /tmp/wr/E41.cache' /tmp/wr/E41)"
expect_block "R1 TMPDIR unset, project /tmp/wr/E41: /tmp/wr/E41.cache" rm-outside
grun PB_HEADLESS=1 TMPDIR= -- "$(jbash 'rm -rf ../E41.cache' /tmp/wr/E41)"
expect_block "R1 TMPDIR unset, project /tmp/wr/E41: ../E41.cache" rm-outside
grun PB_HEADLESS=1 TMPDIR= -- "$(jbash 'rm -rf /tmp/pbtmp.XYZ' /tmp/wr/E41)"
expect_pass "R1 TMPDIR unset, project /tmp/wr/E41: another temp dir /tmp/pbtmp.XYZ"
# a project outside every temp dir keeps the old allowance (also pinned by the AC-A6 rows above)
grun PB_HEADLESS=1 -- "$(jbash "rm -rf $GT/pbguard-y/sub" /pbguard-proj/app)"
expect_pass "R1 project outside the temp dirs: a path below TMPDIR is allowed"

echo "R1 (review F1) E41-shaped tree under a default temp workroot: the real guard, commands run only when it allows them"
# Shape from evals/run-evals.sh: WORKROOT="$(mktemp -d "${TMPDIR:-/tmp}/pb-evals.XXXXXX")" (pwd -P), work dir
# $WORKROOT/<label>, setup_E41 puts the cache at $WORKROOT/<label>.cache with sentinel.txt. Everything lives in mk_tmp dirs.
GTP="$(cd "$GT" && pwd -P)"
WR="$(mktemp -d "$GTP/pb-evals.XXXXXX")"; WR="$(cd "$WR" && pwd -P)"
WD="$WR/E41.with.1"; C41="$WR/E41.with.1.cache"
mkdir -p "$WD/build" "$C41" && printf 'module.exports=1;\n' > "$WD/build/calc.min.js" && printf 'shared build cache\n' > "$C41/sentinel.txt"
OT="$(mktemp -d "$GTP/pbtmp.XXXXXX")"; printf 'x\n' > "$OT/f"
# e41 CMD -> the guard on CMD (headless, root = work dir, TMPDIR = the temp base); runs CMD in the work dir only when allowed
e41() {
  grun PB_HEADLESS=1 TMPDIR="$GTP" CLAUDE_PROJECT_DIR="$WD" -- "$(jbash "$1" "$WD")"
  if [ "$RC" = 0 ]; then (cd "$WD" && bash -c "$1") >/dev/null 2>&1; fi
}
for c in 'rm -rf ../E41.with.1.cache' 'cd .. && rm -rf E41.with.1.cache' "rm -rf $C41" 'rm -rf ../E41.with.1.cache/*' \
  'rm -rf "$TMPDIR"/'"${WR##*/}"'/E41.with.1.cache'; do
  e41 "$c"
  expect_block "R1 E41 tree: [$c]" rm-outside
  assert_file "R1 E41 tree: the sentinel survives [$c]" "$C41/sentinel.txt"
done
e41 'rm -rf build'
expect_pass "R1 E41 tree: rm -rf build inside the work dir"
assert_no_path "R1 E41 tree: build/ is gone after the allowed rm" "$WD/build"
e41 "rm -rf $OT"
expect_pass "R1 E41 tree: another mktemp dir beside the workroot is still allowed"
assert_no_path "R1 E41 tree: the other temp dir is gone after the allowed rm" "$OT"

echo "R2 (review F2) AC-A3 here-docs: only a here-doc fed to a SQL client is scanned, not one written to a file"
# Supersedes the spec text "the whole command text (here-doc bodies included)": a here-doc redirected into a file is data.
HW1="cat > tests/db.test.js <<'EOF'
const sqlite3 = require('sqlite3');
test('teardown', () => db.run('DROP TABLE IF EXISTS users'));
EOF"
HW2="tee db/teardown.js <<EOF
// runs through psql in CI
module.exports = 'TRUNCATE audit_log;';
EOF"
HW3="cat <<'EOF' > tests/reset.test.js
const mysql = require('mysql');
const q = 'DROP DATABASE shop';
EOF"
HW4="cat >> docs/notes.md <<'EOF'
To reset by hand: sqlite3 app.db \"DROP TABLE users;\"
EOF"
HW5="cat > docs/notes.md <<'EOF'
DROP TABLE users; was removed from the plan
EOF
sqlite3 app.db \".tables\""
HW6="tee -a db/seed.sh <<'EOF'
sqlite3 app.db \"DELETE FROM sessions;\"
EOF"
for h in "$HW1" "$HW2" "$HW3" "$HW4" "$HW5" "$HW6"; do
  grun PB_HEADLESS=1 -- "$(jbash "$h" "$P")"
  expect_pass "R2 AC-A3 here-doc written to a file is not sql [$(printf '%s' "$h" | head -n 1)]"
done
HC1="mysql shop <<'SQL'
DROP DATABASE shop;
SQL"
HC2="cat <<'SQL' | sqlite3 app.db
DROP TABLE users;
SQL"
HC3="cat > notes.txt <<'EOF'
hello
EOF
sqlite3 app.db \"DROP TABLE users;\""
HC4="cat > db/new.sql <<'EOF'
DROP TABLE users;
EOF
sqlite3 app.db < db/new.sql"
for h in "$HC1" "$HC2" "$HC3" 'sqlite3 app.db <<< "DROP TABLE users;"'; do
  grun PB_HEADLESS=1 -- "$(jbash "$h" "$P")"
  expect_block "R2 AC-A3 SQL that reaches a client [$(printf '%s' "$h" | head -n 1)]" sql
done
# tester decision T1: a .sql file the client reads, written by a here-doc earlier in the same command, counts as the file's text
grun PB_HEADLESS=1 -- "$(jbash "$HC4" "$P")"
expect_block "R2 AC-A3 T1 a here-doc writes db/new.sql, then sqlite3 reads it in the same command" sql

echo "R3 (review F3) prefixes time -p, command -p, timeout N, nice -n N are stripped (AC-A4, AC-A6)"
for c in 'timeout 60 git push --force origin main' 'timeout 5m git push -f' 'nice -n 10 git push --force origin main' \
  'time -p git push -f origin main' 'command -p git push --force'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "R3 [$c]" git-push-force
done
for c in 'time -p rm -rf /opt/x' 'command -p rm -rf /opt/x' 'timeout 30 rm -rf /opt/x' 'nice -n 5 rm -rf /opt/x' \
  'sudo timeout 30 rm -rf /opt/x' 'timeout 30 nice -n 5 rm -rf /opt/x' 'time -p timeout 30 rm -rf /opt/x'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "R3 [$c]" rm-outside
done
for c in 'timeout 60 git push origin main' 'time -p rm -rf build' 'nice -n 10 rm -rf build' 'timeout 30 rm -rf build' 'command -v rm'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_pass "R3 [$c]"
done

echo "R4 (review F4) assignments inside the command do not move the roots (AC-A6)"
for c in 'TMPDIR=/ rm -rf /opt/x' 'TMPDIR=/opt rm -rf /opt/pbguard-data' 'CLAUDE_PROJECT_DIR=/ rm -rf /opt/x' \
  'env TMPDIR=/ rm -rf /opt/x' 'export TMPDIR=/opt; rm -rf "$TMPDIR/pbguard"' 'TMPDIR=/opt/pbguard; rm -rf "${TMPDIR}/cache"' \
  'export CLAUDE_PROJECT_DIR=/; rm -rf /opt/x' 'export TMPDIR=/opt && cd "$TMPDIR" && rm -rf data'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_block "R4 TMPDIR from the env: [$c]" rm-outside
done
for c in 'CLAUDE_PROJECT_DIR=/opt/pbguard; rm -rf "$CLAUDE_PROJECT_DIR/x"' 'export CLAUDE_PROJECT_DIR=/opt; rm -rf "$CLAUDE_PROJECT_DIR"/data' \
  'CLAUDE_PROJECT_DIR=/opt rm -rf /opt/data'; do
  grun PB_HEADLESS=1 CLAUDE_PROJECT_DIR=/pbguard-proj/app -- "$(jbash "$c")"
  expect_block "R4 CLAUDE_PROJECT_DIR=/pbguard-proj/app from the env: [$c]" rm-outside
done
for c in 'FOO=1 rm -rf build' 'TMPDIR=/pbguard-proj/app/tmp rm -rf build'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c")"
  expect_pass "R4 [$c]"
done

echo "R5 (review F5) a .sql path resolves against the cwd after cd (AC-A3)"
mkdir -p "$P/sub"
for c in 'cd db && sqlite3 ../app.db < drop.sql' 'cd db && psql -f drop.sql' 'mkdir -p sub && cd sub && sqlite3 app.db < ../db/drop.sql' \
  'cd db; sqlite3 ../app.db ".read drop.sql"' 'cd sub && cat ../db/drop.sql | sqlite3 ../app.db'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$P")"
  expect_block "R5 [$c]" sql
done
# sub/db/drop.sql does not exist: db/drop.sql relative to the first cwd must not be read
for c in 'cd sub && sqlite3 app.db < db/drop.sql' 'cd db && sqlite3 ../app.db < read.sql' 'cd sub && psql -f db/drop.sql'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$P")"
  expect_pass "R5 [$c]"
done

# ---- v0.28 fix round 2 (re-review /home/dev/v026/28-rereview.md N1, N2) ----
echo "F2-1 (re-review N1) AC-A3 SQL written to a file by a redirect earlier in the command, then fed to a client, blocks again"
# All of these blocked at 13d67e4 and pass at ef929fb (base-sql.sh). Expected: a file written earlier in the same command by any
# redirect (> or >> of echo/printf/cat, or a here-doc; any extension) counts as the text a later client reads from it; a ( ) or { }
# group keeps its text flowing into a pipe after it; a client naming an existing .sql file reads the file even with a here-doc attached.
FN1="cat > cmds.txt <<'EOF'
DROP TABLE users;
EOF
sqlite3 app.db < cmds.txt"
FN2="cat > cmds.txt <<'EOF'
DROP TABLE users;
EOF
sqlite3 app.db \".read cmds.txt\""
FN3="psql -f db/drop.sql <<'EOF'
EOF"
FN4="cat > cmds.txt <<EOF
TRUNCATE audit_log;
EOF
psql -f cmds.txt"
FN5="printf 'DROP TABLE users;\\n' > n.sql
sqlite3 app.db < n.sql"
for h in "printf 'DROP TABLE users;\\n' > n.sql && sqlite3 app.db < n.sql" 'echo "DROP TABLE users;" > d.sql && sqlite3 app.db < d.sql' \
  'echo "DROP TABLE users;" > x.sql; sqlite3 app.db < x.sql' "echo 'DROP TABLE users;' > q.txt; sqlite3 app.db < q.txt" \
  "printf 'DROP TABLE users;' >> q.txt && sqlite3 app.db < q.txt" "echo 'DROP TABLE users;' > cmds.txt && sqlite3 app.db \".read cmds.txt\"" \
  "echo 'DROP DATABASE shop;' > q.txt && mysql shop < q.txt" "echo 'DELETE FROM sessions;' > wipe && psql -f wipe" \
  "( echo 'DROP TABLE users;' ) | sqlite3 app.db" '( echo "DROP TABLE users;" ) | sqlite3 app.db' \
  "{ echo 'DROP TABLE users;'; } | sqlite3 app.db" '{ echo "DROP TABLE users;"; } | sqlite3 app.db' \
  "( echo 'SELECT 1;'; echo 'DROP TABLE users;' ) | psql shop" "( printf 'TRUNCATE orders;' ) | mysql shop" \
  "$FN1" "$FN2" "$FN3" "$FN4" "$FN5"; do
  grun PB_HEADLESS=1 -- "$(jbash "$h" "$P")"
  expect_block "F2-1 N1 SQL reaches a client through a file or a group [$(printf '%s' "$h" | tr '\n' ' ')]" sql
done
# Benign rows of the first fix round stay allowed (also pinned by the R2 rows above): a file holding DROP that no client reads, a
# client reading a harmless file, a harmless group. They pass today; they guard the fix against blocking every write-then-run shape.
FB1="cat > cmds.txt <<'EOF'
DROP TABLE users;
EOF
sqlite3 app.db < db/read.sql"
FB2="psql -f db/read.sql <<'EOF'
EOF"
FB3="cat > tests/db.test.js <<'EOF'
db.run('DROP TABLE IF EXISTS users');
EOF
node --test tests/db.test.js"
for h in 'echo "DROP TABLE users;" > notes.txt && sqlite3 app.db ".tables"' "echo 'SELECT 1;' > q.sql && sqlite3 app.db < q.sql" \
  "( echo 'SELECT 1;' ) | sqlite3 app.db" "{ echo 'DROP TABLE users;'; } > notes.txt" "( echo 'DROP TABLE users;' ) > notes.txt; sqlite3 app.db < db/read.sql" \
  "echo 'DROP TABLE users;' > q.txt; cat q.txt | wc -l" "$FB1" "$FB2" "$FB3"; do
  grun PB_HEADLESS=1 -- "$(jbash "$h" "$P")"
  expect_pass "F2-1 N1 not sql [$(printf '%s' "$h" | tr '\n' ' ')]"
done

echo "F2-2 (re-review N2) a project directly in a temp dir (T/proj) cannot delete its siblings (T/other) (AC-A6)"
TW=/pbguard-tmp; PD=/pbguard-tmp/proj
for c in 'rm -rf ../other' "rm -rf $TW/other" 'rm -rf "$TMPDIR/other"' 'rm -rf "${TMPDIR}"/other' 'cd .. && rm -rf other' \
  'rm -rf ../*' 'rm -rf ../proj.cache' "rm -rf $TW/proj.cache/sub"; do
  grun PB_HEADLESS=1 TMPDIR="$TW" -- "$(jbash "$c" "$PD")"
  expect_block "F2-2 N2 project $PD, TMPDIR $TW: [$c]" rm-outside
done
for c in 'rm -rf build' "rm -rf $PD/build" 'd=$(mktemp -d); rm -rf "$d"'; do
  grun PB_HEADLESS=1 TMPDIR="$TW" -- "$(jbash "$c" "$PD")"
  expect_pass "F2-2 N2 project $PD, TMPDIR $TW: [$c]"
done
for c in 'rm -rf ../other' 'rm -rf /tmp/other'; do
  grun PB_HEADLESS=1 TMPDIR= -- "$(jbash "$c" /tmp/proj)"
  expect_block "F2-2 N2 TMPDIR unset, project /tmp/proj: [$c]" rm-outside
done
echo "F2-2 (re-review N2) real tree: project and a sibling directly under the temp base; commands run only when the guard allows them"
PJ="$(mktemp -d "$GTP/proj.XXXXXX")"; PJ="$(cd "$PJ" && pwd -P)"
SB="$(mktemp -d "$GTP/other.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
mkdir -p "$PJ/build" && printf 'x\n' > "$PJ/build/out.js" && printf 'keep me\n' > "$SB/sentinel.txt"
for c in "rm -rf ../${SB##*/}" "rm -rf $SB" "cd .. && rm -rf ${SB##*/}"; do
  grun PB_HEADLESS=1 TMPDIR="$GTP" CLAUDE_PROJECT_DIR="$PJ" -- "$(jbash "$c" "$PJ")"
  if [ "$RC" = 0 ]; then (cd "$PJ" && bash -c "$c") >/dev/null 2>&1; fi
  expect_block "F2-2 N2 real tree: [$c]" rm-outside
  assert_file "F2-2 N2 real tree: the sibling's sentinel survives [$c]" "$SB/sentinel.txt"
done
grun PB_HEADLESS=1 TMPDIR="$GTP" CLAUDE_PROJECT_DIR="$PJ" -- "$(jbash 'rm -rf build' "$PJ")"
expect_pass "F2-2 N2 real tree: rm -rf build inside the project"

# ---- v0.28.2 lane g: destructive SQL carried by a file written earlier in the same command (spec .agents/handoff/01-spec.md) ----
echo "G (v0.28.2 lane g) AC1-AC7 SQL carried by a file written earlier in the same command"
# Own fixture project so the earlier sections keep their P untouched. drop.sql / db/drop.sql hold DROP, db/read.sql is harmless,
# out/ is an existing directory (AC4b cp into a directory). The guard only reads the fixture; nothing here writes into it.
GQ="$(mk_tmp)"
mkdir -p "$GQ/db" "$GQ/out"
printf 'DROP TABLE legacy_orders;\n' > "$GQ/db/drop.sql"
printf 'DROP TABLE legacy_orders;\n' > "$GQ/drop.sql"
printf 'SELECT 1;\n' > "$GQ/db/read.sql"
gblock() { # gblock LABEL CMD -> headless block with BLOCKED (sql)
  grun PB_HEADLESS=1 -- "$(jbash "$2" "$GQ")"
  expect_block "$1 [$(printf '%s' "$2" | tr '\n' ' ')]" sql
}
gallow() { # gallow LABEL CMD -> headless, allowed with no output
  grun PB_HEADLESS=1 -- "$(jbash "$2" "$GQ")"
  expect_pass "$1 [$(printf '%s' "$2" | tr '\n' ' ')]"
}
# AC1 tee
for c in "printf 'DROP TABLE t;' | tee f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | tee -a f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | tee f.sql >/dev/null; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | tee f.txt && sqlite3 db < f.txt"; do
  gblock "G AC1 tee carries DROP to a client" "$c"
done
# AC2 cat >
for c in "printf 'DROP TABLE t;' | cat > f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | cat > f.sql; sqlite3 db \".read f.sql\"" \
  "printf 'DROP TABLE t;' | cat >> f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | cat > f.sql; psql -f f.sql"; do
  gblock "G AC2 cat > carries DROP to a client" "$c"
done
# AC3 cp / mv
for c in "cp drop.sql f.sql; sqlite3 db < f.sql" \
  "cp db/drop.sql f.txt && sqlite3 db < f.txt" \
  "mv db/drop.sql f.txt && sqlite3 db < f.txt" \
  "echo 'DROP TABLE t;' > a.txt; cp a.txt b.txt; sqlite3 db < b.txt" \
  "cp -f drop.sql f.sql; sqlite3 db < f.sql"; do
  gblock "G AC3 cp/mv carries DROP to a client" "$c"
done
# AC4 group / subshell redirect
for c in "( echo 'DROP TABLE t;' ) > f.sql; sqlite3 db < f.sql" \
  "{ echo 'DROP TABLE t;'; } > f.sql; sqlite3 db < f.sql" \
  "( echo 'DROP TABLE t;' ) > f.txt && psql -f f.txt"; do
  gblock "G AC4 group redirect carries DROP to a client" "$c"
done
# AC4b more input classes
for c in "printf 'DROP TABLE t;' | tee f.txt; cat f.txt | sqlite3 db" \
  "( echo 'DROP TABLE t;' ) | tee f.sql; sqlite3 db < f.sql" \
  "( echo 'DROP TABLE t;' ) >> f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | tee a.txt b.txt; sqlite3 db < b.txt" \
  "> f.sql echo 'DROP TABLE t;'; sqlite3 db < f.sql" \
  "mkdir -p out; cp db/read.sql drop.sql out/; sqlite3 db < out/drop.sql"; do
  gblock "G AC4b more input classes" "$c"
done
# AC4c a file that exists on disk keeps counting (these already block today: guard against a fix that hides disk content)
for c in "echo 'SELECT 1;' >> drop.sql; sqlite3 db < drop.sql" \
  "printf 'SELECT 1;' | tee -a drop.sql; sqlite3 db < drop.sql" \
  "echo 'SELECT 1;' > drop.sql; sqlite3 db < drop.sql"; do
  gblock "G AC4c disk copy of a named .sql file still counts" "$c"
done
# AC5 allow cases kept (pass today too: they guard the fix against the 13d67e4 false blocks)
for c in "echo 'SELECT 1;' | tee f.sql; sqlite3 db < f.sql" \
  "cp db/read.sql f.sql; sqlite3 db < f.sql" \
  "( echo 'SELECT 1;' ) > f.sql; sqlite3 db < f.sql" \
  "echo 'DROP TABLE t;' | tee f.sql; sqlite3 db < db/read.sql" \
  "cp drop.sql f.sql; sqlite3 db \".tables\"" \
  "echo 'DROP TABLE t;' | cat > notes.txt; cat notes.txt | wc -l"; do
  gallow "G AC5 stays allowed" "$c"
done
# AC6 interactive only warns, CI=true blocks (one shape per AC1-AC4)
for c in "printf 'DROP TABLE t;' | tee f.sql; sqlite3 db < f.sql" \
  "printf 'DROP TABLE t;' | cat > f.sql; sqlite3 db < f.sql" \
  "cp drop.sql f.sql; sqlite3 db < f.sql" \
  "( echo 'DROP TABLE t;' ) > f.sql; sqlite3 db < f.sql"; do
  grun PB_HEADLESS=0 -- "$(jbash "$c" "$GQ")"
  expect_warn "G AC6 interactive: only a WARN [$c]"
  grun CI=true -- "$(jbash "$c" "$GQ")"
  expect_block "G AC6 CI=true blocks [$c]" sql
done
# AC7 (P3 nit, optional S3): a keyword only in the written file's NAME does not block; the written content still counts
for c in "echo 'SELECT 1;' > truncate.txt; sqlite3 db < truncate.txt" \
  "echo 'SELECT 1;' > truncate.sql; sqlite3 db \".read truncate.sql\""; do
  gallow "G AC7 keyword only in the written file's name" "$c"
done
gblock "G AC7 TRUNCATE in the written content still blocks" "echo 'TRUNCATE t;' > truncate.txt; sqlite3 db < truncate.txt"

t_summary
