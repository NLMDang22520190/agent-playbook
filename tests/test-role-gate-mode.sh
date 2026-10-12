#!/usr/bin/env bash
# Tests for scripts/role-gate.sh, part 2 of 2 (split from test-role-gate.sh in v0.24.1): the executable-bit sections of v0.23.2 from "paths with a
# double quote or a tab" on, and the v0.23.3 sections (the mode check never fails open). Shared setup: role-gate-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
unset PB_ALLOW_MODE_CHANGE

echo "v0.23.2 fix LOW-6 paths with a double quote or a tab: real name reported, allowed through PB_ALLOW_MODE_CHANGE"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
QP='src/we"ird.sh'
TP="$(printf 'src/ta\tb.sh')"
for P in "$QP" "$TP"; do
  if cp src/run.sh "$P" 2>/dev/null && [ -f "$P" ] && git add -- "$P" 2>/dev/null && [ -n "$(git ls-files -- "$P")" ]; then
    git update-index --chmod=+x -- "$P" && git commit -q -m "add odd name"
    git update-index --chmod=-x -- "$P"
    gchk implementer; assert_rc "LOW-6 [$P] a staged drop fails" 1
    assert_contains "LOW-6 [$P] the real path is printed unquoted" "$OUT" "VIOLATION (mode): $P lost its executable bit (100755 -> 100644)"
    gchk_allow "$P" implementer; assert_rc "LOW-6 [$P] PB_ALLOW_MODE_CHANGE with the real path passes" 0
    git update-index --chmod=+x -- "$P"
  else rm -f -- "$P" 2>/dev/null; t_skip 3 "LOW-6 path [$P] (this file system or git refuses the name)"; fi
done
HDR="$(sed -n 1,45p "$GATE" | tr 'A-Z' 'a-z')"
assert_contains "LOW-6 the help says a path with a colon cannot be listed in PB_ALLOW_MODE_CHANGE" "$HDR" "cannot be listed"

echo "v0.23.2 round 2 MINOR-B a rename plus a mode drop that exists only in the work tree (core.fileMode=true) is caught"
for spec in tester:tests/run.sh:tests/renamed.sh implementer:src/run.sh:src/renamed.sh reviewer:src/run.sh:src/renamed.sh infra:ci/run.sh:ci/renamed.sh; do
  role="${spec%%:*}"; rest="${spec#*:}"; old="${rest%%:*}"; new="${rest#*:}"
  MSG="VIOLATION (mode): $new lost its executable bit (100755 -> 100644)"
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  if ! fm_true_ok; then t_skip 4 "MINOR-B $role (this file system does not keep executable bits)"; continue; fi
  git mv "$old" "$new"; chmod -x "$new" 2>/dev/null          # the new path is NOT re-added: the index still says 100755
  if [ -x "$new" ]; then t_skip 4 "MINOR-B $role (chmod -x has no effect here)"; continue; fi
  assert_eq "MINOR-B $role: fixture: the index still says $new is 100755" "100755" "$(git ls-files -s -- "$new" | cut -d' ' -f1)"
  gchk "$role"; assert_rc "MINOR-B $role: a work-tree-only rename + drop fails" 1
  assert_contains "MINOR-B $role: the NEW path is named with both modes" "$OUT" "$MSG"
  gchk_allow "$new" "$role"
  assert_not_contains "MINOR-B $role: PB_ALLOW_MODE_CHANGE=new path silences it" "$OUT" "VIOLATION (mode)"
done
echo "v0.23.2 round 2 MINOR-B a work-tree-only rename that keeps the bit is not reported"
for spec in implementer:src/run.sh:src/renamed.sh tester:tests/run.sh:tests/renamed.sh; do
  role="${spec%%:*}"; rest="${spec#*:}"; old="${rest%%:*}"; new="${rest#*:}"
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  if ! fm_true_ok; then t_skip 1 "MINOR-B $role keep (this file system does not keep executable bits)"; continue; fi
  git mv "$old" "$new"
  gchk "$role"
  assert_not_contains "MINOR-B $role: a rename that keeps 100755 has no mode violation" "$OUT" "(mode)"
done

echo "v0.23.2 round 2 LOW-a an empty executable deleted and an empty 644 file added is not a rename"
for role in tester implementer reviewer infra; do
  R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
  if ! fm_true_ok; then t_skip 2 "LOW-a $role (this file system does not keep executable bits)"; continue; fi
  : > keep.sh; chmod +x keep.sh 2>/dev/null
  git add keep.sh; git update-index --chmod=+x -- keep.sh; git commit -q -m "empty exec"
  git rm -q keep.sh
  mkdir -p pkg; : > pkg/__init__.py; git add pkg/__init__.py
  assert_eq "LOW-a $role: fixture: keep.sh was committed 100755" "100755" "$(git ls-tree HEAD -- keep.sh | cut -d' ' -f1)"
  gchk "$role"
  assert_not_contains "LOW-a $role: no mode violation for a delete + an unrelated empty add" "$OUT" "(mode)"
done

echo "v0.23.2 round 2 LOW-b the header describes rename detection as a rename with unchanged content"
HDR2="$(sed -n 1,45p "$GATE" | sed 's/^# \{0,1\}//' | tr 'A-Z' 'a-z' | tr -s ' \n\t' '   ')"
assert_contains "LOW-b the header says 'a rename with unchanged content'" "$HDR2" "a rename with unchanged content"

# ---- v0.23.3 lane A (tester): AC3 (R3) the mode check never fails open ----
echo "v0.23.3 AC3.1 (R3) a work-tree file git cannot hash is reported, and it does not hide the other drops"
unset PB_ALLOW_MODE_CHANGE
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
UNH_OK=0
if [ "$(id -u)" = 0 ]; then UNH_WHY="running as root (chmod 000 does not stop root)"
elif ! fm_true_ok; then UNH_WHY="this file system does not keep executable bits"
else
  # two renamed work-tree files: src/renamed.sh just loses its bit (hashed, paired with the deleted src/run.sh);
  # src/second2.sh cannot be read at all (chmod 000), so git hash-object fails on it
  git mv src/run.sh src/renamed.sh; git mv src/second.sh src/second2.sh
  chmod -x src/renamed.sh 2>/dev/null; chmod 000 src/second2.sh 2>/dev/null
  if cat src/second2.sh >/dev/null 2>&1 || [ -x src/renamed.sh ]; then UNH_WHY="chmod 000 / chmod -x have no effect here"
  else UNH_OK=1; fi
fi
if [ "$UNH_OK" = 1 ]; then
  LOSTMSG="VIOLATION (mode): src/renamed.sh lost its executable bit (100755 -> 100644)"
  CANTMSG="VIOLATION (mode): cannot hash src/second2.sh; the mode check is incomplete"
  gchk implementer
  assert_rc "AC3.1 an unhashable file next to a normal drop: the gate fails" 1
  assert_contains "AC3.1 the normal drop is reported as a lost bit (the unhashable file does not hide it)" "$OUT" "$LOSTMSG"
  assert_contains "AC3.1 the unhashable file is reported: cannot hash PATH; the mode check is incomplete" "$OUT" "$CANTMSG"
  gchk_allow "src/second2.sh" implementer
  assert_rc "AC3.1 PB_ALLOW_MODE_CHANGE with the unhashable path: the normal drop still fails" 1
  assert_contains "AC3.1 ... the normal drop is still reported" "$OUT" "$LOSTMSG"
  assert_not_contains "AC3.1 ... the allowed unhashable path is silenced (and only it)" "$OUT" "cannot hash"
  gchk_allow "src/renamed.sh" implementer
  assert_rc "AC3.1 PB_ALLOW_MODE_CHANGE with the normal path: the unhashable one still fails" 1
  assert_contains "AC3.1 ... the unhashable path is still reported" "$OUT" "$CANTMSG"
  assert_not_contains "AC3.1 ... the allowed normal path is silenced" "$OUT" "VIOLATION (mode): src/renamed.sh"
  gchk_allow "src/renamed.sh:src/second2.sh" implementer
  assert_rc "AC3.1 both listed: the gate passes" 0
  assert_not_contains "AC3.1 both listed: no mode violation" "$OUT" "(mode)"
  # alone, the unhashable file still fails closed (it is not just a side effect of the other drop)
  chmod +x src/renamed.sh 2>/dev/null   # src/renamed.sh keeps its bit now: only the unreadable file is left
  gchk implementer
  assert_contains "AC3.1 the unhashable file alone is reported too" "$OUT" "$CANTMSG"
  chmod 644 src/second2.sh 2>/dev/null
else t_skip 12 "AC3.1 unhashable work-tree file ($UNH_WHY)"; fi

echo "v0.23.3 AC3.2 (R3) a path with a newline fails closed, there is no PB_ALLOW_MODE_CHANGE escape"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
NLP="$(printf 'src/new\nline.sh')"
if printf '#!/bin/sh\n' > "$NLP" 2>/dev/null && [ -f "$NLP" ] && git add -- "$NLP" 2>/dev/null && git ls-files --error-unmatch -- "$NLP" >/dev/null 2>&1; then
  NLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  for role in implementer tester reviewer infra; do
    gchk "$role"
    assert_rc "AC3.2 $role: a staged path with a newline fails" 1
    assert_contains "AC3.2 $role: the message says a path contains a newline and the mode check is incomplete" "$OUT" "$NLMSG"
  done
  gchk_allow "$NLP" implementer
  assert_rc "AC3.2 PB_ALLOW_MODE_CHANGE with the whole path is no escape" 1
  assert_contains "AC3.2 ... the message is still printed" "$OUT" "$NLMSG"
  gchk_allow "src/new:line.sh:src/new
line.sh" implementer
  assert_rc "AC3.2 PB_ALLOW_MODE_CHANGE with the pieces is no escape either" 1
  git rm -q --cached -f -- "$NLP"; rm -f "$NLP"
  gchk implementer
  assert_rc "AC3.2 once the path is gone the gate passes again" 0
else rm -f "$NLP" 2>/dev/null; t_skip 12 "AC3.2 newline path (this file system or git refuses the name)"; fi

# ---- v0.23.3 lane A review of 146dd98 ----
echo "v0.23.3 lane A review MINOR-3 the header and the message name control bytes, not only newlines"
if head -n 45 "$GATE" | grep -Eqi 'control byte|\\002 byte'; then t_ok "the header (first 45 lines) mentions the control-byte limit"; else t_bad "the header (first 45 lines) mentions the control-byte limit" "no 'control byte' in lines 1-45 of scripts/role-gate.sh"; fi
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
CTLP="src/ctl$(printf '\002')x.sh"
if printf '#!/bin/sh\n' > "$CTLP" 2>/dev/null && [ -f "$CTLP" ] && git add -- "$CTLP" 2>/dev/null && git ls-files --error-unmatch -- "$CTLP" >/dev/null 2>&1; then
  CTLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  for role in implementer tester reviewer infra; do
    gchk "$role"
    assert_rc "$role: a staged path with a \\002 byte fails" 1
    assert_contains "$role: the message says a path contains a newline or control byte" "$OUT" "$CTLMSG"
  done
  gchk_allow "$CTLP" implementer
  assert_rc "PB_ALLOW_MODE_CHANGE with the path is no escape" 1
  assert_contains "... the message is still printed" "$OUT" "$CTLMSG"
  git rm -q --cached -f -- "$CTLP"; rm -f "${R:?}/${CTLP:?}"
else rm -f "${R:?}/${CTLP:?}" 2>/dev/null; t_skip 11 "control-byte path (this file system or git refuses the name)"; fi

echo "v0.23.3 lane A review MINOR-4 one unreadable intent-to-add file among 1000 readable ones: the fallback stays bounded"
unset PB_ALLOW_MODE_CHANGE
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
FB_OK=0
if [ "$(id -u)" = 0 ]; then FB_WHY="running as root (chmod 000 does not stop root)"
else
  mkdir -p bulk
  fbi=0; while [ "$fbi" -lt 1000 ]; do printf 'x%d\n' "$fbi" > "bulk/f$fbi.txt"; fbi=$((fbi + 1)); done
  printf 'locked\n' > bulk/unreadable.txt
  git add -N -- bulk
  chmod 000 bulk/unreadable.txt 2>/dev/null
  if cat bulk/unreadable.txt >/dev/null 2>&1; then FB_WHY="chmod 000 has no effect here"; else FB_OK=1; fi
fi
if [ "$FB_OK" = 1 ]; then
  FBLOG="$(mk_tmp)/hash.log"; : > "$FBLOG"
  FBSHIM="$(mk_tmp)/shim"; mkdir -p "$FBSHIM"
  FBREAL="$(command -v git)"
  cat > "$FBSHIM/git" <<SHIM
#!/bin/sh
for a in "\$@"; do
  case "\$a" in hash-object) echo "\$*" >> "$FBLOG"; break ;; esac
done
exec "$FBREAL" "\$@"
SHIM
  chmod +x "$FBSHIM/git"
  run env PLAYBOOK_HOME="$IH" PATH="$FBSHIM:$PATH" bash "$GATE" check implementer
  FBN="$(wc -l < "$FBLOG" | tr -d ' ')"
  if [ "$FBN" -ge 1 ]; then t_ok "fixture: the shim saw git hash-object ($FBN call(s))"; else t_bad "fixture: the shim saw git hash-object" "0 calls; shim not on the path of the gate, or no intent-to-add path reached the hash step"; fi
  if [ "$FBN" -le 10 ]; then t_ok "hash-object is started at most 10 times for 1001 paths ($FBN)"; else t_bad "hash-object is started at most 10 times for 1001 paths" "$FBN hash-object processes: one per readable path"; fi
  assert_rc "the gate fails (the unreadable file)" 1
  assert_contains "the one unreadable file is still reported: cannot hash" "$OUT" "VIOLATION (mode): cannot hash bulk/unreadable.txt; the mode check is incomplete"
  assert_eq "only one path is reported as unhashable" "1" "$(printf '%s\n' "$OUT" | grep -c 'cannot hash')"
  chmod 644 bulk/unreadable.txt 2>/dev/null
else t_skip 5 "bounded fallback ($FB_WHY)"; fi
t_summary
