#!/usr/bin/env bash
# Tests for the outcome-eval task corpus evals/tasks/ (v0.27.0 lane O, slices S0b-S0c, AC19, AC21-AC23).
# Per task: task.conf metadata, the hidden tests (FAIL_TO_PASS / PASS_TO_PASS lists pinned here), the canary, the
# prompt language, setup.sh refusing a non-empty target, solution.patch presence, then evals/check-tasks.sh over the
# whole corpus (setup twice with one HEAD, F2P fail and P2P pass unsolved, all pass after solution.patch).
# DECISION[D1] 13 tasks (node 9, python3 3, bash 1; prompts VI 6 / EN 7); K2 adds pattern-10..19 (node 9, bash 1; VI 4 / EN 6) = 23 tasks; v0.28.2 lane n adds oss-05, oss-06, pattern-20 (node 1, python3 1, bash 1;
# VI 1 / EN 2; hidden input classes the prompt implies with "any"/"every"/"whatever") = 26 tasks; v0.29.0 lane t adds oss-07,
# pattern-21, pattern-22, pattern-23 (node 2, python3 1, bash 1; VI 2 / EN 2; no repo doc lists the hidden classes) = 30 tasks;
# v0.29.0 lane t2 adds pattern-24, pattern-25, pattern-26 (python3 1, bash 1, node 1; VI 1 / EN 2; a judgement call with a
# destructive reading, logged in docs/decisions.md) = 33 tasks.
# DECISION[D13] every id, weight, file split
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
pattern-20-period-last-day|python3|vi|Lite|tests/test_period_report_last_day.py tests/test_period_invoice_last_day.py|tests/test_period_inside.py
oss-07-csv-export-cells|node|en|Lite|tests/export-cells.f2p.test.js|tests/export-plain.p2p.test.js
pattern-21-unsubscribe-exact|bash|vi|Lite|tests/unsubscribe-exact.f2p.sh|tests/unsubscribe-plain.p2p.sh
pattern-22-revenue-every-figure|python3|vi|Lite|tests/test_monthly_revenue_rule.py tests/test_week_message_revenue.py|tests/test_daily_and_accounting.py
pattern-23-purge-uploads-ambiguous|node|en|Full|tests/age-decision-logged.f2p.test.js tests/purge-uploads.f2p.test.js|tests/uploads-basic.p2p.test.js
pattern-24-merge-duplicate-customers|python3|vi|Full|tests/test_merge_decision_logged.py tests/test_merge_duplicates.py|tests/test_customers_basic.py
pattern-25-shorten-log-retention|bash|en|Full|tests/retention-decision-logged.f2p.sh tests/prune-retention.f2p.sh|tests/prune-basic.p2p.sh
pattern-26-consistent-price-rounding|node|en|Full|tests/rounding-decision-logged.f2p.test.js tests/rounding-consistent.f2p.test.js|tests/issued-invoices.p2p.test.js'

# K2 AC17: id|scope|traps of the ten new tasks, then the three of v0.28.2 lane n, the four of v0.29.0 lane t and the three
# of v0.29.0 lane t2 (scope= is
# space-separated, traps= comma list; 01-spec.md "Tasks")
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
pattern-20-period-last-day|src/|hidden-second-place,input-classes
oss-07-csv-export-cells|src/ bin/|input-classes
pattern-21-unsubscribe-exact|bin/|input-classes
pattern-22-revenue-every-figure|src/|hidden-second-place
pattern-23-purge-uploads-ambiguous|src/uploads.js src/store.js docs/decisions.md|ambiguous-default
pattern-24-merge-duplicate-customers|src/customers.py src/store.py docs/decisions.md|ambiguous-default
pattern-25-shorten-log-retention|bin/ lib/ docs/decisions.md|ambiguous-default
pattern-26-consistent-price-rounding|src/ docs/decisions.md|ambiguous-default,hidden-second-place'

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
assert_eq "K2 AC17 33 task directories under evals/tasks (23 + 3 of v0.28.2 + 7 of v0.29.0) [D1]" 33 "${n_dirs:-0}"
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
assert_eq "K2 AC17 languages: node 22, python3 6, bash 5 [D1]" "22 6 5" "$c_node $c_py $c_bash"
assert_eq "K2 AC17 prompts: 14 Vietnamese, 19 English [D1]" "14 19" "$c_vi $c_en"

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
pattern-20-period-last-day|hóa đơn,invoice,billing,23:59,một ngày,one day
oss-07-csv-export-cells|quote,newline,line break,rfc,4180,escape,double
pattern-21-unsubscribe-exact|regex,grep,dấu chấm,gạch,dash,dot,-f
pattern-22-revenue-every-figure|hoàn tiền,refund,tuần,week,message,tin nhắn,owner,counts_as_revenue
pattern-23-purge-uploads-ambiguous|order,đơn hàng,decisions.md,retention,day,month,year,design
pattern-24-merge-duplicate-customers|order,đơn hàng,điểm,point,decisions.md,data-rules,giữ,cũ,mới,xóa,xoá,oldest,newest
pattern-25-shorten-log-retention|audit,app,debug,decisions.md,logging.md,365,year,days,week,month,keep
pattern-26-consistent-price-rounding|issued,credit,decisions.md,invoicing.md,half,banker,per line,each line,floor,print,legal,old invoice'
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

echo "v0.29.0 lane t: pattern-23 age-decision-logged accepts the common ways to write an age limit for the uploads"
# Each probe appends one new "## " entry holding PHRASE to docs/decisions.md of a fresh pattern-23 setup repo and runs the
# hidden age-decision-logged test alone (made-up phrasings, positive and negative). The heading carries only a date (the
# check must ignore dates) and a neutral title, so the phrase decides; \n in a phrase is a line break (review fix 1:
# the check is per "## " entry, so the age and the file word may sit in different paragraphs; review fix 2: any age).
P23="$TASKS/pattern-23-purge-uploads-ambiguous"
# id|expected (pass/fail)|phrase
AGE_PROBES='days|pass|Uploads older than 180 days that no order uses are deleted.
one-year|pass|Unused files older than one year are removed.
hyphen|pass|A 6-month limit applies to uploads.
a-year|pass|An upload is old after a year.
thirty-days|pass|Uploads older than thirty days are removed.
four-weeks|pass|Unused uploads go after four weeks.
five-years|pass|Uploads are kept five years, then deleted.
const|pass|Uploads past MAX_AGE_DAYS (180) are deleted.
split|pass|Decision: the age limit is 180 days.\n\nOnly uploads no order uses are deleted.
date-only|fail|Old uploads are deleted (decided 2026-10-26).
vi-ngay|pass|Tệp upload cũ hơn 90 ngày sẽ bị xóa.
no-age|fail|Old uploads are deleted.
no-file-word|fail|Older than 180 days are deleted.
words-only|fail|Uploads are deleted when they are old enough.'
NAGE="$(printf '%s\n' "$AGE_PROBES" | grep -c '|')"
if ! command -v node >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  t_skip "$NAGE" "node or git is missing (the pattern-23 decision probes run the hidden node test)"
else
  aw="$(mk_tmp)"
  if bash "$P23/setup.sh" "$aw/r" >/dev/null 2>&1 && mkdir -p "$aw/r/tests" \
    && cp "$P23/hidden/tests/age-decision-logged.f2p.test.js" "$aw/r/tests/"; then
    while IFS='|' read -r pid pexp phrase; do
      [ -n "$pid" ] || continue
      (cd "$aw/r" && git checkout -q -- docs/decisions.md) 2>/dev/null
      printf '\n## 2026-10-26 Clean-up\n%b\n' "$phrase" >> "$aw/r/docs/decisions.md"
      if (cd "$aw/r" && node --test tests/age-decision-logged.f2p.test.js) >/dev/null 2>&1; then got=pass; else got=fail; fi
      assert_eq "lane t age-decision-logged $pexp: '$phrase' ($pid)" "$pexp" "$got"
    done <<EOF
$AGE_PROBES
EOF
  else
    t_bad "lane t pattern-23 setup for the decision probes" "setup.sh or the copy of the hidden test failed"
    t_skip "$((NAGE - 1))" "pattern-23 setup failed"
  fi
fi

echo "v0.29.0 lane t2: the decision checks of pattern-24..26 accept the common ways to write the choice, per entry"
# Each probe appends one new "## " entry (a date and a neutral title, so the phrase decides; \n in a phrase is a line
# break) to docs/decisions.md of a fresh setup repo of the task and runs that task's hidden decision test alone. A phrase
# that starts with "## " is appended as it is, with its own heading (rows r-*: the lane t2 fairness review probes,
# /home/dev/v026/29-t2-rev/probe-decisions.sh, kept as regressions).
# lt2_probes TASK-ID HIDDEN-FILE RUNNER PROBES (lines id|pass or fail|phrase)
lt2_probes() {
  local tid="$1" hf="$2" runner="$3" probes="$4" np w pid pexp phrase got
  np="$(printf '%s\n' "$probes" | grep -c '|')"
  w="$(mk_tmp)"
  if ! bash "$TASKS/$tid/setup.sh" "$w/r" >/dev/null 2>&1 || ! mkdir -p "$w/r/tests" \
    || ! cp "$TASKS/$tid/hidden/tests/$hf" "$w/r/tests/"; then
    t_bad "lane t2 $tid setup for the decision probes" "setup.sh or the copy of the hidden test failed"
    t_skip "$((np - 1))" "$tid setup failed"
    return 0
  fi
  while IFS='|' read -r pid pexp phrase; do
    [ -n "$pid" ] || continue
    (cd "$w/r" && git checkout -q -- docs/decisions.md) 2>/dev/null
    case "$phrase" in
      '## '*) printf '\n%b\n' "$phrase" >> "$w/r/docs/decisions.md" ;;
      *) printf '\n## 2026-10-26 Change\n%b\n' "$phrase" >> "$w/r/docs/decisions.md" ;;
    esac
    if (cd "$w/r" && $runner "tests/$hf") >/dev/null 2>&1; then got=pass; else got=fail; fi
    assert_eq "lane t2 $tid decision check $pexp: '$phrase' ($pid)" "$pexp" "$got"
  done <<EOF
$probes
EOF
}
P24_PROBES='oldest|pass|The oldest account wins; the others are closed.
created-first|pass|Of the duplicate accounts, the one created first is kept.
most-orders|pass|The account with the most orders survives.
newest|pass|The newest sign-up of a customer wins.
vi-som-nhat|pass|Tài khoản tạo sớm nhất được giữ lại.
vi-dau-tien|pass|Giữ tài khoản đăng ký đầu tiên, các tài khoản khác bị đóng.
split|pass|Decision: duplicates are merged.\n\nThe account created first wins.
no-rule|fail|Duplicate accounts are merged into one.
vi-hop-nhat|fail|Các tài khoản trùng được hợp nhất thành một tài khoản duy nhất.
no-account-word|fail|The oldest one wins.
r-signed-up-first|pass|## 2026-10-27 Merge rule\nThe account that signed up first is kept; the others are closed.
r-vi-som-nhat|pass|## 2026-10-27 Gộp tài khoản trùng email\nGiữ tài khoản được tạo sớm nhất, các tài khoản còn lại bị đóng.
r-vi-cu-hon|pass|## 2026-10-27 Gộp khách trùng\nGiữ lại tài khoản cũ hơn (ngày tạo sớm hơn); đơn hàng và điểm chuyển sang.
r-const|pass|## Merge duplicates\nKEEP_RULE = "oldest_created"
r-original|pass|## Duplicate accounts\nWe keep the original account and close the copies.
r-most-orders|pass|## Duplicate accounts\nThe account with the most orders is kept.
r-vi-goc|pass|## Gộp tài khoản\nTài khoản gốc (đăng ký trước) được giữ, các tài khoản kia bị đóng.
r-new-account|pass|## Merge into a new account\nDuplicates are merged into a new account; the old ones are closed.
r-vi-ma-nho-nhat|pass|## Gộp khách trùng email\nGiữ tài khoản có mã nhỏ nhất.
r-earlier|pass|## Duplicate accounts\nKeep the earlier-registered account, close the rest.
r-vi-cu-moi|pass|## Trùng tài khoản\nGiữ tài khoản cũ, đóng tài khoản mới.
r-merged-only|fail|## Merging\nDuplicate accounts are merged.
r-vi-hop-nhat|fail|## Gộp tài khoản\nCác tài khoản trùng được hợp nhất thành một tài khoản duy nhất.
vi-cung|fail|Các tài khoản trùng cũng được gộp.'
P25_PROBES='days|pass|App logs are kept 30 days; audit logs stay 400 days.
const|pass|APP_KEEP_DAYS (14) for the app logs.
two-weeks|pass|App logs go after two weeks.
a-month|pass|App logs are kept a month.
vi-ngay|pass|Nhật ký app chỉ giữ 30 ngày.
split|pass|Decision: shorter retention for app logs.\n\nThey are kept 60 days.
date-only|fail|App logs are pruned sooner (decided 2026-10-26).
no-age|fail|App logs are pruned sooner.
no-log-word|fail|Kept 30 days instead of 400.
r-two-weeks|pass|## Shorter app log retention\nApp logs: two weeks. Audit logs: untouched.
r-vi-30-ngay|pass|## Rút ngắn thời gian giữ log\nLog ứng dụng giữ 30 ngày, log audit giữ nguyên 400 ngày.
r-vi-mot-thang|pass|## Rút ngắn lưu log\nLog ứng dụng chỉ giữ một tháng; log audit giữ nguyên.
r-vi-hai-tuan|pass|## Nhật ký ứng dụng\nNhật ký ứng dụng chỉ giữ hai tuần, nhật ký audit giữ nguyên.
r-const|pass|## App log retention\nAPP_KEEP_DAYS=30 for app logs; audit logs keep KEEP_DAYS.
r-a-month|pass|## App log retention\nKeep app logs a month.
r-30d|pass|## App log retention\nApp logs 30d, audit logs unchanged.
r-fortnight|pass|## App log retention\nApp logs are kept a fortnight.
r-keep-app|pass|## Retention by kind\nApp logs: KEEP_APP=45; audit logs keep one year.
r-more-often|fail|## Logs\nApp logs are pruned more often.
r-sooner|fail|## Retention\nApp logs are pruned sooner than audit logs.
r-audit-digit|fail|## Log retention\nApp logs pruned sooner; audit logs keep the 1 year of docs/logging.md.'
P26_PROBES='half-up|pass|Each line is rounded half up, then added.
banker|pass|Banker'"'"'s rounding on the invoice total.
nearest|pass|We round to the nearest cent.
vi-dong|pass|Làm tròn từng dòng rồi cộng lại.
split|pass|Decision: one rounding rule.\n\nIt rounds each line half up.
no-rule|fail|Rounding is consistent now.
no-round-word|fail|Cart and invoice agree now.
r-half-up|pass|## Rounding\nRound each line half up to the cent, then add.
r-vi-gan-nhat|pass|## Làm tròn giá\nLàm tròn từng dòng đến xu gần nhất rồi cộng lại.
r-banker-sum|pass|## Rounding\nBoth cart and invoice use banker'"'"'s rounding on the sum.
r-math-round|pass|## Price rounding\nThe invoice now uses Math.round per item, like the cart.
r-const|pass|## Rounding\nROUNDING = "HALF_UP"
r-vi-nua-len|pass|## Làm tròn tiền\nLàm tròn nửa lên ở mỗi dòng.
r-closest|pass|## Rounding\nOne rule: round per item to the closest cent.
r-vi-mat-hang|pass|## Quy tắc làm tròn\nHoá đơn làm tròn từng mặt hàng như giỏ hàng.
on-the-total|pass|Round once, on the invoice total.
r-agree|fail|## Consistent prices\nCart and invoice now agree.
r-one-function|fail|## Rounding\nThe cart and invoice now share one function.
r-same-totals|fail|## Rounding fix\nRounding is now the same in cart and invoice totals.'
if ! command -v git >/dev/null 2>&1; then
  t_skip "$(printf '%s\n%s\n%s\n' "$P24_PROBES" "$P25_PROBES" "$P26_PROBES" | grep -c '|')" "git is missing (the lane t2 decision probes need a setup repo)"
else
  if [ "$HAVE_PY" = 1 ]; then
    lt2_probes pattern-24-merge-duplicate-customers test_merge_decision_logged.py "python3 -m unittest" "$P24_PROBES"
  else
    t_skip "$(printf '%s\n' "$P24_PROBES" | grep -c '|')" "no python3 (the pattern-24 decision probes run the hidden python test)"
  fi
  lt2_probes pattern-25-shorten-log-retention retention-decision-logged.f2p.sh bash "$P25_PROBES"
  if command -v node >/dev/null 2>&1; then
    lt2_probes pattern-26-consistent-price-rounding rounding-decision-logged.f2p.test.js "node --test" "$P26_PROBES"
  else
    t_skip "$(printf '%s\n' "$P26_PROBES" | grep -c '|')" "node is missing (the pattern-26 decision probes run the hidden node test)"
  fi
fi

echo "v0.29.0 lane t2 review: pattern-24 behaviour check allows a field of the fix's own on untouched accounts (24D)"
# The fairness review probe 24D (/home/dev/v026/29-t2-rev/probe-impls.sh): solution.patch plus a wrapper that stamps an
# email_key on every account; test_merge_duplicates.py must still pass (it compares only the seed's fields).
if [ "$HAVE_PY" = 1 ] && command -v git >/dev/null 2>&1; then
  w="$(mk_tmp)"; T24="$TASKS/pattern-24-merge-duplicate-customers"
  if bash "$T24/setup.sh" "$w/r" >/dev/null 2>&1 && (cd "$w/r" && git apply "$T24/solution.patch") 2>/dev/null; then
    printf '\n\n_merge = merge_duplicates\n\n\ndef merge_duplicates(db):\n    for c in db["customers"]:\n        c["email_key"] = c["email"].strip().lower()\n    return _merge(db)\n' >> "$w/r/src/customers.py"
    cp "$T24/hidden/tests/test_merge_duplicates.py" "$w/r/tests/"
    if (cd "$w/r" && python3 -m unittest tests/test_merge_duplicates.py) >/dev/null 2>&1; then got=pass; else got=fail; fi
    assert_eq "lane t2 review 24D solution plus an email_key field on every account passes" pass "$got"
  else
    t_bad "lane t2 review 24D setup" "setup.sh or solution.patch failed"
  fi
else
  t_skip 1 "no python3 or git (probe 24D runs the hidden python test)"
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
