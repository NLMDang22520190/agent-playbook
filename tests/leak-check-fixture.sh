#!/usr/bin/env bash
# Shared setup of tests/test-leak-check.sh and its split parts (test-leak-check-mode.sh, test-leak-check-push.sh; split in v0.24.1 so that
# no part is the floor of a CI shard): the constants and helpers every part needs, and the two helpers of the mode-check sections (modrepo,
# scan_streams) that the push part reuses. Source it after lib.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# This file names neither the README nor the CHANGELOG: only the part that reads them is in the docs-only reduced set.
LC="$PB_ROOT/scripts/leak-check.sh"
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
