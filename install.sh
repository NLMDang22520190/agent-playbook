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

CMD=""; H="${HOME:-}"; HARNESS=""; COPY=0; DRY=0; FORCE=0; YES=0
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

Options
  --harness LIST   claude,codex,opencode | all   (install: auto-detected from ~/.claude,
                   ~/.codex, ~/.config/opencode when omitted; status/doctor default: all)
  --home DIR       use DIR instead of $HOME (sandboxes, Windows home from WSL, tests)
  --copy           copy instead of symlink (Windows without symlink rights)
  --dry-run        print what would change, change nothing
  --force          move conflicting foreign files/dirs to ~/.agents/playbook-backups
  --yes            do not ask for confirmation (required when stdin is not a terminal)
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
  install|uninstall|status|doctor) shift ;;
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
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" 2 ;;
  esac
  shift
done
[ -n "$H" ] || die "cannot determine home directory; pass --home" 2

# ---------- paths ----------
STABLE="$H/.agents/playbook"
BK="$H/.agents/playbook-backups"
CLAUDE_RULES="$H/.claude/CLAUDE.md"
CODEX_RULES="$H/.codex/AGENTS.md"
OC_RULES="$H/.config/opencode/AGENTS.md"

SKILLS=""
for d in "$REPO"/skills/*/; do
  [ -f "${d}SKILL.md" ] && SKILLS="$SKILLS $(basename "$d")"
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
  local dir="$1" name="$2" src="$REPO/skills/$2" dst="$1/$2" st
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
  say "done. Start a NEW session in your harness (skills are discovered at startup), then say: set up the playbook"
}

cmd_uninstall() {
  local d s f
  resolve_harness
  confirm
  say "uninstalling agent-playbook from $H (harness: $HARNESS)"
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
  say "done. Your settings (~/.agents/playbook.conf) and backups (~/.agents/playbook-backups) were kept."
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
  if [ -f "$H/.agents/playbook.conf" ]; then say "OK    $H/.agents/playbook.conf exists"
  else say "INFO  no $H/.agents/playbook.conf yet: the first agent session will run playbook-setup"; fi
  if [ "$PROBLEMS" -eq 0 ]; then say "doctor: healthy"; else say "doctor: $PROBLEMS problem(s)"; exit 1; fi
}

case "$CMD" in
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  doctor) cmd_doctor ;;
esac
