#!/usr/bin/env bash
# Tests for the v0.23.2 documentation rules: AC1.3 (role files: the exec bit at commit time) and AC11 (README: WSL idle notes).
# Reads $PB_ROOT/README.md and the three role files; nothing else.
. "$(dirname "$0")/lib.sh"
ROLES="$PB_ROOT/skills/playbook-tdd/roles"
README="$PB_ROOT/README.md"

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

echo "AC11 README: WSL idle behaviour"
assert_file "AC11 README.md exists" "$README"
# near FILE KEY NEEDLE -> 0 when NEEDLE (fixed) is on a line with KEY or within the 2 lines after it
near() { grep -A2 -F -e "$2" "$1" 2>/dev/null | grep -Fq -e "$3"; }
if grep -Fq 'instanceIdleTimeout' "$README"; then t_ok "AC11 README names instanceIdleTimeout"; else t_bad "AC11 README names instanceIdleTimeout" "missing"; fi
if near "$README" instanceIdleTimeout '[general]'; then t_ok "AC11 instanceIdleTimeout is placed under [general]"; else t_bad "AC11 instanceIdleTimeout is placed under [general]" "no [general] next to it"; fi
if near "$README" instanceIdleTimeout '-1'; then t_ok "AC11 instanceIdleTimeout: -1 disables it"; else t_bad "AC11 instanceIdleTimeout: -1 disables it" "no -1 next to it"; fi
if grep -Fq 'vmIdleTimeout' "$README"; then t_ok "AC11 README names vmIdleTimeout"; else t_bad "AC11 README names vmIdleTimeout" "missing"; fi
if near "$README" vmIdleTimeout '[wsl2]'; then t_ok "AC11 vmIdleTimeout is placed under [wsl2]"; else t_bad "AC11 vmIdleTimeout is placed under [wsl2]" "no [wsl2] next to it"; fi
if grep -Fq 'sleep infinity' "$README"; then t_ok "AC11 README says to keep a process alive (sleep infinity)"; else t_bad "AC11 README says to keep a process alive (sleep infinity)" "no 'sleep infinity'"; fi
if grep -Fq 'autoMemoryReclaim' "$README"; then t_ok "AC11 README names autoMemoryReclaim"; else t_bad "AC11 README names autoMemoryReclaim" "missing"; fi
if near "$README" autoMemoryReclaim '[experimental]'; then t_ok "AC11 autoMemoryReclaim is placed under [experimental]"; else t_bad "AC11 autoMemoryReclaim is placed under [experimental]" "no [experimental] next to it"; fi
if grep -Ei '/tmp' "$README" | grep -Ei 'wiped|cleared|emptied' | grep -Eiq 'observed|one machine'; then t_ok "AC11 /tmp wiped on restart is stated as observed (one machine)"; else t_bad "AC11 /tmp wiped on restart is stated as observed (one machine)" "no line with /tmp, wiped and observed"; fi
if grep -Eq 'vmIdleTimeout[[:space:]]*(=|:)?[[:space:]]*`?-1' "$README"; then t_bad "AC11 README does not claim vmIdleTimeout=-1" "found a vmIdleTimeout -1 claim"; else t_ok "AC11 README does not claim vmIdleTimeout=-1"; fi
if grep -F 'vmIdleTimeout' "$README" | grep -Eq '(=|: ?)-1'; then t_bad "AC11 no vmIdleTimeout line carries =-1" "a vmIdleTimeout line has -1"; else t_ok "AC11 no vmIdleTimeout line carries =-1"; fi

t_summary
