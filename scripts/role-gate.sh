#!/usr/bin/env bash
# Mechanical enforcement of role separation in the TDD workflow.
#   role-gate.sh check <tester|implementer|reviewer|infra> [--base REF] [--baseline FILE]
#   role-gate.sh snapshot [--out FILE]  records the work-tree and index state of every changed path (a baseline)
#   role-gate.sh classify <path>        prints "infra", "test" or "code"
#   role-gate.sh size [--base REF] [--max-files N] [--max-lines M] [--baseline FILE]
#                                       Lite size check (defaults 3 files, 100 lines)
#
# Test paths include test configuration and snapshots (jest/vitest/playwright/cypress
# config, karma.conf, .mocharc, pytest.ini, phpunit.xml, __snapshots__/, *.snap).
# *.snap counts as a test file anywhere: a snapshot is a test expectation, and an implementer who
# rewrites it makes a failing test pass without changing behaviour. A project whose *.snap files
# are not tests (e.g. Ubuntu snap packages) sets its own test_path_regex.
#
# size counts production files (non-test, outside .agents/handoff/) changed since REF
# (default HEAD; committed, staged, unstaged and untracked) and their added+deleted lines
# (git diff --numstat; a binary file counts as 1 line; an untracked file counts all its
# lines). Prints "files: F/N lines: L/M"; over either limit -> exit 1, escalate to Full.
#
# What each role may change (relative to REF, default HEAD; includes staged, unstaged
# and untracked files):
#   tester       only test paths            -> production code changed = violation
#   implementer  only non-test paths        -> any test path changed (even deleted) = violation
#   reviewer     nothing                    -> any change = violation
#   infra        only test-infra paths      -> any test or code path changed = violation
# Test infrastructure (runners, shared test helpers) is opt-in: project key test_infra_regex (ERE on
# repo-relative paths, empty = off). Matching paths classify as "infra" (before the test regex); the
# tester and the implementer may not change them, and size counts them like production files.
# Every role: a path that goes from mode 100755 to 100644 (git diff --raw against REF, work tree and index, also a drop
# that is only staged, also a rename with unchanged content that drops the bit: the new path is named) is a
# violation "VIOLATION (mode): <path> lost its executable bit (100755 -> 100644)", unless the path is listed in
# PB_ALLOW_MODE_CHANGE (colon-separated, exact repo-relative paths; a path that contains a colon cannot be listed there).
# The check never fails open: a work-tree file git cannot hash is "VIOLATION (mode): cannot hash PATH; the mode check is
# incomplete" (the escape silences that path only); a path with a newline or a \002 byte is
# "VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete" and has no escape (rename the file).
# Gaining the bit or deleting a file is fine.
# implementer: a test path whose only change since REF is a mode restore (100644 -> 100755, same content) is not a violation:
# "note: <path> mode restore only (...)" (v0.24.9). A drop, a content change or a delete of a test stays a violation.
# Files under .agents/handoff/ are always allowed (role hand-off notes, evidence logs).
#
# Baseline (v0.24.17, a repo that is already dirty when a role starts): snapshot writes a manifest, by default
# `git rev-parse --git-path pb-gate-baseline` (in the git dir, never in the work tree): the header line
# "# role-gate baseline v1", then one line per path that differs from HEAD (work tree, index, untracked; not
# .agents/handoff/): <work-tree state> TAB <index state> TAB <path>. A work-tree state is absent, unhashable or
# "<mode> <sha>" (raw bytes, --no-filters; a symlink is 120000 plus the hash of its link text); an index state is
# none, unhashable or "<mode> <sha>" (stage 0). It prints "baseline: N path(s) recorded in FILE (digest D)".
# check --baseline FILE skips a changed path ONLY when its current work-tree state and index state both equal the recorded
# ones (exact strings; unhashable never matches); every other path, and every manifest path whose state changed (a
# pre-dirty file reverted, a pre-existing untracked file deleted), is judged as today. Each skipped path prints
# "note: unchanged since the baseline: PATH" (control characters but TAB shown as ?); the note "baseline FILE (N path(s), digest D): K path(s) unchanged, not checked"
# shows the digest of the manifest (compare it with the one snapshot printed). A mode drop on a path unchanged since the
# baseline is not reported. A relative FILE is resolved against the caller's directory. A missing or malformed manifest
# (bad header, missing TAB, empty path, bad state, or the same path on two lines) exits 3. Without --baseline nothing changes.
# size --baseline FILE (same manifest): leaves out the paths unchanged since the baseline; a manifest path whose state changed
# but is no longer in the numstat list (reverted, deleted) counts as 1 file and 1 line when production, 0 when test.
#
# Exit: 0 ok | 1 violation | 2 usage | 3 environment (not a git repo, bad ref, bad baseline manifest)
set -u
. "$(dirname "$0")/lib.sh"

DEFAULT_REGEX='(^|/)(test|tests|__tests__|spec|specs|e2e|__mocks__|fixtures|testdata|__snapshots__)(/|$)|(\.test\.|\.spec\.|_test\.|_spec\.)|(^|/)test_[^/]*$|(^|/)conftest\.py$|\.feature$|Tests?\.(java|kt|cs|swift)$|(^|/)(jest|vitest|playwright|cypress)\.config\.[^/]+$|(^|/)karma\.conf\.[^/]+$|(^|/)\.mocharc(\.[^/]+)?$|(^|/)pytest\.ini$|(^|/)phpunit\.xml(\.dist)?$|\.snap$'

# Read both regexes once per run, and refuse an invalid one: grep exits 2 on a bad pattern, which
# would otherwise read as "no match" and let every file through (fail open).
# conf_src KEY -> sets SRC_VAL and SRC_SCOPE (project before global, like pb_conf_get); exit 1 if unset
conf_src() {
  SRC_VAL=""; SRC_SCOPE=""
  if SRC_VAL="$(pb_conf_read "$(pb_conf_project)" "$1")"; then SRC_SCOPE=project; return 0; fi
  if SRC_VAL="$(pb_conf_read "$(pb_conf_global)" "$1")"; then SRC_SCOPE=global; return 0; fi
  SRC_VAL=""; return 1
}
TEST_RE="$DEFAULT_REGEX"; TEST_SCOPE=""
if conf_src test_path_regex; then TEST_RE="$SRC_VAL"; TEST_SCOPE="$SRC_SCOPE"; fi
INFRA_RE=""; INFRA_SCOPE=""; INFRA_SHADOW=""
if conf_src test_infra_regex; then INFRA_RE="$SRC_VAL"; INFRA_SCOPE="$SRC_SCOPE"; fi
# an empty project value switches off a non-empty global one: worth a note (it moves the gate)
if [ -z "$INFRA_RE" ] && [ "$INFRA_SCOPE" = project ]; then
  INFRA_SHADOW="$(pb_conf_read "$(pb_conf_global)" test_infra_regex)" || INFRA_SHADOW=""
fi
valid_re() { printf 'x\n' | grep -Eq -- "$1" 2>/dev/null; [ $? -ne 2 ]; }

classify() {
  if [ -n "$INFRA_RE" ] && printf '%s\n' "$1" | grep -Eq -- "$INFRA_RE"; then echo infra; return; fi
  if printf '%s\n' "$1" | grep -Eq -- "$TEST_RE"; then echo test; else echo code; fi
}

# classify_list: classify many newline-separated, non-empty paths with one grep -E per configured regex
# (infra when set, then test) instead of one grep per path. Sets KINDS to one kind per input record, in order.
# The batch grep runs in the caller's locale, with -a (no "binary file matches" line) and -n: the line number
# before the FIRST colon maps a hit back to its path, so a path with a colon, tab, CR or leading dash is safe.
# A path matching both regexes is infra (infra first), exactly as classify. If a batch grep exits above 1
# (it failed), every path of the batch is classified with the per-file classify.
# Hits are mapped by PHYSICAL line number, walked with a cursor (hit numbers ascend), so the work is linear.
# A path ending in a truncated multibyte lead byte makes bash 5 `read -r` swallow the next newline: such a record
# spans several physical lines. It is classified with classify (the merged text, as v0.24.13 did) and the
# physical counter advances past all of its lines. Uses fds 3 and 4 and closes them before it returns.
classify_list() {
  local list="$1" ihits="" thits="" p k rc fb=0 ph=1 t nl ih=2147483647 th=2147483647
  KINDS=""
  [ -n "$list" ] || return 0
  if [ -n "$INFRA_RE" ]; then
    ihits="$(printf '%s\n' "$list" | grep -Ean -- "$INFRA_RE")"; rc=$?
    [ "$rc" -le 1 ] || fb=1
  fi
  if [ "$fb" -eq 0 ]; then
    thits="$(printf '%s\n' "$list" | grep -Ean -- "$TEST_RE")"; rc=$?
    [ "$rc" -le 1 ] || fb=1
  fi
  if [ "$fb" -eq 0 ]; then
    # keep only the line numbers: a hit line is read again by `read`, which can swallow a newline
    if [ -n "$ihits" ]; then ihits="$(printf '%s\n' "$ihits" | LC_ALL=C cut -d: -f1)"; fi
    if [ -n "$thits" ]; then thits="$(printf '%s\n' "$thits" | LC_ALL=C cut -d: -f1)"; fi
    exec 3<<EOF
$ihits
EOF
    exec 4<<EOF
$thits
EOF
    IFS= read -r ih <&3 || ih=2147483647
    [ -n "$ih" ] || ih=2147483647
    IFS= read -r th <&4 || th=2147483647
    [ -n "$th" ] || th=2147483647
  fi
  while IFS= read -r p; do
    if [ "$fb" -eq 1 ]; then
      k="$(classify "$p")"
    else
      case "$p" in
        *$'\n'*)
          k="$(classify "$p")"
          nl=0; t="$p"
          while :; do
            case "$t" in *$'\n'*) t="${t#*$'\n'}"; nl=$((nl + 1)) ;; *) break ;; esac
          done
          ph=$((ph + nl))
          ;;
        *)
          while [ "$ih" -lt "$ph" ]; do
            IFS= read -r ih <&3 || ih=2147483647
            [ -n "$ih" ] || ih=2147483647
          done
          while [ "$th" -lt "$ph" ]; do
            IFS= read -r th <&4 || th=2147483647
            [ -n "$th" ] || th=2147483647
          done
          if [ "$ih" -eq "$ph" ]; then k="infra"
          elif [ "$th" -eq "$ph" ]; then k="test"
          else k="code"
          fi
          ;;
      esac
      ph=$((ph + 1))
    fi
    KINDS+="$k"$'\n'
  done <<EOF
$list
EOF
  exec 3<&- 4<&-
}

# ---- baselines (v0.24.17) ----
NL='
'
BL_HDR="# role-gate baseline v1"
BL_TMPW=""
bl_cleanup() { if [ -n "$BL_TMPW" ]; then rm -f "$BL_TMPW"; fi; }

# bl_states LIST: LIST holds newline-separated repo-relative paths (none empty, none with a newline); run it at the top of
# the work tree. Sets BL_WT[i] and BL_IX[i], in the order of LIST: the work-tree state and the index state of each path
# (spec "State definitions"). One git ls-files, one git diff, one batch git hash-object --no-filters --stdin-paths for all
# regular files (a symlink is hashed apart: hash-object would follow it); an untracked file costs one ls -ld only when its
# owner execute bit cannot be ruled out with builtins. Returns 3 when git fails or a path holds a newline.
bl_states() {
  local list="$1" lsout raw ixl nml p q i n rc fm="" fmset=0 ixs nmv mode perm reglist="" nreg=0 hout h line r
  local KIND=() NM=() HS=()
  BL_WT=(); BL_IX=()
  [ -n "$list" ] || return 0
  if [ -z "$BL_TMPW" ]; then
    BL_TMPW="$(mktemp "${TMPDIR:-/tmp}/pbgate.XXXXXX")" || return 3
    trap 'exit 1' INT TERM
    trap bl_cleanup EXIT
  fi
  printf '%s\n' "$list" > "$BL_TMPW" || return 3
  lsout="$(git ls-files -s -z | tr '\n\000' '\002\n'; exit "${PIPESTATUS[0]}")" || return 3
  ixl="$(printf '%s\n' "$lsout" | awk '
    FNR == NR { n++; order[n] = $0; want[$0] = 1; next }
    { i = index($0, "\t"); if (i == 0) next
      meta = substr($0, 1, i - 1); path = substr($0, i + 1)
      if (!(path in want)) next
      split(meta, a, " ")
      if (a[3] + 0 != 0) conf[path] = 1; else ix[path] = a[1] " " a[2] }
    END { for (k = 1; k <= n; k++) { p = order[k]
            if (p in conf) print "unhashable"; else if (p in ix) print ix[p]; else print "none" } }' "$BL_TMPW" -)" || return 3
  raw="$(pb_raw_lines --)"; rc=$?
  [ "$rc" -eq 0 ] || return 3
  nml="$(printf '%s\n' "$raw" | awk '
    FNR == NR { n++; order[n] = $0; want[$0] = 1; next }
    { i = index($0, "\t"); if (i == 0) next
      meta = substr($0, 1, i - 1); path = substr($0, i + 1)
      if (path in want) { split(meta, a, " "); nm[path] = a[2] } }
    END { for (k = 1; k <= n; k++) { p = order[k]; if (p in nm) print nm[p]; else print "-" } }' "$BL_TMPW" -)" || return 3
  i=0
  while IFS= read -r line; do BL_IX[i]="$line"; i=$((i + 1)); done <<EOF
$ixl
EOF
  [ "$i" -eq "$(printf '%s\n' "$list" | wc -l | tr -d ' ')" ] || return 3
  i=0
  while IFS= read -r line; do NM[i]="$line"; i=$((i + 1)); done <<EOF
$nml
EOF
  i=0
  while IFS= read -r p; do
    q="./$p"
    if [ -L "$q" ]; then
      KIND[i]="link"
      if r="$(readlink "$q")" && h="$(printf '%s' "$r" | git hash-object --stdin 2>/dev/null)" && [ -n "$h" ]; then
        BL_WT[i]="120000 $h"
      else BL_WT[i]=unhashable; fi
    elif [ -d "$q" ]; then KIND[i]="other"; BL_WT[i]=unhashable
    elif [ -f "$q" ]; then KIND[i]="reg"; BL_WT[i]=unhashable; reglist+="$q"$'\n'; nreg=$((nreg + 1))
    elif [ -e "$q" ]; then KIND[i]="other"; BL_WT[i]=unhashable
    else KIND[i]="other"; BL_WT[i]=absent
    fi
    i=$((i + 1))
  done <<EOF
$list
EOF
  [ "$nreg" -gt 0 ] || return 0
  # one batch for every regular file (./ keeps a leading quote or dash from being read as syntax); a failed or short batch
  # falls back to one hash per file, a file that cannot be hashed stays unhashable
  hout="$(printf '%s' "$reglist" | git hash-object --no-filters --stdin-paths 2>/dev/null)" || hout=""
  n=0
  while IFS= read -r line; do HS[n]="$line"; n=$((n + 1)); done <<EOF
$hout
EOF
  if [ "$n" -ne "$nreg" ]; then
    n=0
    while IFS= read -r q; do
      [ -n "$q" ] || continue
      HS[n]="$(git hash-object --no-filters -- "$q" 2>/dev/null)" || HS[n]=""
      n=$((n + 1))
    done <<EOF
$reglist
EOF
  fi
  i=0; n=0
  while IFS= read -r p; do
    if [ "${KIND[i]}" = reg ]; then
      q="./$p"; h="${HS[n]}"; n=$((n + 1)); ixs="${BL_IX[i]}"; nmv="${NM[i]}"
      mode=""
      case "$ixs" in
        none | unhashable)
          if [ "$fmset" -eq 0 ]; then
            fm="$(git config --bool core.filemode 2>/dev/null)" || fm=""
            [ -n "$fm" ] || fm=true
            fmset=1
          fi
          mode=100644
          if [ "$fm" = true ]; then
            # the OWNER execute bit, read from ls -ld (4th character); [ -x ] is true for root on any x bit, so it only
            # settles the "owned and not executable" case
            if [ -O "$q" ] && [ ! -x "$q" ]; then mode=100644
            else
              perm="$(ls -ld "$q" 2>/dev/null)"; perm="${perm%% *}"
              case "${perm:3:1}" in x | s) mode=100755 ;; esac
            fi
          fi
          ;;
        *)
          if [ "$nmv" != "-" ] && [ "$nmv" != 000000 ]; then mode="$nmv"; else mode="${ixs%% *}"; fi
          ;;
      esac
      case "$mode" in
        100644 | 100755 | 120000) if [ -n "$h" ]; then BL_WT[i]="$mode $h"; else BL_WT[i]=unhashable; fi ;;
        *) BL_WT[i]=unhashable ;;
      esac
    fi
    i=$((i + 1))
  done <<EOF
$list
EOF
  return 0
}

# bl_read FILE: validate a baseline manifest (exit 3 on any problem, before a verdict) and set ML_N, ML_P[i], ML_WT[i],
# ML_IX[i]. The path is everything after the second TAB.
bl_read() {
  local f="$1" verr body line rest i=0
  ML_N=0; ML_P=(); ML_WT=(); ML_IX=()
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then pb_die "baseline manifest not readable: $f" 3; fi
  verr="$(awk -v HDR="$BL_HDR" '
    function hexok(s) { return (s ~ /^[0-9a-f]+$/ && (length(s) == 40 || length(s) == 64)) }
    function stok(s, kind,    a, n) {
      if (s == "unhashable") return 1
      if (kind == "wt" && s == "absent") return 1
      if (kind == "ix" && s == "none") return 1
      n = split(s, a, " ")
      if (n != 2 || a[1] " " a[2] != s || !hexok(a[2])) return 0
      if (kind == "wt") return (a[1] == "100644" || a[1] == "100755" || a[1] == "120000")
      return (a[1] == "100644" || a[1] == "100755" || a[1] == "120000" || a[1] == "160000")
    }
    NR == 1 { if ($0 != HDR) { print "line 1 is not the header: " HDR; bad = 1; exit } next }
    { i = index($0, "\t")
      if (!i) { print "line " NR ": no TAB"; bad = 1; exit }
      wt = substr($0, 1, i - 1); r = substr($0, i + 1); j = index(r, "\t")
      if (!j) { print "line " NR ": only one TAB"; bad = 1; exit }
      ix = substr(r, 1, j - 1); p = substr(r, j + 1)
      if (p == "") { print "line " NR ": empty path"; bad = 1; exit }
      if (!stok(wt, "wt")) { print "line " NR ": bad work-tree state"; bad = 1; exit }
      if (!stok(ix, "ix")) { print "line " NR ": bad index state"; bad = 1; exit }
      if (p in seen) { print "line " NR ": duplicate path (also line " seen[p] ")"; bad = 1; exit }
      seen[p] = NR }
    END { if (bad) exit 1; if (NR == 0) { print "empty file, no header"; exit 1 } }' "$f")" ||
    pb_die "malformed baseline manifest $f: $verr" 3
  body="$(awk 'NR > 1' "$f")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ML_WT[i]="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    ML_IX[i]="${rest%%$'\t'*}"
    ML_P[i]="${rest#*$'\t'}"
    i=$((i + 1))
  done <<EOF
$body
EOF
  ML_N="$i"
}

cmd="${1:-}"
case "$cmd" in
  classify | check | size)
    # an empty test_path_regex would match every path: every file a test (fail open for the tester)
    [ -n "$TEST_RE" ] || pb_die "test_path_regex is empty in the $TEST_SCOPE conf; unset it to use the default" 3
    valid_re "$TEST_RE" || pb_die "invalid test_path_regex (grep -E rejects it): $TEST_RE" 3
    if [ -n "$INFRA_RE" ]; then valid_re "$INFRA_RE" || pb_die "invalid test_infra_regex (grep -E rejects it): $INFRA_RE" 3; fi
    ;;
esac
[ $# -gt 0 ] && shift

case "$cmd" in
  classify)
    [ $# -eq 1 ] || pb_die "usage: role-gate.sh classify <path>" 2
    classify "$1"
    ;;
  check)
    role="${1:-}"
    [ $# -gt 0 ] && shift
    case "$role" in tester|implementer|reviewer|infra) ;; *) pb_die "role must be tester|implementer|reviewer|infra" 2 ;; esac
    base="HEAD"; bl=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) [ $# -ge 2 ] || pb_die "--base needs a ref" 2; base="$2"; shift ;;
        --baseline) { [ $# -ge 2 ] && [ -n "$2" ]; } || pb_die "--baseline needs a file" 2; bl="$2"; shift ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree (role gates need git)" 3
    git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || pb_die "base ref not found: $base" 3
    # a relative manifest path is the caller's: resolve it before the gate moves to the top of the work tree
    if [ -n "$bl" ]; then case "$bl" in /* | [A-Za-z]:[/\\]*) ;; *) bl="$PWD/$bl" ;; esac; fi
    top="$(git rev-parse --show-toplevel)"
    cd "$top" || pb_die "cannot enter $top" 3
    # a config file can move the gate: show where the regexes come from, before the verdict
    # control characters (ESC, CR, ...) in a value could hide or rewrite the note in a terminal: show them as ?
    shown() { printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' '?'; }
    [ -n "$TEST_SCOPE" ] && printf 'note: test_path_regex from the %s conf: %s\n' "$TEST_SCOPE" "$(shown "$TEST_RE")"
    [ -n "$INFRA_RE" ] && printf 'note: test_infra_regex from the %s conf: %s\n' "$INFRA_SCOPE" "$(shown "$INFRA_RE")"
    [ -n "$INFRA_SHADOW" ] && printf 'note: test_infra_regex is empty in the project conf and switches off the global value: %s\n' "$(shown "$INFRA_SHADOW")"

    # -z: a path with a double quote or a tab is read as it is (git would quote it); a path with a newline is not supported
    changed="$( { git -c core.quotepath=off diff --name-only -z --no-renames "$base" --
                  git -c core.quotepath=off ls-files -z --others --exclude-standard; } | tr '\000' '\n' | sort -u )"

    # --baseline: judge only what changed since the snapshot. A manifest path whose work-tree AND index state both equal the
    # recorded ones is skipped (and named); a manifest path whose state differs is judged even when it is no longer in the
    # changed list (reverted or deleted). `changed` becomes the paths to judge; BL_UNCH keeps the skipped ones for the mode check.
    BL_UNCH="$NL"
    if [ -n "$bl" ]; then
      bl_read "$bl"
      ml=""; i=0
      while [ "$i" -lt "$ML_N" ]; do ml+="${ML_P[i]}"$'\n'; i=$((i + 1)); done
      ml="${ml%$'\n'}"
      bl_states "$ml" || pb_die "cannot read the work-tree or index state for the baseline (git failed, or a path holds a newline)" 3
      bl_digest="$(git hash-object -- "$bl" 2>/dev/null)" || pb_die "cannot hash the baseline manifest: $bl" 3
      nunch=0; bnotes=""; newch=""; ML_U=(); i=0
      while [ "$i" -lt "$ML_N" ]; do
        ML_U[i]=0
        case "${ML_P[i]}" in .agents/handoff/*) i=$((i + 1)); continue ;; esac
        if [ "${BL_WT[i]}" = "${ML_WT[i]}" ] && [ "${BL_IX[i]}" = "${ML_IX[i]}" ] &&
           [ "${BL_WT[i]}" != unhashable ] && [ "${BL_IX[i]}" != unhashable ]; then
          ML_U[i]=1
          nunch=$((nunch + 1))
          BL_UNCH+="${ML_P[i]}"$'\n'
          np="${ML_P[i]}"
          # a CR or ESC could hide or rewrite the note: show control characters as ?, except TAB (it rewrites nothing)
          case "$np" in *[[:cntrl:]]*) np="$(printf '%s' "$np" | LC_ALL=C tr '\000-\010\012-\037\177' '?')" ;; esac
          bnotes+="note: unchanged since the baseline: $np"$'\n'
        fi
        i=$((i + 1))
      done
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$BL_UNCH" in *"$NL$f$NL"*) continue ;; esac
        newch+="$f"$'\n'
      done <<EOF
$changed
EOF
      i=0
      while [ "$i" -lt "$ML_N" ]; do
        if [ "${ML_U[i]}" -eq 0 ]; then
          case "${ML_P[i]}" in .agents/handoff/*) ;; *)
            case "$NL$changed$NL" in *"$NL${ML_P[i]}$NL"*) ;; *) newch+="${ML_P[i]}"$'\n' ;; esac ;;
          esac
        fi
        i=$((i + 1))
      done
      changed="$(printf '%s' "$newch" | sort -u)"
      printf 'note: baseline %s (%d path(s), digest %s): %d path(s) unchanged, not checked\n' "$bl" "$ML_N" "$bl_digest" "$nunch"
      printf '%s' "$bnotes"
    fi

    # v0.24.9: a test path whose only change from base to the work tree is a mode RESTORE (base 100644, now 100755, same
    # content) is not an implementer violation (a RED commit dropped the bit, a later commit gave it back): note it instead.
    # Anything else (a drop, a content change, a delete) is not matched here and stays a violation.
    mode_restore_only() {
      local raw meta st oldm newm ent rp="$1"
      raw="$(git -c core.quotepath=off diff --raw --no-abbrev --no-renames "$base" -- ":(literal)$rp" 2>/dev/null)" || return 1
      [ -n "$raw" ] || return 1   # an untracked new file has no raw line: not a restore
      [ "$(printf '%s\n' "$raw" | wc -l | tr -d ' ')" = 1 ] || return 1
      meta="${raw%%$'\t'*}"
      set -- $meta
      [ $# -ge 5 ] || return 1
      oldm="${1#:}"; newm="$2"; st="$5"
      [ "$oldm" = 100644 ] && [ "$newm" = 100755 ] && [ "$st" = M ] || return 1
      ent="$(git hash-object -- "$rp" 2>/dev/null)" || return 1
      [ "$ent" = "$3" ]
    }
    violations=0
    checked=0
    plist=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      plist+="$f"$'\n'
    done <<EOF
$changed
EOF
    plist="${plist%$'\n'}"
    classify_list "$plist"
    exec 3<<EOF
$KINDS
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      checked=$((checked + 1))
      IFS= read -r kind <&3
      if [ "$role" = implementer ] && [ "$kind" = test ] && mode_restore_only "$f"; then
        printf 'note: %s mode restore only (100644 -> 100755, content unchanged)\n' "$(shown "$f")"
        continue
      fi
      bad=0
      case "$role" in
        tester)      [ "$kind" != "test" ] && bad=1 ;;
        implementer) [ "$kind" != "code" ] && bad=1 ;;
        infra)       [ "$kind" != "infra" ] && bad=1 ;;
        reviewer)    bad=1 ;;
      esac
      if [ "$bad" -eq 1 ]; then
        printf 'VIOLATION (%s): %s [%s]\n' "$role" "$f" "$kind"
        violations=$((violations + 1))
      fi
    done <<EOF
$changed
EOF
    exec 3<&-
    # a lost executable bit (100755 -> 100644) is a violation for every role, work tree and staged index together.
    # The escape is PB_ALLOW_MODE_CHANGE: colon-separated exact repo-relative paths (a case pattern: no glob, no split).
    # The work-tree list and the staged list (git diff --cached) are merged, duplicates removed: a drop that is only staged
    # is caught too. A rename that drops the bit (delete 100755 + add 100644, same blob) names the NEW path.
    # A path that cannot be hashed ("cannot hash PATH") is reported too, and the escape silences exactly that path.
    # A path with a newline cannot be listed in the escape: it fails closed with no escape (rename it).
    nlbad=0
    modes_wt="$(pb_raw_lines "$base" --)"; rc=$?
    case "$rc" in 0) ;; 4) nlbad=1; modes_wt="" ;; *) pb_die "git diff failed" 3 ;; esac
    modes_ix="$(pb_raw_lines --cached "$base" --)"; rc=$?
    case "$rc" in 0) ;; 4) nlbad=1; modes_ix="" ;; *) pb_die "git diff failed" 3 ;; esac
    if [ "$nlbad" = 1 ]; then
      printf 'VIOLATION (mode): a path contains a newline or a \\002 byte; the mode check is incomplete\n'
      violations=$((violations + 1))
    fi
    lost="$( { printf '%s\n' "$modes_wt"; printf '%s\n' "$modes_ix"; } | pb_lost_exec_paths )"
    while IFS= read -r mpath; do
      [ -n "$mpath" ] || continue
      mkind="${mpath%"${mpath#?}"}"; mpath="${mpath#?}"
      case ":${PB_ALLOW_MODE_CHANGE:-}:" in *":$mpath:"*) continue ;; esac
      case "$BL_UNCH" in *"$NL$mpath$NL"*) continue ;; esac   # --baseline: the drop was already there (state unchanged)
      if [ "$mkind" = U ]; then
        printf 'VIOLATION (mode): cannot hash %s; the mode check is incomplete\n' "$mpath"
      else
        printf 'VIOLATION (mode): %s lost its executable bit (100755 -> 100644)\n' "$mpath"
      fi
      violations=$((violations + 1))
    done <<EOF
$lost
EOF
    if [ "$violations" -gt 0 ]; then
      printf 'role gate FAILED for %s: %d violation(s), base=%s\n' "$role" "$violations" "$base"
      exit 1
    fi
    printf 'OK: role gate passed for %s (%d file(s) checked, base=%s)\n' "$role" "$checked" "$base"
    ;;
  snapshot)
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --out) { [ $# -ge 2 ] && [ -n "$2" ]; } || pb_die "--out needs a file" 2; out="$2"; shift ;;
        *) pb_die "unknown option: $1
usage: role-gate.sh snapshot [--out FILE]" 2 ;;
      esac
      shift
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree (role gates need git)" 3
    git rev-parse --verify -q "HEAD^{commit}" >/dev/null 2>&1 || pb_die "no HEAD commit to snapshot against" 3
    if [ -n "$out" ]; then case "$out" in /* | [A-Za-z]:[/\\]*) ;; *) out="$PWD/$out" ;; esac; fi
    top="$(git rev-parse --show-toplevel)"
    cd "$top" || pb_die "cannot enter $top" 3
    if [ -z "$out" ]; then
      out="$(git rev-parse --git-path pb-gate-baseline)"
      case "$out" in /* | [A-Za-z]:[/\\]*) ;; *) out="$top/$out" ;; esac
    fi
    # a path with a newline cannot be one manifest line: LF is mapped to \002 while the NULs become line ends
    raw="$( { git -c core.quotepath=off diff --name-only -z --no-renames HEAD --
              git -c core.quotepath=off diff --cached --name-only -z --no-renames HEAD --
              git -c core.quotepath=off ls-files -z --others --exclude-standard; } | tr '\n\000' '\002\n' )"
    case "$raw" in *$'\002'*) pb_die "a path contains a newline or a \\002 byte; it cannot be recorded in a baseline" 3 ;; esac
    raw="$(printf '%s\n' "$raw" | LC_ALL=C sort -u)"
    plist=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      plist+="$f"$'\n'
    done <<EOF
$raw
EOF
    plist="${plist%$'\n'}"
    bl_states "$plist" || pb_die "cannot read the work-tree or index state (git failed, or a path holds a newline)" 3
    content="$BL_HDR"; n=0; i=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "${BL_WT[i]}" = unhashable ] || [ "${BL_IX[i]}" = unhashable ]; then
        printf 'note: %s cannot be hashed (gitlink, directory, unreadable file or conflict); recorded as unhashable, it never counts as unchanged\n' "$f"
      fi
      content+="$NL${BL_WT[i]}"$'\t'"${BL_IX[i]}"$'\t'"$f"
      n=$((n + 1)); i=$((i + 1))
    done <<EOF
$plist
EOF
    printf '%s\n' "$content" > "$out" 2>/dev/null || pb_die "cannot write the baseline manifest: $out" 3
    printf 'baseline: %d path(s) recorded in %s (digest %s)\n' "$n" "$out" "$(git hash-object -- "$out")"
    # a manifest inside the work tree (untracked, not ignored, not under .agents/handoff/) is itself a change the next check
    # judges; say so (v0.24.20). git decides, so a C:/ versus /c/ spelling of the same path on Git Bash does not matter.
    inwt="$(git -c core.quotepath=off ls-files --others --exclude-standard -- "$out" 2>/dev/null)" || inwt=""
    case "$inwt" in
      '' | .agents/handoff/*) ;;
      *) printf 'note: the manifest is inside the work tree: the next role-gate check judges it as a change; keep it in the git dir (the default) or outside the repository\n' ;;
    esac
    ;;
  size)
    base="HEAD"; max_files=""; max_lines=""; bl=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --base)      [ $# -ge 2 ] || pb_die "--base needs a ref" 2; base="$2"; shift ;;
        --baseline)  { [ $# -ge 2 ] && [ -n "$2" ]; } || pb_die "--baseline needs a file" 2; bl="$2"; shift ;;
        --max-files) [ $# -ge 2 ] || pb_die "--max-files needs a number" 2; max_files="$2"; shift ;;
        --max-lines) [ $# -ge 2 ] || pb_die "--max-lines needs a number" 2; max_lines="$2"; shift ;;
        *) pb_die "unknown option: $1
usage: role-gate.sh check <role> [--base REF] [--baseline FILE] | snapshot [--out FILE] | classify <path> | size [--base REF] [--max-files N] [--max-lines M] [--baseline FILE]" 2 ;;
      esac
      shift
    done
    [ -n "$max_files" ] || max_files=3
    [ -n "$max_lines" ] || max_lines=100
    for n in "$max_files" "$max_lines"; do
      case "$n" in ''|*[!0-9]*) pb_die "limit must be a non-negative integer: $n" 2 ;; esac
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree (role gates need git)" 3
    git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || pb_die "base ref not found: $base" 3
    # a relative manifest path is the caller's: resolve it before the gate moves to the top of the work tree
    if [ -n "$bl" ]; then case "$bl" in /* | [A-Za-z]:[/\\]*) ;; *) bl="$PWD/$bl" ;; esac; fi
    top="$(git rev-parse --show-toplevel)"
    cd "$top" || pb_die "cannot enter $top" 3

    # --baseline: BL_UNCH holds the manifest paths whose work-tree and index state equal the recorded ones (left out below);
    # BL_EXTRA the changed ones, counted even when no longer in the numstat list (a reverted or deleted path)
    BL_UNCH="$NL"; BL_EXTRA=""
    if [ -n "$bl" ]; then
      bl_read "$bl"
      ml=""; i=0
      while [ "$i" -lt "$ML_N" ]; do ml+="${ML_P[i]}"$'\n'; i=$((i + 1)); done
      ml="${ml%$'\n'}"
      bl_states "$ml" || pb_die "cannot read the work-tree or index state for the baseline (git failed, or a path holds a newline)" 3
      i=0
      while [ "$i" -lt "$ML_N" ]; do
        case "${ML_P[i]}" in .agents/handoff/*) ;; *)
          if [ "${BL_WT[i]}" = "${ML_WT[i]}" ] && [ "${BL_IX[i]}" = "${ML_IX[i]}" ] &&
             [ "${BL_WT[i]}" != unhashable ] && [ "${BL_IX[i]}" != unhashable ]; then
            BL_UNCH+="${ML_P[i]}"$'\n'
          else
            BL_EXTRA+="${ML_P[i]}"$'\n'
          fi ;;
        esac
        i=$((i + 1))
      done
    fi

    # one "added<TAB>deleted<TAB>path" line per file; untracked files diffed against /dev/null
    stats="$( git -c core.quotepath=off diff --numstat --no-renames "$base" --
              git -c core.quotepath=off ls-files --others --exclude-standard |
                while IFS= read -r u; do
                  [ -n "$u" ] || continue
                  counts="$(git diff --no-index --numstat -- /dev/null "$u" | cut -f1,2)"
                  [ -n "$counts" ] || counts="$(printf '0\t0')"   # empty file: no numstat line
                  printf '%s\t%s\n' "$counts" "$u"
                done )"

    files=0
    lines=0
    plist=""
    metas=""
    seen=""
    while IFS=$'\t' read -r added deleted f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      case "$BL_UNCH" in *"$NL$f$NL"*) continue ;; esac
      plist+="$f"$'\n'
      metas+="$added $deleted"$'\n'
      seen+="$f"$'\n'
    done <<EOF
$stats
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$NL$seen" in *"$NL$f$NL"*) continue ;; esac
      plist+="$f"$'\n'
      metas+="1 0"$'\n'
    done <<EOF
$BL_EXTRA
EOF
    plist="${plist%$'\n'}"
    classify_list "$plist"
    exec 3<<EOF
$KINDS
EOF
    while IFS=' ' read -r added deleted; do
      [ -n "$added" ] || continue
      IFS= read -r kind <&3
      [ "$kind" != "test" ] || continue   # code and infra count
      files=$((files + 1))
      if [ "$added" = "-" ]; then
        lines=$((lines + 1))
      else
        lines=$((lines + added + deleted))
      fi
    done <<EOF
$metas
EOF
    exec 3<&-
    printf 'files: %d/%d lines: %d/%d (base=%s)\n' "$files" "$max_files" "$lines" "$max_lines" "$base"
    if [ "$files" -gt "$max_files" ] || [ "$lines" -gt "$max_lines" ]; then
      printf 'over the Lite size limit: escalate to Full\n'
      exit 1
    fi
    ;;
  *)
    pb_die "usage: role-gate.sh check <role> [--base REF] [--baseline FILE] | snapshot [--out FILE] | classify <path> | size [--base REF] [--max-files N] [--max-lines M] [--baseline FILE]" 2
    ;;
esac
