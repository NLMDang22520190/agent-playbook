#!/usr/bin/env bash
# Tests for the batch classification in scripts/role-gate.sh (v0.24.14 lane G, slice S1): `check` and `size` classify the
# changed paths with a constant number of grep processes, and every output byte stays as it was in v0.24.13.
#   AC1  check <role> / size equal today's per-file result on the equivalence corpus (UTF-8 locale and C locale)
#   AC2  the classify subcommand is unchanged
#   AC3  grep processes per run do not grow with the number of changed files (grep shim counts them)
#   AC4  a batch grep that exits 2 reads like today's per-file result (grep shim exits 2 on a multi-line stdin)
#   AC5  a test path whose only change is a mode restore is still a note, in its sorted place
#   AC6  the match stays grep -E with the user's ERE
#   R2   (review round 1) truncated UTF-8 lead byte merges two records in bash 5 (F1), ':' in a path (F2), only the infra batch fails (F3)
# The expected values are today's behaviour: REFERENCE below is the v0.24.13 per-file logic (one grep -Eq per path), copied here.
# Changed paths enter the diff without a work-tree file (git update-index --index-info + commit, then the file is missing:
# a deleted path is still listed), so the odd file names (tab, CR, \377) need no support from the file system.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"

REAL_GREP="$(command -v grep)"; export REAL_GREP
DT="$(mk_tmp)"
PH0="$(mk_tmp)"                                   # a global conf dir with no conf
DEFAULT_RE='(^|/)(test|tests|__tests__|spec|specs|e2e|__mocks__|fixtures|testdata|__snapshots__)(/|$)|(\.test\.|\.spec\.|_test\.|_spec\.)|(^|/)test_[^/]*$|(^|/)conftest\.py$|\.feature$|Tests?\.(java|kt|cs|swift)$|(^|/)(jest|vitest|playwright|cypress)\.config\.[^/]+$|(^|/)karma\.conf\.[^/]+$|(^|/)\.mocharc(\.[^/]+)?$|(^|/)pytest\.ini$|(^|/)phpunit\.xml(\.dist)?$|\.snap$'

# ---------------------------------------------------------------- helpers
chk() { # name expected actual: one assertion, a short diff on failure
  if [ "$2" = "$3" ]; then t_ok "$1"; return; fi
  printf '%s\n' "$2" > "$DT/exp"; printf '%s\n' "$3" > "$DT/act"
  t_bad "$1" "$(diff -a "$DT/exp" "$DT/act" | head -6)"
}
# idx_add PATH... -> put each path into the index of the current repo as a 100644 blob (no work-tree file)
idx_add() {
  local blob p
  blob="$(printf 'l1\nl2\n' | git hash-object -w --stdin)" || return 1
  for p in "$@"; do printf '100644 %s\t%s\0' "$blob" "$p"; done | git update-index -z --index-info
}
# gate_run DIR GLOBAL_CONF_DIR LOCALE ARGS... -> OUT (stdout+stderr), RC; GPATH, when set, replaces PATH (a grep shim dir first)
gate_run() {
  local d="$1" ph="$2" loc="$3"; shift 3
  OUT="$(cd "$d" && env PLAYBOOK_HOME="$ph" LC_ALL="$loc" PATH="${GPATH:-$PATH}" bash "$GATE" "$@" 2>&1 </dev/null)"; RC=$?
}
write_conf() { # DIR TEST_RE INFRA_RE -> DIR/.agents/playbook.conf (global conf of a run)
  mkdir -p "$1/.agents"
  : > "$1/.agents/playbook.conf"
  if [ -n "$2" ]; then printf 'test_path_regex=%s\n' "$2" >> "$1/.agents/playbook.conf"; fi
  if [ -n "$3" ]; then printf 'test_infra_regex=%s\n' "$3" >> "$1/.agents/playbook.conf"; fi
}

# ---------------------------------------------------------------- platform probes (L-0004)
UTF8=""
for l in C.UTF-8 en_US.UTF-8 C.utf8 en_US.utf8; do
  if [ "$(printf '\303\251\n' | LC_ALL=$l "$REAL_GREP" -Ec '^.$' 2>/dev/null)" = 1 ]; then UTF8="$l"; break; fi
done
ODD=( $'src/a\tb.js' $'tests/a\tb.test.js' $'src/cr\r.js' $'tests/cr\r.js' $'x.snap\r'
      $'src/\377.js' $'tests/\377a.test.js' $'src/a\377b.snap' $'a\377b.js' $'\377tests/a.js' )
ODD_OK=0
PROBE="$(mk_tmp)"; mk_repo "$PROBE"
if ( cd "$PROBE" && idx_add "${ODD[@]}" 2>/dev/null && git commit -q -m odd 2>/dev/null &&
     [ "$(git diff --name-only -z HEAD -- | tr -cd '\000' | wc -c | tr -d ' ')" = "${#ODD[@]}" ] ) &&
   [ "$(bash -c 'printf "%s" "$1"' _ $'a\377b' | od -An -tx1 | tr -d ' \n')" = 61ff62 ]; then ODD_OK=1; fi

# ---------------------------------------------------------------- reference: v0.24.13 per-file logic
CT=( "" "" "" '^tests/|^-' '\.js$' 'x*' '[0-9]{2}' '[[:digit:]]' 'caf./|a.b|\.snap$' '^.*$' "" '(/|^)tests(/|$)|^b' )
CI=( "" "" '^ci/|(^|/)tests/helpers/' "" "" "" "" "" "" '^ci/' 'x*' "" )
RKIND=""
ref_class() { # PATH LOCALE TEST_RE INFRA_RE -> RKIND (today: one grep -Eq per path, caller's locale, infra first)
  if [ -n "$4" ] && printf '%s\n' "$1" | LC_ALL="$2" "$REAL_GREP" -Eq -- "$4"; then RKIND=infra; return; fi
  if printf '%s\n' "$1" | LC_ALL="$2" "$REAL_GREP" -Eq -- "$3"; then RKIND="test"; else RKIND="code"; fi
}
ref_changed() { # LOCALE -> the sorted changed list of the current repo
  { git -c core.quotepath=off diff --name-only -z --no-renames HEAD --
    git -c core.quotepath=off ls-files -z --others --exclude-standard; } | tr '\000' '\n' | LC_ALL="$1" sort -u
}
ref_stats() {
  { git -c core.quotepath=off diff --numstat --no-renames HEAD --
    git -c core.quotepath=off ls-files --others --exclude-standard |
      while IFS= read -r u; do
        [ -n "$u" ] || continue
        counts="$(git diff --no-index --numstat -- /dev/null "$u" | cut -f1,2)"
        [ -n "$counts" ] || counts="$(printf '0\t0')"
        printf '%s\t%s\n' "$counts" "$u"
      done; }
}
RK_P=(); RK_K=(); CUR_T=""; CUR_I=""; MODE_OK=0
build_ref() { # CONF_INDEX LOCALE -> kinds of the changed list of the current repo
  local t p
  CUR_T="${CT[$1]}"; CUR_I="${CI[$1]}"; t="$CUR_T"; [ -n "$t" ] || t="$DEFAULT_RE"
  RK_P=(); RK_K=()
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    ref_class "$p" "$2" "$t" "$CUR_I"
    RK_P[${#RK_P[@]}]="$p"; RK_K[${#RK_K[@]}]="$RKIND"
  done <<EOF
$(ref_changed "$2")
EOF
  REF_T="$t"; REF_LOC="$2"
}
EXP=""; EXP_RC=0
ref_add() { EXP="$EXP$1"$'\n'; }
ref_check() { # ROLE -> EXP, EXP_RC
  local role="$1" i=0 n=${#RK_P[@]} p kind bad v=0 c=0
  EXP=""
  if [ -n "$CUR_T" ]; then ref_add "note: test_path_regex from the global conf: $CUR_T"; fi
  if [ -n "$CUR_I" ]; then ref_add "note: test_infra_regex from the global conf: $CUR_I"; fi
  while [ "$i" -lt "$n" ]; do
    p="${RK_P[$i]}"; kind="${RK_K[$i]}"; i=$((i + 1))
    case "$p" in .agents/handoff/*) continue ;; esac
    c=$((c + 1))
    if [ "$role" = implementer ] && [ "$kind" = test ] && [ "$MODE_OK" = 1 ] && [ "$p" = tests/restore.sh ]; then
      ref_add "note: $p mode restore only (100644 -> 100755, content unchanged)"; continue
    fi
    bad=0
    case "$role" in
      tester) [ "$kind" != test ] && bad=1 ;;
      implementer) [ "$kind" != code ] && bad=1 ;;
      infra) [ "$kind" != infra ] && bad=1 ;;
      reviewer) bad=1 ;;
    esac
    if [ "$bad" -eq 1 ]; then ref_add "VIOLATION ($role): $p [$kind]"; v=$((v + 1)); fi
  done
  if [ "$v" -gt 0 ]; then ref_add "role gate FAILED for $role: $v violation(s), base=HEAD"; EXP_RC=1
  else ref_add "OK: role gate passed for $role ($c file(s) checked, base=HEAD)"; EXP_RC=0; fi
  EXP="${EXP%$'\n'}"
}
ref_size() { # MAX_FILES MAX_LINES -> EXP, EXP_RC
  local mf="$1" ml="$2" files=0 lines=0 added deleted f k j n=${#RK_P[@]}
  while IFS=$'\t' read -r added deleted f; do
    [ -n "$f" ] || continue
    case "$f" in .agents/handoff/*) continue ;; esac
    k=""; j=0
    while [ "$j" -lt "$n" ]; do if [ "${RK_P[$j]}" = "$f" ]; then k="${RK_K[$j]}"; break; fi; j=$((j + 1)); done
    if [ -z "$k" ]; then ref_class "$f" "$REF_LOC" "$REF_T" "$CUR_I"; k="$RKIND"; fi   # a git-quoted name is classified as printed
    [ "$k" != test ] || continue
    files=$((files + 1))
    if [ "$added" = "-" ]; then lines=$((lines + 1)); else lines=$((lines + added + deleted)); fi
  done <<EOF
$(ref_stats)
EOF
  EXP="files: $files/$mf lines: $lines/$ml (base=HEAD)"; EXP_RC=0
  if [ "$files" -gt "$mf" ] || [ "$lines" -gt "$ml" ]; then EXP="$EXP"$'\n'"over the Lite size limit: escalate to Full"; EXP_RC=1; fi
}
# gawk warns on stderr about invalid UTF-8 in a path (pb_lost_exec_paths, the mode check): not part of the classification, other awks are silent
no_awk_warn() { printf '%s\n' "$1" | LC_ALL=C "$REAL_GREP" -a -v '^awk: ' || true; }
# corp_combo LABEL DIR CONF_INDEX LOCALE DEFAULT_LIMITS(0|1) -> check x 4 roles + size (+ size with the default limits)
corp_combo() {
  local label="$1" d="$2" ci="$3" loc="$4" defl="$5" role ph prev_lc="${LC_ALL-__unset__}"
  ph="$(mk_tmp)"; write_conf "$ph" "${CT[$ci]}" "${CI[$ci]}"
  cd "$d" || exit 3
  LC_ALL="$loc"   # this shell reads the reference records in the gate's locale (bash 5 merges records only in a UTF-8 locale)
  build_ref "$ci" "$loc"
  for role in tester implementer reviewer infra; do
    gate_run "$d" "$ph" "$loc" check "$role"; ref_check "$role"
    chk "$label check $role, conf $ci, locale $loc: output and exit code as per-file grep" "$EXP"$'\n'"rc=$EXP_RC" "$(no_awk_warn "$OUT")"$'\n'"rc=$RC"
  done
  gate_run "$d" "$ph" "$loc" size --max-files 1000 --max-lines 100000; ref_size 1000 100000
  chk "$label size (wide limits), conf $ci, locale $loc: as per-file grep" "$EXP"$'\n'"rc=$EXP_RC" "$(no_awk_warn "$OUT")"$'\n'"rc=$RC"
  if [ "$defl" = 1 ]; then
    gate_run "$d" "$ph" "$loc" size; ref_size 3 100
    chk "$label size (default limits), conf $ci, locale $loc: over the limit as per-file grep" "$EXP"$'\n'"rc=$EXP_RC" "$OUT"$'\n'"rc=$RC"
  fi
  if [ "$prev_lc" = __unset__ ]; then unset LC_ALL; else LC_ALL="$prev_lc"; fi
}

# ---------------------------------------------------------------- AC2 classify, ASCII class rules (locale independent)
echo "AC2 classify: every class rule of the default regex"
for pair in test:test/x.js test:tests/a.js test:__tests__/y.js test:spec/x.rb test:specs/x.rb test:e2e/x.ts \
            test:src/__mocks__/m.js test:fixtures/f.json test:testdata/t.txt test:src/__snapshots__/x.snap \
            test:src/a.test.ts test:src/a.spec.ts test:pkg/x_test.go test:lib/a_spec.rb test:test_foo.py \
            test:conftest.py test:features/a.feature test:src/FooTest.java test:src/FooTests.kt \
            test:src/Foo.Tests.cs test:src/FooTest.swift test:jest.config.js test:vitest.config.ts \
            test:playwright.config.ts test:cypress.config.js test:karma.conf.js test:.mocharc test:.mocharc.yml \
            test:pytest.ini test:phpunit.xml test:phpunit.xml.dist test:foo.snap test:-x.test.js \
            code:src/contest.js code:src/latest/x.js code:src/app.js code:docs/12.md code:-lead.js code:ci/run.sh; do
  want="${pair%%:*}"; p="${pair#*:}"
  gate_run "$PROBE" "$PH0" C classify "$p"
  chk "AC2 classify $p -> $want" "$want" "$OUT"
done
INFRA_PH="$(mk_tmp)"; write_conf "$INFRA_PH" "" '^ci/|(^|/)tests/helpers/'
for pair in infra:ci/run.sh infra:tests/helpers/h.js test:tests/a.js code:src/app.js; do
  want="${pair%%:*}"; p="${pair#*:}"
  gate_run "$PROBE" "$INFRA_PH" C classify "$p"
  chk "AC2 classify $p -> $want with test_infra_regex (infra wins)" "$want" "$OUT"
done

# ---------------------------------------------------------------- the corpus repo
PLAIN=( "tests/a.test.js" "ci/run.sh" "tests/helpers/h.js" "src/__snapshots__/x.snap" "conftest.py" "src/Foo.Tests.cs"
  "jest.config.js" "pkg/x_test.go" "test_foo.py" "features/a.feature" "docs/12.md" "src/v2/x.js" "src/my file.js"
  "tests/my a.test.js" "-lead.js" "-x.test.js" 'src/q"x.js' "src/it's.test.js" "src/café.js" "tests/café.test.js"
  "docs/café/x.md" "spec/x.rb" "specs/x.rb" "e2e/x.ts" "src/__mocks__/m.js" "fixtures/f.json" "testdata/t.txt"
  "test/x.js" "__tests__/y.js" "src/a.spec.ts" "lib/a_spec.rb" "karma.conf.js" ".mocharc.yml" ".mocharc" "pytest.ini"
  "phpunit.xml" "phpunit.xml.dist" "src/FooTest.java" "src/FooTests.kt" "src/FooTest.swift" "vitest.config.ts"
  "playwright.config.ts" "cypress.config.js" "src/contest.js" "src/latest/x.js" ".agents/handoff/n.md"
  "tests/a:b.test.js" "1:2" "src/x:1:y.js" "ci/r:1.sh" "tests/helpers/h:2.js" )
CORP="$(mk_tmp)"; mk_repo "$CORP"
(
  cd "$CORP" || exit 3
  printf 'r\n' > tests/restore.sh; printf 'b\n' > tests/gone.test.js; printf 'B\000\003' > src/blob.bin; printf 'x\n' > src/size.js
  git add -A
  idx_add "${PLAIN[@]}"
  if [ "$ODD_OK" = 1 ]; then idx_add "${ODD[@]}"; fi
  git commit -q -m base
  printf 'b\n' >> src/app.js; printf 'b\n' >> tests/app.test.js; rm tests/gone.test.js
  chmod +x tests/restore.sh 2>/dev/null
  printf 'C\000\002' > src/blob.bin
  printf 'n1\nn2\nn3\n' > src/new.js; printf 'n\n' > tests/new.test.js; printf 'Z\000\003' > bin.dat
  mkdir -p .agents/handoff; printf 'h\n' > .agents/handoff/h.md
)
if ( cd "$CORP" && git diff --raw HEAD -- tests/restore.sh | "$REAL_GREP" -q '^:100644 100755' ); then MODE_OK=1; fi

# ---------------------------------------------------------------- AC1 corpus equivalence
echo "AC1 corpus: check (4 roles) and size equal the per-file grep result"
echo "  (C locale)"
corp_combo AC1 "$CORP" 1 C 1
corp_combo AC1 "$CORP" 2 C 0
corp_combo AC1 "$CORP" 3 C 0
corp_combo AC1 "$CORP" 8 C 0
# Platform tier (v0.24.15), decided by two probes above, not by uname: ODD_OK=0 (the odd names cannot be indexed) and
# MODE_OK=0 (the file system does not keep the executable bit). Both hold on Git Bash over NTFS, where one gate run costs
# about 4 s (a corpus combo about 22 s, measured); macOS has ODD_OK=0 but MODE_OK=1 and Linux has both, so they run it all.
# Without the odd names the corpus holds no invalid UTF-8 byte: its only non-ASCII names are the valid UTF-8 cafe paths, and
# of the confs only 8 (caf./) reads them differently per locale. So there the UTF-8 pass runs conf 8 alone; the C pass above
# still covers every class rule (default regex, infra first, a custom test ERE), every corpus path kind and both callers
# (check, size). The total of passed + skipped stays the same on every platform.
if [ -n "$UTF8" ]; then
  echo "  ($UTF8 locale)"
  if [ "$ODD_OK" = 1 ] || [ "$MODE_OK" = 1 ]; then
    ci=1
    while [ "$ci" -le 11 ]; do
      if [ "$ci" = 1 ]; then corp_combo AC1 "$CORP" "$ci" "$UTF8" 1; else corp_combo AC1 "$CORP" "$ci" "$UTF8" 0; fi
      ci=$((ci + 1))
    done
  else
    corp_combo AC1 "$CORP" 8 "$UTF8" 0
    t_skip 51 "this platform keeps neither the odd names (\\377, CR, tab) nor the executable bit (NTFS): corpus in a UTF-8 locale for conf 8 only (the locale-sensitive one); confs 1-7 and 9-11 run on Linux and macOS"
  fi
else
  t_skip 56 "no UTF-8 locale installed: corpus in a UTF-8 locale"
fi

echo "AC1 named lines (default and infra confs)"
gate_run "$CORP" "$PH0" C check tester
assert_contains "AC1 tester: src/app.js is a code violation" "$OUT" "VIOLATION (tester): src/app.js [code]"
assert_contains "AC1 tester: src/contest.js (near miss) is code" "$OUT" "VIOLATION (tester): src/contest.js [code]"
assert_not_contains "AC1 tester: tests/a.test.js is allowed" "$OUT" "VIOLATION (tester): tests/a.test.js"
assert_not_contains "AC1 handoff dir is skipped" "$OUT" ".agents/handoff"
gate_run "$CORP" "$PH0" C check implementer
assert_contains "AC1 implementer: a snapshot is a test violation" "$OUT" "VIOLATION (implementer): src/__snapshots__/x.snap [test]"
assert_contains "AC1 implementer: a deleted test is a violation" "$OUT" "VIOLATION (implementer): tests/gone.test.js [test]"
assert_not_contains "AC1 implementer: production code is allowed" "$OUT" "VIOLATION (implementer): src/app.js"
gate_run "$CORP" "$INFRA_PH" C check implementer
assert_contains "AC1 infra conf: tests/helpers/h.js is infra, not test" "$OUT" "VIOLATION (implementer): tests/helpers/h.js [infra]"
gate_run "$CORP" "$INFRA_PH" C check infra
assert_contains "AC1 infra role: a test path is a violation" "$OUT" "VIOLATION (infra): tests/a.test.js [test]"
assert_not_contains "AC1 infra role: ci/run.sh is allowed" "$OUT" "VIOLATION (infra): ci/run.sh"

# ---------------------------------------------------------------- F1 (review round 1): truncated UTF-8 lead byte
# Under bash 5 and a UTF-8 locale, `read` takes the newline after a path that ends in a truncated multibyte lead byte as part of
# the character: two lines become one record. v0.24.13 classified that merged text per file; the batch must give the same
# output (the reference above reads records with the same `while IFS= read -r` in this same bash).
echo "F1 a path ending in a truncated UTF-8 lead byte (record merge of bash 5)"
TRUNC=( $'src/caf\351' $'src/d.test.js' $'lib/x\303' 'lib/y.js' 'tests/a.test.js' 'src/z.js' 'ci/x.sh' 'tests/zz.test.js' )
F1_OK=0
F1R="$(mk_tmp)"; mk_repo "$F1R"
if ( cd "$F1R" && idx_add "${TRUNC[@]}" 2>/dev/null && git commit -q -m trunc 2>/dev/null &&
     [ "$(git diff --name-only -z HEAD -- | tr -cd '\000' | wc -c | tr -d ' ')" = "${#TRUNC[@]}" ] ); then F1_OK=1; fi
MERGE=0
if [ -n "$UTF8" ] && [ "$(LC_ALL=$UTF8 bash -c 'L="$(printf "a\351\nb")"; n=0
while IFS= read -r p; do n=$((n+1)); done <<X
$L
X
echo $n' 2>/dev/null)" = 1 ]; then MERGE=1; fi
if [ "$F1_OK" = 1 ]; then
  F1P="$(mk_tmp)"; write_conf "$F1P" "" ""
  F1I="$(mk_tmp)"; write_conf "$F1I" "" '^ci/'
  if [ -n "$UTF8" ]; then
    corp_combo F1 "$F1R" 1 "$UTF8" 1
    corp_combo F1 "$F1R" 2 "$UTF8" 0
    gate_run "$F1R" "$F1P" "$UTF8" check implementer
    if [ "$MERGE" = 1 ]; then
      case "$OUT" in
        *"VIOLATION (implementer): src/caf"$'\351'$'\n'"src/d.test.js [test]"*"role gate FAILED for implementer"*) t_ok "F1 implementer: the merged record is one [test] violation, as v0.24.13 (FAILED)" ;;
        *) t_bad "F1 implementer: the merged record is one [test] violation, as v0.24.13 (FAILED)" "$(printf '%s' "$OUT" | cat -v | head -8)" ;;
      esac
      chk "F1 implementer: exit code 1 (fail closed)" 1 "$RC"
    else
      t_skip 2 "this bash does not merge the records (no multibyte read merge): v0.24.13 and the batch agree anyway"
    fi
  else
    t_skip 13 "no UTF-8 locale installed: truncated lead byte in a UTF-8 locale"
  fi
  corp_combo F1 "$F1R" 1 C 0
else
  t_skip 18 "this platform cannot pass or index a truncated UTF-8 byte in a path name"
fi

# ---------------------------------------------------------------- AC2 classify, odd names
echo "AC2 classify: invalid UTF-8, CR, UTF-8 and tab names"
C8_PH="$(mk_tmp)"; write_conf "$C8_PH" "${CT[8]}" ""
if [ "$ODD_OK" = 1 ]; then
  gate_run "$PROBE" "$PH0" C classify $'x.snap\r';          chk "AC2 x.snap<CR> is code (the \$ is not at the end)" code "$OUT"
  gate_run "$PROBE" "$PH0" C classify $'tests/cr\r.js';     chk "AC2 tests/cr<CR>.js is test" test "$OUT"
  gate_run "$PROBE" "$PH0" C classify $'src/a\377b.snap';   chk "AC2 src/a<377>b.snap is test" test "$OUT"
  gate_run "$PROBE" "$C8_PH" C classify $'a\377b.js';       chk "AC2 conf a.b, C locale: a<377>b.js is test ('.' matches the byte)" test "$OUT"
  gate_run "$PROBE" "$C8_PH" C classify 'docs/café/x.md';   chk "AC2 conf caf./, C locale: café is two bytes, no match -> code" code "$OUT"
  for ci in 1 8; do
    cp_ph="$(mk_tmp)"; write_conf "$cp_ph" "${CT[$ci]}" "${CI[$ci]}"
    t="${CT[$ci]}"; [ -n "$t" ] || t="$DEFAULT_RE"
    EXP=""; ACT=""
    for p in "${ODD[@]}" 'docs/café/x.md' 'src/café.js'; do
      ref_class "$p" C "$t" ""; EXP="$EXP$p -> $RKIND"$'\n'
      gate_run "$PROBE" "$cp_ph" C classify "$p"; ACT="$ACT$p -> $OUT"$'\n'
    done
    chk "AC2 classify of the odd names, conf $ci, C locale, equals per-file grep" "$EXP" "$ACT"
  done
  if [ -n "$UTF8" ]; then
    gate_run "$PROBE" "$C8_PH" "$UTF8" classify $'a\377b.js';     chk "AC2 conf a.b, $UTF8: a<377>b.js is code ('.' does not match an invalid byte)" code "$OUT"
    gate_run "$PROBE" "$C8_PH" "$UTF8" classify 'docs/café/x.md'; chk "AC2 conf caf./, $UTF8: café is one char -> test" test "$OUT"
    for ci in 1 8; do
      cp_ph="$(mk_tmp)"; write_conf "$cp_ph" "${CT[$ci]}" "${CI[$ci]}"
      t="${CT[$ci]}"; [ -n "$t" ] || t="$DEFAULT_RE"
      EXP=""; ACT=""
      for p in "${ODD[@]}" 'docs/café/x.md' 'src/café.js'; do
        ref_class "$p" "$UTF8" "$t" ""; EXP="$EXP$p -> $RKIND"$'\n'
        gate_run "$PROBE" "$cp_ph" "$UTF8" classify "$p"; ACT="$ACT$p -> $OUT"$'\n'
      done
      chk "AC2 classify of the odd names, conf $ci, $UTF8, equals per-file grep" "$EXP" "$ACT"
    done
  else
    t_skip 4 "no UTF-8 locale installed: classify of odd names in a UTF-8 locale"
  fi
else
  t_skip 11 "this platform cannot pass or index the odd names (\\377, CR, tab)"
fi

# ---------------------------------------------------------------- R9: size with a git-quoted untracked name
echo "size with git-quoted untracked names (counted by the raw name, R9)"
UQ="$(mk_tmp)"; mk_repo "$UQ"
TABFILE_OK=0
mkdir -p "$UQ/tests"
if printf 'u\n' > "$UQ/src/a"$'\t'"b.js" 2>/dev/null && printf 'u\n' > "$UQ/tests/a"$'\t'"b.test.js" 2>/dev/null &&
   [ "$(cd "$UQ" && git ls-files --others | wc -l | tr -d ' ')" = 2 ] &&
   [ "$(cd "$UQ" && git ls-files --others | grep -c '^".*\\t')" = 2 ]; then TABFILE_OK=1; fi
# Git Bash on NTFS stores the tab as a substitute character (git prints \357\200\211, not \t), so this case
# does not apply there (found on Windows in the v0.24.14 release run; the v0.24.13 gate gives the same result)
if [ "$TABFILE_OK" = 1 ]; then
  OUT="$(cd "$UQ" && env PLAYBOOK_HOME="$PH0" LC_ALL=C bash "$GATE" size 2>/dev/null </dev/null)"; RC=$?
  chk "size: a git-quoted untracked name is classified by the raw name (code counted with its line, .test. name is test)" "files: 1/3 lines: 1/100 (base=HEAD)"$'\n'"rc=0" "$OUT"$'\n'"rc=$RC"
else
  t_skip 1 "this file system cannot hold a tab in a file name, or git does not print it quoted"
fi

# ---------------------------------------------------------------- AC5 mode restore
echo "AC5 mode restore (implementer)"
mk_restore() { # DIR -> committed 100644 tests/restore.sh (and restore2.sh), then chmod +x on both
  mk_repo "$1"
  ( cd "$1" && printf 'r\n' > tests/restore.sh && printf 'r\n' > tests/restore2.sh && git add -A && git commit -q -m base &&
    chmod +x tests/restore.sh tests/restore2.sh 2>/dev/null )
}
AR1="$(mk_tmp)"; mk_restore "$AR1"
( cd "$AR1" && printf 'y\n' >> tests/restore2.sh && printf 'v\n' > tests/a_viol.test.js && printf 'v\n' > tests/zz.test.js )
AR2="$(mk_tmp)"; mk_restore "$AR2"
( cd "$AR2" && git checkout -q -- tests/restore2.sh 2>/dev/null; chmod -x tests/restore2.sh 2>/dev/null; printf 'z\n' >> src/app.js )
if ( cd "$AR1" && git diff --raw HEAD -- tests/restore.sh | "$REAL_GREP" -q '^:100644 100755' ); then
  gate_run "$AR1" "$PH0" C check implementer
  chk "AC5 restore note sits in sorted place, a content change with the mode stays a violation" \
"VIOLATION (implementer): tests/a_viol.test.js [test]
note: tests/restore.sh mode restore only (100644 -> 100755, content unchanged)
VIOLATION (implementer): tests/restore2.sh [test]
VIOLATION (implementer): tests/zz.test.js [test]
role gate FAILED for implementer: 3 violation(s), base=HEAD
rc=1" "$OUT"$'\n'"rc=$RC"
  gate_run "$AR2" "$PH0" C check implementer
  chk "AC5 a mode restore alone is a note, not a violation" \
"note: tests/restore.sh mode restore only (100644 -> 100755, content unchanged)
OK: role gate passed for implementer (2 file(s) checked, base=HEAD)
rc=0" "$OUT"$'\n'"rc=$RC"
else
  t_skip 2 "this file system does not keep the executable bit"
fi

# ---------------------------------------------------------------- AC3 / AC6: grep process count
echo "AC3 grep processes per run (shim on PATH), AC6 grep -E with the user's ERE"
SHIMDIR="$(mk_tmp)"
cat > "$SHIMDIR/grep" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GREP_LOG"
exec "$REAL_GREP" "$@"
EOF
chmod +x "$SHIMDIR/grep"
GREP_LOG="$DT/greplog"; export GREP_LOG
mk_bulk() { # N -> a repo whose committed index holds N paths (N/2 test, N/2 code, every 20th code path under ci/), all missing in the work tree
  local n="$1" d i=1 half paths=()
  half=$((n / 2))
  d="$(mk_tmp)"; mk_repo "$d"
  while [ "$i" -le "$half" ]; do
    paths[${#paths[@]}]="tests/t$i.test.js"
    if [ $((i % 20)) -eq 0 ]; then paths[${#paths[@]}]="ci/c$i.sh"; else paths[${#paths[@]}]="src/c$i.js"; fi
    i=$((i + 1))
  done
  ( cd "$d" && idx_add "${paths[@]}" && git commit -q -m bulk )
  printf '%s\n' "$d"
}
B200="$(mk_bulk 200)"; B20="$(mk_bulk 20)"
grep_count() { # DIR GLOBAL_CONF_DIR ARGS... -> NG (grep processes), LOG (their command lines), OUT, RC
  local d="$1" ph="$2"; shift 2
  : > "$GREP_LOG"
  GPATH="$SHIMDIR:$PATH"; gate_run "$d" "$ph" C "$@"; GPATH=""
  NG="$(wc -l < "$GREP_LOG" | tr -d ' ')"; LOG="$(cat "$GREP_LOG")"
}
ac3_case() { # VARIANT GLOBAL_CONF_DIR WANT_LINE ARGS...
  local var="$1" ph="$2" want="$3" n200 n20 o200; shift 3
  grep_count "$B200" "$ph" "$@"; n200="$NG"; o200="$OUT"; LOG200="$LOG"
  grep_count "$B20" "$ph" "$@"; n20="$NG"
  if [ "$n200" -le 5 ]; then t_ok "AC3 $var '$*': <= 5 grep processes for 200 files"; else t_bad "AC3 $var '$*': <= 5 grep processes for 200 files" "got $n200 (one per file today)"; fi
  if [ "$n20" = "$n200" ]; then t_ok "AC3 $var '$*': count for 20 files equals count for 200 files"; else t_bad "AC3 $var '$*': count for 20 files equals count for 200 files" "20 files: $n20, 200 files: $n200"; fi
  if [ "$n200" -ge 2 ]; then t_ok "AC3 $var '$*': the shim sees the grep calls (validation + batch)"; else t_bad "AC3 $var '$*': the shim sees the grep calls" "got $n200"; fi
  assert_contains "AC3 $var '$*': result for 200 files" "$o200" "$want"
}
ac3_case default "$PH0" "role gate FAILED for implementer: 100 violation(s), base=HEAD" check implementer
AC6_LOG="$LOG200"
ac3_case default "$PH0" "role gate FAILED for tester: 100 violation(s), base=HEAD" check tester
ac3_case default "$PH0" "files: 100/1000 lines: 200/100000 (base=HEAD)" size --max-files 1000 --max-lines 100000
ac3_case infra "$INFRA_PH" "role gate FAILED for implementer: 105 violation(s), base=HEAD" check implementer
AC6_LOGI="$LOG200"
ac3_case infra "$INFRA_PH" "role gate FAILED for tester: 100 violation(s), base=HEAD" check tester
ac3_case infra "$INFRA_PH" "files: 100/1000 lines: 200/100000 (base=HEAD)" size --max-files 1000 --max-lines 100000
for v in default infra; do
  if [ "$v" = default ]; then L="$AC6_LOG"; else L="$AC6_LOGI"; fi
  nonE="$(printf '%s\n' "$L" | LC_ALL=C "$REAL_GREP" -a -v -E '(^| )-[a-zA-Z]*E' | head -3)"
  chk "AC6 $v: every grep call is grep -E" "" "$nonE"
  cnt="$(printf '%s\n' "$L" | LC_ALL=C "$REAL_GREP" -a -c -F -- "$DEFAULT_RE")"
  if [ "$v" = infra ]; then cnt2="$(printf '%s\n' "$L" | LC_ALL=C "$REAL_GREP" -a -c -F -- '^ci/|(^|/)tests/helpers/')"; else cnt2=2; fi
  if [ "$cnt" -ge 2 ] && [ "$cnt2" -ge 2 ]; then t_ok "AC6 $v: the user's ERE is handed to grep as it is (validation and batch)"
  else t_bad "AC6 $v: the user's ERE is handed to grep as it is" "test ERE in $cnt calls, infra ERE in $cnt2 calls"; fi
done

# ---------------------------------------------------------------- AC4 batch grep exits 2
echo "AC4 a batch grep that exits 2 reads like today's per-file result"
SHIM2="$(mk_tmp)"
cat > "$SHIM2/grep" <<'EOF'
#!/bin/sh
# exits 2 when stdin holds more than one line, else the real grep (whatever its flags)
f="$(mktemp "${TMPDIR:-/tmp}/gshim.XXXXXX")" || exit 3
cat > "$f"
n="$(LC_ALL=C "$REAL_GREP" -c '' "$f")"
if [ "$n" -gt 1 ]; then rm -f "$f"; exit 2; fi
"$REAL_GREP" "$@" < "$f"; rc=$?
rm -f "$f"; exit $rc
EOF
chmod +x "$SHIM2/grep"
AR4="$(mk_tmp)"; mk_repo "$AR4"
( cd "$AR4" && printf 'x\n' >> src/app.js && printf 'x\n' >> tests/app.test.js &&
  mkdir -p ci tests/helpers docs src/__snapshots__ .agents/handoff &&
  printf 'a\n' > ci/run.sh && printf 'a\n' > tests/helpers/h.js && printf 'a\n' > docs/12.md &&
  printf 'a\n' > src/__snapshots__/x.snap && printf 'a\n' > src/contest.js && printf 'h\n' > .agents/handoff/n.md )
GPATH="$SHIM2:$PATH"
corp_combo AC4 "$AR4" 1 C 0
corp_combo AC4 "$AR4" 2 C 0
GPATH=""

# ---------------------------------------------------------------- F3 (review round 1): only the infra batch grep fails
echo "F3 only the infra batch grep exits 2 (the test batch succeeds): per-file result for every path"
SHIM3="$(mk_tmp)"
cat > "$SHIM3/grep" <<'EOF'
#!/bin/sh
# exits 2 only when the infra ERE ($SHIM_INFRA) is an argument AND stdin holds more than one line, else the real grep
f="$(mktemp "${TMPDIR:-/tmp}/gshim.XXXXXX")" || exit 3
cat > "$f"
n="$(LC_ALL=C "$REAL_GREP" -c '' "$f")"
hit=0
for a in "$@"; do if [ -n "$SHIM_INFRA" ] && [ "$a" = "$SHIM_INFRA" ]; then hit=1; fi; done
if [ "$hit" = 1 ] && [ "$n" -gt 1 ]; then rm -f "$f"; exit 2; fi
"$REAL_GREP" "$@" < "$f"; rc=$?
rm -f "$f"; exit $rc
EOF
chmod +x "$SHIM3/grep"
GPATH="$SHIM3:$PATH"
SHIM_INFRA="${CI[2]}"; export SHIM_INFRA
corp_combo F3 "$AR4" 2 C 0
SHIM_INFRA="${CI[9]}"; export SHIM_INFRA
corp_combo F3 "$AR4" 9 C 0
SHIM_INFRA=""; export SHIM_INFRA
GPATH=""

t_summary
