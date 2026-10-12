#!/usr/bin/env bash
# Shared setup of tests/test-role-gate.sh and its split part (test-role-gate-mode.sh; split in v0.24.1 so that neither part is the floor of a
# CI shard): the isolated PLAYBOOK_HOME, the template repo and mk_repo, and the helpers of the executable-bit sections. Source it after lib.sh.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
GATE="$PB_ROOT/scripts/role-gate.sh"
export PLAYBOOK_HOME="$(mk_tmp)"   # isolate from the real ~/.agents/playbook.conf
# Git on Windows defaults to core.autocrlf=true and then prints "LF will be replaced by CRLF" warnings on
# stderr, which would break the byte-identical output checks. Force it off for every git call in this suite
# (command-line style config, git >= 2.31; it beats repository and global config).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false
# One template repo (init, config, first commit) built once and copied for each case: the ~15 cases below
# start from byte-identical repos without spawning git again.
RTPL="$(mk_tmp)"; mk_repo "$RTPL"
mk_repo() { cp -a "$RTPL/." "$1/"; }

IH="$(mk_tmp)"; mkdir -p "$IH/.agents"; printf 'test_infra_regex=^ci/\n' > "$IH/.agents/playbook.conf"
# gchk ROLE [ARGS] -> check in the current repo (global conf with an infra regex for ci/); gchk_allow LIST ROLE [ARGS] sets PB_ALLOW_MODE_CHANGE
gchk() { run env PLAYBOOK_HOME="$IH" bash "$GATE" check "$@"; }
gchk_allow() { local a="$1"; shift; run env PLAYBOOK_HOME="$IH" PB_ALLOW_MODE_CHANGE="$a" bash "$GATE" check "$@"; }
# mk_mode_repo DIR -> a repo whose committed index has 100755 scripts (src/run.sh, src/second.sh, 'src/my run.sh', tests/run.sh,
# ci/run.sh) and a 100644 src/plain.js; modes are set with update-index so Windows (no chmod) builds the same fixture
mk_mode_repo() {
  mk_repo "$1"
  ( cd "$1" && mkdir -p ci &&
    printf '#!/bin/sh\necho a\n' > src/run.sh && cp src/run.sh src/second.sh && cp src/run.sh "src/my run.sh" &&
    cp src/run.sh tests/run.sh && cp src/run.sh ci/run.sh && printf 'plain\n' > src/plain.js &&
    chmod +x src/run.sh src/second.sh "src/my run.sh" tests/run.sh ci/run.sh 2>/dev/null
    git add -A &&
    git update-index --chmod=+x -- src/run.sh src/second.sh "src/my run.sh" tests/run.sh ci/run.sh &&
    git commit -q -m "exec scripts" )
}
# dropped_visible -> 0 when git itself sees a 100755 -> 100644 change against HEAD here (a chmod is a no-op on Windows)
dropped_visible() { git diff --raw --no-renames HEAD 2>/dev/null | grep -q '^:100755 100644'; }
# fm_true_ok: core.fileMode=true and the fresh fixture still shows no mode change, i.e. this file system keeps
# executable bits (Git Bash on NTFS does not: every 100755 file would look dropped)
fm_true_ok() { git config core.fileMode true; [ -z "$(git diff --raw 2>/dev/null)" ]; }
