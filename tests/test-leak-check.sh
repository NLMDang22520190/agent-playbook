#!/usr/bin/env bash
# Tests for scripts/leak-check.sh (v0.22.0 AC1): a guard that refuses secrets and private literals in ADDED lines.
#   leak-check.sh scan --staged | scan --range A..B | scan FILE...
#   leak-check.sh install-hooks [--repo DIR] | uninstall-hooks [--repo DIR]
# Contract the implementer must follow (spec AC1.1 to AC1.5):
#   exit 0 + "leak-check: clean"; exit 1 on a hit, printing "file:line: <pattern name>" with the match masked
#   (first 4 chars then ***, never the full secret); exit 2 usage; exit 3 not a git repo (--staged, --range).
#   pattern names: github-token, anthropic-key, aws-key, private-key, user-pattern, user-literal.
#   conf keys: leak_patterns (ERE), leak_literals (comma-separated FIXED strings), read from PLAYBOOK_HOME/HOME and the project.
#   hooks: .git/hooks/pre-commit and pre-push carry the marker line "# agent-playbook leak-check"; an existing hook
#   without the marker is left alone (exit 1, reported); re-running is idempotent; uninstall removes marked hooks only.
# This repo is public: every secret below is built at run time from pieces, so no scanner finds a literal in this file.
. "$(dirname "$0")/lib.sh"
LC="$PB_ROOT/scripts/leak-check.sh"
SETUP_MD="$PB_ROOT/skills/playbook-setup/SKILL.md"
README="$PB_ROOT/README.md"
MARK='# agent-playbook leak-check'

export PLAYBOOK_HOME="$(mk_tmp)"
PH="$PLAYBOOK_HOME"
mkdir -p "$PH/.agents"
unset GIT_DIR GIT_WORK_TREE

# rep CHAR N -> N copies of CHAR
rep() { local s; s="$(printf '%*s' "$2" '')"; printf '%s' "${s// /$1}"; }
GH="ghp_$(rep a 36)"
GHS="ghs_$(rep d 36)"
GHPAT="github_pat_$(rep c 22)"
ANT="sk-ant-$(rep b 24)"
AWS="AKIA$(rep Q 16)"
PEM="-----BEGIN RSA ""PRIVATE KEY-----"
EML='dev@example.invalid'

G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false "$@"; }
# newrepo -> sets R (a fresh repo with one commit)
newrepo() { R="$(mk_tmp)"; mk_repo "$R"; }
# stage REPO FILE LINE... -> writes the lines to FILE (new content) and stages it
stage() { local r="$1" f="$2"; shift 2; mkdir -p "$r/$(dirname "$f")"; printf '%s\n' "$@" > "$r/$f"; git -C "$r" add -- "$f"; }
conf_global() { printf '%s\n' "$@" > "$PH/.agents/playbook.conf"; }

assert_file "AC1.1 scripts/leak-check.sh exists" "$LC"

echo "scan --staged: built-in patterns"
for spec in "github-token|$GH" "github-token|$GHS" "github-token|$GHPAT" "anthropic-key|$ANT" "aws-key|$AWS" "private-key|$PEM"; do
  name="${spec%%|*}"; sec="${spec#*|}"
  newrepo
  stage "$R" src/conf.txt 'harmless line' "token = $sec" 'tail'
  run_in "$R" bash "$LC" scan --staged
  assert_rc "AC1.1 staged $name [${sec:0:8}...]: exit 1" 1
  assert_contains "AC1.1 staged $name: output names file:line and the pattern" "$OUT" "src/conf.txt:2: $name"
  assert_not_contains "AC1.1 staged $name: the full secret is not printed" "$OUT" "$sec"
  assert_not_contains "AC1.1 staged $name: not even the secret minus its first 4 chars" "$OUT" "${sec:4:20}"
  assert_contains "AC1.1 staged $name: the match is masked with ***" "$OUT" "***"
done
newrepo
stage "$R" a.txt "x $GH"
run_in "$R" bash "$LC" scan --staged
assert_contains "AC1.1 masked form is the first 4 chars then ***" "$OUT" "ghp_***"

echo "scan --staged: boundaries of the built-in patterns"
newrepo
stage "$R" near.txt "gh35 ghp_$(rep a 35)" "ant19 sk-ant-$(rep b 19)" "aws15 AKIA$(rep Q 15)" "pat21 github_pat_$(rep c 21)" "plain BEGIN RSA PRIVATE KEY" "word skeleton-key-1234"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 one char short of every pattern (and look-alike words): clean, exit 0" 0
assert_contains "AC1.2 clean run says 'leak-check: clean'" "$OUT" "leak-check: clean"
newrepo
stage "$R" two.txt "one $GH" 'between' "two $AWS"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 two secrets in one file: exit 1" 1
assert_contains "AC1.1 first secret line reported" "$OUT" "two.txt:1: github-token"
assert_contains "AC1.1 second secret line reported" "$OUT" "two.txt:3: aws-key"

echo "scan --staged: only ADDED lines count"
newrepo
stage "$R" src/clean.txt 'a' 'b'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 clean staged change: exit 0" 0
assert_contains "AC1.1 clean staged change: 'leak-check: clean'" "$OUT" "leak-check: clean"
newrepo
printf 'old\n%s\nold2\n' "$GH" > "$R/s.txt"; git -C "$R" add s.txt; G -C "$R" commit -q -m 'old secret' || true
printf 'old\nold2\n' > "$R/s.txt"; git -C "$R" add s.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 a secret only on a REMOVED line: clean, exit 0" 0
assert_contains "AC1.1 removed-line secret: 'leak-check: clean'" "$OUT" "leak-check: clean"
newrepo
printf 'old\n%s\nold2\n' "$GH" > "$R/s.txt"; git -C "$R" add s.txt; G -C "$R" commit -q -m 'old secret' || true
printf 'old\n%s\nold2\nnew line\n' "$GH" > "$R/s.txt"; git -C "$R" add s.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 a secret on an unchanged context line, another line added: clean" 0
newrepo
printf '%s\n' "$GH" > "$R/gone.txt"; git -C "$R" add gone.txt; G -C "$R" commit -q -m 'add' || true
git -C "$R" rm -q gone.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 a staged deletion of a file that held a secret: clean" 0
newrepo
printf '%s\n' "$GH" > "$R/unstaged.txt"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 --staged looks at the index: an unstaged, untracked secret is not found" 0
newrepo
printf 'module.exports = 2;\n' > "$R/src/app.js"
printf 'x %s\n' "$GH" >> "$R/src/app.js"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 a modified but unstaged tracked file: not found (index vs HEAD)" 0
git -C "$R" add src/app.js
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.1 the same file once staged: exit 1" 1
assert_contains "AC1.1 staged modification of a tracked file: reported at its new line number" "$OUT" "src/app.js:2: github-token"

echo "scan --range A..B"
newrepo
c0="$(git -C "$R" rev-parse HEAD)"
stage "$R" one.txt 'fine'; G -C "$R" commit -q -m clean1
c1="$(git -C "$R" rev-parse HEAD)"
stage "$R" two.txt 'fine' "secret $ANT"; G -C "$R" commit -q -m with-secret
c2="$(git -C "$R" rev-parse HEAD)"
stage "$R" three.txt 'fine again'; G -C "$R" commit -q -m clean3
c3="$(git -C "$R" rev-parse HEAD)"
run_in "$R" bash "$LC" scan --range "$c0..$c3"
assert_rc "AC1.1 --range over three commits, one with a secret: exit 1" 1
assert_contains "AC1.1 --range names the file:line and the pattern" "$OUT" "two.txt:2: anthropic-key"
assert_not_contains "AC1.1 --range does not print the full secret" "$OUT" "$ANT"
run_in "$R" bash "$LC" scan --range "$c0..$c1"
assert_rc "AC1.1 --range over the clean commit only: exit 0" 0
assert_contains "AC1.1 --range clean: 'leak-check: clean'" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --range "$c2..$c3"
assert_rc "AC1.1 --range A..B excludes A: the secret commit is A, so clean" 0
run_in "$R" bash "$LC" scan --range "$c1..$c2"
assert_rc "AC1.1 --range ending at the secret commit: exit 1" 1
run_in "$R" bash "$LC" scan --range "HEAD~3..HEAD"
assert_rc "AC1.1 --range accepts symbolic refs (HEAD~3..HEAD): exit 1" 1
run_in "$R" bash "$LC" scan --range
assert_rc "AC1.1 --range without a value: usage, exit 2" 2

echo "scan FILE..."
D="$(mk_tmp)"
printf 'ok\n%s\n' "$GH" > "$D/leaky.txt"
printf 'ok\nstill ok\n' > "$D/fine.txt"
run_in "$D" bash "$LC" scan leaky.txt
assert_rc "AC1.1 scan FILE with a secret (not in a git repo): exit 1" 1
assert_contains "AC1.1 scan FILE names file:line and the pattern" "$OUT" "leaky.txt:2: github-token"
assert_not_contains "AC1.1 scan FILE does not print the full secret" "$OUT" "$GH"
run_in "$D" bash "$LC" scan fine.txt
assert_rc "AC1.1 scan FILE without a secret: exit 0" 0
assert_contains "AC1.1 scan FILE clean: 'leak-check: clean'" "$OUT" "leak-check: clean"
run_in "$D" bash "$LC" scan fine.txt leaky.txt
assert_rc "AC1.1 scan with two files, one leaky: exit 1" 1
assert_contains "AC1.1 scan with two files names the leaky one" "$OUT" "leaky.txt:2: github-token"
assert_not_contains "AC1.1 scan with two files does not name the clean one" "$OUT" "fine.txt:"

echo "user literals (leak_literals)"
conf_global "leak_literals=$EML,secret-repo-name"
newrepo
stage "$R" notes.txt 'ping' "mail $EML here"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 a configured literal in a staged line: exit 1" 1
assert_contains "AC1.3 reported as user-literal at file:line" "$OUT" "notes.txt:2: user-literal"
assert_not_contains "AC1.3 the literal is masked, not printed in full" "$OUT" "$EML"
newrepo
stage "$R" notes.txt 'see secret-repo-name for details'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 the second literal of the comma list is checked too: exit 1" 1
assert_contains "AC1.3 second literal reported as user-literal" "$OUT" "notes.txt:1: user-literal"
newrepo
stage "$R" notes.txt 'devXexample.invalid' 'dev at example dot invalid' 'secret_repo_name' 'secretXrepoXname'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 dots (and hyphens) in a literal match literally, not as regex: exit 0" 0
assert_contains "AC1.3 near-miss literals: 'leak-check: clean'" "$OUT" "leak-check: clean"
newrepo
stage "$R" notes.txt 'nothing special here'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 literals configured but absent from the change: exit 0" 0
conf_global 'leak_literals=p|q,a.b*c'
newrepo
stage "$R" notes.txt 'p' 'q' 'pq' 'axbbbc' 'a.b'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 literals with | and * are fixed strings (p, q, axbbbc, a.b do not match): exit 0" 0
newrepo
stage "$R" notes.txt 'x p|q y'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 the literal p|q itself matches: exit 1" 1
assert_contains "AC1.3 p|q reported as user-literal" "$OUT" "notes.txt:1: user-literal"
newrepo
stage "$R" notes.txt 'x a.b*c y'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 the literal a.b*c itself matches: exit 1" 1
conf_global 'leak_literals='
newrepo
stage "$R" notes.txt "mail $EML"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 an empty leak_literals checks nothing (an empty literal must not match every line): exit 0" 0
rm -f "$PH/.agents/playbook.conf"

echo "user patterns (leak_patterns)"
conf_global 'leak_patterns=internal-[0-9]{3}|corp\.example'
newrepo
stage "$R" p.txt 'a' 'ticket internal-123 open'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 a configured pattern matches: exit 1" 1
assert_contains "AC1.3 reported as user-pattern at file:line" "$OUT" "p.txt:2: user-pattern"
newrepo
stage "$R" p.txt 'see corp.example now'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 the second alternative of the pattern matches: exit 1" 1
assert_contains "AC1.3 second alternative reported as user-pattern" "$OUT" "p.txt:1: user-pattern"
newrepo
stage "$R" p.txt 'internal-12 only' 'corpXexample'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 near misses of the pattern (repeat bound, escaped dot): exit 0" 0
rm -f "$PH/.agents/playbook.conf"
# project conf
newrepo
mkdir -p "$R/.agents"; printf 'leak_patterns=proj-[a-z]{4}-id\nleak_literals=proj-secret-name\n' > "$R/.agents/playbook.conf"
stage "$R" q.txt 'x proj-abcd-id y'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 leak_patterns from the PROJECT conf is read: exit 1" 1
assert_contains "AC1.3 project pattern reported as user-pattern" "$OUT" "q.txt:1: user-pattern"
stage "$R" q.txt 'about proj-secret-name'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 leak_literals from the PROJECT conf is read: exit 1" 1
assert_contains "AC1.3 project literal reported as user-literal" "$OUT" "q.txt:1: user-literal"
stage "$R" q.txt 'nothing here'
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 project conf present but no match: exit 0" 0
# built-ins stay on when a conf exists
conf_global "leak_literals=$EML"
newrepo
stage "$R" q.txt "k $GH"
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.3 built-in patterns still apply when user keys are set: exit 1" 1
assert_contains "AC1.3 built-in name kept with a user conf present" "$OUT" "q.txt:1: github-token"
rm -f "$PH/.agents/playbook.conf"
# HOME fallback, as the other scripts read the conf
H2="$(mk_tmp)"; mkdir -p "$H2/.agents"; printf 'leak_literals=%s\n' "$EML" > "$H2/.agents/playbook.conf"
newrepo
stage "$R" q.txt "mail $EML"
run_in "$R" env -u PLAYBOOK_HOME HOME="$H2" bash "$LC" scan --staged
assert_rc "AC1.3 without PLAYBOOK_HOME the conf is read from HOME: exit 1" 1
assert_contains "AC1.3 HOME conf literal reported as user-literal" "$OUT" "q.txt:1: user-literal"

echo "usage and environment"
newrepo
run_in "$R" bash "$LC"
assert_rc "AC1.1 no arguments: usage, exit 2" 2
run_in "$R" bash "$LC" bogus
assert_rc "AC1.1 unknown command: usage, exit 2" 2
run_in "$R" bash "$LC" scan
assert_rc "AC1.1 scan without a target: usage, exit 2" 2
run_in "$R" bash "$LC" scan --bogus
assert_rc "AC1.1 scan with an unknown option: usage, exit 2" 2
NG="$(mk_tmp)"
run_in "$NG" bash "$LC" scan --staged
assert_rc "AC1.1 --staged outside a git repo: exit 3" 3
run_in "$NG" bash "$LC" scan --range 'a..b'
assert_rc "AC1.1 --range outside a git repo: exit 3" 3
run_in "$NG" bash "$LC" install-hooks
assert_rc "AC1.4 install-hooks outside a git repo: exit 3" 3

echo "install-hooks / uninstall-hooks"
newrepo
HOOKS="$R/.git/hooks"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.4 install-hooks: exit 0" 0
assert_file "AC1.4 pre-commit written" "$HOOKS/pre-commit"
assert_file "AC1.4 pre-push written" "$HOOKS/pre-push"
for h in pre-commit pre-push; do
  assert_contains "AC1.4 $h carries the marker line" "$(cat "$HOOKS/$h" 2>/dev/null)" "$MARK"
  if [ -x "$HOOKS/$h" ]; then t_ok "AC1.4 $h is executable"; else t_bad "AC1.4 $h is executable" "mode: $(ls -l "$HOOKS/$h" 2>&1)"; fi
done
assert_contains "AC1.4 pre-commit scans the staged change" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "--staged"
assert_contains "AC1.4 pre-push scans a range" "$(cat "$HOOKS/pre-push" 2>/dev/null)" "--range"
before_c="$(cksum < "$HOOKS/pre-commit" 2>/dev/null)"; before_p="$(cksum < "$HOOKS/pre-push" 2>/dev/null)"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.4 install-hooks again (idempotent): exit 0" 0
assert_eq "AC1.4 re-running leaves pre-commit byte-identical" "$before_c" "$(cksum < "$HOOKS/pre-commit" 2>/dev/null)"
assert_eq "AC1.4 re-running leaves pre-push byte-identical" "$before_p" "$(cksum < "$HOOKS/pre-push" 2>/dev/null)"
assert_eq "AC1.4 pre-commit has the marker exactly once" "1" "$(grep -cF "$MARK" "$HOOKS/pre-commit" 2>/dev/null)"
assert_eq "AC1.4 pre-push has the marker exactly once" "1" "$(grep -cF "$MARK" "$HOOKS/pre-push" 2>/dev/null)"

# the pre-commit hook in action
head0="$(git -C "$R" rev-parse HEAD)"
stage "$R" bad.txt "k $GH"
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'add a secret'
if [ "$RC" != 0 ]; then t_ok "AC1.4 a commit with a staged secret is rejected by the hook (exit $RC)"; else t_bad "AC1.4 a commit with a staged secret is rejected by the hook" "exit 0; output: $OUT"; fi
assert_eq "AC1.4 the rejected commit was not created" "$head0" "$(git -C "$R" rev-parse HEAD)"
assert_contains "AC1.4 the hook shows the finding" "$OUT" "bad.txt:1: github-token"
assert_not_contains "AC1.4 the hook output never shows the full secret" "$OUT" "$GH"
git -C "$R" rm -q --cached bad.txt; rm -f "$R/bad.txt"
stage "$R" good.txt 'all fine'
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'clean change'
assert_rc "AC1.4 a clean commit goes through the hook: exit 0" 0
assert_eq "AC1.4 the clean commit exists" "clean change" "$(git -C "$R" log -1 --format=%s)"

# an unmarked hook is left alone
newrepo
HOOKS="$R/.git/hooks"; mkdir -p "$HOOKS"
printf '#!/bin/sh\necho my-own-hook\n' > "$HOOKS/pre-commit"; chmod +x "$HOOKS/pre-commit"
mine="$(cksum < "$HOOKS/pre-commit")"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.4 an existing unmarked pre-commit: install-hooks exits 1" 1
assert_eq "AC1.4 the unmarked pre-commit is untouched" "$mine" "$(cksum < "$HOOKS/pre-commit")"
assert_not_contains "AC1.4 the unmarked pre-commit did not get the marker" "$(cat "$HOOKS/pre-commit")" "$MARK"
assert_contains "AC1.4 the refusal names the hook that was left alone" "$OUT" "pre-commit"
# --repo DIR from elsewhere
newrepo
run_in "$NG" bash "$LC" install-hooks --repo "$R"
assert_rc "AC1.4 install-hooks --repo DIR (from outside the repo): exit 0" 0
assert_contains "AC1.4 --repo DIR wrote the pre-commit into that repo" "$(cat "$R/.git/hooks/pre-commit" 2>/dev/null)" "$MARK"
assert_contains "AC1.4 --repo DIR wrote the pre-push into that repo" "$(cat "$R/.git/hooks/pre-push" 2>/dev/null)" "$MARK"
run_in "$NG" bash "$LC" uninstall-hooks --repo "$R"
assert_rc "AC1.4 uninstall-hooks --repo DIR: exit 0" 0
assert_no_path "AC1.4 uninstall removed the marked pre-commit" "$R/.git/hooks/pre-commit"
assert_no_path "AC1.4 uninstall removed the marked pre-push" "$R/.git/hooks/pre-push"
# uninstall touches marked hooks only
newrepo
HOOKS="$R/.git/hooks"
run_in "$R" bash "$LC" install-hooks
printf '#!/bin/sh\necho my-own-hook\n' > "$HOOKS/pre-commit"; chmod +x "$HOOKS/pre-commit"
mine="$(cksum < "$HOOKS/pre-commit")"
run_in "$R" bash "$LC" uninstall-hooks
assert_no_path "AC1.4 uninstall removes the marked pre-push" "$HOOKS/pre-push"
assert_file "AC1.4 uninstall keeps the unmarked pre-commit" "$HOOKS/pre-commit"
assert_eq "AC1.4 the unmarked pre-commit is byte-identical after uninstall" "$mine" "$(cksum < "$HOOKS/pre-commit")"
# after uninstall a secret commit is no longer blocked
newrepo
run_in "$R" bash "$LC" install-hooks
run_in "$R" bash "$LC" uninstall-hooks
stage "$R" bad.txt "k $GH"
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'now allowed'
assert_rc "AC1.4 after uninstall-hooks nothing blocks the commit: exit 0" 0

echo "the pre-push hook"
newrepo
BARE="$(mk_tmp)/remote.git"; git init -q --bare "$BARE"; git -C "$BARE" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
git -C "$R" remote add origin "$BARE"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.4 pre-push setup: install-hooks exit 0" 0
run_in "$R" git push -q origin main
assert_rc "AC1.4 pushing a clean branch passes the pre-push hook: exit 0" 0
pushed="$(git -C "$BARE" rev-parse --verify main 2>/dev/null)"
assert_eq "AC1.4 the clean push reached the remote" "$(git -C "$R" rev-parse HEAD)" "$pushed"
# a commit with a secret, made past the pre-commit hook, on an existing branch
stage "$R" leak.txt "k $GH"
G -C "$R" commit -q --no-verify -m 'leaky' || echo "fixture: commit --no-verify failed"
leaky="$(git -C "$R" rev-parse HEAD)"
run_in "$R" git push origin main
if [ "$RC" != 0 ]; then t_ok "AC1.4 pushing a commit with a secret is blocked by the hook (exit $RC)"; else t_bad "AC1.4 pushing a commit with a secret is blocked by the hook" "exit 0; output: $OUT"; fi
assert_eq "AC1.4 the blocked push did not move the remote branch" "$pushed" "$(git -C "$BARE" rev-parse --verify main 2>/dev/null)"
assert_contains "AC1.4 the pre-push hook shows the finding" "$OUT" "leak.txt:1: github-token"
assert_not_contains "AC1.4 the pre-push hook never shows the full secret" "$OUT" "$GH"
# a NEW branch: its commits are those not on any remote
run_in "$R" git push origin "HEAD:refs/heads/feature"
if [ "$RC" != 0 ]; then t_ok "AC1.4 pushing a NEW branch holding the secret commit is blocked (exit $RC)"; else t_bad "AC1.4 pushing a NEW branch holding the secret commit is blocked" "exit 0; output: $OUT"; fi
if git -C "$BARE" rev-parse --verify -q refs/heads/feature >/dev/null; then t_bad "AC1.4 the blocked new branch is not on the remote" "feature exists on the remote"; else t_ok "AC1.4 the blocked new branch is not on the remote"; fi
# a new branch with only clean commits (the secret commit is not part of it) goes through
git -C "$R" checkout -q -b cleanbranch "$pushed"
stage "$R" fine.txt 'fine'
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'fine commit'
assert_rc "AC1.4 pre-push setup: clean commit on a new branch: exit 0" 0
run_in "$R" git push -q origin cleanbranch
assert_rc "AC1.4 a new branch whose own commits are clean passes the pre-push hook: exit 0" 0
if git -C "$BARE" rev-parse --verify -q refs/heads/cleanbranch >/dev/null; then t_ok "AC1.4 the clean new branch reached the remote"; else t_bad "AC1.4 the clean new branch reached the remote" "no refs/heads/cleanbranch"; fi
# deleting a remote branch pushes no commits: nothing to scan
run_in "$R" git push -q origin --delete cleanbranch
assert_rc "AC1.4 deleting a remote branch is not blocked by the pre-push hook: exit 0" 0

echo "docs"
if grep -q 'leak_literals' "$SETUP_MD" 2>/dev/null; then t_ok "AC1.5 playbook-setup SKILL.md mentions leak_literals"; else t_bad "AC1.5 playbook-setup SKILL.md mentions leak_literals" "not in $SETUP_MD"; fi
if grep -q 'install-hooks' "$SETUP_MD" 2>/dev/null; then t_ok "AC1.5 playbook-setup SKILL.md mentions install-hooks"; else t_bad "AC1.5 playbook-setup SKILL.md mentions install-hooks" "not in $SETUP_MD"; fi
if grep -qi 'leak-check' "$README" 2>/dev/null; then t_ok "AC1.5 README mentions leak-check"; else t_bad "AC1.5 README mentions leak-check" "not in $README"; fi

t_summary
