#!/usr/bin/env bash
# Tests for the v0.23.2 documentation rules: AC1.3 (role files: the exec bit at commit time) and AC11 (WSL idle notes, now in docs/harness-notes.md).
# Reads $PB_ROOT/docs/harness-notes.md (the WSL section), $PB_ROOT/README.md (the links to it) and the three role files; nothing else.
. "$(dirname "$0")/lib.sh"
ROLES="$PB_ROOT/skills/playbook-tdd/roles"
README="$PB_ROOT/README.md"
HN="$PB_ROOT/docs/harness-notes.md"

# has_line FILE REGEX -> 0 when a line of FILE matches the ERE (case-insensitive)
has_line() { grep -Eiq -e "$2" "$1" 2>/dev/null; }

echo "AC1.3 the role files say how to keep the executable bit"
for role in tester implementer reviewer; do
  f="$ROLES/$role.md"
  assert_file "AC1.3 $role.md exists" "$f"
  if has_line "$f" 'git diff --raw'; then t_ok "AC1.3 $role.md tells to check git diff --raw"; else t_bad "AC1.3 $role.md tells to check git diff --raw" "no 'git diff --raw' in $f"; fi
  if has_line "$f" 'mode change'; then t_ok "AC1.3 $role.md names a mode change"; else t_bad "AC1.3 $role.md names a mode change" "no 'mode change' in $f"; fi
  if has_line "$f" '(executable|exec) bit'; then t_ok "AC1.3 $role.md mentions the executable bit"; else t_bad "AC1.3 $role.md mentions the executable bit" "no '(executable|exec) bit' in $f"; fi
  if has_line "$f" 'editor|edit tool|editing tool|write tool'; then t_ok "AC1.3 $role.md says an editor tool can drop it"; else t_bad "AC1.3 $role.md says an editor tool can drop it" "no editor/edit tool wording in $f"; fi
  if has_line "$f" 'PB_ALLOW_MODE_CHANGE'; then t_ok "AC1.3 $role.md names PB_ALLOW_MODE_CHANGE"; else t_bad "AC1.3 $role.md names PB_ALLOW_MODE_CHANGE" "no PB_ALLOW_MODE_CHANGE in $f"; fi
done

echo "AC11 harness-notes WSL section: WSL idle behaviour"
assert_file "AC11 docs/harness-notes.md exists" "$HN"
assert_file "AC11 README.md exists" "$README"
if grep -q '^## WSL' "$HN"; then t_ok "AC11 harness-notes has a ## WSL section"; else t_bad "AC11 harness-notes has a ## WSL section" "no ## WSL heading"; fi
if grep -Fq '](docs/harness-notes.md#wsl)' "$README"; then t_ok "AC11 README links to the WSL section of docs/harness-notes.md"; else t_bad "AC11 README links to the WSL section of docs/harness-notes.md" "no link to docs/harness-notes.md#wsl"; fi
# near FILE KEY NEEDLE -> 0 when NEEDLE (fixed) is on a line with KEY or within the 2 lines after it
near() { grep -A2 -F -e "$2" "$1" 2>/dev/null | grep -Fq -e "$3"; }
if grep -Fq 'instanceIdleTimeout' "$HN"; then t_ok "AC11 harness-notes names instanceIdleTimeout"; else t_bad "AC11 harness-notes names instanceIdleTimeout" "missing"; fi
if near "$HN" instanceIdleTimeout '[general]'; then t_ok "AC11 instanceIdleTimeout is placed under [general]"; else t_bad "AC11 instanceIdleTimeout is placed under [general]" "no [general] next to it"; fi
if near "$HN" instanceIdleTimeout '-1'; then t_ok "AC11 instanceIdleTimeout: -1 disables it"; else t_bad "AC11 instanceIdleTimeout: -1 disables it" "no -1 next to it"; fi
if grep -Fq 'vmIdleTimeout' "$HN"; then t_ok "AC11 harness-notes names vmIdleTimeout"; else t_bad "AC11 harness-notes names vmIdleTimeout" "missing"; fi
if near "$HN" vmIdleTimeout '[wsl2]'; then t_ok "AC11 vmIdleTimeout is placed under [wsl2]"; else t_bad "AC11 vmIdleTimeout is placed under [wsl2]" "no [wsl2] next to it"; fi
if grep -Fq 'sleep infinity' "$HN"; then t_ok "AC11 harness-notes says to keep a process alive (sleep infinity)"; else t_bad "AC11 harness-notes says to keep a process alive (sleep infinity)" "no 'sleep infinity'"; fi
if grep -Fq 'autoMemoryReclaim' "$HN"; then t_ok "AC11 harness-notes names autoMemoryReclaim"; else t_bad "AC11 harness-notes names autoMemoryReclaim" "missing"; fi
if near "$HN" autoMemoryReclaim '[experimental]'; then t_ok "AC11 autoMemoryReclaim is placed under [experimental]"; else t_bad "AC11 autoMemoryReclaim is placed under [experimental]" "no [experimental] next to it"; fi
if grep -Ei '/tmp' "$HN" | grep -Ei 'wiped|cleared|emptied' | grep -Eiq 'observed|one machine'; then t_ok "AC11 /tmp wiped on restart is stated as observed (one machine)"; else t_bad "AC11 /tmp wiped on restart is stated as observed (one machine)" "no line with /tmp, wiped and observed"; fi
if grep -Eq 'vmIdleTimeout[[:space:]]*(=|:)?[[:space:]]*`?-1' "$HN"; then t_bad "AC11 harness-notes does not claim vmIdleTimeout=-1" "found a vmIdleTimeout -1 claim"; else t_ok "AC11 harness-notes does not claim vmIdleTimeout=-1"; fi
if grep -F 'vmIdleTimeout' "$HN" | grep -Eq '(=|: ?)-1'; then t_bad "AC11 no vmIdleTimeout line carries =-1" "a vmIdleTimeout line has -1"; else t_ok "AC11 no vmIdleTimeout line carries =-1"; fi


echo "v0.23.3 AC9.3 harness-notes: vmIdleTimeout needs Windows 11"
if grep -F 'vmIdleTimeout' "$HN" | grep -Fq 'Windows 11'; then t_ok "AC9.3 the vmIdleTimeout line says Windows 11"; else t_bad "AC9.3 the vmIdleTimeout line says Windows 11" "no vmIdleTimeout line with 'Windows 11'"; fi
if grep -F 'vmIdleTimeout' "$HN" | grep -Eiq 'only'; then t_ok "AC9.3 the vmIdleTimeout line says Windows 11 only"; else t_bad "AC9.3 the vmIdleTimeout line says Windows 11 only" "no 'only' on the vmIdleTimeout line"; fi

t_summary
