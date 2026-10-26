#!/usr/bin/env bash
# Tests for the outcome-eval task corpus evals/tasks/ (v0.27.0 lane O, slices S0b-S0c, AC19, AC21-AC23).
# Per task: task.conf metadata, the hidden tests (FAIL_TO_PASS / PASS_TO_PASS lists pinned here), the canary, the
# prompt language, setup.sh refusing a non-empty target, solution.patch presence, then evals/check-tasks.sh over the
# whole corpus (setup twice with one HEAD, F2P fail and P2P pass unsolved, all pass after solution.patch).
# DECISION[D1] 13 tasks (node 9, python3 3, bash 1; prompts VI 6 / EN 7); K2 adds pattern-10..19 (node 9, bash 1; VI 4 / EN 6) = 23 tasks; v0.28.2 lane n adds oss-05, oss-06, pattern-20 (node 1, python3 1, bash 1;
# VI 1 / EN 2; hidden input classes the prompt implies with "any"/"every"/"whatever") = 26 tasks. DECISION[D13] every id, weight, file split
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
oss-04-path-traversal|node|en|Full|tests/static-traversal.f2p.test.js|tests/static-inside.p2p.test.js
pattern-10-cents-three-files|node|en|Full|tests/coupons-cents.f2p.test.js tests/shipping-cents.f2p.test.js tests/tax-cents.f2p.test.js tests/checkout-total.f2p.test.js|tests/money.p2p.test.js
pattern-11-date-parser-symptom|node|vi|Lite|tests/partner-dates.f2p.test.js|tests/report-render.p2p.test.js tests/web-dates.p2p.test.js
pattern-12-hidden-receipt|node|vi|Lite|tests/invoice-name.f2p.test.js tests/receipt-name.f2p.test.js|tests/packing-slip.p2p.test.js tests/display-name.p2p.test.js
pattern-13-restore-value-label|node|en|Lite|tests/restore-values.f2p.test.js|tests/restore-stale.p2p.test.js
pattern-14-wrong-visible-test|node|en|Full|tests/fees.test.js tests/fees-policy.f2p.test.js|tests/notice-format.p2p.test.js
pattern-15-erase-account-ambiguous|node|vi|Full|tests/decision-logged.f2p.test.js tests/delete-account.f2p.test.js|tests/login.p2p.test.js
pattern-16-negative-stock-not-a-bug|node|en|Lite||tests/labels.p2p.test.js tests/preorder-negative.p2p.test.js tests/regular-stock.p2p.test.js
pattern-17-datefmt-major-upgrade|node|en|Full|tests/upgrade.f2p.test.js|tests/app.p2p.test.js tests/vendor-intact.p2p.test.js
pattern-18-split-name-migration|node|vi|Full|tests/migration-004.f2p.test.js|tests/migrations-old.p2p.test.js
pattern-19-archive-spaces|bash|en|Lite|tests/archive-names.f2p.sh|tests/archive-plain.p2p.sh
oss-05-slug-separators|node|en|Lite|tests/slug-names.f2p.test.js|tests/slug-plain.p2p.test.js
oss-06-conf-value-equals|bash|en|Lite|tests/conf-values.f2p.sh|tests/conf-basic.p2p.sh
pattern-20-period-last-day|python3|vi|Lite|tests/test_period_report_last_day.py tests/test_period_invoice_last_day.py|tests/test_period_inside.py'

# K2 AC17: id|scope|traps of the ten new tasks, then the three of v0.28.2 lane n (scope= is space-separated, traps= comma list; 01-spec.md "Tasks")
NEWMETA='pattern-10-cents-three-files|src/coupons.js src/shipping.js src/tax.js src/checkout.js|multi-file
pattern-11-date-parser-symptom|src/import/|misleading-symptom
pattern-12-hidden-receipt|src/docs/invoice.js src/mail/receipt.js src/names.js|hidden-second-place,multi-file
pattern-13-restore-value-label|src/cart/restore.js|value-label-fixture,hidden-second-place
pattern-14-wrong-visible-test|src/fees.js|wrong-visible-test
pattern-15-erase-account-ambiguous|src/accounts.js src/auth.js docs/decisions.md|ambiguous-default
pattern-16-negative-stock-not-a-bug|docs/|not-a-bug
pattern-17-datefmt-major-upgrade|package.json package-lock.json node_modules/ src/|dependency-upgrade,multi-file
pattern-18-split-name-migration|migrations/ src/users.js docs/decisions.md|migration-rollback
pattern-19-archive-spaces|bin/ lib/|misleading-symptom,multi-file
oss-05-slug-separators|src/|input-classes
oss-06-conf-value-equals|lib/ bin/|input-classes
pattern-20-period-last-day|src/|hidden-second-place,input-classes'

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
assert_eq "K2 AC17 26 task directories under evals/tasks (23 + 3 of v0.28.2) [D1]" 26 "${n_dirs:-0}"
c_node=0; c_py=0; c_bash=0; c_vi=0; c_en=0
while IFS='|' read -r id lang plang weight f2p p2p; do
  [ -n "$id" ] || continue
  d="$TASKS/$id"; conf="$d/task.conf"
  echo "-- $id"
  assert_file "AC19 $id has task.conf" "$conf"
  assert_eq "AC19 $id task.conf id is the directory name" "$id" "$(conf_val "$conf" id)"
  if [ -n "$(conf_val "$conf" scope)" ]; then t_ok "K2 AC17/AC18 $id has a non-empty scope= key"
  else t_bad "K2 AC17/AC18 $id has a non-empty scope= key" "no scope= line in $conf"; fi
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
assert_eq "K2 AC17 languages: node 19, python3 4, bash 3 [D1]" "19 4 3" "$c_node $c_py $c_bash"
assert_eq "K2 AC17 prompts: 11 Vietnamese, 15 English [D1]" "11 15" "$c_vi $c_en"

echo "K2 AC17 scope, traps and wrong fixes of the ten new tasks"
while IFS='|' read -r id scp trp; do
  [ -n "$id" ] || continue
  conf="$TASKS/$id/task.conf"
  assert_eq "K2 AC17 $id scope=" "$scp" "$(conf_val "$conf" scope)"
  assert_eq "K2 AC17 $id traps=" "$trp" "$(conf_val "$conf" traps)"
  nw="$(ls "$TASKS/$id/testdata/" 2>/dev/null | grep -c '^wrong-.*\.patch$')"
  if [ "${nw:-0}" -ge 2 ]; then t_ok "K2 AC17 $id has at least 2 wrong-*.patch ($nw)"
  else t_bad "K2 AC17 $id has at least 2 wrong-*.patch" "found ${nw:-0} in $TASKS/$id/testdata"; fi
done <<EOF
$NEWMETA
EOF

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

echo "K2 AC5 prompts do not reveal hidden tests: no hidden file basename, at most 160 words, no must-not-name word [D9]"
# id|must-not-name words (comma list, 01-spec.md "Tasks"), matched as substrings, ASCII case folded
MNN='pattern-10-cents-three-files|shipping.js,tax.js,toCents
pattern-11-date-parser-symptom|parse,dates.js,DD/MM,05/03
pattern-12-hidden-receipt|receipt,e-mail,mail,biên nhận,displayName
pattern-13-restore-value-label|addon,extra,label,value,fixture
pattern-14-wrong-visible-test|tests/fees.test.js,visible test
pattern-15-erase-account-ambiguous|order,đơn hàng,decisions.md,retention
pattern-16-negative-stock-not-a-bug|pre-order,preorder,backorder,docs
pattern-17-datefmt-major-upgrade|utc,timeZone,parse,report.js,throws
pattern-18-split-name-migration|round trip,expand,contract,keep,giữ
pattern-19-archive-spaces|manifest,IFS,find,quote
oss-05-slug-separators|accent,diacritic,unicode,leading,trailing,consecutive,underscore,đ
oss-06-conf-value-equals|last,prefix,twice,comment,quote,dash,spaces,glob
pattern-20-period-last-day|hóa đơn,invoice,billing,23:59,một ngày,one day'
# prompt_hits FILE WORDS -> the 1-based index of every word of the comma list WORDS found in FILE
prompt_hits() {
  local low w i=0 IFS_OLD="$IFS"
  low="$(LC_ALL=C tr 'A-Z' 'a-z' < "$1" 2>/dev/null)"
  IFS=','
  for w in $2; do
    i=$((i + 1))
    w="$(printf '%s' "$w" | LC_ALL=C tr 'A-Z' 'a-z')"
    [ -n "$w" ] || continue
    if printf '%s\n' "$low" | grep -qF -- "$w"; then printf '%s ' "$i"; fi
  done
  IFS="$IFS_OLD"
}
probe="$(mk_tmp)"; printf 'The Receipt E-mail of đơn hàng 42\n' > "$probe/p.md"
assert_eq "AC5 the must-not-name scan finds words in any ASCII case and Vietnamese words (self-test)" "2 3 4 " \
  "$(prompt_hits "$probe/p.md" "invoice,receipt,e-mail,đơn hàng")"
for d in "$TASKS"/*/; do
  d="${d%/}"; id="${d##*/}"; p="$d/prompt.md"
  [ -f "$p" ] || continue
  nw="$(wc -w < "$p" | tr -d ' ')"
  if [ "$nw" -le 160 ]; then t_ok "AC5 $id prompt has at most 160 words ($nw)"; else t_bad "AC5 $id prompt has at most 160 words" "$nw words"; fi
  bn="$( (cd "$d/hidden" 2>/dev/null && find . -type f) | sed 's#.*/##' | tr '\n' ',')"
  assert_eq "AC5 $id prompt names no hidden test file" "" "$(prompt_hits "$p" "$bn")"
done
while IFS='|' read -r id words; do
  [ -n "$id" ] || continue
  if [ -f "$TASKS/$id/prompt.md" ]; then
    assert_eq "AC5 $id prompt uses no must-not-name word (indexes into: $words)" "" "$(prompt_hits "$TASKS/$id/prompt.md" "$words")"
  else
    t_skip 1 "$id is not in the corpus yet (slices S4-S6 add it; AC17 pins its presence)"
  fi
done <<EOF
$MNN
EOF

echo "K2 review fix 2: pattern-15 decision-logged accepts the common ways to say the orders are kept"
# Each probe appends one new "## " entry holding PHRASE to docs/decisions.md of a fresh pattern-15 setup repo and runs the
# hidden decision-logged test alone. Phrasings from the 28-k2 review probe (grep.sh) plus made-up negatives.
P15="$TASKS/pattern-15-erase-account-ambiguous"
# id|expected (pass/fail)|phrase
DEC_PROBES='preserved|pass|Orders are preserved for accounting.
remain|pass|Orders remain in the store.
not-deleted|pass|Orders are not deleted.
not-be-removed|pass|Orders will not be removed.
stay|pass|Orders stay, anonymised.
intact|pass|Order history stays intact.
retained|pass|Orders are retained for tax.
vi-giu|pass|Đơn hàng được giữ lại.
vi-khong-xoa|pass|Đơn hàng không xóa.
vi-khong-bi-xoa|pass|Đơn hàng không bị xoá khi xóa tài khoản.
vi-van-con|pass|Đơn hàng vẫn còn trong hệ thống.
deleted|fail|Orders are deleted with the account.
removed|fail|Orders are removed.
no-order-word|fail|Account data is preserved.'
NDEC="$(printf '%s\n' "$DEC_PROBES" | grep -c '|')"
if ! command -v node >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  t_skip "$NDEC" "node or git is missing (the pattern-15 decision probes run the hidden node test)"
else
  dw="$(mk_tmp)"
  if bash "$P15/setup.sh" "$dw/r" >/dev/null 2>&1 && mkdir -p "$dw/r/tests" \
    && cp "$P15/hidden/tests/decision-logged.f2p.test.js" "$dw/r/tests/"; then
    while IFS='|' read -r pid pexp phrase; do
      [ -n "$pid" ] || continue
      (cd "$dw/r" && git checkout -q -- docs/decisions.md) 2>/dev/null
      printf '\n## 2026-10-26 Erasing an account\n%s\n' "$phrase" >> "$dw/r/docs/decisions.md"
      if (cd "$dw/r" && node --test tests/decision-logged.f2p.test.js) >/dev/null 2>&1; then got=pass; else got=fail; fi
      assert_eq "fix2 decision-logged $pexp: '$phrase' ($pid)" "$pexp" "$got"
    done <<EOF
$DEC_PROBES
EOF
  else
    t_bad "fix2 pattern-15 setup for the decision probes" "setup.sh or the copy of the hidden test failed"
    t_skip "$((NDEC - 1))" "pattern-15 setup failed"
  fi
fi

echo "AC23 evals/tasks/README.md"
R="$TASKS/README.md"
assert_file "AC23 README exists" "$R"
RT="$(cat "$R" 2>/dev/null)"
for k in task.conf prompt.md setup.sh solution.patch hidden/tests fail_to_pass pass_to_pass expected_weight language source; do
  assert_contains "AC23 README describes $k" "$RT" "$k"
done
assert_contains "AC23 README process line names v0.26.0" "$RT" "v0.26.0"
assert_contains "AC23 README process line: real bugs become synthetic tasks" "$RT" "synthetic"
assert_contains "K2 AC16 README documents the scope= key of task.conf" "$RT" "scope="
assert_contains "K2 AC16 README documents the wrong fixes in testdata/wrong-*.patch" "$RT" "testdata/wrong-"
RTL="$(printf '%s' "$RT" | LC_ALL=C tr 'A-Z' 'a-z')"
assert_contains "K2 AC16 README documents the traps= key" "$RT" "traps="
assert_contains "K2 AC16 README names the extra_files_changed metric" "$RT" "extra_files_changed"
assert_contains "K2 AC16 README names the tests_weakened metric" "$RT" "tests_weakened"
assert_contains "K2 AC16 README states the heuristic of the metrics" "$RTL" "heuristic"
assert_contains "K2 AC16 README lists false positives" "$RTL" "false positive"
assert_contains "K2 AC16 README states the calibration rule" "$RTL" "calibration"
# review 28-k2 findings 3 and 6: the metric blind spots and the scope glob note (pins only; the README text is the implementer's)
KFP="$(printf '%s\n' "$RT" | awk '/Known false positives/ { f = 1 } f && /^[[:space:]]*$/ { exit } f')"
assert_contains "fix3 README 'Known false positives / misses' names a data key such as { skip: 10 } counted as a skip marker" "$KFP" "skip"
assert_contains "fix3 README 'Known false positives / misses' names node:test context assertions t.assert.* as not counted" "$KFP" "t.assert"
assert_eq "fix6 README says a scope glob \`*\` also matches \`/\` (one line naming \`*\`, \`/\` and 'match')" "yes" \
  "$(printf '%s\n' "$RT" | grep -F '`*`' | grep -F '`/`' | grep -qi 'match' && echo yes || echo no)"
t_summary
