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
# (v0.23.3 AC1b: one template repo is built once and copied for each case; mk_repo costs about 1 s per repo on Git Bash, cp -a 0.4 s)
RTPL="$(mk_tmp)"; mk_repo "$RTPL"
newrepo() { R="$(mk_tmp)"; cp -a "$RTPL/." "$R/"; }
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


# ---- review round: binary files, fail-closed hooks, --unpushed, merge commits, masking, finding count, case ----
echo "review 1: binary files are scanned"
newrepo
printf 'PK\000\000 token=%s \000\000\n' "$GH" > "$R/blob.bin"
git -C "$R" add blob.bin
run_in "$R" bash "$LC" scan --staged
assert_rc "RV1 a staged binary file (NUL bytes) holding a token: scan --staged exits 1" 1
assert_contains "RV1 the finding names the binary file" "$OUT" "blob.bin"
assert_not_contains "RV1 the binary finding does not print the full secret" "$OUT" "$GH"
newrepo
rb0="$(git -C "$R" rev-parse HEAD)"
printf 'PK\000\000 token=%s \000\000\n' "$GH" > "$R/blob.bin"
git -C "$R" add blob.bin; G -C "$R" commit -q -m 'binary with a secret'
run_in "$R" bash "$LC" scan --range "$rb0..HEAD"
assert_rc "RV1 a binary file with a token in a commit: scan --range exits 1" 1
assert_contains "RV1 --range names the binary file" "$OUT" "blob.bin"
newrepo
printf 'PK\000\000 no secret here \000\000\n' > "$R/clean.bin"; git -C "$R" add clean.bin
run_in "$R" bash "$LC" scan --staged
assert_rc "RV1 a clean binary file: exit 0" 0

echo "review 2: a hook fails closed when its script is gone"
newrepo
CP="$(mk_tmp)"; cp -R "$PB_ROOT/scripts" "$CP/scripts"
GONE="$(cd "$CP/scripts" && pwd -P)/leak-check.sh"
run_in "$R" bash "$CP/scripts/leak-check.sh" install-hooks
assert_rc "RV2 setup: install-hooks from a copy of scripts/: exit 0" 0
rm -rf "$CP/scripts"
stage "$R" fine.txt 'a clean change'
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'clean change'
if [ "$RC" != 0 ]; then t_ok "RV2 a clean commit is refused when the hook's script is gone (exit $RC)"; else t_bad "RV2 a clean commit is refused when the hook's script is gone" "exit 0 (the hook fails open); output: $OUT"; fi
assert_contains "RV2 the refusal names the missing script path" "$OUT" "$GONE"
case "$OUT" in *uninstall-hooks*|*install-hooks*|*reinstall*) t_ok "RV2 the refusal suggests uninstall-hooks or reinstalling" ;; *) t_bad "RV2 the refusal suggests uninstall-hooks or reinstalling" "output: $OUT" ;; esac
assert_eq "RV2 no commit was created" "init" "$(git -C "$R" log -1 --format=%s)"
# the pre-push hook as well
newrepo
BARE2="$(mk_tmp)/remote.git"; git init -q --bare "$BARE2"; git -C "$BARE2" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
git -C "$R" remote add origin "$BARE2"
CP="$(mk_tmp)"; cp -R "$PB_ROOT/scripts" "$CP/scripts"
run_in "$R" bash "$CP/scripts/leak-check.sh" install-hooks
rm -rf "$CP/scripts"
run_in "$R" git push -q origin main
if [ "$RC" != 0 ]; then t_ok "RV2 a push is refused when the pre-push hook's script is gone (exit $RC)"; else t_bad "RV2 a push is refused when the pre-push hook's script is gone" "exit 0; output: $OUT"; fi
if git -C "$BARE2" rev-parse --verify -q refs/heads/main >/dev/null; then t_bad "RV2 the refused push did not reach the remote" "main is on the remote"; else t_ok "RV2 the refused push did not reach the remote"; fi
# the way out works: uninstall-hooks (from the real script) removes the broken hooks and the commit goes through
run_in "$R" bash "$LC" uninstall-hooks
stage "$R" fine.txt 'a clean change'
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'clean change'
assert_rc "RV2 after uninstall-hooks the commit goes through: exit 0" 0

echo "review 3: scan --unpushed SHA skips the commits that are on a remote"
newrepo
BARE3="$(mk_tmp)/remote.git"; git init -q --bare "$BARE3"; git -C "$BARE3" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
git -C "$R" remote add origin "$BARE3"
stage "$R" old.txt "old secret $GH"; G -C "$R" commit -q -m 'old commit with a secret'
git -C "$R" push -q origin main
git -C "$R" checkout -q -b newclean main
stage "$R" new.txt 'a clean line'; G -C "$R" commit -q -m 'clean on top'
run_in "$R" bash "$LC" scan --unpushed HEAD
assert_rc "RV3 a new branch with one clean commit on top of a pushed secret: clean, exit 0" 0
assert_contains "RV3 ... says 'leak-check: clean'" "$OUT" "leak-check: clean"
git -C "$R" checkout -q -b newleak main
stage "$R" new2.txt "new secret $AWS"; G -C "$R" commit -q -m 'new secret'
run_in "$R" bash "$LC" scan --unpushed HEAD
assert_rc "RV3 a new branch with a new secret commit: exit 1" 1
assert_contains "RV3 the new secret is named" "$OUT" "new2.txt:1: aws-key"
assert_not_contains "RV3 the old, already pushed secret is not reported" "$OUT" "old.txt"
run_in "$R" bash "$LC" scan --unpushed
assert_rc "RV3 --unpushed without a SHA: usage, exit 2" 2
# the hook uses it: pushing the clean new branch works, pushing the leaky one is blocked
run_in "$R" bash "$LC" install-hooks
run_in "$R" git push -q origin newclean
assert_rc "RV3 the pre-push hook lets the clean new branch through (the old pushed secret is not rescanned): exit 0" 0
run_in "$R" git push origin newleak
if [ "$RC" != 0 ]; then t_ok "RV3 the pre-push hook blocks the new branch with a new secret"; else t_bad "RV3 the pre-push hook blocks the new branch with a new secret" "exit 0; output: $OUT"; fi

echo "review 4: merge commits are scanned (evil merges)"
# (a) a secret in a file that only the merge commit adds
newrepo
BAREM="$(mk_tmp)/remote.git"; git init -q --bare "$BAREM"; git -C "$BAREM" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
git -C "$R" remote add origin "$BAREM"; git -C "$R" push -q origin main
mb="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b side; stage "$R" side.txt 'side work'; G -C "$R" commit -q -m side
git -C "$R" checkout -q main; stage "$R" main.txt 'main work'; G -C "$R" commit -q -m mainwork
G -C "$R" merge -q --no-ff --no-commit side >/dev/null 2>&1
stage "$R" evil.txt "evil $GH"
G -C "$R" commit -q -m 'evil merge' || echo "fixture: merge commit failed"
run_in "$R" bash "$LC" scan --range "$mb..HEAD"
assert_rc "RV4 a secret added by the merge commit itself: --range exits 1" 1
assert_contains "RV4 --range names the file the merge added" "$OUT" "evil.txt"
run_in "$R" bash "$LC" scan --unpushed HEAD
assert_rc "RV4 a secret added by the merge commit itself: --unpushed exits 1" 1
assert_contains "RV4 --unpushed names the file the merge added" "$OUT" "evil.txt"
# (b) a secret in the conflict resolution
newrepo
BARE4="$(mk_tmp)/remote.git"; git init -q --bare "$BARE4"; git -C "$BARE4" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
stage "$R" f.txt 'base line' 'tail'; G -C "$R" commit -q -m 'f base'
git -C "$R" remote add origin "$BARE4"; git -C "$R" push -q origin main
mb="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b side2; printf 'side line\ntail\n' > "$R/f.txt"; git -C "$R" add f.txt; G -C "$R" commit -q -m 'side edit'
git -C "$R" checkout -q main; printf 'main line\ntail\n' > "$R/f.txt"; git -C "$R" add f.txt; G -C "$R" commit -q -m 'main edit'
G -C "$R" merge -q side2 >/dev/null 2>&1
printf 'resolved with %s\ntail\n' "$GH" > "$R/f.txt"; git -C "$R" add f.txt
G -C "$R" commit -q -m 'resolve with a secret' || echo "fixture: conflict resolution commit failed"
assert_eq "RV4 setup: the resolving commit is a merge (two parents)" "2" "$(git -C "$R" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ' | awk '{ print $1 - 1 }')"
run_in "$R" bash "$LC" scan --range "$mb..HEAD"
assert_rc "RV4 a secret introduced in a conflict resolution: --range exits 1" 1
assert_contains "RV4 --range names the resolved file" "$OUT" "f.txt"
run_in "$R" bash "$LC" scan --unpushed HEAD
assert_rc "RV4 a secret introduced in a conflict resolution: --unpushed exits 1" 1
assert_contains "RV4 --unpushed names the resolved file" "$OUT" "f.txt"
# a clean merge stays clean
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
mb="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s3; stage "$R" s3.txt 'side'; G -C "$R" commit -q -m s3
git -C "$R" checkout -q main; stage "$R" m3.txt 'main'; G -C "$R" commit -q -m m3
G -C "$R" merge -q --no-ff -m 'clean merge' s3 >/dev/null 2>&1
run_in "$R" bash "$LC" scan --range "$mb..HEAD"
assert_rc "RV4 a clean merge: --range exits 0" 0

echo "review 5: masking"
conf_global 'leak_literals=ab12,abcd1234,qrstuvwxy'
newrepo
stage "$R" m.txt 'one ab12 here' 'two abcd1234 here' 'three qrstuvwxy here'
run_in "$R" bash "$LC" scan --staged
assert_rc "RV5 short literals present: exit 1" 1
assert_contains "RV5 the 4-char literal is reported at its line" "$OUT" "m.txt:1: user-literal"
assert_contains "RV5 the 8-char literal is reported at its line" "$OUT" "m.txt:2: user-literal"
assert_contains "RV5 the 9-char literal is reported at its line" "$OUT" "m.txt:3: user-literal"
assert_not_contains "RV5 the 4-char literal ab12 does not appear in the output" "$OUT" "ab12"
assert_not_contains "RV5 an 8-char match shows no characters (no 'abcd')" "$OUT" "abcd"
assert_not_contains "RV5 an 8-char match shows no characters (no '1234')" "$OUT" "1234"
assert_contains "RV5 an 8-char or shorter match is shown only as ***" "$OUT" "***"
assert_contains "RV5 a match longer than 8 chars still shows the first 4 chars then ***" "$OUT" "qrst***"
assert_not_contains "RV5 a longer match is not shown beyond its first 4 chars" "$OUT" "qrstu"
conf_global 'leak_patterns=zq[0-9]{4}'
newrepo
stage "$R" m.txt 'x zq1234 y'
run_in "$R" bash "$LC" scan --staged
assert_not_contains "RV5 a 6-char pattern match shows no characters (no 'zq12')" "$OUT" "zq12"
rm -f "$PH/.agents/playbook.conf"

echo "review 6: the finding count equals the finding lines shown"
nfind() { printf '%s\n' "$OUT" | grep -oE '[0-9]+ finding' | head -n 1 | grep -oE '[0-9]+'; }
nlines() { printf '%s\n' "$OUT" | grep -cE '^[^ ]+:[0-9]+: '; }
newrepo
stage "$R" d.txt "twice $GH and again $GH"
run_in "$R" bash "$LC" scan --staged
assert_rc "RV6 the same token twice on one line: exit 1" 1
assert_eq "RV6 the duplicate is shown once (after dedupe)" "1" "$(nlines)"
assert_eq "RV6 the printed count equals the number of finding lines (1)" "1" "$(nfind)"
newrepo
stage "$R" d.txt "one $GH" 'between' "two $GH" "three $AWS"
run_in "$R" bash "$LC" scan --staged
assert_eq "RV6 three findings on three lines: three finding lines" "3" "$(nlines)"
assert_eq "RV6 the printed count is 3" "3" "$(nfind)"
newrepo
stage "$R" d.txt "tw $GH $GHS"
run_in "$R" bash "$LC" scan --staged
assert_eq "RV6 two different tokens on one line: the printed count equals the lines shown" "$(nlines)" "$(nfind)"

echo "review 7: leak_literals match case-insensitively"
conf_global "leak_literals=$EML"
newrepo
stage "$R" c.txt 'mail Dev@Example.Invalid today'
run_in "$R" bash "$LC" scan --staged
assert_rc "RV7 a literal matches in another letter case: exit 1" 1
assert_contains "RV7 reported as user-literal" "$OUT" "c.txt:1: user-literal"
newrepo
stage "$R" c.txt 'mail DEV@EXAMPLE.INVALID today'
run_in "$R" bash "$LC" scan --staged
assert_rc "RV7 all capitals: exit 1" 1
newrepo
stage "$R" c.txt 'DevXExample.Invalid'
run_in "$R" bash "$LC" scan --staged
assert_rc "RV7 case-insensitive does not make the dot a wildcard: exit 0" 0
rm -f "$PH/.agents/playbook.conf"

echo "v0.23.1 AC10.1 leak_literals: a UTF-8 locale is probed, so non-ASCII literals fold case under LC_ALL=C"
# the literal and the added text are built from bytes (octal escapes): a d-stroke a-dot-below n g, lower and upper case
LIT_LOW="$(printf '\304\221\341\272\267ng')"
LIT_UP="$(printf '\304\220\341\272\266NG')"
NOTE='leak-check: no UTF-8 locale; literal case folding is ASCII-only'
# the same probe as the script's: the first candidate locale where grep -i folds the case of a non-ASCII letter
ERRF="$(mk_tmp)/err"
HAVE_UTF8=0
for cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if printf '\304\220' | LC_ALL="$cand" grep -qiF "$(printf '\304\221')" 2>/dev/null; then HAVE_UTF8=1; break; fi
done
conf_global "leak_literals=$LIT_LOW"
newrepo
stage "$R" l.txt 'x' "name $LIT_UP here"
OUT="$(cd "$R" && LC_ALL=C bash "$LC" scan --staged 2>"$ERRF")"; RC=$?
ERR="$(cat "$ERRF")"
if [ "$HAVE_UTF8" = 1 ]; then
  assert_rc "AC10.1 under LC_ALL=C a UTF-8 locale is found: the literal matches the upper-case text: exit 1" 1
  assert_contains "AC10.1 reported as user-literal at file:line" "$OUT" "l.txt:2: user-literal"
  assert_not_contains "AC10.1 no ASCII-only note when a UTF-8 locale works" "$ERR" "$NOTE"
else
  assert_rc "AC10.1 no UTF-8 locale: ASCII-only folding does not match the upper-case text: exit 0" 0
  assert_contains "AC10.1 no UTF-8 locale: the stderr note says so" "$ERR" "$NOTE"
fi
newrepo
stage "$R" l.txt 'x' "name $LIT_LOW here"
OUT="$(cd "$R" && LC_ALL=C bash "$LC" scan --staged 2>/dev/null)"; RC=$?
assert_rc "AC10.1 the same-case non-ASCII literal always matches (byte match): exit 1" 1
assert_contains "AC10.1 the same-case literal is reported as user-literal" "$OUT" "l.txt:2: user-literal"
# the ASCII-only case folding of the existing literals keeps working under LC_ALL=C
conf_global "leak_literals=$EML"
newrepo
stage "$R" c.txt 'mail DEV@EXAMPLE.INVALID today'
OUT="$(cd "$R" && LC_ALL=C bash "$LC" scan --staged 2>/dev/null)"; RC=$?
assert_rc "AC10.1 an ASCII literal still folds case under LC_ALL=C: exit 1" 1
rm -f "$PH/.agents/playbook.conf"

echo "v0.23.1 AC10.2 scan --unpushed SHA --remote NAME: only the commits on that remote are skipped"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RA="$(mk_tmp)/a.git"; RB="$(mk_tmp)/b.git"
git init -q --bare "$RA"; git init -q --bare "$RB"
git -C "$R" remote add origin "$RA"; git -C "$R" remote add origin2 "$RB"
stage "$R" only-b.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret, pushed to origin2 only'
git -C "$R" push -q origin2 main
SECRET_B="$(git -C "$R" rev-parse HEAD)"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B" --remote origin
assert_rc "AC10.2 a commit pushed only to origin2 is scanned when pushing to origin: exit 1" 1
assert_contains "AC10.2 ... and the finding is named" "$OUT" "only-b.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B" --remote origin2
assert_rc "AC10.2 the same commit is skipped when pushing to origin2 (it is on that remote): exit 0" 0
assert_contains "AC10.2 ... says 'leak-check: clean'" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B"
assert_rc "AC10.2 without --remote the old behaviour holds (any remote counts): exit 0" 0
# and the other way round: a commit on origin only is scanned for origin2; origin does not match origin2
git -C "$R" checkout -q -b other "$SECRET_B"
stage "$R" only-a.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret, pushed to origin only'
git -C "$R" push -q origin other
SECRET_A="$(git -C "$R" rev-parse HEAD)"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_A" --remote origin2
assert_rc "AC10.2 a commit pushed only to origin is scanned when pushing to origin2: exit 1" 1
assert_contains "AC10.2 ... the finding of the origin-only commit is named" "$OUT" "only-a.txt:1: aws-key"
assert_not_contains "AC10.2 ... the commit on origin2 itself is not rescanned" "$OUT" "only-b.txt"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_A" --remote origin
assert_rc "AC10.2 the origin-only commit is skipped when pushing to origin: exit 0" 0
# a NAME that is not a configured remote (a URL push): v0.23.3 AC2 replaced the old "any remote counts" fallback.
# RA is origin's exact url, so origin's refs count. SECRET_B itself is also on origin/other (pushed above, built on it), so a
# fresh commit that ONLY origin2 holds is used here.
git -C "$R" checkout -q -b b2only main
stage "$R" only-b2.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret, pushed to origin2 only (fresh)'
SECRET_B2="$(git -C "$R" rev-parse HEAD)"
git -C "$R" push -q origin2 b2only
assert_eq "AC10.2 fixture: the fresh commit is on origin2 and on no origin ref" "origin2/b2only" "$(git -C "$R" branch -r --contains "$SECRET_B2" | tr -d ' ' | tr '
' ' ' | sed 's/ $//')"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B2" --remote "$RA"
assert_rc "AC10.2 (v0.23.3 AC2) origin's exact URL uses origin's refs: a commit only on origin2 is scanned: exit 1" 1
assert_contains "AC10.2 ... the finding is named" "$OUT" "only-b2.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B" --remote "$RA"
assert_rc "AC10.2 (v0.23.3 AC2) origin's exact URL: SECRET_B is on origin/other, so it is skipped: exit 0" 0
run_in "$R" bash "$LC" scan --unpushed "$SECRET_B2" --remote nosuchremote
assert_rc "AC10.2 (v0.23.3 AC2) an unknown remote name scans the full range: exit 1" 1
assert_contains "AC10.2 ... the finding is named" "$OUT" "only-b2.txt:1: github-token"
git -C "$R" checkout -q -b fresh main
stage "$R" fresh.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret, pushed nowhere'
run_in "$R" bash "$LC" scan --unpushed HEAD --remote "$RA"
assert_rc "AC10.2 a URL push still scans a commit that is on no remote: exit 1" 1
assert_contains "AC10.2 ... the finding is named" "$OUT" "fresh.txt:1: github-token"

echo "v0.23.1 AC10.2 --unpushed usage: SHA plus an optional --remote NAME, anything else exits 2"
run_in "$R" bash "$LC" scan --unpushed
assert_rc "AC10.2 --unpushed alone: exit 2" 2
run_in "$R" bash "$LC" scan --unpushed HEAD --remote
assert_rc "AC10.2 --remote without a NAME: exit 2" 2
run_in "$R" bash "$LC" scan --unpushed HEAD --bogus origin
assert_rc "AC10.2 an unknown option after the SHA: exit 2" 2
run_in "$R" bash "$LC" scan --unpushed HEAD --remote origin extra
assert_rc "AC10.2 a stray word after --remote NAME: exit 2" 2
run_in "$R" bash "$LC" scan --unpushed HEAD --remote origin --remote origin2
assert_rc "AC10.2 --remote given twice: exit 2" 2
run_in "$R" bash "$LC" scan --staged --remote origin
assert_rc "AC10.2 --remote is not accepted with --staged: exit 2" 2
run_in "$R" bash "$LC" scan --range HEAD~1..HEAD --remote origin
assert_rc "AC10.2 --remote is not accepted with --range: exit 2" 2

echo "v0.23.1 AC10.2 the pre-push hook passes the remote name (\$1)"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RA="$(mk_tmp)/a.git"; RB="$(mk_tmp)/b.git"
git init -q --bare "$RA"; git init -q --bare "$RB"
git -C "$R" remote add origin "$RA"; git -C "$R" remote add origin2 "$RB"
git -C "$R" push -q origin main
run_in "$R" bash "$LC" install-hooks
assert_rc "AC10.2 hook setup: install-hooks exit 0" 0
assert_contains "AC10.2 the pre-push hook passes --remote to the scan" "$(cat "$R/.git/hooks/pre-push" 2>/dev/null)" "--remote"
stage "$R" hk.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret'
git -C "$R" push -q --no-verify origin2 main
run_in "$R" git push origin "HEAD:refs/heads/feature"
if [ "$RC" != 0 ]; then t_ok "AC10.2 a new branch pushed to origin is blocked although origin2 holds the secret commit (exit $RC)"; else t_bad "AC10.2 a new branch pushed to origin is blocked although origin2 holds the secret commit" "exit 0; output: $OUT"; fi
assert_contains "AC10.2 the hook shows the finding" "$OUT" "hk.txt:1: github-token"
if git -C "$RA" rev-parse --verify -q refs/heads/feature >/dev/null; then t_bad "AC10.2 the blocked push did not reach origin" "feature is on origin"; else t_ok "AC10.2 the blocked push did not reach origin"; fi
run_in "$R" git push -q origin2 "HEAD:refs/heads/feature"
assert_rc "AC10.2 pushing the same commit to origin2, which holds it already: exit 0" 0
run_in "$R" git push "$RA" "HEAD:refs/heads/viaurl"
# v0.23.3 AC2: RA is origin's exact url; the secret commit is on origin2 only, so it is scanned and the push is blocked
if [ "$RC" != 0 ]; then t_ok "AC10.2 (v0.23.3 AC2) a push to origin's bare URL scans a commit that only origin2 holds: blocked (exit $RC)"; else t_bad "AC10.2 (v0.23.3 AC2) a push to origin's bare URL scans a commit that only origin2 holds: blocked" "exit 0; output: $OUT"; fi
assert_contains "AC10.2 ... the hook shows the finding" "$OUT" "hk.txt:1: github-token"
if git -C "$RA" rev-parse --verify -q refs/heads/viaurl >/dev/null; then t_bad "AC10.2 ... the blocked URL push did not reach origin" "viaurl is on origin"; else t_ok "AC10.2 ... the blocked URL push did not reach origin"; fi

echo "v0.23.1 AC10.3 install-hooks rewrites an old marked hook, and the docs say to re-run it"
newrepo
HOOKS="$R/.git/hooks"; mkdir -p "$HOOKS"
for h in pre-commit pre-push; do
  printf '#!/bin/sh\n%s\n# an old body from a previous version\nOLD_BODY_LINE=1\nexec true\n' "$MARK" > "$HOOKS/$h"
  chmod +x "$HOOKS/$h"
done
run_in "$R" bash "$LC" install-hooks
assert_rc "AC10.3 install-hooks over marked old hooks: exit 0" 0
for h in pre-commit pre-push; do
  assert_not_contains "AC10.3 $h: the old body is gone" "$(cat "$HOOKS/$h" 2>/dev/null)" "OLD_BODY_LINE"
  assert_eq "AC10.3 $h has the marker exactly once" "1" "$(grep -cF "$MARK" "$HOOKS/$h" 2>/dev/null)"
  if [ -x "$HOOKS/$h" ]; then t_ok "AC10.3 $h is executable"; else t_bad "AC10.3 $h is executable" "$(ls -l "$HOOKS/$h" 2>&1)"; fi
done
assert_contains "AC10.3 the rewritten pre-push hook passes --remote" "$(cat "$HOOKS/pre-push" 2>/dev/null)" "--remote"
assert_contains "AC10.3 the rewritten pre-commit hook scans the staged change" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "--staged"
# the 0.23.1 section itself (it was the newest when written; later releases sit above it)
CL_SEC="$(awk '/^## /{p = ($2 == "0.23.1")} p' "$PB_ROOT/CHANGELOG.md" 2>/dev/null)"
case "$CL_SEC" in "## 0.23.1"*) t_ok "AC10.3 the CHANGELOG has a 0.23.1 section" ;; *) t_bad "AC10.3 the CHANGELOG has a 0.23.1 section" "found: $(printf '%s\n' "$CL_SEC" | head -n 1)" ;; esac
if printf '%s\n' "$CL_SEC" | grep -qi 'install-hooks'; then t_ok "AC10.3 the 0.23.1 CHANGELOG section mentions install-hooks"; else t_bad "AC10.3 the 0.23.1 CHANGELOG section mentions install-hooks" "not in the 0.23.1 section"; fi
if printf '%s\n' "$CL_SEC" | grep -qiE 're-?run|again'; then t_ok "AC10.3 the 0.23.1 CHANGELOG section says to re-run it"; else t_bad "AC10.3 the 0.23.1 CHANGELOG section says to re-run it" "no re-run/again wording"; fi
if grep -i 'install-hooks' "$README" 2>/dev/null | grep -qiE 're-?run|again'; then t_ok "AC10.3 README says existing installs re-run install-hooks"; else t_bad "AC10.3 README says existing installs re-run install-hooks" "no README line with install-hooks and re-run/again"; fi

echo "docs"
if grep -q 'leak_literals' "$SETUP_MD" 2>/dev/null; then t_ok "AC1.5 playbook-setup SKILL.md mentions leak_literals"; else t_bad "AC1.5 playbook-setup SKILL.md mentions leak_literals" "not in $SETUP_MD"; fi
if grep -q 'install-hooks' "$SETUP_MD" 2>/dev/null; then t_ok "AC1.5 playbook-setup SKILL.md mentions install-hooks"; else t_bad "AC1.5 playbook-setup SKILL.md mentions install-hooks" "not in $SETUP_MD"; fi
if grep -qi 'leak-check' "$README" 2>/dev/null; then t_ok "AC1.5 README mentions leak-check"; else t_bad "AC1.5 README mentions leak-check" "not in $README"; fi


# ---- v0.23.2 AC1.2: scan --staged refuses a lost executable bit and warns about a new #! file at 100644 ----
echo "v0.23.2 AC1.2 scan --staged: a staged 100755 -> 100644 is refused"
unset PB_ALLOW_MODE_CHANGE
# modrepo -> sets R: a repo whose HEAD has 100755 bin/run.sh and bin/other.sh and a 100644 notes.txt (modes set with
# update-index, so Windows without chmod builds the same repo)
modrepo() {
  newrepo
  ( cd "$R" && mkdir -p bin &&
    printf '#!/bin/sh\necho a\n' > bin/run.sh && cp bin/run.sh bin/other.sh && printf 'plain\n' > notes.txt &&
    chmod +x bin/run.sh bin/other.sh 2>/dev/null
    git add -A && git update-index --chmod=+x -- bin/run.sh bin/other.sh && G commit -q -m "exec scripts" )
}
# scan_streams -> STD (stdout) and ERR (stderr) of `scan --staged` in $R, RC its exit code
scan_streams() {
  local ef; ef="$(mk_tmp)/err"
  STD="$(cd "$R" && env "$@" bash "$LC" scan --staged 2>"$ef")"; RC=$?
  ERR="$(cat "$ef" 2>/dev/null)"
}
MODEMSG="VIOLATION (mode): bin/run.sh lost its executable bit (100755 -> 100644)"
modrepo
assert_eq "AC1.2 fixture: bin/run.sh is committed 100755" "100755" "$(git -C "$R" ls-files -s -- bin/run.sh | cut -d' ' -f1)"
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 a staged mode drop is refused: exit 1" 1
assert_contains "AC1.2 the refusal names the path and both modes" "$OUT" "$MODEMSG"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "AC1.2 PB_ALLOW_MODE_CHANGE=bin/run.sh lets it pass: exit 0" 0
assert_contains "AC1.2 ... and says clean" "$OUT" "leak-check: clean"
run_in "$R" env PB_ALLOW_MODE_CHANGE=docs/a.sh:bin/run.sh:x bash "$LC" scan --staged
assert_rc "AC1.2 a colon list containing the path passes" 0
for bad in bin "bin/*" run.sh "bin/run.sh.bak" "bin/run" "/bin/run.sh" ""; do
  run_in "$R" env PB_ALLOW_MODE_CHANGE="$bad" bash "$LC" scan --staged
  assert_rc "AC1.2 allow entry [$bad] is not an exact match: exit 1" 1
  assert_contains "AC1.2 allow entry [$bad]: the path is still reported" "$OUT" "$MODEMSG"
done
# two drops, one allowed
git -C "$R" update-index --chmod=-x -- bin/other.sh
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "AC1.2 one of two drops allowed: exit 1" 1
assert_contains "AC1.2 the unlisted drop is reported" "$OUT" "VIOLATION (mode): bin/other.sh lost its executable bit (100755 -> 100644)"
assert_not_contains "AC1.2 the listed drop is not reported" "$OUT" "VIOLATION (mode): bin/run.sh"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh:bin/other.sh bash "$LC" scan --staged
assert_rc "AC1.2 both drops allowed: exit 0" 0
# the secret check still runs next to the mode check
stage "$R" cfg.txt "k $GH"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh:bin/other.sh bash "$LC" scan --staged
assert_rc "AC1.2 the allowed mode drop does not hide a secret: exit 1" 1
assert_contains "AC1.2 ... the secret is named" "$OUT" "cfg.txt:1: github-token"
run_in "$R" bash "$LC" scan --staged

echo "v0.23.2 AC1.2 scan --staged: changes that are not a lost executable bit"
modrepo
printf 'changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 a never-executable file edited: exit 0" 0
assert_not_contains "AC1.2 ... no mode violation" "$OUT" "(mode)"
git -C "$R" update-index --chmod=+x -- notes.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 gaining the executable bit (100644 -> 100755): exit 0" 0
assert_not_contains "AC1.2 ... gaining is no mode violation" "$OUT" "(mode)"
modrepo
git -C "$R" rm -q bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 deleting an executable file: exit 0" 0
assert_not_contains "AC1.2 ... deleting is no mode violation" "$OUT" "(mode)"
modrepo
printf '#!/bin/sh\necho ok\n' > "$R/bin/run.sh"; git -C "$R" add bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 an executable file edited and still 100755: exit 0" 0
assert_not_contains "AC1.2 ... no mode violation" "$OUT" "(mode)"

echo "v0.23.2 AC1.2 scan --staged: a new staged #! file at 100644 is a warning, not a refusal"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' 'echo new'
git -C "$R" update-index --chmod=-x -- bin/new.sh
scan_streams
assert_eq "AC1.2 the exit code is unchanged (0)" "0" "$RC"
assert_contains "AC1.2 stdout still says clean" "$STD" "leak-check: clean"
assert_contains "AC1.2 the warning is on stderr and names the path" "$ERR" "bin/new.sh"
assert_contains "AC1.2 the warning says warning" "$(printf '%s' "$ERR" | tr 'A-Z' 'a-z')" "warning"
assert_not_contains "AC1.2 the warning is not on stdout" "$STD" "bin/new.sh"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' 'echo new'
git -C "$R" update-index --chmod=+x -- bin/new.sh
scan_streams
assert_eq "AC1.2 a new #! file at 100755: exit 0" "0" "$RC"
assert_not_contains "AC1.2 a new #! file at 100755: no warning" "$ERR" "bin/new.sh"
modrepo
stage "$R" docs/new.txt 'just text' '#!/bin/sh'
scan_streams
assert_not_contains "AC1.2 a new 100644 file without #! on line 1: no warning" "$ERR" "docs/new.txt"
modrepo
stage "$R" docs/plain.txt 'just text'
scan_streams
assert_not_contains "AC1.2 a new plain file: no warning" "$ERR" "docs/plain.txt"
modrepo
printf '#!/bin/sh\necho changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
scan_streams
assert_not_contains "AC1.2 an existing file that gains a #! line (not newly added): no warning" "$ERR" "notes.txt"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' "token = $GH"
git -C "$R" update-index --chmod=-x -- bin/new.sh
scan_streams
assert_eq "AC1.2 a warning does not hide a secret: exit 1" "1" "$RC"
assert_contains "AC1.2 ... the finding is named" "$STD" "bin/new.sh:2: github-token"

echo "v0.23.2 AC1.2 the installed pre-commit hook is unchanged and still enforces the mode check"
modrepo
HOOKS="$R/.git/hooks"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.2 install-hooks: exit 0" 0
assert_contains "AC1.2 the hook body still ends with 'exec bash \"\$LC\" scan --staged'" "$(tail -n 1 "$HOOKS/pre-commit" 2>/dev/null)" 'exec bash "$LC" scan --staged'
assert_not_contains "AC1.2 the hook body carries no mode logic of its own (100755)" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "100755"
assert_not_contains "AC1.2 the hook body carries no mode logic of its own (ls-files)" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "ls-files"
assert_not_contains "AC1.2 the hook body does not mention PB_ALLOW_MODE_CHANGE" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "PB_ALLOW_MODE_CHANGE"
head1="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'drop the bit'
if [ "$RC" != 0 ]; then t_ok "AC1.2 the installed hook refuses a commit that drops the exec bit (exit $RC)"; else t_bad "AC1.2 the installed hook refuses a commit that drops the exec bit" "exit 0; output: $OUT"; fi
assert_contains "AC1.2 the hook output names the lost bit" "$OUT" "$MODEMSG"
assert_eq "AC1.2 the refused commit was not created" "$head1" "$(git -C "$R" rev-parse HEAD)"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'deliberate'
assert_rc "AC1.2 the environment escape reaches the hook: the commit goes through" 0
assert_eq "AC1.2 the deliberate commit exists" "deliberate" "$(git -C "$R" log -1 --format=%s)"
assert_eq "AC1.2 the committed mode is now 100644" "100644" "$(git -C "$R" ls-files -s -- bin/run.sh | cut -d' ' -f1)"

# ---- v0.23.2 AC7.1: --remote NAME owns the refs of its fetch refspec (longest destination wins) ----
echo "v0.23.2 AC7.1 without a configured remote origin/foo, refs/remotes/origin/foo/x belongs to origin"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RF="$(mk_tmp)/f.git"
git init -q --bare "$RO"; git init -q --bare "$RF"
git -C "$R" remote add origin "$RO"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret on origin/foo/x'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/x "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "AC7.1 origin/foo/x is origin's own branch foo/x: not scanned when pushing to origin: exit 0" 0
assert_contains "AC7.1 ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "AC7.1 without --remote any remote counts: exit 0" 0

echo "v0.23.2 AC7.1 with a configured remote origin/foo, its commits are scanned when pushing to origin"
git -C "$R" update-ref -d refs/remotes/origin/foo/x
git -C "$R" push -q "$RF" sec:main
# newer git refuses `remote add origin/foo` when origin exists ("subset of existing remote"); such remotes still
# exist through config (older git, hand edits), so the fixture writes the config directly
git -C "$R" config remote.origin/foo.url "$RF"
git -C "$R" config remote.origin/foo.fetch '+refs/heads/*:refs/remotes/origin/foo/*'
git -C "$R" update-ref refs/remotes/origin/foo/main "$SEC"
assert_eq "AC7.1 fixture: refs/remotes/origin/foo/main holds the secret commit" "$SEC" "$(git -C "$R" rev-parse --verify -q refs/remotes/origin/foo/main 2>/dev/null)"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "AC7.1 a commit only on remote origin/foo IS scanned when pushing to origin: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin/foo
assert_rc "AC7.1 the same commit is skipped when pushing to origin/foo itself: exit 0" 0
assert_contains "AC7.1 ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "AC7.1 without --remote any remote still counts: exit 0" 0

echo "v0.23.2 AC7.1 the longest matching destination wins (origin's own foo/x counts as origin/foo's)"
git -C "$R" checkout -q -b sec2 main
stage "$R" s2.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret 2'
SEC2="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/x "$SEC2"
run_in "$R" bash "$LC" scan --unpushed "$SEC2" --remote origin
assert_rc "AC7.1 refs/remotes/origin/foo/x belongs to origin/foo now: scanned for origin: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s2.txt:1: aws-key"
run_in "$R" bash "$LC" scan --unpushed "$SEC2" --remote origin/foo
assert_rc "AC7.1 ... and skipped for origin/foo: exit 0" 0
git -C "$R" checkout -q -b sec3 main
stage "$R" s3.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret 3'
SEC3="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$SEC3"
run_in "$R" bash "$LC" scan --unpushed "$SEC3" --remote origin
assert_rc "AC7.1 an ordinary origin ref (origin/main) is still skipped for origin: exit 0" 0
run_in "$R" bash "$LC" scan --unpushed "$SEC3" --remote origin/foo
assert_rc "AC7.1 ... and scanned for origin/foo: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s3.txt:1: github-token"

echo "v0.23.2 AC7.1 the help states the consequence"
run_in "$R" bash "$LC" scan
assert_rc "AC7.1 no scan arguments: usage, exit 2" 2
assert_contains "AC7.1 the usage text names the origin/foo case" "$OUT" "origin/foo"
assert_contains "AC7.1 the usage text says the nested ref is scanned too" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "scanned"


# ---- v0.23.2 fix round (lane A): bounded argv, implicit remote ownership, renamed and odd-named mode drops ----
# gitshim DIR -> DIR/git, a wrapper that logs every call. GIT_SHIM_LOG gets one line per call: "<argc> <subcommand-ish first word>".
# GIT_SHIM_MAXARGS (when set) makes a call with more arguments fail like a too-long command line (exit 126).
gitshim() {
  local real; real="$(command -v git)"
  mkdir -p "$1"
  cat > "$1/git" <<SHIM
#!/bin/sh
echo "\$# \$1" >> "\${GIT_SHIM_LOG:-/dev/null}"
if [ -n "\${GIT_SHIM_MAXARGS:-}" ] && [ "\$#" -gt "\$GIT_SHIM_MAXARGS" ]; then
  echo "shim: Argument list too long" >&2
  exit 126
fi
exec "$real" "\$@"
SHIM
  chmod +x "$1/git"
}
# shim_max LOG -> the largest argc in the log
shim_max() { awk 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { print m }' "$1"; }
SHIMD="$(mk_tmp)/shim"; gitshim "$SHIMD"

echo "v0.23.2 fix MAJOR-1 scan --unpushed SHA --remote NAME with ~1200 remote refs keeps the command line bounded"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; git init -q --bare "$RO"
git -C "$R" remote add origin "$RO"
BASE_SHA="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'local only secret'
SEC="$(git -C "$R" rev-parse HEAD)"
UR="$(mk_tmp)/refs.txt"
awk -v s="$BASE_SHA" 'BEGIN { for (i = 1; i <= 1200; i++) printf "create refs/remotes/origin/feature/some-long-branch-name-%d %s\n", i, s }' > "$UR"
git -C "$R" update-ref --stdin < "$UR"
assert_eq "MAJOR-1 fixture: 1200 long remote refs exist" "1200" "$(git -C "$R" for-each-ref refs/remotes/origin/feature | wc -l | tr -d ' ')"
# v0.23.3 AC1b: 1200 refs are enough: as one command line they are longer than the 32768 characters of a Windows command line
REFCHARS="$(git -C "$R" for-each-ref --format='%(refname)' refs/remotes/origin/feature | awk '{ n += length($0) + 1 } END { print n + 0 }')"
assert_eq "MAJOR-1 fixture: the 1200 ref names alone are over 32768 characters on a command line (computed: ${REFCHARS})" "ok" "$([ "$REFCHARS" -gt 32768 ] && echo ok || echo "only $REFCHARS")"
SLOG="$(mk_tmp)/shim.log"; : > "$SLOG"
run_in "$R" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOG" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-1 a local-only secret is found with 1200 remote refs: exit 1 (not 3)" 1
assert_contains "MAJOR-1 ... the finding is named" "$OUT" "s.txt:1: github-token"
assert_not_contains "MAJOR-1 ... no 'git log failed'" "$OUT" "git log failed"
assert_eq "MAJOR-1 no git call gets more than 50 arguments (Windows has a 32K command line)" "ok" "$([ "$(shim_max "$SLOG")" -le 50 ] && echo ok || echo "max argc $(shim_max "$SLOG")")"
: > "$SLOG"
run_in "$R" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOG" GIT_SHIM_MAXARGS=1000 bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-1 with a 1000-argument limit on git calls the secret is still found: exit 1" 1
assert_not_contains "MAJOR-1 ... no 'git log failed' under the limit" "$OUT" "git log failed"
# a commit that IS on a ref of origin is still skipped
run_in "$R" bash "$LC" scan --unpushed "$BASE_SHA" --remote origin
assert_rc "MAJOR-1 a commit on one of the 1200 refs is skipped: exit 0" 0

echo "v0.23.2 fix MAJOR-2a a remote without a fetch line still owns refs/remotes/NAME/*"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RF="$(mk_tmp)/f.git"; git init -q --bare "$RO"; git init -q --bare "$RF"
git -C "$R" remote add origin "$RO"
# newer git refuses `remote add origin/foo` when origin exists ("subset of existing remote"); such remotes still
# exist through config (older git, hand edits), so the fixture writes the config directly
git -C "$R" config remote.origin/foo.url "$RF"
git -C "$R" config remote.origin/foo.fetch '+refs/heads/*:refs/remotes/origin/foo/*'
git -C "$R" config --unset remote.origin/foo.fetch
assert_eq "MAJOR-2a fixture: origin/foo has no fetch line" "" "$(git -C "$R" config --get-all remote.origin/foo.fetch)"
assert_contains "MAJOR-2a fixture: origin keeps its standard fetch line" "$(git -C "$R" config --get-all remote.origin.fetch)" "refs/remotes/origin/*"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret only on origin/foo/main'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/main "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-2a a commit only on fetch-less remote origin/foo IS scanned when pushing to origin: exit 1" 1
assert_contains "MAJOR-2a ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin/foo
assert_rc "MAJOR-2a ... and skipped when pushing to origin/foo itself (MAJOR-2c): exit 0" 0
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "MAJOR-2a without --remote any remote counts: exit 0" 0

echo "v0.23.2 fix MAJOR-2a variant: remote o owns refs/remotes/o*, remote o2 has no fetch line"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; R2="$(mk_tmp)/o2.git"; git init -q --bare "$RO"; git init -q --bare "$R2"
git -C "$R" remote add o "$RO"
git -C "$R" config --replace-all remote.o.fetch '+refs/heads/*:refs/remotes/o*'
git -C "$R" remote add o2 "$R2"
git -C "$R" config --unset remote.o2.fetch
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret only on o2/main'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/o2/main "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote o
assert_rc "MAJOR-2a variant: a commit only on fetch-less remote o2 IS scanned when pushing to o: exit 1" 1
assert_contains "MAJOR-2a variant: ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote o2
assert_rc "MAJOR-2a variant: ... and skipped when pushing to o2: exit 0" 0

echo "v0.23.2 fix MAJOR-2b a tie between two remotes: the ref is scanned when pushing to either, in either config order"
for order in "ta tb" "tb ta"; do
  newrepo
  git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
  for rn in $order; do
    RT="$(mk_tmp)/$rn.git"; git init -q --bare "$RT"
    git -C "$R" remote add "$rn" "$RT"
    git -C "$R" config --replace-all "remote.$rn.fetch" '+refs/heads/*:refs/remotes/shared/*'
  done
  git -C "$R" checkout -q -b sec
  stage "$R" s.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret on the tied ref'
  SEC="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" update-ref refs/remotes/shared/main "$SEC"
  run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote ta
  assert_rc "MAJOR-2b order [$order]: scanned when pushing to ta: exit 1" 1
  assert_contains "MAJOR-2b order [$order]: ta: the finding is named" "$OUT" "s.txt:1: aws-key"
  run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote tb
  assert_rc "MAJOR-2b order [$order]: scanned when pushing to tb: exit 1" 1
  assert_contains "MAJOR-2b order [$order]: tb: the finding is named" "$OUT" "s.txt:1: aws-key"
done

echo "v0.23.2 fix MAJOR-2c a fetch-less remote owns refs/remotes/NAME/*: its commits are not re-scanned when pushing to it"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RN="$(mk_tmp)/n.git"; git init -q --bare "$RO"; git init -q --bare "$RN"
git -C "$R" remote add origin "$RO"
git -C "$R" remote add nofetch "$RN"
git -C "$R" config --unset remote.nofetch.fetch
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $ANT"; G -C "$R" commit -q --no-verify -m 'secret on nofetch/x'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/nofetch/x "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote nofetch
assert_rc "MAJOR-2c a commit already on refs/remotes/nofetch/x is skipped when pushing to nofetch: exit 0" 0
assert_contains "MAJOR-2c ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-2c ... but scanned when pushing to origin (not its ref): exit 1" 1

echo "v0.23.2 fix MINOR-5 a rename plus a mode drop is a lost executable bit (scan --staged)"
modrepo
git -C "$R" mv bin/run.sh bin/renamed.sh
chmod -x "$R/bin/renamed.sh" 2>/dev/null; git -C "$R" update-index --chmod=-x -- bin/renamed.sh
assert_eq "MINOR-5 fixture: bin/renamed.sh is staged 100644" "100644" "$(git -C "$R" ls-files -s -- bin/renamed.sh | cut -d' ' -f1)"
RENMSG="VIOLATION (mode): bin/renamed.sh lost its executable bit (100755 -> 100644)"
run_in "$R" bash "$LC" scan --staged
assert_rc "MINOR-5 rename + drop is refused: exit 1" 1
assert_contains "MINOR-5 the NEW path is named with both modes" "$OUT" "$RENMSG"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/renamed.sh bash "$LC" scan --staged
assert_rc "MINOR-5 PB_ALLOW_MODE_CHANGE with the new path lets it pass: exit 0" 0
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "MINOR-5 listing the OLD path does not let it pass: exit 1" 1
assert_contains "MINOR-5 ... the new path is still named" "$OUT" "$RENMSG"
modrepo
git -C "$R" rm -q bin/run.sh
stage "$R" bin/unrelated.sh '#!/bin/sh' 'echo different'
git -C "$R" update-index --chmod=-x -- bin/unrelated.sh
run_in "$R" bash "$LC" scan --staged
assert_not_contains "MINOR-5 a deleted 100755 path plus a 100644 path with a DIFFERENT blob is no mode violation" "$OUT" "(mode)"

echo "v0.23.2 fix LOW-6 paths with a double quote or a tab are reported with their real name and can be allowed"
modrepo
QP='bin/we"ird.sh'
TP="$(printf 'bin/ta\tb.sh')"
for P in "$QP" "$TP"; do
  if ( cd "$R" && cp bin/run.sh "$P" && git add -- "$P" ) 2>/dev/null && [ -f "$R/$P" ] && [ -n "$(git -C "$R" ls-files -- "$P")" ]; then
    ( cd "$R" && git update-index --chmod=+x -- "$P" && G commit -q -m "add odd name" )
    git -C "$R" update-index --chmod=-x -- "$P"
    run_in "$R" bash "$LC" scan --staged
    assert_rc "LOW-6 [$P] mode drop is refused: exit 1" 1
    assert_contains "LOW-6 [$P] the real path is printed unquoted" "$OUT" "VIOLATION (mode): $P lost its executable bit (100755 -> 100644)"
    run_in "$R" env PB_ALLOW_MODE_CHANGE="$P" bash "$LC" scan --staged
    assert_rc "LOW-6 [$P] PB_ALLOW_MODE_CHANGE with the real path lets it pass: exit 0" 0
    git -C "$R" update-index --chmod=+x -- "$P"
  else rm -f -- "$R/$P" 2>/dev/null; t_skip 3 "LOW-6 path [$P] (this file system or git refuses the name)"; fi
done
run_in "$R" bash "$LC" scan
assert_rc "LOW-6 usage: exit 2" 2
assert_contains "LOW-6 the usage says a path with a colon cannot be listed in PB_ALLOW_MODE_CHANGE" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "cannot be listed"

echo "v0.23.2 fix LOW-7 a secret and a mode violation together: the summary counts both"
modrepo
git -C "$R" update-index --chmod=-x -- bin/run.sh
stage "$R" cfg.txt "k $GH"
run_in "$R" bash "$LC" scan --staged
assert_rc "LOW-7 secret + mode drop: exit 1" 1
assert_contains "LOW-7 the summary has the finding count" "$OUT" "1 finding(s)"
assert_contains "LOW-7 the summary has the mode violation count" "$OUT" "1 mode violation(s)"
assert_contains "LOW-7 the mode violation line is printed" "$OUT" "$MODEMSG"
assert_contains "LOW-7 the finding line is printed" "$OUT" "cfg.txt:1: github-token"
modrepo
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_contains "LOW-7 mode only: the summary still says 'no secret found'" "$OUT" "1 mode violation(s); no secret found"

echo "v0.23.2 fix MINOR-4 scan --staged does not run one git process per new staged file"
NF=1000
# mkmany DIR MODEFLAG -> DIR gets NF new files (#! first line) staged; MODEFLAG x makes them 100755
mkmany() {
  local d="$1" x="$2"
  mkdir -p "$d/gen"
  awk -v d="$d/gen" 'BEGIN { for (i = 1; i <= '"$NF"'; i++) { f = d "/f" i ".sh"; printf "#!/bin/sh\necho %d\n", i > f; close(f) } }'
  [ "$x" != x ] || chmod +x "$d"/gen/*.sh 2>/dev/null
  git -C "$d" add -A
}
# nsecs REPO LOG -> seconds the scan takes (stdout) ; LOG gets the git shim log
newrepo; RX="$R"; mkmany "$RX" x
newrepo; RN="$R"; mkmany "$RN" n
XMODES="$(git -C "$RX" ls-files -s -- gen | cut -c1-6 | sort -u | tr '\n' ' ')"
NMODES="$(git -C "$RN" ls-files -s -- gen | cut -c1-6 | sort -u | tr '\n' ' ')"
if [ "$XMODES" != "100755 " ] || [ "$NMODES" != "100644 " ]; then
  t_skip 7 "MINOR-4 (cannot stage 100755 / 100644 files here: [$XMODES] [$NMODES])"
else
  T0="$(date +%s)"; run_in "$RX" bash "$LC" scan --staged; XRC="$RC"; T1="$(date +%s)"
  run_in "$RN" bash "$LC" scan --staged; NRC="$RC"; T2="$(date +%s)"
  XT=$((T1 - T0)); NT=$((T2 - T1))
  assert_eq "MINOR-4 baseline (1000 new 100755 files) is clean: exit 0" "0" "$XRC"
  assert_eq "MINOR-4 1000 new 100644 #! files are clean (a warning only): exit 0" "0" "$NRC"
  assert_eq "MINOR-4 the 100644 scan takes under baseline + 10 s (baseline ${XT}s, took ${NT}s)" "ok" "$([ "$NT" -lt $((XT + 10)) ] && echo ok || echo "slow: ${NT}s vs baseline ${XT}s")"
  SLOGX="$(mk_tmp)/x.log"; SLOGN="$(mk_tmp)/n.log"; : > "$SLOGX"; : > "$SLOGN"
  run_in "$RX" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOGX" bash "$LC" scan --staged
  run_in "$RN" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOGN" bash "$LC" scan --staged
  assert_eq "MINOR-4 baseline: at most 10 git processes for 1000 new files" "ok" "$([ "$(wc -l < "$SLOGX" | tr -d ' ')" -le 10 ] && echo ok || echo "$(wc -l < "$SLOGX" | tr -d ' ') git calls")"
  assert_eq "MINOR-4 at most 10 git processes for 1000 new 100644 files (not one per file)" "ok" "$([ "$(wc -l < "$SLOGN" | tr -d ' ')" -le 10 ] && echo ok || echo "$(wc -l < "$SLOGN" | tr -d ' ') git calls")"
  assert_contains "MINOR-4 the #! warning is still printed for the 100644 files" "$OUT" "gen/f1.sh"
  assert_eq "MINOR-A all $NF new 100644 #! files are warned about, one line each" "$NF" "$(printf '%s\n' "$OUT" | grep -c 'warning: new file .* starts with #! ')"
fi

echo "v0.23.2 round 2 MINOR-A the one-pass #! warning keeps its byte count across a mixed batch"
# every blob's size decides where the next header starts: plain files with and without a trailing newline, an empty one,
# a CRLF #! file, a #! file right after an empty one, a #! file with no trailing newline, and a #! file last in the batch
newrepo
mkdir -p "$R/mix"
printf 'plain text\nsecond line\n' > "$R/mix/a01_plain.txt"
printf 'no trailing newline' > "$R/mix/a02_nonl.txt"
: > "$R/mix/a03_empty.txt"
printf '#!/bin/sh\r\necho crlf\r\n' > "$R/mix/a04_crlf.sh"
: > "$R/mix/a05_empty.txt"
printf '#!/bin/sh\necho after-empty\n' > "$R/mix/a06_after_empty.sh"
printf '#!/bin/sh' > "$R/mix/a07_shebang_nonl.sh"
printf 'x\n\n\n' > "$R/mix/a08_blank_lines.txt"
printf 'x\n#!/bin/sh\n' > "$R/mix/a09_shebang_on_line2.txt"
printf '#!/bin/sh\necho last\n' > "$R/mix/a10_last.sh"
git -C "$R" add -A
MIXMODES="$(git -C "$R" ls-files -s -- mix | cut -c1-6 | sort -u | tr '\n' ' ')"
scan_streams
assert_eq "MINOR-A fixture: all ten files are staged 100644" "100644 " "$MIXMODES"
assert_eq "MINOR-A the exit code is 0 (warnings only)" "0" "$RC"
WARNED="$(printf '%s\n' "$ERR" | grep 'warning: new file ' | sed 's/^.*warning: new file \(.*\) starts with #! .*$/\1/' | LC_ALL=C sort)"
WANT="$(printf '%s\n' mix/a04_crlf.sh mix/a06_after_empty.sh mix/a07_shebang_nonl.sh mix/a10_last.sh)"
assert_eq "MINOR-A exactly the four #! files are warned about (no other file, none missed)" "$WANT" "$WARNED"
assert_eq "MINOR-A four warning lines" "4" "$(printf '%s\n' "$ERR" | grep -c 'warning: new file ')"

echo "v0.23.2 round 2 LOW-a an empty executable deleted and an empty 644 file added is not a rename"
newrepo
: > "$R/keep.sh"; chmod +x "$R/keep.sh" 2>/dev/null
git -C "$R" add keep.sh; git -C "$R" update-index --chmod=+x -- keep.sh; G -C "$R" commit -q -m "empty exec"
assert_eq "LOW-a fixture: keep.sh is committed 100755" "100755" "$(git -C "$R" ls-files -s -- keep.sh | cut -d' ' -f1)"
git -C "$R" rm -q keep.sh
mkdir -p "$R/pkg"; : > "$R/pkg/__init__.py"; git -C "$R" add pkg/__init__.py
assert_eq "LOW-a fixture: pkg/__init__.py is staged 100644" "100644" "$(git -C "$R" ls-files -s -- pkg/__init__.py | cut -d' ' -f1)"
run_in "$R" bash "$LC" scan --staged
assert_rc "LOW-a deleting an empty 100755 file and adding an empty 100644 file: exit 0" 0
assert_not_contains "LOW-a ... no mode violation" "$OUT" "(mode)"

echo "v0.23.2 round 2 LOW-b the usage describes rename detection as a rename with unchanged content"
run_in "$R" bash "$LC" scan
USAGE_FLAT="$(printf '%s' "$OUT" | tr 'A-Z' 'a-z' | tr -s ' \n\t' '   ')"
assert_contains "LOW-b the usage says 'a rename with unchanged content'" "$USAGE_FLAT" "a rename with unchanged content"

# ---- v0.23.3 lane A (tester): AC2 (R2) URL pushes, AC3 (R3) the mode check fails closed, AC11 (R10) no awk multibyte noise ----
# lc_streams ARGS... -> STD (stdout), ERR (stderr) and RC of `leak-check scan ARGS` run in $R
lc_streams() {
  local ef; ef="$(mk_tmp)/err"
  STD="$(cd "$R" && bash "$LC" scan "$@" 2>"$ef")"; RC=$?
  ERR="$(cat "$ef" 2>/dev/null)"
}
# note_for NAME -> the stderr note a scan with a NAME that is not a configured remote must print (R2)
note_for() { printf 'leak-check: %s is not a configured remote; scanning the full range (push through a named remote to limit it)' "$1"; }

echo "v0.23.3 AC2 (R2) a push to a new URL scans the full range"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
U_A="$(mk_tmp)/a.git"; U_B="$(mk_tmp)/b.git"; U_NEW="$(mk_tmp)/new.git"
git -C "$R" remote add origin "$U_A"; git -C "$R" remote add up "$U_B"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held only by remote up'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/up/main "$SEC"
assert_eq "AC2 fixture: refs/remotes/up/main holds the secret commit" "$SEC" "$(git -C "$R" rev-parse --verify -q refs/remotes/up/main)"
lc_streams --unpushed "$SEC" --remote "$U_NEW"
assert_eq "AC2 a commit only on refs/remotes/up/main, pushed to a NEW url: scanned, exit 1" "1" "$RC"
assert_contains "AC2 ... the finding is named on stdout" "$STD" "s.txt:1: github-token"
assert_contains "AC2 ... stderr carries the note (NAME is not a configured remote; scanning the full range)" "$ERR" "$(note_for "$U_NEW")"
lc_streams --unpushed "$SEC" --remote nosuchremote
assert_eq "AC2 an unknown NAME: scanned, exit 1" "1" "$RC"
assert_contains "AC2 an unknown NAME: the note names it" "$ERR" "$(note_for nosuchremote)"
lc_streams --unpushed "$SEC"
assert_eq "AC2.2 without --remote any remote counts (unchanged): exit 0" "0" "$RC"
assert_not_contains "AC2.2 without --remote there is no note" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote up
assert_eq "AC2 a configured remote NAME keeps its own refs: up holds the commit: exit 0" "0" "$RC"
assert_not_contains "AC2 a configured remote NAME prints no note" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote origin
assert_eq "AC2 a configured remote NAME: origin does not hold it: exit 1" "1" "$RC"
assert_not_contains "AC2 ... and no note either" "$ERR" "is not a configured remote"

echo "v0.23.3 AC2 (R2) NAME equal to a configured remote's exact url uses that remote's refs"
git -C "$R" update-ref -d refs/remotes/up/main
git -C "$R" update-ref refs/remotes/origin/main "$SEC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 a commit on refs/remotes/origin/* pushed to origin's exact url: skipped, exit 0" "0" "$RC"
assert_contains "AC2 ... says clean" "$STD" "leak-check: clean"
assert_not_contains "AC2 ... no note (the url belongs to a configured remote)" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote "$U_B"
assert_eq "AC2 the url of up (which holds nothing): the commit is scanned, exit 1" "1" "$RC"
assert_not_contains "AC2 ... and the url of a configured remote prints no note" "$ERR" "is not a configured remote"
git -C "$R" config remote.origin.pushurl "$U_A"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 a pushurl equal to the url is the same place: still skipped, exit 0" "0" "$RC"
U_P="$(mk_tmp)/push.git"
git -C "$R" config remote.origin.pushurl "$U_P"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 the same push when origin's pushurl differs: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... the finding is named" "$STD" "s.txt:1: github-token"
lc_streams --unpushed "$SEC" --remote "$U_P"
assert_eq "AC2 NAME equal to the differing pushurl: full scan, exit 1" "1" "$RC"
git -C "$R" config --unset remote.origin.pushurl
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 fixture check: with the pushurl removed origin's exact url is skipped again: exit 0" "0" "$RC"

echo "v0.23.3 AC2 (R2) a second url value, and insteadOf, name the same place"
DIR_A="$(dirname "$U_A")"
git -C "$R" config "url.$DIR_A/.insteadOf" 'short:'
git -C "$R" config --add remote.origin.url 'short:a.git'
assert_eq "AC2 fixture: origin has two url values" "2" "$(git -C "$R" config --get-all remote.origin.url | wc -l | tr -d ' ')"
lc_streams --unpushed "$SEC" --remote 'short:a.git'
assert_eq "AC2 NAME equal to the SECOND url value (both expand to the same place): origin's refs, exit 0" "0" "$RC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 NAME equal to the first url value with a second value present: exit 0" "0" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
lc_streams --unpushed "$SEC" --remote 'short:a.git'
assert_eq "AC2 an insteadOf form of origin's url (git ls-remote --get-url): origin's refs, exit 0" "0" "$RC"
assert_not_contains "AC2 ... no note" "$ERR" "is not a configured remote"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url 'short:a.git'
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 origin configured through insteadOf, NAME is the expanded url: exit 0" "0" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
git -C "$R" config --add remote.origin.url "$U_B"
lc_streams --unpushed "$SEC" --remote "$U_B"
assert_eq "AC2 a second url value that names ANOTHER place: not every value is the same place: full scan, exit 1" "1" "$RC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 ... also for the first value: full scan, exit 1" "1" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
git -C "$R" config --unset "url.$DIR_A/.insteadOf"

echo "v0.23.3 AC2 (R2) a trailing .git or / is not normalized: the safe side is the full scan"
lc_streams --unpushed "$SEC" --remote "${U_A%.git}"
assert_eq "AC2 origin's url without its trailing .git: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... with the note" "$ERR" "$(note_for "${U_A%.git}")"
lc_streams --unpushed "$SEC" --remote "$U_A/"
assert_eq "AC2 origin's url plus a trailing /: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... with the note" "$ERR" "$(note_for "$U_A/")"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 the exact url is skipped as before: exit 0" "0" "$RC"

echo "v0.23.3 AC2 (R2) several remotes with the same url: the union of their refs counts"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
BASE3="$(git -C "$R" rev-parse HEAD)"
U_S="$(mk_tmp)/shared.git"; U_O="$(mk_tmp)/other.git"
git -C "$R" remote add r1 "$U_S"; git -C "$R" remote add r2 "$U_S"; git -C "$R" remote add r3 "$U_O"
git -C "$R" checkout -q -b s1 "$BASE3"
stage "$R" one.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret one (r1)'
S1="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s2 "$BASE3"
stage "$R" two.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret two (r2)'
S2="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s3 "$BASE3"
stage "$R" three.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret three (r3)'
S3="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/r1/main "$S1"
git -C "$R" update-ref refs/remotes/r2/main "$S2"
git -C "$R" update-ref refs/remotes/r3/main "$S3"
git -C "$R" checkout -q -b top "$BASE3"
git -C "$R" merge -q --no-edit -m 'octopus of the three' s1 s2 s3 >/dev/null 2>&1 || echo "fixture: octopus merge failed"
TOP="$(git -C "$R" rev-parse HEAD)"
lc_streams --unpushed "$TOP" --remote "$U_S"
assert_eq "AC2 the url shared by r1 and r2: the commits on r1/* and r2/* are skipped, the one on r3 is scanned: exit 1" "1" "$RC"
assert_contains "AC2 ... r3's secret is named" "$STD" "three.txt:1: github-token"
assert_not_contains "AC2 ... r1's commit (union) is not scanned" "$STD" "one.txt"
assert_not_contains "AC2 ... r2's commit (union) is not scanned" "$STD" "two.txt"
assert_not_contains "AC2 ... no note for a configured url" "$ERR" "is not a configured remote"

echo "v0.23.3 AC2 the usage still describes --remote, and the pre-push hook passes a URL through unchanged"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
HU_A="$(mk_tmp)/a.git"; HU_B="$(mk_tmp)/b.git"; HU_NEW="$(mk_tmp)/n.git"
git init -q --bare "$HU_A"; git init -q --bare "$HU_B"; git init -q --bare "$HU_NEW"
git -C "$R" remote add up "$HU_B"; git -C "$R" push -q up main
run_in "$R" bash "$LC" install-hooks
stage "$R" hk.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret'
git -C "$R" push -q --no-verify up "HEAD:refs/heads/held"
run_in "$R" git push "$HU_NEW" "HEAD:refs/heads/viaurl"
if [ "$RC" != 0 ]; then t_ok "AC2 a hook push of a commit that only remote up holds to a NEW bare url is blocked (exit $RC)"; else t_bad "AC2 a hook push of a commit that only remote up holds to a NEW bare url is blocked" "exit 0; output: $OUT"; fi
assert_contains "AC2 ... the hook shows the finding" "$OUT" "hk.txt:1: github-token"
if git -C "$HU_NEW" rev-parse --verify -q refs/heads/viaurl >/dev/null; then t_bad "AC2 ... the blocked push did not reach the new url" "viaurl exists"; else t_ok "AC2 ... the blocked push did not reach the new url"; fi

# ---- AC3 (R3): the mode check never fails open (leak-check side) ----
echo "v0.23.3 AC3.2 (R3) scan --staged: a path with a newline fails closed, with no escape"
modrepo
NLP="$(printf 'bin/new\nline.sh')"
if printf '#!/bin/sh\n' > "$R/$NLP" 2>/dev/null && [ -f "$R/$NLP" ] && git -C "$R" add -- "$NLP" 2>/dev/null && git -C "$R" ls-files --error-unmatch -- "$NLP" >/dev/null 2>&1; then
  NLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  scan_streams
  assert_eq "AC3.2 a staged path with a newline: exit 1" "1" "$RC"
  assert_contains "AC3.2 the refusal says the path contains a newline and the check is incomplete" "$STD$ERR" "$NLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="$NLP"
  assert_eq "AC3.2 PB_ALLOW_MODE_CHANGE with the whole path is no escape: exit 1" "1" "$RC"
  assert_contains "AC3.2 ... the message is still printed" "$STD$ERR" "$NLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="bin/new:line.sh:bin/new
line.sh"
  assert_eq "AC3.2 PB_ALLOW_MODE_CHANGE with the pieces is no escape either: exit 1" "1" "$RC"
  git -C "$R" rm -q --cached -f -- "$NLP"; rm -f "$R/$NLP"
  scan_streams
  assert_eq "AC3.2 after the path is gone the scan is clean again: exit 0" "0" "$RC"
else rm -f "$R/$NLP" 2>/dev/null; t_skip 6 "AC3.2 newline path (this file system or git refuses the name)"; fi

echo "v0.23.3 AC3.3 (R3) scan --staged: a failing raw diff makes the mode check fail closed"
modrepo
printf 'changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
RAWSHIM="$(mk_tmp)/rawshim"; mkdir -p "$RAWSHIM"
REALGIT="$(command -v git)"
cat > "$RAWSHIM/git" <<SHIM
#!/bin/sh
# fails like a broken clean filter on every "diff --raw" call, runs the real git otherwise
for a in "\$@"; do
  case "\$a" in --raw) echo "shim: git diff --raw failed" >&2; exit 128 ;; esac
done
exec "$REALGIT" "\$@"
SHIM
chmod +x "$RAWSHIM/git"
scan_streams
assert_eq "AC3.3 fixture: without the shim the scan is clean: exit 0" "0" "$RC"
scan_streams PATH="$RAWSHIM:$PATH"
assert_eq "AC3.3 pb_raw_lines fails (shim): the mode check fails closed, exit 1" "1" "$RC"
assert_contains "AC3.3 ... the output says VIOLATION (mode)" "$STD$ERR" "VIOLATION (mode)"
assert_contains "AC3.3 ... and that the mode check is incomplete" "$STD$ERR" "the mode check is incomplete"
assert_not_contains "AC3.3 ... and does not say clean" "$STD" "leak-check: clean"
scan_streams PATH="$RAWSHIM:$PATH" PB_ALLOW_MODE_CHANGE=notes.txt
assert_eq "AC3.3 PB_ALLOW_MODE_CHANGE does not turn the failure off: exit 1" "1" "$RC"

# ---- AC11 (R10): gawk under a UTF-8 locale prints nothing for invalid bytes; the masking stays per character ----
echo "v0.23.3 AC11 (R10) gawk + UTF-8 locale: invalid UTF-8 in a diff prints nothing on stderr, the findings are unchanged"
GAWK="$(command -v gawk 2>/dev/null)" || GAWK=""
UCAND=""
if [ -n "$GAWK" ]; then
  # a UTF-8 locale where gawk counts characters (so it also complains about invalid bytes)
  for cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if [ "$(LC_ALL="$cand" "$GAWK" 'BEGIN { print length("\303\251") }' 2>/dev/null)" = 1 ]; then UCAND="$cand"; break; fi
  done
fi
if [ -z "$GAWK" ] || [ -z "$UCAND" ]; then
  t_skip 6 "AC11 gawk under a UTF-8 locale (gawk: [${GAWK:-missing}], locale: [${UCAND:-none}])"
else
  GAWKD="$(mk_tmp)/gawkbin"; mkdir -p "$GAWKD"
  ln -s "$GAWK" "$GAWKD/awk" 2>/dev/null && [ -x "$GAWKD/awk" ] || { rm -f "$GAWKD/awk"; cp "$GAWK" "$GAWKD/awk" 2>/dev/null; chmod +x "$GAWKD/awk" 2>/dev/null; }
  newrepo
  mkdir -p "$R/bin"
  printf 'bad bytes \377\376 and \300\257 here\n%s\nlast line\n' "k $GH" > "$R/bin/inv.txt"
  git -C "$R" add -- bin/inv.txt
  U8E="$(mk_tmp)/err"
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>"$U8E")"; U8RC=$?
  U8ERR="$(grep -v 'LF will be replaced by CRLF' "$U8E" 2>/dev/null)"
  assert_eq "AC11 invalid bytes next to a secret: exit 1 (the finding is unchanged)" "1" "$U8RC"
  assert_contains "AC11 ... the secret is found on its line" "$U8OUT" "bin/inv.txt:2: github-token"
  assert_not_contains "AC11 ... stderr has no 'Invalid multibyte data' warning" "$U8ERR" "multibyte"
  assert_eq "AC11 ... stderr is empty" "" "$U8ERR"
  # the same scan with a clean file: still nothing on stderr
  newrepo
  mkdir -p "$R/bin"; printf 'bad bytes \377\376 only\n' > "$R/bin/inv.txt"; git -C "$R" add -- bin/inv.txt
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>"$U8E")"; U8RC=$?
  U8ERR="$(grep -v 'LF will be replaced by CRLF' "$U8E" 2>/dev/null)"
  assert_eq "AC11 invalid bytes and no secret: exit 0" "0" "$U8RC"
  assert_eq "AC11 ... stderr is empty" "" "$U8ERR"
fi

echo "v0.23.3 AC11 (R10) the masking awk keeps the user locale: per-character masking of multibyte text (gawk, UTF-8)"
if [ -z "$GAWK" ] || [ -z "$UCAND" ]; then
  t_skip 6 "AC11 multibyte masking (gawk: [${GAWK:-missing}], locale: [${UCAND:-none}])"
else
  E1="$(printf '\303\251')"   # one letter, two bytes
  E2="$(printf '\303\274')"   # another one
  LIT7="$E1$E1$E1$E1$E1$E1$E1"
  LIT10="$E2$E2$E2$E2$E2$E2$E2$E2$E2$E2"
  conf_global "leak_literals=$LIT7,${LIT10}x"
  newrepo
  stage "$R" mb.txt "one ${LIT7} here" "two ${LIT10}x here"
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>/dev/null)"; U8RC=$?
  L1="$(printf '%s\n' "$U8OUT" | grep '^mb.txt:1: ')"
  L2="$(printf '%s\n' "$U8OUT" | grep '^mb.txt:2: ')"
  assert_eq "AC11 multibyte literals present: exit 1" "1" "$U8RC"
  assert_contains "AC11 the 7-letter match (14 bytes) is reported at its line" "$L1" "mb.txt:1: user-literal"
  assert_not_contains "AC11 a 7-LETTER match is 8 characters or fewer: no letter of it is shown" "$L1" "$E1"
  assert_contains "AC11 the 11-letter match is reported at its line" "$L2" "mb.txt:2: user-literal"
  assert_contains "AC11 a longer match shows its first 4 LETTERS then ***" "$L2" "user-literal $E2$E2$E2$E2***"
  assert_not_contains "AC11 ... and not a fifth letter (per character, not per byte)" "$L2" "$E2$E2$E2$E2$E2"
  rm -f "$PH/.agents/playbook.conf"
fi

# ---- v0.23.3 lane A review of 146dd98 ----
echo "v0.23.3 lane A review MAJOR-1 pushInsteadOf: git pushes to the NAME after pushInsteadOf, so a rewritten push scans the full range"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
PU="$(mk_tmp)/u.git"; PZ="$(mk_tmp)/z.git"
git init -q --bare "$PU"; git init -q --bare "$PZ"
git -C "$R" remote add origin "$PU"
git -C "$R" config remote.origin.pushurl "$PU"
git -C "$R" push -q "$PZ" main
stage "$R" p1.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held by origin/main only'
PSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$PSEC"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 control: no pushInsteadOf, origin's exact url uses origin's refs: exit 0" "0" "$RC"
assert_not_contains "P1 control: no note" "$ERR" "is not a configured remote"
git -C "$R" config "url.$PZ.pushInsteadOf" "$PU"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 origin url = pushurl = U, pushInsteadOf U -> Z: the full range is scanned, exit 1" "1" "$RC"
assert_contains "P1 ... the finding is named" "$STD" "p1.txt:1: github-token"
assert_contains "P1 ... stderr carries the usual note" "$ERR" "$(note_for "$PU")"
run_in "$R" bash "$LC" install-hooks
assert_rc "P1 hook setup: install-hooks exit 0" 0
run_in "$R" git push "$PU" "main:refs/heads/newbr"
if [ "$RC" != 0 ]; then t_ok "P1 the installed hook refuses 'git push U main:newbr' (exit $RC)"; else t_bad "P1 the installed hook refuses 'git push U main:newbr'" "exit 0; output: $OUT"; fi
assert_contains "P1 ... the hook shows the finding" "$OUT" "p1.txt:1: github-token"
if git -C "$PZ" rev-parse --verify -q refs/heads/newbr >/dev/null; then t_bad "P1 Z.git did not receive the branch" "newbr is on Z"; else t_ok "P1 Z.git did not receive the branch"; fi
if git -C "$PZ" cat-file -e "$PSEC" 2>/dev/null; then t_bad "P1 Z.git did not receive the secret commit" "object is on Z"; else t_ok "P1 Z.git did not receive the secret commit"; fi
git -C "$R" config --unset-all "url.$PZ.pushInsteadOf"
git -C "$R" config "url.$PZ.pushInsteadOf" "no-such-prefix:"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 control: a pushInsteadOf whose value is no prefix of NAME changes nothing: exit 0" "0" "$RC"

echo "v0.23.3 lane A review MAJOR-1 P2: insteadOf and pushInsteadOf on one prefix, origin with no pushurl"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
QU="$(mk_tmp)/u.git"; QZ="$(mk_tmp)/z.git"
git init -q --bare "$QU"; git init -q --bare "$QZ"
git -C "$R" remote add origin "$QU"
git -C "$R" config "url.$QU.insteadOf" 'short:'
git -C "$R" config "url.$QZ.pushInsteadOf" 'short:'
git -C "$R" push -q "$QZ" main
stage "$R" p2.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held by origin/main only (P2)'
QSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$QSEC"
lc_streams --unpushed "$QSEC" --remote 'short:'
assert_eq "P2 NAME short: (insteadOf -> U, pushInsteadOf -> Z): the full range is scanned, exit 1" "1" "$RC"
assert_contains "P2 ... the finding is named" "$STD" "p2.txt:1: github-token"
assert_contains "P2 ... stderr carries the usual note" "$ERR" "$(note_for 'short:')"
run_in "$R" bash "$LC" install-hooks
assert_rc "P2 hook setup: install-hooks exit 0" 0
run_in "$R" git push 'short:' "main:refs/heads/newbr"
if [ "$RC" != 0 ]; then t_ok "P2 the installed hook refuses 'git push short: main:newbr' (exit $RC)"; else t_bad "P2 the installed hook refuses 'git push short: main:newbr'" "exit 0; output: $OUT"; fi
if git -C "$QZ" cat-file -e "$QSEC" 2>/dev/null; then t_bad "P2 Z.git did not receive the secret commit" "object is on Z"; else t_ok "P2 Z.git did not receive the secret commit"; fi

echo "v0.23.3 lane A review MINOR-2 the usage text shows the Exit line"
newrepo
run_in "$R" bash "$LC"
assert_rc "usage: no arguments, exit 2" 2
assert_contains "usage prints the Exit line (0 clean, 1 a hit, 2 usage, 3 not a git repo)" "$OUT" "Exit: 0 clean"
assert_contains "usage prints the whole Exit line (up to exit 3)" "$OUT" "3 not a git repo"

echo "v0.23.3 lane A review MINOR-3 scan --staged: a path with a control byte fails closed with the control-byte message"
modrepo
CTLP="bin/ctl$(printf '\002')x.sh"
if printf '#!/bin/sh\n' > "$R/$CTLP" 2>/dev/null && [ -f "$R/$CTLP" ] && git -C "$R" add -- "$CTLP" 2>/dev/null && git -C "$R" ls-files --error-unmatch -- "$CTLP" >/dev/null 2>&1; then
  CTLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  scan_streams
  assert_eq "a staged path with a \\002 byte: exit 1" "1" "$RC"
  assert_contains "... the message says a path contains a newline or control byte" "$STD$ERR" "$CTLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="$CTLP"
  assert_eq "... PB_ALLOW_MODE_CHANGE with the path is no escape: exit 1" "1" "$RC"
  assert_contains "... the message is still printed" "$STD$ERR" "$CTLMSG"
  git -C "$R" rm -q --cached -f -- "$CTLP"; rm -f "${R:?}/${CTLP:?}"
else rm -f "${R:?}/${CTLP:?}" 2>/dev/null; t_skip 4 "control-byte path (this file system or git refuses the name)"; fi

# ---- v0.23.3 lane A review round 3 (fix round 3) ----
# pfix WHERE -> sets R (work repo), D-level bare repos PRIV (origin's url), PUB (empty), FORK (empty) and PSEC (the secret commit).
# WHERE=origin: the secret commit is on origin/main (pushed to PRIV, fetched). WHERE=fork: it is on remote fork's refs only
# (origin holds the base commit only). Then a branch feat adds a benign commit on top, and the hooks are installed.
pfix() {
  local d; d="$(mk_tmp)"; PRIV="$d/priv.git"; PUB="$d/pub.git"; FORK="$d/fork.git"
  git init -q --bare "$PRIV"; git init -q --bare "$PUB"; git init -q --bare "$FORK"
  newrepo
  git -C "$R" remote add origin "$PRIV"
  git -C "$R" push -q --no-verify origin HEAD:refs/heads/main
  git -C "$R" fetch -q origin
  if [ "$1" = fork ]; then git -C "$R" remote add fork "$FORK"; fi
  stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret commit'
  PSEC="$(git -C "$R" rev-parse HEAD)"
  if [ "$1" = fork ]; then
    git -C "$R" push -q --no-verify fork HEAD:refs/heads/main; git -C "$R" fetch -q fork
  else
    git -C "$R" push -q --no-verify origin HEAD:refs/heads/main; git -C "$R" fetch -q origin
  fi
  git -C "$R" checkout -q -b feat
  stage "$R" b.txt 'benign'; G -C "$R" commit -q -m 'benign commit'
  run_in "$R" bash "$LC" install-hooks
}
# holds BARE -> 0 when BARE has the secret commit or a feat branch
holds_secret() { git -C "$1" cat-file -e "$PSEC" 2>/dev/null; }
holds_feat() { git -C "$1" rev-parse --verify -q refs/heads/feat >/dev/null 2>&1; }

echo "v0.23.3 lane A review round 3 MAJOR-1: a pushInsteadOf base holding '.pushinsteadof ' is not split at its first occurrence"
pfix origin
XB="$(mk_tmp)/x.pushinsteadof y.git"
if git init -q --bare "$XB" 2>/dev/null && [ -d "$XB" ]; then
  git -C "$R" config "url.$PRIV.insteadOf" 'pv:'
  git -C "$R" config "url.$XB.pushInsteadOf" 'pv:'
  lc_streams --unpushed "$(git -C "$R" rev-parse feat)" --remote 'pv:'
  assert_eq "R3 M1 scan --remote pv: (insteadOf -> priv, pushInsteadOf -> a base with '.pushinsteadof y'): full range, exit 1" "1" "$RC"
  assert_contains "R3 M1 ... the finding is named" "$STD" "s.txt:1: github-token"
  assert_contains "R3 M1 ... stderr carries the usual note" "$ERR" "$(note_for 'pv:')"
  run_in "$R" git push 'pv:' feat
  if [ "$RC" != 0 ]; then t_ok "R3 M1 the installed hook refuses 'git push pv: feat' (exit $RC)"; else t_bad "R3 M1 the installed hook refuses 'git push pv: feat'" "exit 0; output: $OUT"; fi
  assert_contains "R3 M1 ... the hook shows the finding" "$OUT" "s.txt:1: github-token"
  if holds_secret "$XB"; then t_bad "R3 M1 the secret commit did not reach the x.pushinsteadof y.git repo" "object is there"; else t_ok "R3 M1 the secret commit did not reach the x.pushinsteadof y.git repo"; fi
else t_skip 6 "R3 M1 a directory name with a space and '.pushinsteadof' (this file system refuses it)"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 control: a plain named push, no rewrite, the secret on origin/main"
pfix origin
run_in "$R" git push origin feat
assert_rc "R3 M2 control: git push origin feat with the secret on origin/main: exit 0" 0
if holds_feat "$PRIV"; then t_ok "R3 M2 control: the push reached priv"; else t_bad "R3 M2 control: the push reached priv" "no feat on priv; output: $OUT"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F: named remote origin, pushInsteadOf on its url, no pushurl"
pfix origin
git -C "$R" config "url.$PUB.pushInsteadOf" "$PRIV"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R3 M2 F: git push origin feat (the push goes to pub) is refused (exit $RC)"; else t_bad "R3 M2 F: git push origin feat (the push goes to pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R3 M2 F: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R3 M2 F: pub did not receive the secret commit" "object is on pub"; else t_ok "R3 M2 F: pub did not receive the secret commit"; fi
if holds_feat "$PUB"; then t_bad "R3 M2 F: pub did not receive the branch" "feat is on pub"; else t_ok "R3 M2 F: pub did not receive the branch"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F2: named remote origin, pushurl = pub, no pushInsteadOf"
pfix origin
git -C "$R" config remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R3 M2 F2: git push origin feat (pushurl is pub) is refused (exit $RC)"; else t_bad "R3 M2 F2: git push origin feat (pushurl is pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R3 M2 F2: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R3 M2 F2: pub did not receive the secret commit" "object is on pub"; else t_ok "R3 M2 F2: pub did not receive the secret commit"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F3: origin's pushurl is remote fork's url, and fork holds the secret commit"
pfix fork
git -C "$R" config remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
assert_rc "R3 M2 F3: git push origin feat (the push destination is fork, which holds the secret) is allowed: exit 0" 0
assert_not_contains "R3 M2 F3: no finding is printed" "$OUT" "github-token"
if holds_feat "$FORK"; then t_ok "R3 M2 F3: the push reached fork"; else t_bad "R3 M2 F3: the push reached fork" "no feat on fork; output: $OUT"; fi
if holds_feat "$PRIV"; then t_bad "R3 M2 F3: the push did not go to origin's fetch url" "feat is on priv"; else t_ok "R3 M2 F3: the push did not go to origin's fetch url"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 G: pushurl = url (same place) with a pushInsteadOf on that url: git ignores the rewrite"
pfix origin
git -C "$R" config remote.origin.pushurl "$PRIV"
git -C "$R" config "url.$PUB.pushInsteadOf" "$PRIV"
run_in "$R" git push origin feat
assert_rc "R3 M2 G: git push origin feat (pushurl = url = priv; the secret is on origin/main): exit 0" 0
if holds_feat "$PRIV"; then t_ok "R3 M2 G: git pushed to the pushurl (priv)"; else t_bad "R3 M2 G: git pushed to the pushurl (priv)" "no feat on priv; output: $OUT"; fi
if holds_feat "$PUB"; then t_bad "R3 M2 G: nothing went to pub" "feat is on pub"; else t_ok "R3 M2 G: nothing went to pub"; fi

# ---- v0.23.3 lane A review round 4 (fix round 4): remotes with several urls ----
# git fetches only from a remote's FIRST url but pushes to all its urls (or to all its pushurls): git-push(1), REMOTES.
# So a secret fetched from the first url is not "owned" by the second url, and the push must scan the full range.
echo "v0.23.3 lane A review round 4 N6: origin has urls priv and pub, no pushurl; the secret is on origin/main (fetched from priv)"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N6: git push origin feat (it also pushes to pub) is refused (exit $RC)"; else t_bad "R4 N6: git push origin feat (it also pushes to pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N6: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N6: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N6: pub did not receive the secret commit"; fi
# NIT-C: the push goes to origin's own first url AND elsewhere; the note must not claim that no configured remote owns it
assert_contains "R4 NIT-C N6: the note says origin pushes to a place its fetched refs do not cover" "$OUT" "origin pushes to a place its fetched refs do not cover; scanning the full range"
assert_not_contains "R4 NIT-C N6: the note does not say 'no configured remote owns' (priv is origin's own url)" "$OUT" "no configured remote owns"

echo "v0.23.3 lane A review round 4 N6b: origin has urls priv and pub, pushurl = pub"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
git -C "$R" config remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N6b: git push origin feat (pushurl is pub) is refused (exit $RC)"; else t_bad "R4 N6b: git push origin feat (pushurl is pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N6b: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N6b: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N6b: pub did not receive the secret commit"; fi

echo "v0.23.3 lane A review round 4 N6c control: origin has urls priv and pub, pushurl = priv (the first url)"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
git -C "$R" config remote.origin.pushurl "$PRIV"
run_in "$R" git push origin feat
assert_rc "R4 N6c control: git push origin feat (it only pushes to priv, whose refs origin fetched): exit 0" 0
if holds_feat "$PRIV"; then t_ok "R4 N6c control: the push reached priv"; else t_bad "R4 N6c control: the push reached priv" "no feat on priv; output: $OUT"; fi
if holds_feat "$PUB"; then t_bad "R4 N6c control: nothing went to pub" "feat is on pub"; else t_ok "R4 N6c control: nothing went to pub"; fi

echo "v0.23.3 lane A review round 4 N2: origin has pushurls priv and pub (a check of only the first push destination misses pub)"
pfix origin
git -C "$R" config --add remote.origin.pushurl "$PRIV"
git -C "$R" config --add remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N2: git push origin feat (pushurls priv and pub) is refused (exit $RC)"; else t_bad "R4 N2: git push origin feat (pushurls priv and pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N2: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N2: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N2: pub did not receive the secret commit"; fi
assert_contains "R4 NIT-C N2: the note says origin pushes to a place its fetched refs do not cover" "$OUT" "origin pushes to a place its fetched refs do not cover; scanning the full range"
assert_not_contains "R4 NIT-C N2: the note does not say 'no configured remote owns'" "$OUT" "no configured remote owns"

echo "v0.23.3 lane A review round 4 N8: origin has pushurls fork and pub; the secret is on refs/remotes/fork/* only; pub is unowned"
pfix fork
git -C "$R" config --add remote.origin.pushurl "$FORK"
git -C "$R" config --add remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N8: git push origin feat (pushurls fork and pub) is refused (exit $RC)"; else t_bad "R4 N8: git push origin feat (pushurls fork and pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N8: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N8: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N8: pub did not receive the secret commit"; fi

echo "v0.23.3 lane A review round 4 F3 control: origin's pushurl is remote fork's url, fork holds the secret (still allowed)"
pfix fork
git -C "$R" config remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
assert_rc "R4 F3 control: git push origin feat (the only destination is fork, which holds the secret): exit 0" 0
if holds_feat "$FORK"; then t_ok "R4 F3 control: the push reached fork"; else t_bad "R4 F3 control: the push reached fork" "no feat on fork; output: $OUT"; fi
t_summary
