#!/usr/bin/env bash
# agent-playbook installer. Bash 3.2+. Run `install.sh help` for usage.
# Installs: skills (symlinks, or copies with --copy), a stable scripts path
# (~/.agents/playbook), and a managed always-on block in each harness's global
# instruction file. Idempotent. Never touches files it does not own (use --force
# to move foreign conflicts into ~/.agents/playbook-backups).
set -u

REPO="$(cd "$(dirname "$0")" && pwd -P)"
VERSION="$(tr -d '[:space:]' < "$REPO/VERSION")"
BEGIN_PREFIX='<!-- BEGIN agent-playbook'
END_LINE='<!-- END agent-playbook -->'
MARKER='.playbook-managed'

CMD=""; H="${HOME:-}"; HARNESS=""; COPY=0; DRY=0; FORCE=0; YES=0; TO=""; CHECK=0; ALLOW_UNSIGNED=0; ALLOW_UNRELEASED=0; HOOKS_FLAG=""
# Every successful install is recorded here so `update` can refresh all targets
# (WSL home, Windows home in copy mode, ...). Tests point it elsewhere.
REGISTRY="${PLAYBOOK_REGISTRY:-$REPO/.install-targets}"
PROBLEMS=0
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMPS=""
trap 'for t in $TMPS; do rm -f "$t"; done' EXIT

usage() {
  cat <<'EOF'
agent-playbook installer

Usage: install.sh <command> [options]

Commands
  install     install skills + always-on block (idempotent; repairs drift)
  uninstall   remove only what this installer created
  status      one line per harness: installed | partial | not installed
  doctor      verify links, copies, blocks and known pitfalls (exit 1 on problems)
  update      fetch release tags, verify the tag's signature, show the changelog, check out
              the newest (or --to TAG) and re-install every recorded target; --check only reports

Options
  --harness LIST   claude,codex,opencode | all   (install: auto-detected from ~/.claude,
                   ~/.codex, ~/.config/opencode when omitted; status/doctor default: all)
  --home DIR       use DIR instead of $HOME (sandboxes, Windows home from WSL, tests)
  --copy           copy instead of symlink (Windows without symlink rights)
  --dry-run        print what would change, change nothing
  --force          move conflicting foreign files/dirs to ~/.agents/playbook-backups
  --yes            do not ask for confirmation (required when stdin is not a terminal)
  --to TAG         update: release to check out (rollback: --to v0.31.0)
  --check          update: only report whether a newer release exists
  --no-hooks       install: do not install the Claude Code hooks; writes hooks_optout=yes to
                   <home>/.agents/playbook.conf, so update keeps the choice (PB_HOOKS=off skips them
                   for one run and persists nothing)
  --hooks          install: install the Claude Code hooks (the default) and clear hooks_optout
  --allow-unsigned update: continue with an unsigned tag (or one whose signature cannot be
                   checked, a failing PGP/x509 signature included) although require_signed_tags=yes;
                   an SSH signature that fails against gpg.ssh.allowedSignersFile still stops it
  --allow-unreleased update: take a tag that has no GitHub Release (or when the Releases API cannot
                   be checked): the newest v* tag, or --to TAG; the signature check still runs

Release tag signatures (update)
  The tag is checked with `git verify-tag` before anything changes. Verified: reported.
  Unsigned, or signed but cannot be checked: a WARN line and the update continues. That covers
  an SSH signature while gpg.ssh.allowedSignersFile is not set, and a PGP/x509 signature that
  does not verify (no key, no gpg, or a bad signature). An SSH signature that does not verify
  against a configured gpg.ssh.allowedSignersFile stops the update (exit 1), even with
  --allow-unsigned.
  require_signed_tags=yes in ~/.agents/playbook.conf (global conf only; set it with
  scripts/conf.sh set require_signed_tags yes) makes an unsigned or unchecked tag fatal.
  Values: yes | no (default no); any other value stops the update (exit 2).
EOF
}

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$1"; exit "${2:-1}"; }
problem() { printf 'PROBLEM: %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }
doit() { if [ "$DRY" -eq 1 ]; then say "  would: $*"; return 0; fi; "$@"; }
mktmp() { local t; t="$(mktemp "${TMPDIR:-/tmp}/pbinst.XXXXXX")" || die "mktemp failed" 3; TMPS="$TMPS $t"; printf '%s' "$t"; }

# ---------- argument parsing ----------
CMD="${1:-}"
case "$CMD" in
  install|uninstall|status|doctor|update) shift ;;
  help|-h|--help|"") usage; exit 0 ;;
  *) err "unknown command: $CMD"; usage >&2; exit 2 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --harness) [ $# -ge 2 ] || die "--harness needs a value" 2; HARNESS="$2"; shift ;;
    --home)    [ $# -ge 2 ] || die "--home needs a value" 2; H="$2"; shift ;;
    --copy) COPY=1 ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --yes|-y) YES=1 ;;
    --to) [ $# -ge 2 ] || die "--to needs a tag" 2; TO="$2"; shift ;;
    --check) CHECK=1 ;;
    --allow-unsigned) ALLOW_UNSIGNED=1 ;;
    --allow-unreleased) ALLOW_UNRELEASED=1 ;;
    --no-hooks) HOOKS_FLAG=off ;;
    --hooks) HOOKS_FLAG=on ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" 2 ;;
  esac
  shift
done
[ -n "$H" ] || die "cannot determine home directory; pass --home" 2
if [ -d "$H" ]; then H="$(cd "$H" && pwd)"; fi   # absolute (logical) path for the registry

# ---------- paths ----------
STABLE="$H/.agents/playbook"
BK="$H/.agents/playbook-backups"
CLAUDE_RULES="$H/.claude/CLAUDE.md"
CODEX_RULES="$H/.codex/AGENTS.md"
OC_RULES="$H/.config/opencode/AGENTS.md"

SKILLS=""
for d in "$REPO"/skills/*/; do
  sk="${d%/}"; sk="${sk##*/}"   # basename without a process (slow on Git Bash, runs on every command)
  [ -f "${d}SKILL.md" ] && SKILLS="$SKILLS $sk"
done
[ -n "$SKILLS" ] || die "no skills found under $REPO/skills" 3

# ---------- harness selection ----------
resolve_harness() {
  local list="$HARNESS" h out=""
  if [ -z "$list" ]; then
    if [ "$CMD" = "install" ] || [ "$CMD" = "uninstall" ]; then
      [ -d "$H/.claude" ] && out="$out,claude"
      [ -d "$H/.codex" ] && out="$out,codex"
      [ -d "$H/.config/opencode" ] && out="$out,opencode"
      out="${out#,}"
      [ -n "$out" ] || die "no harness detected under $H (looked for .claude, .codex, .config/opencode). Pass --harness claude,codex,opencode|all" 2
      list="$out"
    else
      list="all"
    fi
  fi
  [ "$list" = "all" ] && list="claude,codex,opencode"
  out=""
  local IFS=','
  for h in $list; do
    case "$h" in claude|codex|opencode) ;; *) die "unknown harness: $h (use claude, codex, opencode or all)" 2 ;; esac
    case ",$out," in *",$h,"*) ;; *) out="$out,$h" ;; esac
  done
  HARNESS="${out#,}"
}
want() { case ",$HARNESS," in *",$1,"*) return 0 ;; esac; return 1; }
claude_covers() { want claude && return 0; grep -q "^$BEGIN_PREFIX" "$CLAUDE_RULES" 2>/dev/null; }

skill_dirs() {
  { want claude && printf '%s\n' "$H/.claude/skills"
    want codex && printf '%s\n' "$H/.agents/skills"
    if want opencode && ! want claude && ! want codex; then printf '%s\n' "$H/.agents/skills"; fi
  } | sort -u
}
rules_files() {
  want claude && printf '%s\n' "$CLAUDE_RULES"
  want codex && printf '%s\n' "$CODEX_RULES"
  if want opencode; then
    if [ -f "$OC_RULES" ] || ! claude_covers; then printf '%s\n' "$OC_RULES"; fi
  fi
}

# ---------- state probes ----------
skill_state() { # dst src -> ok | copy-ok | copy-drift | broken | stale | foreign | foreign-dir | missing
  local dst="$1" src="$2" tgt
  if [ -L "$dst" ]; then
    tgt="$(readlink "$dst")"
    if [ "$tgt" = "$src" ]; then if [ -e "$dst" ]; then echo ok; else echo broken; fi; return; fi
    case "$tgt" in "$REPO"/*) echo stale ;; *) echo foreign ;; esac
    return
  fi
  if [ -d "$dst" ]; then
    if [ -f "$dst/$MARKER" ]; then
      if diff -r -q --exclude="$MARKER" "$src" "$dst" >/dev/null 2>&1; then echo copy-ok; else echo copy-drift; fi
    else
      echo foreign-dir
    fi
    return
  fi
  if [ -e "$dst" ]; then echo foreign; else echo missing; fi
}

stable_state() { # -> ok-link | ok-copy | drift | foreign | missing
  local e links=0 copies=0
  if [ ! -e "$STABLE" ] && [ ! -L "$STABLE" ]; then echo missing; return; fi
  if [ ! -d "$STABLE" ] || [ -L "$STABLE" ]; then echo foreign; return; fi
  if [ ! -f "$STABLE/$MARKER" ]; then
    if [ -z "$(ls -A "$STABLE" 2>/dev/null)" ]; then echo missing; else echo foreign; fi
    return
  fi
  for e in scripts templates VERSION; do
    if [ -L "$STABLE/$e" ]; then
      [ "$(readlink "$STABLE/$e")" = "$REPO/$e" ] && [ -e "$STABLE/$e" ] || { echo drift; return; }
      links=$((links + 1))
    elif [ -e "$STABLE/$e" ]; then
      diff -r -q "$REPO/$e" "$STABLE/$e" >/dev/null 2>&1 || { echo drift; return; }
      copies=$((copies + 1))
    else
      echo drift; return
    fi
  done
  if [ "$links" -eq 3 ]; then echo ok-link
  elif [ "$copies" -eq 3 ]; then echo ok-copy
  else echo drift; fi
}

block_state() { # file -> absent | ok | drift | invalid
  local f="$1" nb ne tmp
  [ -f "$f" ] || { echo absent; return; }
  nb="$(grep -c "^$BEGIN_PREFIX" "$f" || true)"; ne="$(grep -c "^$END_LINE" "$f" || true)"
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then echo absent; return; fi
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then echo invalid; return; fi
  if [ "$(grep -n "^$BEGIN_PREFIX" "$f" | cut -d: -f1)" -gt "$(grep -n "^$END_LINE" "$f" | cut -d: -f1)" ]; then echo invalid; return; fi
  tmp="$(mktmp)"
  sed -n "/^$BEGIN_PREFIX/,/^$END_LINE/p" "$f" > "$tmp"
  if render_block | cmp -s - "$tmp"; then echo ok; else echo drift; fi
}

render_block() {
  printf '%s v%s (managed block: edit the agent-playbook repo and re-run install.sh; do not edit here) -->\n' "$BEGIN_PREFIX" "$VERSION"
  cat "$REPO/AGENTS.global.md"
  printf '%s\n' "$END_LINE"
}

# ---------- mutation helpers ----------
safe_rm_path() { # refuse to rm -rf anything that is not clearly ours
  case "$1" in
    */playbook-*|"$STABLE") ;;
    *) die "internal safety check: refusing to remove $1" 3 ;;
  esac
}

stash_away() { # move a foreign path into the backups dir
  local p="$1" b n=0
  b="$BK/$(basename "$p").$STAMP"
  while [ -e "$b" ]; do n=$((n + 1)); b="$BK/$(basename "$p").$STAMP.$n"; done
  doit mkdir -p "$BK"
  doit mv "$p" "$b"
  say "  backed up $p -> $b"
}

backup_copy() { # copy a file into the backups dir
  local f="$1" b n=0
  b="$BK/$(basename "$f").$STAMP"
  while [ -e "$b" ]; do n=$((n + 1)); b="$BK/$(basename "$f").$STAMP.$n"; done
  doit mkdir -p "$BK"
  doit cp "$f" "$b"
  say "  backed up $f -> $b"
}

remove_owned() { # remove a symlink or a marker-owned copy
  local p="$1"
  if [ -L "$p" ]; then doit rm "$p"
  elif [ -d "$p" ] && [ -f "$p/$MARKER" ]; then safe_rm_path "$p"; doit rm -rf "$p"
  fi
}

make_item() { # src dst (as link or copy)
  if [ "$DRY" -eq 0 ] && { [ -e "$2" ] || [ -L "$2" ]; }; then
    die "internal safety check: $2 still exists; refusing to write into it" 3
  fi
  if [ "$COPY" -eq 1 ]; then
    doit cp -R "$1" "$2"
  else
    doit ln -s "$1" "$2"
    if [ "$DRY" -eq 0 ] && [ ! -L "$2" ]; then
      die "could not create a symlink at $2 (Windows without symlink rights?). Re-run with --copy" 1
    fi
  fi
}

place_skill() { # dir name
  local dir="$1" src="$REPO/skills/$2" dst="$1/$2" st
  st="$(skill_state "$dst" "$src")"
  case "$st:$COPY" in
    ok:0|copy-ok:1) say "  =  $dst (unchanged)"; return 0 ;;
    foreign:*|foreign-dir:*) stash_away "$dst" ;;
    missing:*) ;;
    *) remove_owned "$dst" ;;
  esac
  doit mkdir -p "$dir"
  make_item "$src" "$dst"
  if [ "$COPY" -eq 1 ] && [ "$DRY" -eq 0 ]; then printf 'agent-playbook %s\n' "$VERSION" > "$dst/$MARKER"; fi
  if [ "$COPY" -eq 1 ]; then say "  +  $dst (copy)"; else say "  +  $dst -> $src"; fi
}

place_stable() {
  local st e
  st="$(stable_state)"
  case "$st:$COPY" in
    ok-link:0|ok-copy:1) say "  =  $STABLE (unchanged)"; return 0 ;;
    foreign:*) stash_away "$STABLE" ;;
    missing:*) ;;
    *) safe_rm_path "$STABLE"; doit rm -rf "$STABLE" ;;
  esac
  doit mkdir -p "$STABLE"
  if [ "$DRY" -eq 0 ]; then printf 'agent-playbook %s\n' "$VERSION" > "$STABLE/$MARKER"; fi
  for e in scripts templates VERSION; do make_item "$REPO/$e" "$STABLE/$e"; done
  if [ "$COPY" -eq 1 ]; then say "  +  $STABLE (copy)"; else say "  +  $STABLE/{scripts,templates,VERSION} -> $REPO"; fi
}

apply_block() { # file
  local f="$1" st tmpb tmpn
  st="$(block_state "$f")"
  [ "$st" = "invalid" ] && die "$f has a broken or duplicated agent-playbook block; fix it by hand (keep exactly one BEGIN and one END line)" 1
  tmpb="$(mktmp)"; tmpn="$(mktmp)"
  render_block > "$tmpb"
  if [ ! -f "$f" ]; then
    cp "$tmpb" "$tmpn"
  elif [ "$st" = "absent" ]; then
    { cat "$f"
      if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then printf '\n'; fi
      if [ -s "$f" ]; then printf '\n'; fi
      cat "$tmpb"; } > "$tmpn"
  else
    awk -v bf="$tmpb" -v bp="$BEGIN_PREFIX" -v el="$END_LINE" '
      index($0, bp) == 1 { if (!done) { while ((getline l < bf) > 0) print l; close(bf); done = 1 } skip = 1; next }
      $0 == el { skip = 0; next }
      skip != 1 { print }
    ' "$f" > "$tmpn"
  fi
  if [ -f "$f" ] && cmp -s "$f" "$tmpn"; then say "  =  $f (unchanged)"; return 0; fi
  [ -f "$f" ] && backup_copy "$f"
  doit mkdir -p "$(dirname "$f")"
  doit cp "$tmpn" "$f"
  say "  ~  $f (managed block written)"
}

remove_block() { # file
  local f="$1" st tmpn
  st="$(block_state "$f")"
  case "$st" in
    absent) say "  -  $f (no block)"; return 0 ;;
    invalid) warn "$f has a broken agent-playbook block; leaving it alone"; return 0 ;;
  esac
  tmpn="$(mktmp)"
  awk -v bp="$BEGIN_PREFIX" -v el="$END_LINE" '
    index($0, bp) == 1 { skip = 1; next }
    $0 == el { skip = 0; next }
    skip != 1 { print }
  ' "$f" > "$tmpn"
  backup_copy "$f"
  if [ -z "$(tr -d '[:space:]' < "$tmpn")" ]; then
    doit rm "$f"; say "  -  $f (removed: it only contained the playbook block)"
  else
    doit cp "$tmpn" "$f"; say "  ~  $f (block removed, your text kept)"
  fi
}

confirm() {
  [ "$DRY" -eq 1 ] && return 0
  [ "$YES" -eq 1 ] && return 0
  if [ -t 0 ]; then
    printf 'This will modify files under %s . Continue? [y/N] ' "$H"
    read -r a
    case "$a" in y|Y|yes|YES) return 0 ;; esac
    die "aborted" 1
  fi
  die "non-interactive session: pass --yes to proceed (or --dry-run to preview)" 2
}

# ---------- registry of install targets (home <TAB> harness-list <TAB> link|copy) ----------
registry_harness() { awk -F '\t' -v h="$1" '$1 == h { print $2; exit }' "$REGISTRY" 2>/dev/null; }
registry_write() { # home harness-list mode   (empty harness-list = drop the entry)
  local tmp
  tmp="$(mktmp)"
  { [ -f "$REGISTRY" ] && awk -F '\t' -v h="$1" '$1 != h && $0 != ""' "$REGISTRY"
    [ -n "$2" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3"; } > "$tmp"
  if ! cat "$tmp" > "$REGISTRY" 2>/dev/null; then warn "could not write the install registry $REGISTRY (update will not know about $1)"; fi
}
registry_add() { # home harness-list mode
  [ "$DRY" -eq 1 ] && return 0
  local old h merged=""
  old="$(registry_harness "$1")"
  for h in claude codex opencode; do
    case ",$old,$2," in *",$h,"*) merged="$merged,$h" ;; esac
  done
  registry_write "$1" "${merged#,}" "$3"
}
registry_drop() { # home [harness-list]  (no list = whole entry)
  [ "$DRY" -eq 1 ] && return 0
  local old h left="" mode
  old="$(registry_harness "$1")"
  mode="$(awk -F '\t' -v h="$1" '$1 == h { print $3; exit }' "$REGISTRY" 2>/dev/null)"
  if [ $# -ge 2 ]; then
    for h in claude codex opencode; do
      case ",$old," in *",$h,"*) case ",$2," in *",$h,"*) ;; *) left="$left,$h" ;; esac ;; esac
    done
  fi
  registry_write "$1" "${left#,}" "$mode"
}

# ---------- commands ----------
cmd_install() {
  local d s f conflicts=0 st
  resolve_harness
  say "agent-playbook v$VERSION -> $H  (harness: $HARNESS; mode: $([ "$COPY" -eq 1 ] && echo copy || echo symlink)$([ "$DRY" -eq 1 ] && echo ', dry run'))"
  # preflight: refuse before changing anything
  if [ "$FORCE" -ne 1 ]; then
    st="$(stable_state)"
    if [ "$st" = "foreign" ]; then err "$STABLE exists and is not managed by agent-playbook (use --force to move it to backups)"; conflicts=1; fi
    while IFS= read -r d; do
      for s in $SKILLS; do
        case "$(skill_state "$d/$s" "$REPO/skills/$s")" in
          foreign|foreign-dir) err "$d/$s exists and is not managed by agent-playbook (use --force to move it to backups)"; conflicts=1 ;;
        esac
      done
    done < <(skill_dirs)
  fi
  [ "$conflicts" -eq 0 ] || exit 1
  confirm
  place_stable
  while IFS= read -r d; do
    for s in $SKILLS; do place_skill "$d" "$s"; done
  done < <(skill_dirs)
  while IFS= read -r f; do apply_block "$f"; done < <(rules_files)
  if want opencode && ! rules_files | grep -qxF "$OC_RULES"; then
    say "  note: OpenCode falls back to ~/.claude/CLAUDE.md for global rules (no ~/.config/opencode/AGENTS.md present), so nothing extra was written. Skills are read from ~/.claude/skills or ~/.agents/skills."
  fi
  if want codex && [ -s "$H/.codex/AGENTS.override.md" ]; then
    warn "$H/.codex/AGENTS.override.md is non-empty: Codex reads it INSTEAD of AGENTS.md, so the always-on block will not load until you move the block there or remove the override."
  fi
  if want claude; then install_hooks; fi
  registry_add "$H" "$HARNESS" "$([ "$COPY" -eq 1 ] && echo copy || echo link)"
  say "done. Start a NEW session in your harness (skills are discovered at startup), then say: set up the playbook"
}

cmd_uninstall() {
  local d s f
  resolve_harness
  confirm
  say "uninstalling agent-playbook from $H (harness: $HARNESS)"
  if want claude; then uninstall_hooks; fi
  while IFS= read -r d; do
    for s in $SKILLS; do
      case "$(skill_state "$d/$s" "$REPO/skills/$s")" in
        ok|stale|broken|copy-ok|copy-drift) remove_owned "$d/$s"; say "  -  $d/$s" ;;
        foreign|foreign-dir) warn "$d/$s is not managed by agent-playbook; left alone" ;;
        missing) ;;
      esac
    done
  done < <(skill_dirs)
  for f in "$CLAUDE_RULES" "$CODEX_RULES" "$OC_RULES"; do
    case "$f" in
      "$CLAUDE_RULES") want claude || continue ;;
      "$CODEX_RULES") want codex || continue ;;
      "$OC_RULES") want opencode || continue ;;
    esac
    remove_block "$f"
  done
  if ! anything_installed; then
    if [ -d "$STABLE" ] && [ -f "$STABLE/$MARKER" ]; then safe_rm_path "$STABLE"; doit rm -rf "$STABLE"; say "  -  $STABLE"; fi
  else
    say "  keeping $STABLE (other harnesses still use it)"
  fi
  registry_drop "$H" "$HARNESS"
  say "done. Your settings (~/.agents/playbook.conf) and backups (~/.agents/playbook-backups) were kept."
}

# uninstall_hooks: remove our Claude Code hook handlers from $H/.claude/settings.json before the scripts go away.
# DECISION[D24]: install.ps1 delegates uninstall to this script, so Windows uninstalls reach this too. Without node the
# file is left as it is and a WARN names the manual step (DECISION[D12]).
uninstall_hooks() {
  local s="$H/.claude/settings.json" flags=""
  if [ ! -f "$s" ] || ! grep -qF '# agent-playbook:' "$s"; then return 0; fi
  [ "$DRY" -eq 1 ] && flags="--dry-run"
  # shellcheck disable=SC2086
  bash "$REPO/scripts/claude-hooks.sh" uninstall --home "$H" $flags >/dev/null && { say "  -  agent-playbook hooks in $s"; return 0; }
  warn "hooks: the agent-playbook hooks in $s were not removed (the merge needs node). Remove by hand every handler whose command contains '# agent-playbook:'"
}

# conf_value KEY: last value of KEY in $H/.agents/playbook.conf (the --home dir, never $HOME unless they are the same)
conf_value() {
  local f="$H/.agents/playbook.conf" line v=""
  [ -f "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$1="*) v="${line#"$1="}" ;; esac
  done < "$f"
  printf '%s' "$v"
}

# install_hooks: the Claude Code hooks are installed by default (claude-hooks.sh install --home H). Skipped by --no-hooks (which
# writes hooks_optout=yes), by PB_HOOKS=off (this run only) and by hooks_optout=yes in H's conf; --hooks installs and writes
# hooks_optout=no. A legacy `hooks off` is not a choice: it earns one line when this run added the handlers (D8, N5).
install_hooks() {
  local skip=0 why="" out before="" legacy=""
  if [ "$HOOKS_FLAG" = off ]; then skip=1; why="--no-hooks"
  elif [ "$HOOKS_FLAG" != on ]; then
    if [ "${PB_HOOKS:-}" = off ]; then skip=1; why="PB_HOOKS=off"
    elif [ "$(conf_value hooks_optout)" = yes ]; then skip=1; why="hooks_optout yes"; fi
  fi
  if [ "$DRY" -eq 1 ]; then
    if [ "$skip" -eq 1 ]; then say "  would: skip the Claude Code hooks ($why)"; else say "  would: install the Claude Code hooks (scripts/claude-hooks.sh install)"; fi
    [ "$HOOKS_FLAG" = off ] && say "  would: set hooks_optout yes in $H/.agents/playbook.conf"
    [ "$HOOKS_FLAG" = on ] && say "  would: set hooks_optout no in $H/.agents/playbook.conf"
    return 0
  fi
  if [ "$HOOKS_FLAG" = off ]; then
    PLAYBOOK_HOME="$H" bash "$REPO/scripts/conf.sh" set hooks_optout yes --global >/dev/null || warn "hooks: could not write hooks_optout to $H/.agents/playbook.conf"
  elif [ "$HOOKS_FLAG" = on ]; then
    PLAYBOOK_HOME="$H" bash "$REPO/scripts/conf.sh" set hooks_optout no --global >/dev/null || warn "hooks: could not write hooks_optout to $H/.agents/playbook.conf"
  fi
  if [ "$skip" -eq 1 ]; then say "  hooks: not installed ($why)"; return 0; fi
  before="$(bash "$REPO/scripts/claude-hooks.sh" status --home "$H" 2>/dev/null | sed -n 's/^guard: //p')"
  [ "$(conf_value hooks)" = off ] && legacy=1
  if out="$(bash "$REPO/scripts/claude-hooks.sh" install --home "$H")"; then
    say "  hooks: $out"
    if [ "$before" != installed ] && [ -n "$legacy" ]; then
      say "hooks: turned on (they were off by the old default; turn off: install.sh install --no-hooks)"
    fi
  else
    warn "hooks: not installed (the merge needs node; add the entries printed above by hand, or run scripts/claude-hooks.sh install once node is available)"
  fi
}

# doctor_hooks: one line on the Claude Code hooks (on by default since v0.33), from claude-hooks.sh status (grep only)
doctor_hooks() {
  local out ok="" broken="" miss="" dis=0 n st
  out="$(bash "$REPO/scripts/claude-hooks.sh" status --home "$H" 2>/dev/null)"
  for n in guard guard-ps guard-start guard-stop learnings; do
    st="$(printf '%s\n' "$out" | sed -n "s/^$n: //p")"
    case "$st" in
      installed) ok="$ok${ok:+, }$n" ;;
      broken*) broken="$broken${broken:+, }$n" ;;
      *) miss="$miss${miss:+, }$n" ;;
    esac
  done
  printf '%s\n' "$out" | grep -qF 'disabled (disableAllHooks)' && dis=1
  if [ -n "$broken" ]; then
    problem "hooks: $broken point at a missing script (run scripts/claude-hooks.sh install or uninstall)"
  elif [ -z "$ok" ]; then
    if [ "$(conf_value hooks_optout)" = yes ]; then say "INFO  hooks: off (hooks_optout yes; turn on: install.sh install --hooks)"
    else say "WARN  hooks: not installed (run install.sh install, or install.sh install --no-hooks to keep them off)"; fi
  elif [ "$dis" -eq 1 ]; then
    say "INFO  hooks: installed but disabled (disableAllHooks)"
  elif [ -z "$miss" ]; then
    say "OK    hooks: guard, learnings installed"
  else
    say "INFO  hooks: partly installed ($ok; missing: $miss; run scripts/claude-hooks.sh install)"
  fi
}

anything_installed() {
  local d s f
  for d in "$H/.claude/skills" "$H/.agents/skills"; do
    for s in $SKILLS; do
      case "$(skill_state "$d/$s" "$REPO/skills/$s")" in ok|stale|broken|copy-ok|copy-drift) return 0 ;; esac
    done
  done
  for f in "$CLAUDE_RULES" "$CODEX_RULES" "$OC_RULES"; do
    case "$(block_state "$f")" in ok|drift|invalid) return 0 ;; esac
  done
  return 1
}

harness_status() { # prints state word for the single harness in $HARNESS
  local d s f total=0 okc=0 st
  st="$(stable_state)"
  while IFS= read -r d; do
    for s in $SKILLS; do
      total=$((total + 1))
      case "$(skill_state "$d/$s" "$REPO/skills/$s")" in ok|copy-ok) okc=$((okc + 1)) ;; esac
    done
  done < <(skill_dirs)
  while IFS= read -r f; do
    total=$((total + 1))
    [ "$(block_state "$f")" = "ok" ] && okc=$((okc + 1))
  done < <(rules_files)
  if [ "$total" -eq 0 ]; then
    if claude_covers && [ "$(block_state "$CLAUDE_RULES")" = "ok" ]; then echo "installed (via ~/.claude)"; else echo "not installed"; fi
    return
  fi
  case "$st" in ok-link|ok-copy) ;; *) [ "$okc" -gt 0 ] && okc=$((okc - 1)) ;; esac
  if [ "$okc" -eq 0 ]; then echo "not installed"
  elif [ "$okc" -eq "$total" ]; then echo "installed"
  else echo "partial ($okc/$total ok)"; fi
}

cmd_status() {
  local all h
  resolve_harness
  all="$HARNESS"
  say "agent-playbook v$VERSION  home=$H"
  while IFS= read -r h; do
    HARNESS="$h"
    printf '%s: %s\n' "$h" "$(harness_status)"
  done < <(printf '%s\n' "$all" | tr ',' '\n')
}

cmd_doctor() {
  local d s f st
  resolve_harness
  say "agent-playbook v$VERSION doctor  home=$H  harness=$HARNESS"
  st="$(stable_state)"
  case "$st" in
    ok-link|ok-copy) say "OK    $STABLE ($st)" ;;
    *) problem "$STABLE is $st (run install.sh install)" ;;
  esac
  while IFS= read -r d; do
    for s in $SKILLS; do
      case "$(skill_state "$d/$s" "$REPO/skills/$s")" in
        ok|copy-ok) say "OK    $d/$s" ;;
        copy-drift) problem "$d/$s: copy drift (differs from repo; re-run install --copy)" ;;
        missing) problem "$d/$s: missing" ;;
        broken|stale) problem "$d/$s: broken or stale link" ;;
        *) problem "$d/$s: exists but is not managed by agent-playbook" ;;
      esac
    done
  done < <(skill_dirs)
  while IFS= read -r f; do
    case "$(block_state "$f")" in
      ok) say "OK    $f (block up to date)" ;;
      absent) problem "$f: managed block missing" ;;
      drift) problem "$f: managed block drift (differs from repo; run install.sh install)" ;;
      invalid) problem "$f: broken or duplicated block markers" ;;
    esac
  done < <(rules_files)
  if want opencode && ! rules_files | grep -qxF "$OC_RULES"; then
    if [ "$(block_state "$CLAUDE_RULES")" = "ok" ]; then say "OK    opencode reads rules via ~/.claude/CLAUDE.md fallback"
    else problem "opencode relies on ~/.claude/CLAUDE.md fallback but it has no current block"; fi
  fi
  if want codex && [ -s "$H/.codex/AGENTS.override.md" ]; then
    problem "$H/.codex/AGENTS.override.md is non-empty and shadows AGENTS.md (Codex reads the override instead)"
  fi
  if want claude; then doctor_hooks; fi
  if [ -f "$H/.agents/playbook.conf" ]; then say "OK    $H/.agents/playbook.conf exists"
  else say "INFO  no $H/.agents/playbook.conf yet: the first agent session will run playbook-setup"; fi
  if [ "$PROBLEMS" -eq 0 ]; then say "doctor: healthy"; else say "doctor: $PROBLEMS problem(s)"; exit 1; fi
}

reinstall_targets() {
  local entries line home hs mode flags fails=0
  entries="$(cat "$REGISTRY" 2>/dev/null)"
  if [ -z "$entries" ]; then
    say "no recorded installs in $REGISTRY: run install once with your usual flags (it is recorded from then on)"
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    home="$(printf '%s\n' "$line" | cut -f1)"
    hs="$(printf '%s\n' "$line" | cut -f2)"
    mode="$(printf '%s\n' "$line" | cut -f3)"
    if [ ! -d "$home" ]; then
      say "  skipping $home (no longer exists; removed from the registry)"
      registry_drop "$home"
      continue
    fi
    flags=""
    [ "$mode" = "copy" ] && flags="--copy"
    say "== re-installing $home ($hs, $mode)"
    # shellcheck disable=SC2086
    if bash "$REPO/install.sh" install --home "$home" --harness "$hs" $flags --yes < /dev/null; then
      bash "$REPO/install.sh" doctor --home "$home" --harness "$hs" < /dev/null || fails=$((fails + 1))
    else
      fails=$((fails + 1))
    fi
  done <<EOF
$entries
EOF
  [ "$fails" -eq 0 ] || die "$fails target(s) failed after the update; see the output above" 1
}

# require_signed_tags from the GLOBAL conf only -> yes | no; another value exits 2.
# DECISION[S5]: a project conf comes from whatever repo the user stands in, so it cannot switch the check off.
require_signed_tags() {
  local v
  # shellcheck source=scripts/lib.sh
  . "$REPO/scripts/lib.sh" || die "cannot load $REPO/scripts/lib.sh" 3
  v="$(pb_conf_read "$(pb_conf_global)" require_signed_tags)" || v=no
  case "$v" in
    yes|no) printf '%s' "$v" ;;
    *) die "invalid value require_signed_tags=$v in $(pb_conf_global) (use yes or no)" 2 ;;
  esac
}

# verify_release_tag TAG OID: classify the tag object and act on it before anything changes.
# DECISION[S1]: classify by the tag object (lightweight / signature marker), never by git's localized messages.
verify_release_tag() {
  local t="$1" oid="$2" req state="" why="" asf
  req="$(require_signed_tags)" || exit $?
  if [ "$(git -C "$REPO" cat-file -t "$oid")" != tag ]; then
    state=unsigned
  elif git -C "$REPO" cat-file tag "$oid" | LC_ALL=C grep -q -e '^-----BEGIN SSH SIGNATURE-----'; then
    asf="$(git -C "$REPO" config --type=path --get gpg.ssh.allowedSignersFile 2>/dev/null)"
    # git reads a relative path from the top of the work tree (git-config(1), gpg.ssh.allowedSignersFile), not from the cwd.
    case "$asf" in
      '' | /* | [A-Za-z]:/* | [A-Za-z]:\\*) ;;
      *) asf="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$REPO")/$asf" ;;
    esac
    if [ -z "$asf" ] || [ ! -s "$asf" ]; then
      # DECISION[S2]: no trust anchor configured -> the signature proves nothing; treat like unsigned.
      state=untrusted; why=" (SSH signature; gpg.ssh.allowedSignersFile is not set, or names a missing or empty file)"
    elif git -C "$REPO" verify-tag "$oid" >/dev/null 2>&1; then
      state=verified
    else
      state=bad
    fi
  elif git -C "$REPO" cat-file tag "$oid" | LC_ALL=C grep -q \
         -e '^-----BEGIN PGP SIGNATURE-----' -e '^-----BEGIN PGP MESSAGE-----' -e '^-----BEGIN SIGNED MESSAGE-----'; then
    if git -C "$REPO" verify-tag "$oid" >/dev/null 2>&1; then
      state=verified
    else
      # DECISION[S4]: a failing PGP/x509 signature (no key, no gpg, or bad) is untrusted, not bad.
      state=untrusted; why=" (PGP/x509 signature: key or gpg not available here)"
    fi
  else
    state=unsigned
  fi
  case "$state" in
    verified) say "release tag $t: signature verified"; return 0 ;;
    # DECISION[S3]: --allow-unsigned never overrides a signature that does not verify.
    bad) die "release tag $t: signature does not verify (tampered tag, or signer not in gpg.ssh.allowedSignersFile); nothing was changed" 1 ;;
  esac
  if [ "$req" = yes ] && [ "$ALLOW_UNSIGNED" -eq 0 ]; then
    if [ "$state" = unsigned ]; then why=" is not signed"; else why=": signature cannot be checked$why"; fi
    die "release tag $t$why and require_signed_tags=yes; nothing was changed (pass --allow-unsigned to update anyway)" 1
  fi
  if [ "$state" = unsigned ]; then
    warn "release tag $t is not signed; continuing"
  else
    warn "release tag $t: signature cannot be checked$why; continuing"
  fi
}

# is_release_name TAG: a release tag name is vMAJOR.MINOR.PATCH, digits only. Any other v* tag (v0.34.0-rc1, v0.33.0#hotfix)
# is never sent to the Releases API: a character such as # or ? would change which release the URL asks about.
is_release_name() { printf '%s\n' "$1" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; }

# release_state TAG: is there a GitHub Release for TAG? Sets REL_WHY. Returns 0 released (HTTP 200),
# 1 not released (404, or a name that is not a release tag name: no request is sent), 2 cannot check (any other answer, curl missing
# or failing, origin not on github.com).
# DECISION[D9]: only 200 counts as released; the other answers are "cannot check", never "not released".
release_state() {
  local t="$1" api repo url code url_o rc
  is_release_name "$t" || { REL_WHY="tag $t is not a release tag name"; return 1; }
  api="${PB_RELEASES_API:-https://api.github.com}"
  if [ -n "${PB_RELEASES_API:-}" ] && [ -n "${PB_RELEASES_REPO:-}" ]; then
    repo="$PB_RELEASES_REPO"
  else
    url_o="$(git -C "$REPO" remote get-url origin 2>/dev/null)" || url_o=""
    case "$url_o" in
      https://github.com/*) repo="${url_o#https://github.com/}" ;;
      git@github.com:*) repo="${url_o#git@github.com:}" ;;
      ssh://git@github.com/*) repo="${url_o#ssh://git@github.com/}" ;;
      *) repo="" ;;
    esac
    repo="${repo%.git}"
    case "$repo" in
      */*/*|*/|/*|"" ) repo="" ;;
      */*) ;;
      *) repo="" ;;
    esac
    if [ -z "$repo" ] && [ -z "${PB_RELEASES_API:-}" ]; then
      REL_WHY="origin is not a github.com repository (${url_o:-no origin remote})"; return 2
    fi
    [ -n "$repo" ] || { REL_WHY="cannot read owner/repo from origin (${url_o:-no origin remote})"; return 2; }
  fi
  command -v curl >/dev/null 2>&1 || { REL_WHY="curl is not installed"; return 2; }
  url="$api/repos/$repo/releases/tags/$t"
  code="$(curl -q -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then REL_WHY="curl failed (exit $rc) for $url"; return 2; fi
  case "$code" in
    200) return 0 ;;
    404) return 1 ;;
    *) REL_WHY="the Releases API answered HTTP ${code:-none} for $url"; return 2 ;;
  esac
}

RELEASE_HINT="(pass --allow-unreleased to update anyway)"

cmd_update() {
  local cur latest target oid commit t rs newest_rel="" skipped="" badname="" unrel_msg="" cant=""
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$REPO is not a git checkout; update needs git" 3
  git -C "$REPO" fetch --quiet --tags origin 2>/dev/null || warn "could not fetch from origin (offline?); using the tags already present"
  cur="$(git -C "$REPO" tag --points-at HEAD -l 'v*' --sort=-v:refname | head -n 1)"   # newest tag when several share HEAD
  [ -n "$cur" ] || cur="untagged ($(git -C "$REPO" rev-parse --short HEAD))"
  latest="$(git -C "$REPO" tag -l 'v*' --sort=-v:refname | head -n 1)"
  [ -n "$latest" ] || die "no release tags (v*) found in $REPO" 2
  if [ -n "$TO" ]; then
    git -C "$REPO" rev-parse -q --verify "refs/tags/$TO^{commit}" >/dev/null 2>&1 || die "unknown release: $TO (see: git -C $REPO tag -l)" 2
    if [ "$ALLOW_UNRELEASED" -eq 0 ] && ! is_release_name "$TO"; then
      die "release tag $TO is not a release tag name (vMAJOR.MINOR.PATCH); nothing was changed $RELEASE_HINT" 1
    fi
  fi
  # Newest released tag: walk newest first, stop at the first 200. For --to, only TO is checked.
  if [ -n "$TO" ] || { [ "$ALLOW_UNRELEASED" -eq 1 ] && [ "$CHECK" -eq 0 ]; }; then
    target="${TO:-$latest}"   # --allow-unreleased: the newest v* tag as before; only that tag is checked (for the WARN)
    release_state "$target"; rs=$?
    [ "$rs" -eq 2 ] && cant="$REL_WHY"
  else
    for t in $(git -C "$REPO" tag -l 'v*' --sort=-v:refname); do
      if ! is_release_name "$t"; then badname="$badname $t"; continue; fi
      release_state "$t"; rs=$?
      if [ "$rs" -eq 0 ]; then newest_rel="$t"; break; fi
      if [ "$rs" -eq 2 ]; then cant="$REL_WHY"; break; fi
      skipped="$skipped $t"
    done
    if [ -n "$newest_rel" ]; then target="$newest_rel"; rs=0
    else target="$latest"; [ -n "$cant" ] && rs=2 || rs=1; fi
  fi
  if [ "$CHECK" -eq 1 ]; then
    latest="$target"
    if [ -n "$cant" ]; then say "cannot check GitHub Releases: $cant"; latest="$(git -C "$REPO" tag -l 'v*' --sort=-v:refname | head -n 1)"; skipped=""; badname=""; fi
    for t in $badname; do say "agent-playbook: tag $t is not a release tag name; skipped"; done
    for t in $skipped; do say "agent-playbook: newer tag $t has no GitHub Release; skipped"; done
    if [ -z "$cant" ] && [ -z "$newest_rel" ] && [ -z "$TO" ]; then say "agent-playbook: no tag has a GitHub Release; reporting against $latest"; fi
    # DECISION[D1]: compare commits, not tag names (two tags can share one commit).
    if [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse "refs/tags/$latest^{commit}")" ]; then
      say "agent-playbook $cur: up to date"
    elif git -C "$REPO" merge-base --is-ancestor "refs/tags/$latest^{commit}" HEAD; then
      say "agent-playbook: installed $cur is ahead of $latest by $(git -C "$REPO" rev-list --count "refs/tags/$latest^{commit}..HEAD") commit(s)"
    elif git -C "$REPO" merge-base --is-ancestor HEAD "refs/tags/$latest^{commit}"; then
      say "agent-playbook: installed $cur, latest release $latest -> UPDATE AVAILABLE (run: $REPO/install.sh update)"
    else
      # DECISION[D2]: diverged is information, not an update; updating would drop local commits.
      say "agent-playbook: installed $cur has diverged from $latest (pick a release with: $REPO/install.sh update --to <tag>)"
    fi
    return 0
  fi
  [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] || die "the playbook repo $REPO has uncommitted changes; commit or stash them before updating" 1
  # DECISION[S7]: resolve refs/tags/T once; verify and check out that object, never the bare name
  # (a branch or refs/T of the same name could win). DECISION[S6]: verify before the changelog, confirm and dry run.
  oid="$(git -C "$REPO" rev-parse -q --verify "refs/tags/$target")" || die "unknown release: $target" 2
  commit="$(git -C "$REPO" rev-parse -q --verify "$oid^{commit}")" || die "unknown release: $target" 2
  if [ "$rs" -eq 0 ]; then
    say "release tag $target: GitHub Release found"
    for t in $skipped; do say "INFO  newer tag $t has no GitHub Release; skipped"; done
    for t in $badname; do say "INFO  tag $t is not a release tag name; skipped"; done
  elif [ "$ALLOW_UNRELEASED" -eq 1 ]; then
    if [ "$rs" -eq 1 ]; then warn "release tag $target has no GitHub Release; continuing (--allow-unreleased)"
    else warn "release tag $target: cannot check for a GitHub Release ($cant); continuing (--allow-unreleased)"; fi
  elif [ "$rs" -eq 1 ]; then
    die "release tag $target has no GitHub Release (its CI release gate did not pass, or it was pushed by hand); nothing was changed $RELEASE_HINT" 1
  else
    die "release tag $target: cannot check for a GitHub Release ($cant); nothing was changed $RELEASE_HINT" 1
  fi
  verify_release_tag "$target" "$oid"
  say "agent-playbook: $cur -> $target"
  say "---- CHANGELOG at $target ----"
  git -C "$REPO" show "$commit:CHANGELOG.md" 2>/dev/null | sed -n '1,30p'
  say "------------------------------"
  confirm
  if [ "$DRY" -eq 1 ]; then say "dry run: would check out $target and re-install the recorded targets"; return 0; fi
  git -C "$REPO" -c advice.detachedHead=false checkout -q "$commit" || die "checkout of $target failed" 1
  # From here on the files on disk are the new release: run its installer, not this process.
  reinstall_targets
  say "updated to $target. Start new harness sessions to load the new skills."
}

# Each branch exits immediately: `update` replaces this very file on disk while it runs.
case "$CMD" in
  install) cmd_install; exit $? ;;
  uninstall) cmd_uninstall; exit $? ;;
  status) cmd_status; exit $? ;;
  doctor) cmd_doctor; exit $? ;;
  update) cmd_update; exit $? ;;
esac
