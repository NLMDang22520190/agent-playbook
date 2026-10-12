#!/usr/bin/env bash
# Tests for tools/docs-only.sh (v0.23.0 AC5.1): is a pull request a docs-only change?
#   tools/docs-only.sh BASE HEAD   run inside the repository; prints "true" or "false" on stdout, exit 0 always.
# true only when `git diff --name-only --no-renames BASE...HEAD` lists at least one path, every path is exactly
# README.md or CHANGELOG.md at the repo root, and the README's test-count places (badge tests-N, **N passing**,
# N tests, run in sandboxes) are unchanged. Anything else (zero paths, rename onto a doc, nested README, bad sha) is false.
# Fixture repositories only; no network.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/docs-only.sh"
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false "$@"; }

assert_file "AC5.1 tools/docs-only.sh exists" "$TOOL"

# mkrepo -> sets D: a repo on branch main with README (count lines), CHANGELOG, scripts/x.sh, src/app.js, docs/README.md
mkrepo() {
  D="$(mk_tmp)"
  mkdir -p "$D/scripts" "$D/src" "$D/docs"
  ( cd "$D" && G init -q && G symbolic-ref HEAD refs/heads/main
    printf '# demo\n![tests](https://img.shields.io/badge/tests-100-1F9D63)\n| Tests | **100 passing** |\ntree: 100 tests, run in sandboxes\nprose one\n' > README.md
    printf '# Changelog\n\n## 1.0.0\n- first\n' > CHANGELOG.md
    printf '#!/bin/sh\necho x\n' > scripts/x.sh
    printf 'module.exports = 1;\n' > src/app.js
    printf '# docs readme\n' > docs/README.md
    G add -A && G commit -q -m base )
  BASE="$(cd "$D" && git rev-parse HEAD)"
}
# edit then commit on a branch: topic CMD... (CMD runs in $D)
commit_all() { ( cd "$D" && G add -A && G commit -q -m change ); HEADSHA="$(cd "$D" && git rev-parse HEAD)"; }
# docs BASE HEAD -> OUT (stdout only), RC; run inside $D
docs() { OUT="$(cd "$D" && bash "$TOOL" "$1" "$2" 2>/dev/null)"; RC=$?; }
expect() { # NAME WANT
  assert_eq "AC5.1 $1: prints $2" "$2" "$OUT"
  assert_eq "AC5.1 $1: exit 0" "0" "$RC"
}

echo "AC5.1 docs-only changes -> true"
mkrepo; printf 'prose two\n' >> "$D/README.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "README prose only" true
mkrepo; printf -- '- second\n' >> "$D/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "CHANGELOG only" true
mkrepo; printf 'prose two\n' >> "$D/README.md"; printf -- '- second\n' >> "$D/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "README and CHANGELOG" true
mkrepo; printf 'prose two\n' >> "$D/README.md"; commit_all
printf -- '- more\n' >> "$D/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "two commits, both docs" true

echo "AC5.1 any other path -> false"
mkrepo; printf 'module.exports = 2;\n' > "$D/src/app.js"; commit_all
docs "$BASE" "$HEADSHA"; expect "a code file" false
mkrepo; printf 'prose two\n' >> "$D/README.md"; printf 'module.exports = 2;\n' > "$D/src/app.js"; commit_all
docs "$BASE" "$HEADSHA"; expect "README plus a code file" false
mkrepo; printf 'more\n' >> "$D/docs/README.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "a nested docs/README.md" false
mkrepo; printf 'more\n' > "$D/docs/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "a nested docs/CHANGELOG.md" false
mkrepo; printf 'new\n' > "$D/README.md.bak"; commit_all
docs "$BASE" "$HEADSHA"; expect "a file whose name only starts like README.md" false
mkrepo; printf 'new\n' > "$D/README.markdown"; commit_all
docs "$BASE" "$HEADSHA"; expect "README.markdown" false
mkrepo; printf 'new\n' > "$D/readme.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "readme.md in lower case" false
mkrepo; printf 'prose two\n' >> "$D/README.md"; ( cd "$D" && G add -A && G commit -q -m a ); printf 'x\n' > "$D/src/new.js"; commit_all
docs "$BASE" "$HEADSHA"; expect "a docs commit then a code commit" false
mkrepo; ( cd "$D" && G rm -q scripts/x.sh ); commit_all
docs "$BASE" "$HEADSHA"; expect "a deleted script" false

echo "AC5.1 a rename onto a doc is not docs-only (rename detection is off)"
mkrepo; ( cd "$D" && G mv -f scripts/x.sh CHANGELOG.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "scripts/x.sh renamed onto CHANGELOG.md" false
mkrepo
# a rename of README.md away: path README.md deleted and docs/R.md added
( cd "$D" && G mv README.md docs/R.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "README.md moved into docs/" false

echo "AC5.1 zero paths -> false"
mkrepo; docs "$BASE" "$BASE"; expect "base equals head (empty diff)" false
mkrepo; ( cd "$D" && G commit -q --allow-empty -m empty ); HEADSHA="$(cd "$D" && git rev-parse HEAD)"
docs "$BASE" "$HEADSHA"; expect "an empty commit" false

echo "AC5.1 the README test count changed -> false (decision D2)"
mkrepo; sed 's#badge/tests-100#badge/tests-101#' "$D/README.md" > "$D/R.tmp" && cat "$D/R.tmp" > "$D/README.md" && rm -f "$D/R.tmp"; commit_all
docs "$BASE" "$HEADSHA"; expect "the badge count changed" false
mkrepo; sed 's#\*\*100 passing\*\*#**101 passing**#' "$D/README.md" > "$D/R.tmp" && cat "$D/R.tmp" > "$D/README.md" && rm -f "$D/R.tmp"; commit_all
docs "$BASE" "$HEADSHA"; expect "the **N passing** count changed" false
mkrepo; sed 's#100 tests, run in sandboxes#101 tests, run in sandboxes#' "$D/README.md" > "$D/R.tmp" && cat "$D/R.tmp" > "$D/README.md" && rm -f "$D/R.tmp"; commit_all
docs "$BASE" "$HEADSHA"; expect "the N tests, run in sandboxes count changed" false
mkrepo; sed 's#100#200#g' "$D/README.md" > "$D/R.tmp" && cat "$D/R.tmp" > "$D/README.md" && rm -f "$D/R.tmp"; printf -- '- c\n' >> "$D/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "all three counts changed together with the CHANGELOG" false
mkrepo; printf 'prose two\n' >> "$D/README.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "prose added, counts unchanged: still true" true
mkrepo; sed 's#prose one#prose uno#' "$D/README.md" > "$D/R.tmp" && cat "$D/R.tmp" > "$D/README.md" && rm -f "$D/R.tmp"; commit_all
docs "$BASE" "$HEADSHA"; expect "a prose line edited, counts unchanged" true
mkrepo; printf -- '- 555 passing in this release\n' >> "$D/CHANGELOG.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "a count-like number in CHANGELOG is not a README count" true

echo "AC5.1 three-dot diff: only the PR side counts (merge base)"
mkrepo
( cd "$D" && G checkout -q -b topic && printf 'prose two\n' >> README.md && G add -A && G commit -q -m topic && G checkout -q main && printf 'module.exports = 3;\n' > src/app.js && G add -A && G commit -q -m 'main moved on' )
MAINSHA="$(cd "$D" && git rev-parse main)"; TOPIC="$(cd "$D" && git rev-parse topic)"
docs "$MAINSHA" "$TOPIC"; expect "main changed code after the branch point, the PR changed only README" true
mkrepo
( cd "$D" && G checkout -q -b topic && printf 'module.exports = 4;\n' > src/app.js && G add -A && G commit -q -m topic && G checkout -q main && printf -- '- on main\n' >> CHANGELOG.md && G add -A && G commit -q -m 'main docs' )
MAINSHA="$(cd "$D" && git rev-parse main)"; TOPIC="$(cd "$D" && git rev-parse topic)"
docs "$MAINSHA" "$TOPIC"; expect "main changed only docs after the branch point, the PR changed code" false

echo "AC5.1 any git error -> false, exit 0"
mkrepo; printf 'prose two\n' >> "$D/README.md"; commit_all
docs "$BASE" "0000000000000000000000000000000000000000"; expect "an unknown head sha" false
docs "0000000000000000000000000000000000000000" "$HEADSHA"; expect "an unknown base sha" false
docs "not-a-sha" "$HEADSHA"; expect "a base that is not a sha" false
docs "" ""; expect "empty arguments" false
OUT="$(cd "$D" && bash "$TOOL" 2>/dev/null)"; RC=$?; expect "no arguments" false
OUT="$(cd "$(mk_tmp)" && bash "$TOOL" "$BASE" "$HEADSHA" 2>/dev/null)"; RC=$?; expect "run outside a git repository" false
assert_eq "AC5.1 stdout is one word and nothing else (true case)" "1" "$( (cd "$D" && bash "$TOOL" "$BASE" "$HEADSHA" 2>/dev/null) | wc -l | tr -d ' ')"

echo "AC5.1 review: glob-safe paths (run from the repo root, where the real CHANGELOG.md and README.md exist)"
mkrepo; printf 'x\n' > "$D/CHANGELO[G].md"; commit_all
assert_file "AC5.1 fixture: the real CHANGELOG.md is in the repo root the tool runs from" "$D/CHANGELOG.md"
docs "$BASE" "$HEADSHA"; expect "a file literally named CHANGELO[G].md" false
mkrepo; printf 'x\n' > "$D/READM[E].md"; commit_all
assert_file "AC5.1 fixture: the real README.md is in the repo root the tool runs from" "$D/README.md"
docs "$BASE" "$HEADSHA"; expect "a file literally named READM[E].md" false
mkrepo; printf 'x\n' > "$D/*.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "a file literally named *.md" false
mkrepo; printf 'x\n' > "$D/R?ADME.md"; commit_all
docs "$BASE" "$HEADSHA"; expect "a file literally named R?ADME.md" false

echo "AC5.1 review: rename detection must be off (the doc path is new in the PR)"
mkrepo; ( cd "$D" && G rm -q CHANGELOG.md && G commit -q -m 'no changelog' ); BASE="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && G mv scripts/x.sh CHANGELOG.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "base has no CHANGELOG.md; scripts/x.sh moved onto CHANGELOG.md" false
mkrepo; ( cd "$D" && G rm -q README.md && G commit -q -m 'no readme' ); BASE="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && G mv scripts/x.sh README.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "base has no README.md; scripts/x.sh moved onto README.md" false
mkrepo; ( cd "$D" && G rm -q CHANGELOG.md && G commit -q -m 'no changelog' ); BASE="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && cp src/app.js CHANGELOG.md && G rm -q src/app.js ); commit_all
docs "$BASE" "$HEADSHA"; expect "base has no CHANGELOG.md; src/app.js moved (copied then removed) onto CHANGELOG.md" false

echo "AC5.1 review: README.md and CHANGELOG.md must be regular blobs"
mkrepo; ( cd "$D" && G rm -q --cached README.md && G update-index --add --cacheinfo "160000,$BASE,README.md" ); commit_all
docs "$BASE" "$HEADSHA"; expect "README.md replaced by a gitlink (mode 160000) at head" false
mkrepo; ( cd "$D" && G rm -q --cached CHANGELOG.md && G update-index --add --cacheinfo "160000,$BASE,CHANGELOG.md" ); commit_all
docs "$BASE" "$HEADSHA"; expect "CHANGELOG.md replaced by a gitlink at head" false
mkrepo; ( cd "$D" && G rm -q --cached README.md && G update-index --add --cacheinfo "160000,$BASE,README.md" && G commit -q -m 'readme is a gitlink' ); BASE="$(cd "$D" && git rev-parse HEAD)"
printf '# demo\nprose\n' > "$D/README.md"; ( cd "$D" && G rm -q --cached README.md 2>/dev/null; G add README.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "README.md is a gitlink at base and a blob at head" false
mkrepo; ( cd "$D" && G rm -q --cached CHANGELOG.md && G update-index --add --cacheinfo "160000,$BASE,CHANGELOG.md" && G commit -q -m 'changelog is a gitlink' ); BASE="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && G rm -q --cached CHANGELOG.md 2>/dev/null; printf '# Changelog\n' > CHANGELOG.md && G add CHANGELOG.md ); commit_all
docs "$BASE" "$HEADSHA"; expect "CHANGELOG.md is a gitlink at base and a blob at head" false
if [ "$SYMLINKS" = 1 ]; then
  mkrepo; ( cd "$D" && rm -f CHANGELOG.md && ln -s docs/README.md CHANGELOG.md ); commit_all
  docs "$BASE" "$HEADSHA"; expect "CHANGELOG.md replaced by a symlink (mode 120000)" false
else t_skip 1 "AC5.1 symlink as CHANGELOG.md (no symlink rights here)"; fi

t_summary
