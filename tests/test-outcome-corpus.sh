#!/usr/bin/env bash
# Tests for the outcome-eval task corpus evals/tasks/ (v0.27.0 lane O, slices S0b-S0c, AC19, AC21-AC23).
# Per task: task.conf metadata, the hidden tests (FAIL_TO_PASS / PASS_TO_PASS lists pinned here), the canary, the
# prompt language, setup.sh refusing a non-empty target, solution.patch presence, then evals/check-tasks.sh over the
# whole corpus (setup twice with one HEAD, F2P fail and P2P pass unsolved, all pass after solution.patch).
# DECISION[D1] 13 tasks (node 9, python3 3, bash 1; prompts VI 6 / EN 7). DECISION[D13] every id, weight, file split
# and expected value below is an author-chosen oracle from 01-spec.md "Corpus" [UNVERIFIED] until the user reviews it.
# DECISION[D12] the private-name denylist is never committed: it comes from PB_CORPUS_DENYLIST (comma list) or is skipped.
. "$(dirname "$0")/lib.sh"
TASKS="$PB_ROOT/evals/tasks"
CHECK="$PB_ROOT/evals/check-tasks.sh"
CAN="PB-HIDDEN-""CANARY"

# id|language|prompt language|expected_weight|fail_to_pass|pass_to_pass
CORPUS='pattern-01-option-value-label|node|en|Full|tests/pricing-value.f2p.test.js|tests/pricing-manual.p2p.test.js
pattern-02-dimension-text|node|vi|Lite|tests/dims-separators.f2p.test.js|tests/dims-valid.p2p.test.js
pattern-03-second-screen|node|vi|Lite|tests/order-detail-system.f2p.test.js tests/inbox-system.f2p.test.js|tests/views-user.p2p.test.js
pattern-04-role-check|node|en|Full|tests/auth-roles.f2p.test.js|tests/auth-allowed.p2p.test.js
pattern-05-money-rounding|python3|vi|Full|tests/test_invoice_half_up.py|tests/test_invoice_plain.py
pattern-06-day-boundary-tz|node|vi|Lite|tests/report-shop-day.f2p.test.js|tests/report-same-day.p2p.test.js
pattern-07-idempotent-retry|node|en|Full|tests/webhook-retry.f2p.test.js|tests/webhook-credit.p2p.test.js
pattern-08-state-transition|python3|vi|Full|tests/test_cancel_after_shipping.py|tests/test_cancel_before_shipping.py
pattern-09-not-a-bug|node|vi|Lite||tests/discount-threshold.p2p.test.js
oss-01-csv-quoted-comma|python3|en|Lite|tests/test_csvsum_quoted.py|tests/test_csvsum_plain.py
oss-02-version-compare|node|en|Lite|tests/semver-numeric.f2p.test.js|tests/semver-basic.p2p.test.js
oss-03-last-line-no-newline|bash|en|Lite|tests/sum-last-line.f2p.sh|tests/sum-newline.p2p.sh
oss-04-path-traversal|node|en|Full|tests/static-traversal.f2p.test.js|tests/static-inside.p2p.test.js'

# conf_val FILE KEY -> the value of KEY= (first line), surrounding double quotes removed
conf_val() {
  local v
  v="$(sed -n "s/^$2=//p" "$1" 2>/dev/null | sed -n 1p | tr -d '\r')"
  v="${v#\"}"; v="${v%\"}"
  printf '%s' "$v"
}
# words_sorted "a b c" -> one per line, sorted, empty lines dropped
words_sorted() { printf '%s\n' $1 | sed '/^$/d' | LC_ALL=C sort; }
# Vietnamese-only letters in UTF-8: d-stroke, u-horn, o-horn, a-breve, and the precomposed tone block U+1EA0-U+1EF9
VI_RE="$(printf '\304\221|\306\260|\306\241|\304\203|\341\272|\341\273')"
HAVE_PY=0
if python3 -c 'import sys' >/dev/null 2>&1; then HAVE_PY=1; fi

echo "AC21 corpus layout"
n_dirs="$(cd "$TASKS" 2>/dev/null && find . -mindepth 1 -maxdepth 1 -type d | sed '/^$/d' | wc -l | tr -d ' ')"
assert_eq "AC21 13 task directories under evals/tasks [D1]" 13 "${n_dirs:-0}"
c_node=0; c_py=0; c_bash=0; c_vi=0; c_en=0
while IFS='|' read -r id lang plang weight f2p p2p; do
  [ -n "$id" ] || continue
  d="$TASKS/$id"; conf="$d/task.conf"
  echo "-- $id"
  assert_file "AC19 $id has task.conf" "$conf"
  assert_eq "AC19 $id task.conf id is the directory name" "$id" "$(conf_val "$conf" id)"
  assert_eq "AC19/AC21 $id language=$lang [D13]" "$lang" "$(conf_val "$conf" language)"
  assert_eq "AC19 $id expected_weight=$weight [D13]" "$weight" "$(conf_val "$conf" expected_weight)"
  src="$(conf_val "$conf" source)"
  case "$id" in pattern-*) want_pre="pattern:" ;; *) want_pre="oss:" ;; esac
  case "$src" in
    "$want_pre"?*) t_ok "AC19 $id source is $want_pre<slug>" ;;
    *) t_bad "AC19 $id source is $want_pre<slug>" "got [$src]" ;;
  esac
  assert_eq "AC19 $id fail_to_pass lists the pinned F2P files" "$(words_sorted "$f2p")" "$(words_sorted "$(conf_val "$conf" fail_to_pass)")"
  assert_eq "AC19 $id pass_to_pass lists the pinned P2P files" "$(words_sorted "$p2p")" "$(words_sorted "$(conf_val "$conf" pass_to_pass)")"
  # hidden/ holds exactly the listed files, all under hidden/tests/
  have="$(cd "$d/hidden" 2>/dev/null && find . -type f | sed 's#^\./##' | LC_ALL=C sort)"
  assert_eq "AC19 $id hidden/ holds only the F2P and P2P files under hidden/tests/" "$(words_sorted "$f2p $p2p")" "$have"
  for f in $f2p $p2p; do
    if grep -qF -- "$CAN:$id" "$d/hidden/$f" 2>/dev/null; then t_ok "AC9 $id $f carries $CAN:$id"
    else t_bad "AC9 $id $f carries $CAN:$id" "marker missing in $d/hidden/$f"; fi
  done
  # nothing the agent is given carries the canary
  leaked="$(cd "$d" 2>/dev/null && find . -type f ! -path './hidden/*' -exec grep -lF -- "$CAN" {} + 2>/dev/null)"
  assert_eq "AC9/AC20 $id: no canary outside hidden/" "" "$leaked"
  assert_file "AC19 $id has prompt.md" "$d/prompt.md"
  if [ -s "$d/prompt.md" ]; then
    if LC_ALL=C grep -Eq -- "$VI_RE" "$d/prompt.md"; then got_pl=vi; else got_pl=en; fi
  else got_pl=missing; fi
  assert_eq "AC21 $id prompt is in $plang [D13]" "$plang" "$got_pl"
  assert_file "AC19 $id has setup.sh" "$d/setup.sh"
  if [ -n "$f2p" ]; then
    if [ -s "$d/solution.patch" ]; then t_ok "AC19 $id has a non-empty solution.patch"
    else t_bad "AC19 $id has a non-empty solution.patch" "missing or empty: $d/solution.patch"; fi
  else
    assert_no_path "AC19 $id has no F2P, so no solution.patch file [D18]" "$d/solution.patch"
  fi
  # setup.sh refuses an existing non-empty target and leaves it alone
  ne="$(mk_tmp)"; printf 'keep\n' > "$ne/keep.txt"
  if [ -f "$d/setup.sh" ]; then
    run bash "$d/setup.sh" "$ne"
    if [ "$RC" != 0 ] && [ "$RC" != 127 ]; then t_ok "AC19 $id setup.sh refuses a non-empty target (exit $RC)"
    else t_bad "AC19 $id setup.sh refuses a non-empty target" "exit $RC; output: $OUT"; fi
  else
    t_bad "AC19 $id setup.sh refuses a non-empty target" "no setup.sh"
  fi
  assert_eq "AC19 $id setup.sh leaves the non-empty target unchanged" "./keep.txt keep" \
    "$(cd "$ne" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//') $(cat "$ne/keep.txt" 2>/dev/null)"
  case "$(conf_val "$conf" language)" in node) c_node=$((c_node + 1)) ;; python3) c_py=$((c_py + 1)) ;; bash) c_bash=$((c_bash + 1)) ;; esac
  case "$got_pl" in vi) c_vi=$((c_vi + 1)) ;; en) c_en=$((c_en + 1)) ;; esac
done <<EOF
$CORPUS
EOF
assert_eq "AC21 languages: node 9, python3 3, bash 1 [D1]" "9 3 1" "$c_node $c_py $c_bash"
assert_eq "AC21 prompts: 6 Vietnamese, 7 English [D1]" "6 7" "$c_vi $c_en"

echo "AC20/AC21 every task passes evals/check-tasks.sh"
assert_file "AC20 evals/check-tasks.sh exists" "$CHECK"
run bash "$CHECK" --tasks-dir "$TASKS"
assert_rc "AC21 check-tasks over the corpus exits 0" 0
while IFS='|' read -r id lang plang weight f2p p2p; do
  [ -n "$id" ] || continue
  if [ "$lang" = python3 ] && [ "$HAVE_PY" = 0 ]; then
    if printf '%s\n' "$OUT" | grep -Eq -- "^$id .*SKIPPED \(no python3\)"; then t_ok "AC20 $id SKIPPED (no python3) on this host"
    else t_bad "AC20 $id SKIPPED (no python3) on this host" "$OUT"; fi
  else
    if printf '%s\n' "$OUT" | grep -Eq -- "^$id SELF-CHECK OK( |\$)"; then t_ok "AC21 $id SELF-CHECK OK"
    else t_bad "AC21 $id SELF-CHECK OK" "$(printf '%s\n' "$OUT" | grep -E -- "^$id " || echo "no line for $id")"; fi
  fi
done <<EOF
$CORPUS
EOF

echo "AC22 no private names (denylist from PB_CORPUS_DENYLIST, never committed) [D12]"
# deny_hits DIR LIST -> prints the 1-based index of every denylisted word found (case-insensitive) in file names or contents
deny_hits() {
  local all w i=0 IFS_OLD="$IFS"
  all="$(mk_tmp)/all.txt"
  { (cd "$1" && find . -print); find "$1" -type f -exec cat {} + 2>/dev/null; } | tr 'A-Z' 'a-z' > "$all"
  IFS=','
  for w in $2; do
    i=$((i + 1))
    w="$(printf '%s' "$w" | tr 'A-Z' 'a-z' | sed 's/^ *//; s/ *$//')"
    [ -n "$w" ] || continue
    if grep -qF -- "$w" "$all"; then printf '%s ' "$i"; fi
  done
  IFS="$IFS_OLD"
}
probe="$(mk_tmp)"; printf 'Order from ACMEPRINT shop\n' > "$probe/x.txt"
assert_eq "AC22 the denylist scan finds a word in any case (self-test)" "2 " "$(deny_hits "$probe" "nothing-here,acmeprint")"
if [ -n "${PB_CORPUS_DENYLIST:-}" ]; then
  assert_eq "AC22 no denylisted word in evals/tasks (indexes of hits shown, not the words)" "" "$(deny_hits "$TASKS" "$PB_CORPUS_DENYLIST")"
else
  t_skip 1 "PB_CORPUS_DENYLIST is not set (the private name list stays local; run with it before a release)"
fi

echo "review fixes 6/7: the prompts state what the hidden tests require (hidden tests unchanged)"
P3="$TASKS/pattern-03-second-screen/prompt.md"
assert_eq "fix6 pattern-03 prompt puts the inbox in scope (it names the inbox; inbox-system is FAIL_TO_PASS)" "yes" \
  "$(grep -qi 'inbox' "$P3" 2>/dev/null && echo yes || echo no)"
P1="$TASKS/pattern-01-option-value-label/prompt.md"
P1T="$(tr '\n' ' ' < "$P1" 2>/dev/null)"
assert_eq "fix7 pattern-01 prompt says the API accepts option values only" "yes" \
  "$(printf '%s\n' "$P1T" | grep -Eiq 'only (the |option |the option )?values?|values? only' && echo yes || echo no)"
assert_eq "fix7 pattern-01 prompt says a label is not accepted" "yes" \
  "$(printf '%s\n' "$P1T" | grep -Eiq "not (the |a |an |by )?(option |choice )?labels?|labels? (are|is) (not|never)|never (the |a )?labels?" && echo yes || echo no)"
# characterization (passes today on purpose): review fix 7 keeps this hidden case
assert_contains "fix7 pattern-01 keeps the hidden case 'a label sent in place of a value is not a known choice'" \
  "$(cat "$TASKS/pattern-01-option-value-label/hidden/tests/pricing-value.f2p.test.js" 2>/dev/null)" "a label sent in place of a value is not a known choice"

echo "AC23 evals/tasks/README.md"
R="$TASKS/README.md"
assert_file "AC23 README exists" "$R"
RT="$(cat "$R" 2>/dev/null)"
for k in task.conf prompt.md setup.sh solution.patch hidden/tests fail_to_pass pass_to_pass expected_weight language source; do
  assert_contains "AC23 README describes $k" "$RT" "$k"
done
assert_contains "AC23 README process line names v0.26.0" "$RT" "v0.26.0"
assert_contains "AC23 README process line: real bugs become synthetic tasks" "$RT" "synthetic"
t_summary
