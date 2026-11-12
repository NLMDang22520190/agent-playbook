#!/usr/bin/env bash
# Tests for the ten held-out outcome tasks evals/tasks/pattern-27..36 (v0.35.0 S1, .agents/handoff/01-spec.md AC3-AC5, AC7,
# Revision 1 R1-4, Revision 2 R2-4): check-tasks self-checks the ten (moved here from test-outcome-corpus.sh to keep that
# suite's CI time, finding 10); no hidden file reads a decision log, a docs/ file or a .md file; the ten dirs landed in one
# commit whose message says "held-out: written before any run" and no later commit touched them; DEFAULT_TASKS of
# tools/release-gate.sh is main's (b9f407a); evals/tasks/README.md documents the held-out set.
# Per-task metadata, canary, prompt and setup pins of the ten live in tests/test-outcome-corpus.sh.
# L-0009: tests/shard-weights carries this suite's measured Windows weight (221 s, Windows CI run 42584250555, ten
# shards). Never calls a harness. Bash 3.2 / BSD tools.
. "$(dirname "$0")/lib.sh"
TASKS="$PB_ROOT/evals/tasks"
CHECK="$PB_ROOT/evals/check-tasks.sh"
HELDOUT='pattern-27-refund-rounding-cap
pattern-28-cancel-releases-stock
pattern-29-backup-rotation-newest
pattern-30-split-address-migration
pattern-31-price-cents-migration
pattern-32-new-season-reset
pattern-33-close-inactive-accounts
pattern-34-discount-codes
pattern-35-currency-export
pattern-36-shipping-incident'
NH="$(printf '%s\n' "$HELDOUT" | grep -c .)"
HAVE_PY=0
if python3 -c 'import sys' >/dev/null 2>&1; then HAVE_PY=1; fi

echo "AC5 check-tasks self-checks each held-out task (F2P fails unsolved, all pass on solution.patch, wrong fixes fail)"
assert_eq "AC5 the held-out list names ten tasks" 10 "$NH"
run bash "$CHECK" --tasks-dir "$TASKS" --tasks "$(printf '%s\n' "$HELDOUT" | tr '\n' ',' | sed 's/,$//')"
if [ "$HAVE_PY" = 1 ]; then
  assert_rc "AC5 check-tasks --tasks <the ten> exits 0" 0
else
  t_skip 1 "no python3: the python3 tasks print SKIPPED (exit code checked per task below)"
fi
while IFS= read -r id; do
  [ -n "$id" ] || continue
  lang="$(sed -n 's/^language=//p' "$TASKS/$id/task.conf" 2>/dev/null | sed -n 1p | tr -d '\r')"
  if [ "$lang" = python3 ] && [ "$HAVE_PY" = 0 ]; then
    if printf '%s\n' "$OUT" | grep -Eq -- "^$id .*SKIPPED \(no python3\)"; then t_ok "AC5 $id SKIPPED (no python3) on this host"
    else t_bad "AC5 $id SKIPPED (no python3) on this host" "$OUT"; fi
  else
    if printf '%s\n' "$OUT" | grep -Eq -- "^$id SELF-CHECK OK( |\$)"; then t_ok "AC5 $id SELF-CHECK OK"
    else t_bad "AC5 $id SELF-CHECK OK" "$(printf '%s\n' "$OUT" | grep -E -- "^$id " || echo "no line for $id")"; fi
  fi
done <<EOF
$HELDOUT
EOF

echo "AC3 no hidden test reads a decision log, a docs/ file or a .md file"
# (a) the word "decision" in any case, anywhere in a hidden file (comments included: the hidden tests grade no decision log);
# (b) a read call (readFileSync, readFile, createReadStream, open(, read_text(, read_bytes(, cat, source, head, tail, grep,
#     awk, sed, less, more, `. FILE`) on a line that names docs or a .md file;
# (c) a quoted literal naming a docs directory or ending in .md (catches a path built on one line and read on another);
# (d) in a shell hidden file, any non-comment line naming docs/ or a .md file.
# Comments that cite the rule's doc in prose ("docs/money-rules.md: ...") are allowed: they are not reads.
READ_RE='(readFileSync|readFile|createReadStream|open|read_text|read_bytes)[[:space:]]*\(|(^|[^A-Za-z_])(cat|source|head|tail|grep|awk|sed|less|more)[[:space:]]|(^|[[:space:]])\.[[:space:]]'
DOC_RE='(^|[^A-Za-z0-9_])docs([^A-Za-z0-9_]|$)|\.md([^A-Za-z0-9_]|$)'
LIT_RE="[\"'\`]([^\"'\`]*/)?docs([/\"'\`])|[\"'\`][^\"'\` ]*\\.md[\"'\`]"
# hidden_hits DIR -> "file:line" of every (a)-(d) hit under DIR, one per line
hidden_hits() {
  local f
  find "$1" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    grep -inH -- 'decision' "$f" 2>/dev/null | sed 's/^/decision: /'
    grep -nHE -- "$READ_RE" "$f" 2>/dev/null | grep -E -- "$DOC_RE" | sed 's/^/read: /'
    grep -nHE -- "$LIT_RE" "$f" 2>/dev/null | sed 's/^/literal: /'
    case "$f" in
      *.sh) grep -nHvE '^[[:space:]]*#' "$f" 2>/dev/null | grep -E -- "$DOC_RE" | sed 's/^/shell: /' ;;
    esac
  done
}
# self-test: each probe line is one way to read a log or a doc; the clean probe is the prose-comment case the ten use
PR="$(mk_tmp)"; mkdir -p "$PR/bad" "$PR/ok"
printf '%s\n' "const t = fs.readFileSync('docs/decisions.md', 'utf8');" > "$PR/bad/a.test.js"
printf '%s\n' "with open(os.path.join(ROOT, 'docs', 'loyalty-rules.md')) as f:" > "$PR/bad/b.py"
printf '%s\n' "p = ROOT / 'docs' / 'notes.md'" "text = p.read_text()" > "$PR/bad/c.py"
printf '%s\n' '#!/usr/bin/env bash' 'f=docs/retention.md' 'n="$(wc -l < "$f")"' > "$PR/bad/d.sh"
printf '%s\n' '# the rule is logged' 'grep -q "Decision" notes.txt' > "$PR/bad/e.sh"
printf '%s\n' "// Hidden test: docs/stock-rules.md: available = on hand - reserved (would delete <name>)." \
  "const m = require('../src/orders');" > "$PR/ok/a.test.js"
printf '%s\n' '#!/usr/bin/env bash' '# rule: docs/backups.md keeps the KEEP newest' 'out="$(bash bin/rotate-backups.sh)"' > "$PR/ok/b.sh"
assert_eq "AC3 the hidden-file scan flags each probe that reads a log or a doc (self-test)" "a.test.js b.py c.py d.sh e.sh" \
  "$(hidden_hits "$PR/bad" | sed 's#^[a-z]*: ##; s#:.*##; s#.*/##' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
assert_eq "AC3 the hidden-file scan passes prose comments that cite a doc (self-test)" "" "$(hidden_hits "$PR/ok")"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  hd="$TASKS/$id/hidden"
  if [ -d "$hd" ] && [ -n "$(find "$hd" -type f 2>/dev/null)" ]; then
    assert_eq "AC3 $id: no hidden file names a decision log or reads docs/ or a .md file" "" "$(hidden_hits "$hd")"
  else
    t_bad "AC3 $id: no hidden file names a decision log or reads docs/ or a .md file" "no hidden files under $hd"
  fi
done <<EOF
$HELDOUT
EOF

echo "AC4 the ten task dirs landed in one commit that says held-out, and nothing changed them since"
# Skipped (same count) when git or the history is missing, or when the adding commit is a shallow-clone boundary (a
# depth-1 checkout makes its only commit "add" every file, which proves nothing).
NAC4=4
GD="$(git -C "$PB_ROOT" rev-parse --git-dir 2>/dev/null)"
ADD=""
if [ -n "$GD" ]; then
  ADD="$(git -C "$PB_ROOT" log --diff-filter=A --format=%H -- evals/tasks/pattern-27-refund-rounding-cap/task.conf 2>/dev/null | tail -n 1)"
fi
SHF="$(git -C "$PB_ROOT" rev-parse --git-path shallow 2>/dev/null)"
case "$SHF" in /*) ;; ?*) SHF="$PB_ROOT/$SHF" ;; esac
if [ -z "$GD" ] || [ -z "$ADD" ]; then
  t_skip "$NAC4" "no git history holds evals/tasks/pattern-27-refund-rounding-cap/task.conf"
elif [ -f "$SHF" ] && grep -qx -- "$ADD" "$SHF"; then
  t_skip "$NAC4" "shallow clone: the adding commit $ADD is the history boundary"
else
  assert_contains "AC4 the commit that added pattern-27's task.conf says 'held-out: written before any run'" \
    "$(git -C "$PB_ROOT" log -1 --format=%B "$ADD")" "held-out: written before any run"
  OTHER=""
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    a="$(git -C "$PB_ROOT" log --diff-filter=A --format=%H -- "evals/tasks/$id/task.conf" 2>/dev/null | tail -n 1)"
    [ "$a" = "$ADD" ] || OTHER="$OTHER $id(${a:-none})"
  done <<EOF
$HELDOUT
EOF
  assert_eq "AC4 that one commit added the task.conf of all ten held-out tasks" "" "$OTHER"
  DIRS="$(printf 'evals/tasks/%s\n' $HELDOUT)"
  # shellcheck disable=SC2086   # DIRS: one pathspec per word
  HAVE="$(git -C "$PB_ROOT" ls-files -- $DIRS | LC_ALL=C sort)"
  # shellcheck disable=SC2086
  ADDED="$(git -C "$PB_ROOT" show --format= --name-only --diff-filter=A "$ADD" -- $DIRS | LC_ALL=C sort)"
  assert_eq "AC4 every tracked file of the ten dirs was added by that commit" "" \
    "$(LC_ALL=C comm -23 <(printf '%s\n' "$HAVE") <(printf '%s\n' "$ADDED") | sed '/^$/d')"
  # shellcheck disable=SC2086
  assert_eq "AC4 no later commit changed the ten held-out dirs (they are not tuned after the held-out commit)" "" \
    "$(git -C "$PB_ROOT" log --format='%h %s' "$ADD..HEAD" -- $DIRS)"
fi

echo "AC7 DEFAULT_TASKS of tools/release-gate.sh is unchanged from main (b9f407a)"
dt_of() { sed -n 's/^DEFAULT_TASKS=//p' | sed -n 1p | tr -d '\r'; }
if git -C "$PB_ROOT" cat-file -e 'b9f407a^{commit}' 2>/dev/null; then
  MAIN_DT="$(git -C "$PB_ROOT" show b9f407a:tools/release-gate.sh 2>/dev/null | dt_of)"
  if [ -n "$MAIN_DT" ]; then t_ok "AC7 main's tools/release-gate.sh has a DEFAULT_TASKS= line"
  else t_bad "AC7 main's tools/release-gate.sh has a DEFAULT_TASKS= line" "none at b9f407a"; fi
  assert_eq "AC7 DEFAULT_TASKS equals main's" "$MAIN_DT" "$(dt_of < "$PB_ROOT/tools/release-gate.sh")"
else
  t_skip 2 "commit b9f407a (main at the start of v0.35.0) is not in this clone"
fi

echo "R1-4 evals/tasks/README.md documents the held-out set"
R="$TASKS/README.md"
RT="$(cat "$R" 2>/dev/null)"
# the section from the first heading that names "held-out" (any case) to the next heading of the same or a higher level
HSEC="$(printf '%s\n' "$RT" | awk '
  f && /^#+ / { l = $0; sub(/ .*/, "", l); if (length(l) <= lvl) exit }
  !f && /^#+ / && tolower($0) ~ /held-out/ { f = 1; l = $0; sub(/ .*/, "", l); lvl = length(l) }
  f')"
if [ -n "$HSEC" ]; then t_ok "R1-4 README has a heading that names held-out tasks"
else t_bad "R1-4 README has a heading that names held-out tasks" "no heading with 'held-out' in $R"; fi
for n in 27 28 29 30 31 32 33 34 35 36; do
  assert_contains "R1-4 the held-out section lists pattern-$n" "$HSEC" "pattern-$n"
done
assert_contains "R1-4/AC4 the held-out section says they were written before any run" "$HSEC" "written before any run"
assert_eq "R1-4 the held-out section says the Calibration loop does not apply to them" "yes" \
  "$(printf '%s\n' "$HSEC" | tr '\n' ' ' | grep -Eiq 'calibration[^.]*(not|never) appl|(not|never) appl[^.]*calibration|not tuned[^.]*calibration|calibration[^.]*not tuned' && echo yes || echo no)"
# setup.sh may make several commits, each with fixed dates (the old row said "then one git commit")
SROW="$(printf '%s\n' "$RT" | grep -F '| `setup.sh`')"
assert_not_contains "R1-4 the setup.sh row no longer says setup makes exactly one git commit" "$SROW" "then one git commit"
assert_eq "R1-4 the setup.sh row allows several commits with fixed dates" "yes" \
  "$(printf '%s\n' "$SROW" | grep -Eiq '(several|one or more|more than one|any number of)[^|]*commits' && printf '%s\n' "$SROW" | grep -qi 'fixed' && echo yes || echo no)"
# a paragraph that names pattern-32 and 33 and says they grade no decision log
P3233="$(printf '%s\n' "$RT" | awk 'BEGIN { RS = "" } /pattern-32/ && /(pattern-)?33/ { print; print "" }')"
assert_eq "R1-4 README says pattern-32 and 33 grade no decision log" "yes" \
  "$(printf '%s\n' "$P3233" | tr '\n' ' ' | grep -Eiq '(no|not a|not the|never a|never the) (decision )?log|grade[sd]? no|(do|does) not grade|never grade' && echo yes || echo no)"
# the existing ambiguous-default note still names the tasks that do grade the log
assert_contains "R1-4 the ambiguous-default note still names pattern-15, pattern-23 to pattern-26" "$RT" "pattern-15, pattern-23 to pattern-26"

t_summary
