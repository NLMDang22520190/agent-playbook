#!/usr/bin/env bash
# Lane C (v0.26.3) S1, spec A1 and A1b: word budgets only go down.
#   A1  evals/word-budgets at HEAD vs the previous release tag (the newest v* tag reachable from HEAD that does not point
#       at HEAD): FAIL naming PATH, old and new value for every path present at both points whose budget is higher (every
#       path, references files included), and FAIL when the SUM over the always-loaded paths (AGENTS.global.md and every
#       skills/*/SKILL.md) at HEAD is higher than at the tag. references/ files are loaded on demand: a new one gets a budget
#       at its size and stays out of the sum (orchestrator decision, supersedes spec D8/A1c on this point).
#       No reachable tag (a tarball, a shallow clone): t_skip with the same count.
#   A1b the table header names this suite instead of "raising a budget needs a CHANGELOG line"; tools/check-release.sh
#       runs the same comparison at release time (its cases are in tests/test-release.sh).
# The comparison on the real repo passes today (no budget rose since v0.25.1): a characterization guard. The cases on
# fixture tables prove the comparison can fail.
. "$(dirname "$0")/lib.sh"
WB="$PB_ROOT/evals/word-budgets"

# wb_cmp OLD NEW -> one line per risen path "RISE PATH OLD -> NEW", then "SUM OLD -> NEW" over the always-loaded paths only
# (AGENTS.global.md and skills/<name>/SKILL.md); exit 1 on any rise or a higher sum.
# A table line is "PATH WORDS [# comment]"; lines starting with # are comments; a CR at the end is ignored.
wb_cmp() {
  awk '
    { sub(/\r$/, "") }
    /^#/ || NF < 2 || $2 !~ /^[0-9]+$/ { next }
    function loaded(p) { return p == "AGENTS.global.md" || p ~ /^skills\/[^\/]+\/SKILL\.md$/ }
    FNR == NR { old[$1] = $2; if (loaded($1)) so += $2; next }
    { if (loaded($1)) sn += $2; if (($1 in old) && $2 + 0 > old[$1] + 0) { print "RISE " $1 " " old[$1] " -> " $2; bad = 1 } }
    END { print "SUM " so + 0 " -> " sn + 0; if (sn > so) bad = 1; exit bad }' "$1" "$2"
}
# prev_tag DIR -> the newest v* tag reachable from HEAD that does not point at HEAD (empty when none)
prev_tag() {
  local head t
  head="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || return 0
  for t in $(git -C "$1" tag -l 'v*' --merged HEAD --sort=-v:refname 2>/dev/null); do
    if [ "$(git -C "$1" rev-list -n 1 "$t" 2>/dev/null)" != "$head" ]; then printf '%s\n' "$t"; return 0; fi
  done
  return 0
}

echo "A1 evals/word-budgets: no budget and not the always-loaded sum rose since the previous release"
TAG="$(prev_tag "$PB_ROOT")"
OLDT="$(mk_tmp)/old-word-budgets"
if [ -n "$TAG" ] && git -C "$PB_ROOT" show "$TAG:evals/word-budgets" > "$OLDT" 2>/dev/null; then
  CMP="$(wb_cmp "$OLDT" "$WB")"
  RISES="$(printf '%s\n' "$CMP" | grep '^RISE ')"
  assert_eq "A1 no budget in evals/word-budgets is higher than at $TAG" "" "$RISES"
  if wb_cmp "$OLDT" "$WB" >/dev/null; then t_ok "A1 the sum of the always-loaded budgets is not higher than at $TAG ($(printf '%s\n' "$CMP" | grep '^SUM '))"
  else t_bad "A1 the sum of the always-loaded budgets is not higher than at $TAG" "$(printf '%s\n' "$CMP" | grep '^SUM ')"; fi
else
  t_skip 2 "A1 no previous v* release tag with evals/word-budgets reachable from HEAD (tarball or shallow clone)"
fi

echo "A1 the comparison on fixture tables"
F="$(mk_tmp)"
printf '# header\nAGENTS.global.md 730   # note\nskills/a/SKILL.md 700\nskills/b/SKILL.md 500\n' > "$F/old"
printf '# header\nAGENTS.global.md 730\nskills/a/SKILL.md 750   # raised\nskills/b/SKILL.md 400\n' > "$F/raised"
OUT="$(wb_cmp "$F/old" "$F/raised")"; RC=$?
assert_eq "A1 a raised budget fails even when the sum falls (exit 1)" "1" "$RC"
assert_contains "A1 the failure names the path, the old and the new value" "$OUT" "RISE skills/a/SKILL.md 700 -> 750"
assert_not_contains "A1 a lowered budget is not reported" "$OUT" "skills/b/SKILL.md"
printf 'AGENTS.global.md 700\nskills/a/SKILL.md 600\nskills/b/SKILL.md 500\nskills/c/SKILL.md 100\n' > "$F/down"
OUT="$(wb_cmp "$F/old" "$F/down")"; RC=$?
assert_eq "A1 lower budgets plus a new path that keeps the sum lower: exit 0" "0" "$RC"
assert_contains "A1 the sum line shows both sums" "$OUT" "SUM 1930 -> 1900"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 700\nskills/b/SKILL.md 500\nskills/playbook-tdd/references/full.md 1490\n' > "$F/newref"
OUT="$(wb_cmp "$F/old" "$F/newref")"; RC=$?
assert_eq "A1 a new references file with a big budget stays out of the sum: exit 0" "0" "$RC"
assert_contains "A1 the sum line counts only the always-loaded paths" "$OUT" "SUM 1930 -> 1930"
assert_not_contains "A1 a path absent at the tag is not a per-path rise" "$OUT" "RISE"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 700\nskills/b/SKILL.md 500\nskills/c/SKILL.md 100\n' > "$F/newskill"
OUT="$(wb_cmp "$F/old" "$F/newskill")"; RC=$?
assert_eq "A1 a new SKILL.md that raises the always-loaded sum fails" "1" "$RC"
assert_contains "A1 the sum failure shows both sums" "$OUT" "SUM 1930 -> 2030"
assert_not_contains "A1 a SKILL.md absent at the tag is not a per-path rise" "$OUT" "RISE"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 700\nskills/b/SKILL.md 500\nskills/playbook-tdd/references/full.md 1490\nskills/playbook-tdd/references/weights.md 290\n' > "$F/refold"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 700\nskills/b/SKILL.md 500\nskills/playbook-tdd/references/full.md 1500\nskills/playbook-tdd/references/weights.md 100\n' > "$F/refnew"
OUT="$(wb_cmp "$F/refold" "$F/refnew")"; RC=$?
assert_eq "A1 a references file whose budget rose versus the previous release fails even when the sum is equal" "1" "$RC"
assert_contains "A1 the references rise is named" "$OUT" "RISE skills/playbook-tdd/references/full.md 1490 -> 1500"
assert_not_contains "A1 a lowered references budget is not reported" "$OUT" "weights.md"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 600\nskills/b/SKILL.md 500\nskills/playbook-tdd/references/full.md 900\n' > "$F/moved"
OUT="$(wb_cmp "$F/old" "$F/moved")"; RC=$?
assert_eq "A1 SKILL.md lower and a new references file added: exit 0 (the split)" "0" "$RC"
assert_contains "A1 the sum line shows the drop" "$OUT" "SUM 1930 -> 1830"
printf 'AGENTS.global.md 730\r\nskills/a/SKILL.md 701   # one more\r\nskills/b/SKILL.md 499\r\n' > "$F/crlf"
OUT="$(wb_cmp "$F/old" "$F/crlf")"; RC=$?
assert_eq "A1 a CRLF table with comments still compares (one word more fails)" "1" "$RC"
assert_contains "A1 a CRLF table: the rise is named" "$OUT" "RISE skills/a/SKILL.md 700 -> 701"
printf 'AGENTS.global.md 730\nskills/a/SKILL.md 700\n' > "$F/removed"
OUT="$(wb_cmp "$F/old" "$F/removed")"; RC=$?
assert_eq "A1 a removed path is not a rise: exit 0" "0" "$RC"

echo "A1 the previous release tag is the newest v* tag that does not point at HEAD"
R="$(mk_tmp)/r"; mk_repo "$R"
( cd "$R" && git tag v0.1.0 && printf 'x\n' >> README.md && git commit -qam two && git tag v0.2.0 && printf 'y\n' >> README.md &&
  git commit -qam three && git tag v0.3.0 && git tag other-tag ) >/dev/null 2>&1
assert_eq "A1 HEAD tagged v0.3.0: the previous release is v0.2.0" "v0.2.0" "$(prev_tag "$R")"
( cd "$R" && printf 'z\n' >> README.md && git commit -qam four ) >/dev/null 2>&1
assert_eq "A1 HEAD untagged: the previous release is the newest tag, v0.3.0" "v0.3.0" "$(prev_tag "$R")"
R2="$(mk_tmp)/r2"; mk_repo "$R2"
assert_eq "A1 no tag: no previous release (the suite skips)" "" "$(prev_tag "$R2")"
assert_eq "A1 not a git checkout: no previous release (the suite skips)" "" "$(prev_tag "$(mk_tmp)")"

echo "A1b the table header names this suite, not a CHANGELOG raise"
HDR="$(grep '^#' "$WB" 2>/dev/null)"
if printf '%s\n' "$HDR" | grep -qi 'raising a budget needs a CHANGELOG line'; then
  t_bad "A1b the header no longer says a budget may be raised with a CHANGELOG line" "still there"
else t_ok "A1b the header no longer says a budget may be raised with a CHANGELOG line"; fi
assert_contains "A1b the header names tests/test-budgets-down.sh" "$HDR" "tests/test-budgets-down.sh"
if grep -q 'raising a budget needs a CHANGELOG line' "$PB_ROOT/evals/run-checks.sh" 2>/dev/null; then
  t_bad "A1b the run-checks over-budget message no longer offers a CHANGELOG raise (D-T2)" "still in evals/run-checks.sh"
else t_ok "A1b the run-checks over-budget message no longer offers a CHANGELOG raise (D-T2)"; fi

t_summary
