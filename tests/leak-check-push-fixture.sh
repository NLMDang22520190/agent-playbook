#!/usr/bin/env bash
# Shared setup of tests/test-leak-check-push.sh and tests/test-leak-check-push-b.sh (split in v0.24.19 so that neither is the floor of a CI shard):
# lc_streams (the streams of a scan in $R) and pfix with its two holds_* checks (the push fixtures of the pushInsteadOf and multi-url sections).
# Source it after lib.sh and leak-check-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# lc_streams ARGS... -> STD (stdout), ERR (stderr) and RC of `leak-check scan ARGS` run in $R
lc_streams() {
  local ef; ef="$(mk_tmp)/err"
  STD="$(cd "$R" && bash "$LC" scan "$@" 2>"$ef")"; RC=$?
  ERR="$(cat "$ef" 2>/dev/null)"
}

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
