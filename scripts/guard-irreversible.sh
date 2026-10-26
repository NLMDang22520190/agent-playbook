#!/usr/bin/env bash
# guard-irreversible.sh: agent-playbook guard hook for irreversible actions (Claude Code hooks, opt-in).
# Reads the hook JSON on stdin (https://code.claude.com/docs/en/hooks) and exits 0 or 2, nothing else.
#   (no mode flag)    PreToolUse on Bash, Write and Edit
#   --session-start   SessionStart: records HEAD in <git-common-dir>/pb-guard/<session_id> (the first write wins)
#   --stop            Stop: end-of-turn diff of schema files and migrations against the session baseline
#   --eval            the eval runner's handlers; while PB_EVAL_HOOKS is set, a call without --eval does nothing
# BLOCK = exit 2, reason on stderr (headless). WARN = exit 0, one JSON line (interactive). PENDING = exit 0, JSON (a
# contract migration was written, not run). PASS = exit 0, no output. PB_EVAL_HOOK_LOG gets one line per non-PASS decision.
# DECISION[D1] fail-open: malformed input, another tool or an internal error -> exit 0.
# DECISION[D2] headless = PB_HEADLESS=1; PB_HEADLESS=0 = interactive; otherwise headless when CI is true or 1 (any case).
# DECISION[D3] SQL in a Bash command counts only when it reaches a database client: the client's words, here-strings and
#   here-docs, what earlier commands of its pipeline or of a ( ) / { } group piped into it print, the .sql files they name, and
#   any file a > / >> / tee earlier in the same command wrote (as written, any name). A file no client reads is data (R2).
# DECISION[D-g1..3] a file written earlier in the same command carries the text that flowed into the writer (PLT before it, a
#   group's text after a ( ) > f) plus the writer's own; cp/mv record DEST (the last non-option operand; an existing directory
#   -> DEST/<basename>) with each source's written text or .sql disk content; a client operand naming a written file (a < target,
#   a word piece like ".read f") contributes that text instead of its name, so a keyword in the name is no hit (the .sql disk copy is read).
# DECISION[D5] every force-push variant is irreversible (--force, -f, lease, if-includes, --mirror, +refspec).
# DECISION[D16] Stop baseline = the session file, else merge-base with @{upstream}, else HEAD (work tree only).
# DECISION[D17] headless Stop refuses to finish while the tree holds a schema table/column drop or a contract migration.
# DECISION[D18] git reset --hard, checkout -- / ., restore, clean -f count only when git status shows something to lose.
# DECISION[D19] a rename (equal column lists, or a session migration with RENAME TO) is not a drop.
# DECISION[D23] rm targets expand same-command assignments (export too), then HOME, PWD, TMPDIR, CLAUDE_PROJECT_DIR from the
#   env; the rest is outside. The roots (project, temp dirs) come from the env only (review R4).
# DECISION[R1] a temp dir allows rm below it, except beside a project that sits inside that same temp dir: a target in the
#   project's own first directory under the innermost temp dir holding it is outside (the E41 tree: <workroot>/<label>.cache);
#   a project directly in the temp dir makes the whole temp dir outside, but for a mktemp dir of the same command (N2).
# DECISION[R6] the project's .git and .git/pb-guard (the guard's session baselines) count as outside the project, and so does
#   a glob that can match either of them (N3).
# DECISION[D26] C:\x, C:/x and /c/x are one path, compared without case when a drive letter is involved.
# DECISION[D28] after 3 Stop blocks in one session the 4th Stop gives up (exit 0 and a warning).
# DECISION[D29] home paths come from pb_home (scripts/lib.sh) only, tilde expansion included.
# Bash 3.2 and BWK awk; no jq, node or python. Known bypasses (bash -c, eval, interpreters, ...) are listed in README.
case "$0" in */*) PB_GDIR="${0%/*}" ;; *) PB_GDIR=. ;; esac
# shellcheck source=scripts/lib.sh
. "$PB_GDIR/lib.sh" || exit 0
LC_ALL=C
export LC_ALL
set -f

MODE=pre
EVAL=0
for a in "$@"; do
  case "$a" in
    --eval) EVAL=1 ;;
    --session-start) MODE=start ;;
    --stop) MODE=stop ;;
  esac
done
# D7: the user's own hooks stand aside during eval runs; the runner's handlers pass --eval
if [ -n "${PB_EVAL_HOOKS:-}" ] && [ "$EVAL" = 0 ]; then exit 0; fi

DS=$'\034'   # an expansion starts ($NAME, ${...}, $(...)); its raw text runs to US
US=$'\037'
BQ=$'\035'   # a backtick command substitution (never resolved)
TL=$'\036'   # an unquoted tilde at the start of a word
NL=$'\n'
TAB=$'\t'
CR=$'\r'
G_PFX="agent-playbook guard: "

# ---- hook JSON on stdin -> shell assignments (one awk process: JSON decode + shell tokens of a Bash command) ----
# JSON escapes \" \\ \/ \n \t \r \b \f are decoded; \uXXXX stays as it is (a documented limit). Malformed JSON prints nothing.
# Tokens of tool_input.command: "w<word>" (quotes removed, expansions marked with DS..US, BQ, TL), "r<word>" (a redirection
# target read by < or <<<), "o<word>" (a > or >> target), "h<N>" (here-doc N of this command, its body in H[N]), "s|" (a pipe), "s(" and
# "s)" (a subshell opens or closes) and "s" (another separator: ; & || newline).
JP='
function ws() { while (p <= n && (C[p] == " " || C[p] == "\t" || C[p] == "\n" || C[p] == "\r")) p++ }
function pstr(   o, st, c, e) {
  p++; o = ""; st = p
  while (p <= n) {
    c = C[p]
    if (c == "\"") { o = o substr(S, st, p - st); p++; return o }
    if (c == "\\") {
      o = o substr(S, st, p - st); e = C[p + 1]
      if (e == "n") o = o "\n"
      else if (e == "t") o = o "\t"
      else if (e == "r") o = o "\r"
      else if (e == "\"" || e == "\\" || e == "/") o = o e
      else if (e == "b") o = o "\b"
      else if (e == "f") o = o "\f"
      else if (e == "u") o = o "\\u"
      else { bad = 1; return "" }
      p += 2; st = p; continue
    }
    p++
  }
  bad = 1; return ""
}
function pval(d, k1,   c, k, v) {
  ws()
  if (p > n) { bad = 1; return "" }
  c = C[p]
  if (c == "{") {
    p++; ws()
    if (C[p] == "}") { p++; VT = "o"; return "" }
    while (!bad) {
      ws()
      if (C[p] != "\"") { bad = 1; return "" }
      k = pstr()
      if (bad) return ""
      ws()
      if (C[p] != ":") { bad = 1; return "" }
      p++
      v = pval(d + 1, (d == 0) ? k : k1)
      if (bad) return ""
      if (VT != "o") { if (d == 0) TOP[k] = v; else if (d == 1 && k1 == "tool_input") TI[k] = v }
      ws()
      if (C[p] == ",") { p++; continue }
      if (C[p] == "}") { p++; VT = "o"; return "" }
      bad = 1; return ""
    }
    return ""
  }
  if (c == "[") {
    p++; ws()
    if (C[p] == "]") { p++; VT = "o"; return "" }
    while (!bad) {
      pval(d + 1, "")
      if (bad) return ""
      ws()
      if (C[p] == ",") { p++; continue }
      if (C[p] == "]") { p++; VT = "o"; return "" }
      bad = 1; return ""
    }
    return ""
  }
  if (c == "\"") { v = pstr(); VT = "s"; return v }
  v = ""
  while (p <= n && C[p] != "" && index("abcdefghijklmnopqrstuvwxyz0123456789+-.E", C[p]) > 0) { v = v C[p]; p++ }
  if (v == "") { bad = 1; return "" }
  VT = "l"; return v
}
function q(v,   m, i, o, a) {
  m = split(v, a, "\047"); o = a[1]
  for (i = 2; i <= m; i++) o = o "\047\\\047\047" a[i]
  return "\047" o "\047"
}
function emit(t) { TOK = TOK " " q(t) }
function endw() {
  if (inw) {
    if (pend == "h") { nhd++; HD[nhd] = w; HDT[nhd] = hdtab; hdg++; HDI[nhd] = hdg; HB[hdg] = ""; emit("h" hdg) }
    else if (pend == "r") emit("r" w)
    else if (pend == "o") emit("o" w)
    else emit("w" w)
    pend = ""
  }
  w = ""; inw = 0
}
function sepw() { endw(); emit("s") }
function mclose(j, op, cl,   dep, c) {
  dep = 0
  while (j <= m) {
    c = T[j]
    if (c == "\\") { j += 2; continue }
    if (c == "\047") { j++; while (j <= m && T[j] != "\047") j++; j++; continue }
    if (c == "\"") { j++; while (j <= m && T[j] != "\"") { if (T[j] == "\\") j++; j++ } j++; continue }
    if (c == op) dep++
    else if (c == cl) { dep--; if (dep == 0) return j }
    j++
  }
  return m + 1
}
function dollar(i,   c, j, k) {
  c = T[i + 1]; inw = 1
  if (c == "{") { j = mclose(i + 1, "{", "}"); w = w DS substr(str, i + 1, j - i) US; return j + 1 }
  if (c == "(") { j = mclose(i + 1, "(", ")"); w = w DS substr(str, i + 1, j - i) US; return j + 1 }
  if (c != "" && c ~ /[A-Za-z_]/) {
    k = i + 1
    while (k <= m && T[k] ~ /[A-Za-z0-9_]/) k++
    w = w DS substr(str, i + 1, k - i - 1) US; return k
  }
  if (c != "" && index("?#@*!$-0123456789", c) > 0) { w = w DS c US; return i + 2 }
  w = w "$"; return i + 1
}
function bquote(i,   j) {
  j = i + 1
  while (j <= m && T[j] != "`") { if (T[j] == "\\") j++; j++ }
  w = w BQ substr(str, i + 1, j - i - 1) US; inw = 1; return j + 1
}
function dquote(i,   c, e) {
  inw = 1
  while (i <= m) {
    c = T[i]
    if (c == "\"") return i + 1
    if (c == "\\") {
      e = T[i + 1]
      if (e == "$" || e == "`" || e == "\"" || e == "\\") { w = w e; i += 2; continue }
      if (e == "\n") { i += 2; continue }
      w = w c; i++; continue
    }
    if (c == "$") { i = dollar(i); continue }
    if (c == "`") { i = bquote(i); continue }
    w = w c; i++
  }
  return i
}
function heredocs(i,   h, k, ln) {
  for (h = 1; h <= nhd; h++) {
    while (i <= m) {
      k = i
      while (k <= m && T[k] != "\n") k++
      ln = substr(str, i, k - i); i = k + 1
      if (HDT[h]) sub(/^\t+/, "", ln)
      sub(/\r$/, "", ln)
      if (ln == HD[h]) break
      HB[HDI[h]] = HB[HDI[h]] ln "\n"
    }
  }
  nhd = 0
  return i
}
function tokenize(s,   i, c, k) {
  str = s; m = split(s, T, ""); i = 1; w = ""; inw = 0; pend = ""; nhd = 0; TOK = ""
  while (i <= m) {
    c = T[i]
    if (c == " " || c == "\t" || c == "\r") { endw(); i++; continue }
    if (c == "\n") { sepw(); i++; if (nhd) i = heredocs(i); continue }
    if (c == "|" && T[i + 1] != "|") { endw(); emit("s|"); i++; if (T[i] == "&") i++; continue }
    if (c == "|") { sepw(); i += 2; continue }
    if (c == "(" || c == ")") { endw(); emit("s" c); i++; continue }
    if (c == ";" || c == "&") { sepw(); i++; continue }
    if (c == "<" || c == ">") {
      if (inw && pend == "" && w ~ /^[0-9]+$/) { w = ""; inw = 0 } else endw()
      if (c == "<" && T[i + 1] == "<" && T[i + 2] == "<") { pend = "r"; i += 3; continue }
      if (c == "<" && T[i + 1] == "<") { i += 2; hdtab = 0; if (T[i] == "-") { hdtab = 1; i++ } pend = "h"; continue }
      i++
      if (T[i] == ">" || T[i] == "&" || T[i] == "|") i++
      pend = (c == ">") ? "o" : "r"; continue
    }
    if (c == "#" && !inw) { while (i <= m && T[i] != "\n") i++; continue }
    if (c == "\\") { if (T[i + 1] == "\n") { i += 2; continue } w = w T[i + 1]; inw = 1; i += 2; continue }
    if (c == "\047") { k = i + 1; while (k <= m && T[k] != "\047") k++; w = w substr(s, i + 1, k - i - 1); inw = 1; i = k + 1; continue }
    if (c == "\"") { i = dquote(i + 1); continue }
    if (c == "$") { i = dollar(i); continue }
    if (c == "`") { i = bquote(i); continue }
    if (c == "~" && !inw) { w = TL; inw = 1; i++; continue }
    w = w c; inw = 1; i++
  }
  sepw()
}
BEGIN { DS = "\034"; US = "\037"; BQ = "\035"; TL = "\036" }
{ S = S $0 "\n" }
END {
  n = split(S, C, ""); p = 1
  ws()
  if (p > n || C[p] != "{") exit 0
  pval(0, "")
  if (bad) exit 0
  ws()
  if (p <= n) exit 0
  print "J_tool=" q(TOP["tool_name"])
  print "J_sid=" q(TOP["session_id"])
  print "J_cwd=" q(TOP["cwd"])
  print "J_active=" q(TOP["stop_hook_active"])
  print "J_cmd=" q(TI["command"])
  print "J_file=" q(TI["file_path"])
  print "J_content=" q(TI["content"])
  print "J_new=" q(TI["new_string"])
  if (TOP["tool_name"] == "Bash") {
    tokenize(TI["command"]); print "W=(" TOK ")"
    TOK = ""; for (i = 1; i <= hdg; i++) TOK = TOK " [" i "]=" q(HB[i])
    print "H=(" TOK ")"
  }
  print "J_ok=1"
}'

J_ok=0; J_tool=""; J_sid=""; J_cwd=""; J_active=""; J_cmd=""; J_file=""; J_content=""; J_new=""
W=()
H=()
PARSED="$(awk "$JP" 2>/dev/null)" || exit 0
eval "$PARSED" 2>/dev/null
[ "$J_ok" = 1 ] || exit 0

# a session id names a state file: only [A-Za-z0-9._-], not starting with a dot
SIDV="$J_sid"
case "$SIDV" in '' | .* | *[!A-Za-z0-9._-]*) SIDV="" ;; esac

# ---- decisions ----
headless() {
  case "${PB_HEADLESS:-}" in 1) return 0 ;; 0) return 1 ;; esac
  case "${CI:-}" in [Tt][Rr][Uu][Ee] | 1) return 0 ;; esac
  return 1
}
hlog() { if [ -n "${PB_EVAL_HOOK_LOG:-}" ]; then printf 'guard %s\n' "$1" >> "$PB_EVAL_HOOK_LOG" 2>/dev/null; fi; return 0; }
# jesc TEXT -> JE: TEXT as the body of a JSON string
jesc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$NL/\\n}"
  s="${s//$TAB/\\t}"
  s="${s//$CR/\\r}"
  s="${s//[[:cntrl:]]/}"
  JE="$s"
}
# warn_json TEXT -> the PreToolUse WARN / PENDING line (systemMessage for the user, additionalContext for the agent)
warn_json() {
  jesc "$G_PFX$1"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$JE" "$JE"
}
# decide KIND TEXT [HINT] -> BLOCK headless, WARN interactive (both end the script)
decide() {
  local kind="$1" what="${2:0:200}" hint="${3:-}"
  if headless; then
    hlog "block $kind"
    printf '%s\n' "${G_PFX}BLOCKED ($kind), an irreversible action: $what" \
      "This is a headless run and nobody can confirm it, so the action is left pending. Do not try another way to do it (another command, a script or an interpreter). Name it in your final reply as a pending action for the user.$hint" >&2
    exit 2
  fi
  hlog "warn $kind"
  warn_json "$kind, an irreversible action: $what. Ask the user to confirm before running it.$hint"
  exit 0
}

# ---- text checks ----
RE_DROP3='[Dd][Rr][Oo][Pp][[:space:]]+([Tt][Aa][Bb][Ll][Ee]|[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]|[Ss][Cc][Hh][Ee][Mm][Aa])([^A-Za-z0-9_]|$)'
RE_DROP4='[Dd][Rr][Oo][Pp][[:space:]]+([Tt][Aa][Bb][Ll][Ee]|[Cc][Oo][Ll][Uu][Mm][Nn]|[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]|[Ss][Cc][Hh][Ee][Mm][Aa])([^A-Za-z0-9_]|$)'
RE_TRUNC='(^|[^A-Za-z0-9_])[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]([^A-Za-z0-9_]|$)'
RE_ALTDROP='[Aa][Ll][Tt][Ee][Rr][[:space:]]+[Tt][Aa][Bb][Ll][Ee][^;]*[[:space:]][Dd][Rr][Oo][Pp]([^A-Za-z0-9_]|$)'
RE_DELETE='[Dd][Ee][Ll][Ee][Tt][Ee][[:space:]]+[Ff][Rr][Oo][Mm][[:space:]]+[^[:space:];]'
RE_WHERE='(^|[^A-Za-z0-9_])[Ww][Hh][Ee][Rr][Ee]([^A-Za-z0-9_]|$)'
RE_SQLF="([^[:space:]\"'=<>|;&()]+[.][Ss][Qq][Ll])([^A-Za-z0-9_]|$)"

# has_contract TEXT -> 0 when TEXT holds DROP TABLE|COLUMN|DATABASE|SCHEMA, TRUNCATE or ALTER TABLE ... DROP
has_contract() {
  [[ $1 =~ $RE_DROP4 ]] && return 0
  [[ $1 =~ $RE_TRUNC ]] && return 0
  [[ $1 =~ $RE_ALTDROP ]] && return 0
  return 1
}
# sql_destructive TEXT -> 0 when TEXT holds DROP TABLE|DATABASE|SCHEMA, TRUNCATE, or DELETE FROM <t> with no WHERE before the next ;
sql_destructive() {
  local rest="$1" st after
  [[ $rest =~ $RE_DROP3 ]] && return 0
  [[ $rest =~ $RE_TRUNC ]] && return 0
  case "$rest" in *[Dd][Ee][Ll][Ee][Tt][Ee]*) ;; *) return 1 ;; esac
  while [ -n "$rest" ]; do
    st="${rest%%;*}"
    if [[ $st =~ $RE_DELETE ]]; then
      after="${st#*"${BASH_REMATCH[0]}"}"
      [[ $after =~ $RE_WHERE ]] || return 0
    fi
    case "$rest" in *\;*) rest="${rest#*;}" ;; *) rest="" ;; esac
  done
  return 1
}

# ---- paths ----
# lower TEXT -> LW (ASCII lower case, no process)
lower() {
  local s="$1" u
  for u in Aa Bb Cc Dd Ee Ff Gg Hh Ii Jj Kk Ll Mm Nn Oo Pp Qq Rr Ss Tt Uu Vv Ww Xx Yy Zz; do s="${s//${u%?}/${u#?}}"; done
  LW="$s"
}
# norm_path PATH BASE -> NP: absolute and lexical (. and .. folded); C:\x, C:/x and /c/x all become /c/x. Sets NP_DRV=1 on a drive.
norm_path() {
  local p="$1" d seg
  local -a st
  p="${p//\\//}"
  case "$p" in
    [A-Za-z]:/* | [A-Za-z]:) d="${p%%:*}"; lower "$d"; p="/$LW${p#??}"; NP_DRV=1 ;;
    /*) ;;
    *) p="$2/$p" ;;
  esac
  st=()
  local IFS=/
  # shellcheck disable=SC2086
  set -- $p
  for seg in "$@"; do
    case "$seg" in
      '' | .) ;;
      ..) [ "${#st[@]}" -gt 0 ] && unset "st[$((${#st[@]} - 1))]" ;;
      *) st[${#st[@]}]="$seg" ;;
    esac
  done
  NP="/${st[*]}"
}
# below PATH DIR -> 0 when PATH is strictly below DIR (both from norm_path); without case when CIC=1
below() {
  local a="$1" b="$2"
  if [ "$CIC" = 1 ]; then lower "$a"; a="$LW"; lower "$b"; b="$LW"; fi
  [ "$a" != "$b" ] || return 1
  [ "$b" = / ] && return 0
  case "$a" in "$b"/*) return 0 ;; esac
  return 1
}
# var_value NAME -> VV; 1 when NAME cannot be resolved
var_value() {
  local n f
  case "$1" in '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;; esac
  f="GS_$1"; n="GV_$1"
  case "${!f:-}" in 1) VV="${!n:-}"; return 0 ;; 0) return 1 ;; esac
  case "$1" in
    HOME) VV="$(pb_home)"; return 0 ;;
    PWD) [ "$CWD_OK" = 1 ] || return 1; VV="$CWD"; return 0 ;;
    TMPDIR) [ -n "${TMPDIR:-}" ] || return 1; VV="$TMPDIR"; return 0 ;;
    CLAUDE_PROJECT_DIR) [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 1; VV="$CLAUDE_PROJECT_DIR"; return 0 ;;
  esac
  return 1
}
# assign NAME=VALUE -> records a same-command assignment for var_value; 1 when NAME is not a variable name
assign() {
  local name="${1%%=*}"
  case "$name" in '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;; esac
  if expand "${1#*=}"; then printf -v "GV_$name" '%s' "$EXP"; printf -v "GS_$name" '%s' 1
  else printf -v "GS_$name" '%s' 0; fi
  return 0
}
# expand WORD -> EXP (expansions resolved); 1 when something in WORD cannot be resolved
expand() {
  local s="$1" out="" raw name def hasdef
  case "$s" in *"$BQ"*) return 1 ;; esac
  case "$s" in
    "$TL") out="$(pb_home)"; s="" ;;
    "$TL"/*) out="$(pb_home)"; s="${s#"$TL"}" ;;
    "$TL"*) return 1 ;;
  esac
  while :; do
    case "$s" in *"$DS"*) ;; *) break ;; esac
    out="$out${s%%"$DS"*}"; s="${s#*"$DS"}"
    raw="${s%%"$US"*}"; s="${s#*"$US"}"
    case "$raw" in
      '(mktemp'*) [ -n "$TMPS" ] || temp_dirs; out="$out$TMPN/pbguard-mktemp"; continue ;;
      '('*) return 1 ;;
      '{'*'}') raw="${raw#?}"; raw="${raw%?}" ;;
    esac
    name="$raw"; def=""; hasdef=0
    case "$raw" in
      *:-*) name="${raw%%:-*}"; def="${raw#*:-}"; hasdef=1 ;;
      *-*) name="${raw%%-*}"; def="${raw#*-}"; hasdef=1 ;;
    esac
    if var_value "$name" && [ -n "$VV" ]; then out="$out$VV"; continue; fi
    [ "$hasdef" = 1 ] || return 1
    case "$def" in *'$'* | *'`'*) return 1 ;; esac
    out="$out$def"
  done
  EXP="$out$s"
  return 0
}
# temp_dirs -> TMPS: the temp dirs below which rm is allowed (TMPDIR, /tmp, and TEMP/TMP through cygpath on Git Bash)
temp_dirs() {
  local v c
  TMPS=""
  if [ -n "${TMPDIR:-}" ]; then
    c="$TMPDIR"
    if command -v cygpath >/dev/null 2>&1; then c="$(cygpath -u "$TMPDIR" 2>/dev/null)" || c="$TMPDIR"; fi
    norm_path "$c" /; TMPS="$NP"
  fi
  norm_path /tmp /; TMPS="$TMPS$NL$NP"
  TMPN="${TMPS%%"$NL"*}"
  [ -n "$TMPN" ] || TMPN=/tmp
  if command -v cygpath >/dev/null 2>&1; then
    for v in "${TEMP:-}" "${TMP:-}"; do
      [ -n "$v" ] || continue
      c="$(cygpath -u "$v" 2>/dev/null)" || continue
      norm_path "$c" /; TMPS="$TMPS$NL$NP"
    done
  fi
}
# state_path PATH -> 0 when PATH is the project's .git or is at or below .git/pb-guard (R6)
state_path() {
  local a="$1" g="${ROOTN%/}/.git"
  if [ "$CIC" = 1 ]; then lower "$a"; a="$LW"; lower "$g"; g="$LW"; fi
  [ "$a" = "$g" ] && return 0
  case "$a/" in "$g/pb-guard/"*) return 0 ;; esac
  return 1
}
# glob_state PATTERN -> 0 when the glob PATTERN (from norm_path) can match the project's .git or a path at or below .git/pb-guard (N3)
glob_state() {
  local a="${1#/}" g="${ROOTN%/}/.git/pb-guard" ps gs
  g="${g#/}"
  if [ "$CIC" = 1 ]; then lower "$a"; a="$LW"; lower "$g"; g="$LW"; fi
  while [ -n "$g" ]; do
    [ -n "$a" ] || { [ "$g" = pb-guard ]; return; }
    ps="${a%%/*}"; gs="${g%%/*}"
    # shellcheck disable=SC2254
    case "$gs" in $ps) ;; *) return 1 ;; esac
    case "$a" in */*) a="${a#*/}" ;; *) a="" ;; esac
    case "$g" in */*) g="${g#*/}" ;; *) g="" ;; esac
  done
  return 0
}
# target_ok WORD -> 0 when the rm target resolves strictly below the project root or a temp dir (R1); else sets RM_T, UNRES
# and RM_STATE
target_ok() {
  local p t best="" r p1 g=""
  if ! expand "$1"; then UNRES=1; RM_T="$1"; return 1; fi
  p="$EXP"
  case "$p" in *[\*\?\[]*) g="$p"; p="${p%%[\*\?\[]*}" ;; esac
  case "$p" in
    /* | [A-Za-z]:* | *\\*) ;;
    *) if [ "$CWD_OK" != 1 ]; then UNRES=1; RM_T="$1"; return 1; fi ;;
  esac
  case "$p" in [A-Za-z]:*) CIC=1 ;; esac
  [ -n "$TMPS" ] || temp_dirs
  norm_path "$p" "$CWD"
  p="$NP"
  RM_T="$p"
  if state_path "$p"; then RM_STATE=1; return 1; fi
  if [ -n "$g" ]; then norm_path "$g" "$CWD"; if glob_state "$NP"; then RM_T="$NP"; RM_STATE=1; return 1; fi; fi
  below "$p" "$ROOTN" && return 0
  # a mktemp dir of this command (expand names it TMPN/pbguard-mktemp) is the command's own (AC-A9)
  case "$p/" in "${TMPN%/}/pbguard-mktemp/"*) return 0 ;; esac
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if below "$p" "$t" && [ "${#t}" -gt "${#best}" ]; then best="$t"; fi
  done <<EOF
$TMPS
EOF
  [ -n "$best" ] || return 1
  below "$ROOTN" "$best" || return 0
  # the project sits inside this temp dir: its own first directory there is not a temp dir of its own
  r="$ROOTN"
  if [ "$CIC" = 1 ]; then lower "$r"; r="$LW"; lower "$p"; p="$LW"; lower "$best"; best="$LW"; fi
  r="${r#"${best%/}"/}"; p1="${p#"${best%/}"/}"
  # the project sits directly in this temp dir: its siblings are outside too (N2)
  case "$r" in */*) ;; *) return 1 ;; esac
  [ "${r%%/*}" != "${p1%%/*}" ]
}

# ---- git helpers ----
# repo_info DIR -> TOP (work tree top) and GC (absolute git common dir); 1 outside a work tree
repo_info() {
  local out
  out="$(git -C "$1" rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || return 1
  TOP="${out%%"$NL"*}"; GC="${out#*"$NL"}"
  [ -n "$TOP" ] && [ -n "$GC" ] && [ "$TOP" != "$out" ] || return 1
  case "$GC" in /* | [A-Za-z]:*) ;; *) GC="$1/$GC" ;; esac
  return 0
}
# base_of -> BASE: the session file (D16), else merge-base HEAD @{upstream}, else HEAD, else none
base_of() {
  BASE=""
  if [ -n "$SIDV" ] && [ -f "$GC/pb-guard/$SIDV" ]; then
    IFS= read -r BASE < "$GC/pb-guard/$SIDV"
    BASE="${BASE%"$CR"}"
    case "$BASE" in none) return 0 ;; '' | *[!0-9a-f]*) BASE="" ;; *) return 0 ;; esac
  fi
  BASE="$(git -C "$TOP" merge-base HEAD '@{upstream}' 2>/dev/null)" && [ -n "$BASE" ] && return 0
  BASE="$(git -C "$TOP" rev-parse -q --verify HEAD 2>/dev/null)" && [ -n "$BASE" ] && return 0
  BASE=none
}
# diff_base -> DB: BASE, or the empty tree when there is no baseline commit
diff_base() {
  if [ "$BASE" = none ]; then DB="$(git -C "$TOP" hash-object -t tree /dev/null 2>/dev/null)"; else DB="$BASE"; fi
}
hook_dir() { if [ -n "$J_cwd" ] && [ -d "$J_cwd" ]; then HDIR="$J_cwd"; else HDIR="$PWD"; fi; }
is_mig() {
  case "$1" in .agents/*) return 1 ;; *[Mm][Ii][Gg][Rr][Aa][Tt]*) return 0 ;; esac
  return 1
}
is_schema() {
  case "$1" in *.[Ss][Qq][Ll]) ;; *) return 1 ;; esac
  case "$1" in .agents/* | *[Mm][Ii][Gg][Rr][Aa][Tt]*) return 1 ;; esac
  case "/$1" in */test/* | */tests/* | */spec/* | */fixture/* | */fixtures/*) return 1 ;; esac
  return 0
}
# mig_pending DIR -> 0 when a migration file new or changed since the baseline holds a contract statement (MIG_FILE)
mig_pending() {
  local list f c
  repo_info "$1" || return 1
  base_of
  diff_base
  list="$(git -C "$TOP" -c core.quotepath=off diff --name-only --no-renames "$DB" -- 2>/dev/null)"
  list="$list$NL$(git -C "$TOP" -c core.quotepath=off ls-files -o --exclude-standard 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] && is_mig "$f" && [ -f "$TOP/$f" ] || continue
    c="$(cat "$TOP/$f" 2>/dev/null)"
    if has_contract "$c"; then MIG_FILE="$f"; return 0; fi
  done <<EOF
$list
EOF
  return 1
}

# ---- PreToolUse: Bash ----
SEGW=()   # the words of the current command (type prefix kept)
# seg_git START: git push --force family (D5) and the discard family (D18)
seg_git() {
  local i="$1" n="${#SEGW[@]}" w gdir="$CWD" gok="$CWD_OK" sub a mode="" staged=0 wt=0 force=0 dry=0 cx=0 cX=0 dd=0 out l ign=""
  while [ "$i" -lt "$n" ]; do
    w="${SEGW[$i]#?}"
    case "$w" in
      -C)
        i=$((i + 1)); a="${SEGW[$i]#?}"
        if expand "$a"; then norm_path "$EXP" "$gdir"; gdir="$NP"; else gok=0; fi ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path | --config-env) i=$((i + 1)) ;;
      -*) ;;
      *) break ;;
    esac
    i=$((i + 1))
  done
  sub="${SEGW[$i]#?}"
  i=$((i + 1))
  case "$sub" in
    push)
      while [ "$i" -lt "$n" ]; do
        a="${SEGW[$i]}"; i=$((i + 1))
        case "$a" in r* | o*) continue ;; esac
        a="${a#?}"
        case "$a" in
          --force | --force-with-lease | --force-with-lease=* | --force-if-includes | --mirror) HIT=git-push-force; return 0 ;;
          --*) ;;
          -*f*) HIT=git-push-force; return 0 ;;
          +?*) HIT=git-push-force; return 0 ;;
        esac
      done
      return 1 ;;
    reset)
      while [ "$i" -lt "$n" ]; do
        a="${SEGW[$i]#?}"; i=$((i + 1))
        [ "$a" = --hard ] && mode=tracked
      done ;;
    checkout)
      while [ "$i" -lt "$n" ]; do
        a="${SEGW[$i]#?}"; i=$((i + 1))
        case "$a" in
          --) dd=1 ;;
          .) mode=tracked ;;
          -*) ;;
          *) [ "$dd" = 1 ] && mode=tracked ;;
        esac
      done ;;
    restore)
      while [ "$i" -lt "$n" ]; do
        a="${SEGW[$i]#?}"; i=$((i + 1))
        case "$a" in --staged | -S) staged=1 ;; --worktree | -W) wt=1 ;; esac
      done
      if [ "$staged" = 0 ] || [ "$wt" = 1 ]; then mode=tracked; fi ;;
    clean)
      while [ "$i" -lt "$n" ]; do
        a="${SEGW[$i]#?}"; i=$((i + 1))
        case "$a" in
          --force) force=1 ;;
          --dry-run) dry=1 ;;
          --*) ;;
          -*)
            case "$a" in *f*) force=1 ;; esac
            case "$a" in *n*) dry=1 ;; esac
            case "$a" in *x*) cx=1 ;; esac
            case "$a" in *X*) cX=1 ;; esac ;;
        esac
      done
      if [ "$force" = 1 ] && [ "$dry" = 0 ]; then mode=clean; fi ;;
  esac
  [ -n "$mode" ] && [ "$gok" = 1 ] || return 1
  if [ "$mode" = clean ] && { [ "$cx" = 1 ] || [ "$cX" = 1 ]; }; then ign=--ignored; fi
  # shellcheck disable=SC2086
  out="$(GIT_OPTIONAL_LOCKS=0 git -C "$gdir" status --porcelain $ign 2>/dev/null)" || return 1
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$mode" in
      tracked) case "$l" in '??'* | '!!'*) ;; *) HIT=git-discard ;; esac ;;
      clean)
        case "$l" in
          '??'*) [ "$cX" = 1 ] || HIT=git-discard ;;
          '!!'*) [ "$cx" = 1 ] || [ "$cX" = 1 ] && HIT=git-discard ;;
        esac ;;
    esac
    [ -n "$HIT" ] && { HINT=" Something would be lost for good (git status shows it): keep it first with git stash -u, or leave it to the user."; return 0; }
  done <<EOF
$out
EOF
  return 1
}
# seg_rm START: rm -r with a target outside the project root and the temp dirs (D8, D23)
seg_rm() {
  local i="$1" n="${#SEGW[@]}" a rec=0 dd=0 t
  local -a tg
  tg=()
  while [ "$i" -lt "$n" ]; do
    a="${SEGW[$i]}"; i=$((i + 1))
    case "$a" in r* | o*) continue ;; esac
    a="${a#?}"
    if [ "$dd" = 0 ]; then
      case "$a" in
        --) dd=1; continue ;;
        --recursive) rec=1; continue ;;
        --*) continue ;;
        -?*) case "$a" in *[rR]*) rec=1 ;; esac; continue ;;
      esac
    fi
    tg[${#tg[@]}]="$a"
  done
  [ "$rec" = 1 ] && [ "${#tg[@]}" -gt 0 ] || return 1
  for t in "${tg[@]}"; do
    UNRES=0; RM_STATE=0
    if ! target_ok "$t"; then
      HIT=rm-outside
      if [ "$RM_STATE" = 1 ]; then
        HINT=" The target $RM_T holds the guard's session baselines (.git/pb-guard): leave it in place."
      elif [ "$UNRES" = 1 ]; then
        HINT=" A target could not be resolved to a path (an unknown variable, a command substitution or ~user): use a literal path inside the project or a temp dir."
      else
        HINT=" The target $RM_T is outside the project root ($ROOTN) and the temp dirs."
      fi
      return 0
    fi
  done
  return 1
}
# seg_cd START: follow cd for later relative paths
seg_cd() {
  local i="$1" n="${#SEGW[@]}" a
  while [ "$i" -lt "$n" ]; do
    a="${SEGW[$i]#?}"
    case "$a" in -P | -L | -e | -@ | --) i=$((i + 1)) ;; *) break ;; esac
  done
  if [ "$i" -ge "$n" ]; then CWD_OK=0; return; fi
  a="${SEGW[$i]#?}"
  if [ "$a" = - ] || ! expand "$a"; then CWD_OK=0; return; fi
  case "$EXP" in
    /* | [A-Za-z]:* | *\\*) ;;
    *) [ "$CWD_OK" = 1 ] || return ;;
  esac
  case "$EXP" in [A-Za-z]:*) CIC=1 ;; esac
  norm_path "$EXP" "$CWD"; CWD="$NP"; CWD_OK=1
}
# seg_run CMD ARGS...: migration runners (pending contract migration) and the always-destructive database commands
seg_run() {
  local c="$1" a1="${2:-}" a2="${3:-}" a3="${4:-}" a run=0
  shift
  case "$c" in
    npm | pnpm | yarn | bun)
      case "$a1" in run | run-script) case "$a2" in *[Mm][Ii][Gg][Rr][Aa][Tt]*) run=1 ;; esac ;; esac ;;
    knex) case "$a1" in migrate*) run=1 ;; esac ;;
    prisma)
      if [ "$a1" = migrate ]; then
        case "$a2" in reset) HIT=migration-run; return 0 ;; deploy | dev) run=1 ;; esac
      elif [ "$a1" = db ] && [ "$a2" = push ]; then
        for a in "$@"; do [ "$a" = --accept-data-loss ] && { HIT=migration-run; return 0; }; done
      fi ;;
    rails | rake)
      for a in "$@"; do
        case "$a" in db:drop* | db:reset*) HIT=migration-run; return 0 ;; db:migrate*) run=1 ;; esac
      done ;;
    alembic) for a in "$@"; do [ "$a" = upgrade ] && run=1; done ;;
    flyway) for a in "$@"; do [ "$a" = migrate ] && run=1; done ;;
    goose | dbmate) for a in "$@"; do [ "$a" = up ] && run=1; done ;;
    sequelize | sequelize-cli) for a in "$@"; do [ "$a" = db:migrate ] && run=1; done ;;
    typeorm | typeorm-ts-node-commonjs | typeorm-ts-node-esm) for a in "$@"; do [ "$a" = migration:run ] && run=1; done ;;
    wrangler) [ "$a1" = d1 ] && [ "$a2" = migrations ] && [ "$a3" = apply ] && run=1 ;;
    supabase) [ "$a1" = db ] && [ "$a2" = push ] && run=1 ;;
    dropdb) HIT=migration-run; return 0 ;;
  esac
  [ "$run" = 1 ] && [ "$CWD_OK" = 1 ] || return 1
  if mig_pending "$CWD"; then
    HIT=migration-run
    HINT=" $MIG_FILE is new or changed in this session and holds a contract statement (DROP or TRUNCATE): it stays a pending proposal."
    return 0
  fi
  return 1
}
# seg: one simple command in SEGW
seg() {
  local n="${#SEGW[@]}" i=0 w cw pf
  local -a args
  while [ "$i" -lt "$n" ]; do
    w="${SEGW[$i]}"
    case "$w" in r* | o* | h*) i=$((i + 1)); continue ;; esac
    w="${w#?}"
    case "$w" in
      [A-Za-z_]*=*) if assign "$w"; then i=$((i + 1)); continue; fi ;;
      sudo | env | command | nice | time | nohup | exec | timeout | '{' | '!' | then | do | else | if | while | until | elif)
        pf="$w"
        i=$((i + 1))
        # options with an argument per prefix (R3); time -p and command -p take none
        while [ "$i" -lt "$n" ]; do
          w="${SEGW[$i]#?}"
          case "$pf:$w" in
            sudo:-[ugpCDhrtTU] | env:-[uCS] | nice:-n | timeout:-[sk] | time:-[fo] | exec:-a) i=$((i + 2)) ;;
            *:-* | *:[A-Za-z_]*=*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        # timeout DURATION COMMAND
        if [ "$pf" = timeout ] && [ "$i" -lt "$n" ]; then i=$((i + 1)); fi
        continue ;;
    esac
    break
  done
  [ "$i" -lt "$n" ] || return 1
  cw="${SEGW[$i]#?}"; cw="${cw##*/}"
  case "$cw" in
    npx | bunx | pnpx)
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do case "${SEGW[$i]#?}" in -*) i=$((i + 1)) ;; *) break ;; esac; done ;;
    bundle | pnpm | yarn)
      case "${SEGW[$((i + 1))]:-}" in wexec | wdlx) i=$((i + 2)) ;; esac ;;
  esac
  [ "$i" -lt "$n" ] || return 1
  cw="${SEGW[$i]#?}"; cw="${cw##*/}"
  case "$cw" in
    export | declare | typeset | local | readonly)
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do
        case "${SEGW[$i]}" in w[A-Za-z_]*=*) assign "${SEGW[$i]#?}" ;; esac
        i=$((i + 1))
      done
      return 1 ;;
    cd) seg_cd $((i + 1)); return 1 ;;
    git) seg_git $((i + 1)); return ;;
    rm) seg_rm $((i + 1)); return ;;
  esac
  args=()
  i=$((i + 1))
  while [ "$i" -lt "$n" ]; do
    case "${SEGW[$i]}" in w*) args[${#args[@]}]="${SEGW[$i]#?}" ;; esac
    i=$((i + 1))
  done
  if [ "${#args[@]}" -gt 0 ]; then seg_run "$cw" "${args[@]}"; else seg_run "$cw"; fi
}
# wf_text: WTX = the text written, earlier in this command, to the file NP (D-g1); 1 when none was
wf_text() {
  local k=0 hit=1
  WTX=""
  while [ "$k" -lt "${#WF_P[@]}" ]; do
    if [ "${WF_P[$k]}" = "$NP" ]; then WTX="$WTX$NL${WF_T[$k]}"; hit=0; fi
    k=$((k + 1))
  done
  return "$hit"
}
# seg_sql: adds what the command in SEGW feeds forward (its words, here-strings, here-doc bodies, the .sql files it names as
# they are on disk, and the text of any file written earlier in this command, in place of its name) to PLT, the text of the
# pipeline so far (D3), and sets SEGT to it; records the files this command writes (WF_P, WF_T: the text piped in plus its own,
# D-g1; cp/mv: the sources' text, D-g2). 0 when the command is a database client and PLT holds destructive SQL.
seg_sql() {
  local t a b txt="" cl=" " f k rest pc tee=0 cmd="" cf=0 wa m st d dn bn pf="" tsk=0 ad
  local -a fl ot co
  fl=(); ot=(); co=()
  for t in "${SEGW[@]}"; do
    a="${t#?}"
    case "$t" in
      h*) txt="$txt$NL${H[$a]:-}"; continue ;;
      o*) ot[${#ot[@]}]="$a"; continue ;;
      w*)
        case "$a" in *[[:space:]]*) ;; *) b="${a##*/}"; cl="$cl${b%.exe} " ;; esac
        if [ "$tee" = 1 ]; then case "$a" in -*) ;; *) ot[${#ot[@]}]="$a"; continue ;; esac; fi
        [ "${a##*/}" = tee ] && tee=1
        if [ "$cf" = 1 ]; then
          case "$a" in -*) ;; *) co[${#co[@]}]="$a" ;; esac
        elif [ "$tsk" -gt 0 ]; then tsk=$((tsk - 1))
        else
          # the command word: skip the prefixes seg() skips (assignments, sudo, env, ... and their options)
          ad=0
          if [ -n "$pf" ]; then
            case "$pf:$a" in
              sudo:-[ugpCDhrtTU] | env:-[uCS] | nice:-n | timeout:-[sk] | time:-[fo] | exec:-a) tsk=1; ad=1 ;;
              *:-* | *:[A-Za-z_]*=*) ad=1 ;;
              *) [ "$pf" = timeout ] && ad=1; pf="" ;;
            esac
          fi
          if [ "$ad" = 0 ]; then
            case "$a" in
              [A-Za-z_]*=*) ;;
              sudo | env | command | nice | time | nohup | exec | timeout | '{' | '!' | then | do | else | if | while | until | elif) pf="$a" ;;
              *) cf=1; cmd="${a##*/}" ;;
            esac
          fi
        fi ;;
    esac
    rest="$a"
    while [[ $rest =~ $RE_SQLF ]]; do
      f="${BASH_REMATCH[1]}"; rest="${rest#*"$f"}"
      fl[${#fl[@]}]="$f"
    done
    wa="$a"
    if [ "${#WF_P[@]}" -gt 0 ]; then
      # each word of an argument (".read cmds.txt") can name a written file; set -f keeps globs literal
      wa=""; m=0
      for pc in $a; do
        norm_path "$pc" "$CWD"
        if wf_text; then txt="$txt$WTX"; m=1; else wa="$wa $pc"; fi
      done
      [ "$m" = 1 ] || wa="$a"
    fi
    txt="$txt $wa"
  done
  for f in "${fl[@]+"${fl[@]}"}"; do
    norm_path "$f" "$CWD"
    if [ -f "$NP" ] && [ -r "$NP" ]; then txt="$txt$NL$(cat "$NP" 2>/dev/null)"; fi
  done
  for f in "${ot[@]+"${ot[@]}"}"; do
    norm_path "$f" "$CWD"
    WF_P[${#WF_P[@]}]="$NP"; WF_T[${#WF_T[@]}]="$PLT$NL$txt"
  done
  if [ "${#co[@]}" -ge 2 ] && { [ "$cmd" = cp ] || [ "$cmd" = mv ]; }; then
    d="${co[$((${#co[@]} - 1))]}"
    for f in "${co[@]:0:$((${#co[@]} - 1))}"; do
      norm_path "$f" "$CWD"
      st=""
      if wf_text; then st="$WTX"; fi
      if [[ $f =~ $RE_SQLF ]] && [ -f "$NP" ] && [ -r "$NP" ]; then st="$st$NL$(cat "$NP" 2>/dev/null)"; fi
      norm_path "$d" "$CWD"; dn="$NP"
      norm_path "$dn/${f##*/}" /; bn="$NP"
      # DEST may be a directory a mkdir earlier in this command makes: unless it is one now (or ends in /), record DEST too
      if [ -d "$dn" ] || [ "${d%/}" != "$d" ]; then dn="$bn"; else WF_P[${#WF_P[@]}]="$dn"; WF_T[${#WF_T[@]}]="$st"; fi
      WF_P[${#WF_P[@]}]="$bn"; WF_T[${#WF_T[@]}]="$st"
    done
  fi
  SEGT="$txt"
  PLT="$PLT$NL$txt"
  case "$cl" in
    *" sqlite3 "* | *" psql "* | *" mysql "* | *" mariadb "* | *" sqlcmd "* | *" duckdb "* | *" clickhouse-client "* | \
      *" wrangler d1 execute "* | *" supabase db "*) ;;
    *) return 1 ;;
  esac
  sql_destructive "$PLT"
}
# gclose: a ( ) or { } group ends; back at depth 0 its text (GT) is what flows into a pipe after it
gclose() {
  GD=$((GD - 1))
  if [ "$GD" = 0 ]; then PLT="$GT"; GT=""; fi
}
pre_bash() {
  local t
  HIT=""; HINT=""; TMPS=""; CIC=0
  case "${OSTYPE:-}" in msys* | cygwin*) CIC=1 ;; esac
  NP_DRV=0
  if [ -n "$J_cwd" ]; then norm_path "$J_cwd" /; CWD="$NP"; else CWD="$PWD"; fi
  CWD_OK=1
  norm_path "${CLAUDE_PROJECT_DIR:-$CWD}" /; ROOTN="$NP"
  [ "$NP_DRV" = 1 ] && CIC=1
  SEGW=(); PLT=""; WF_P=(); WF_T=(); GD=0; GT=""; SEGT=""
  for t in "${W[@]}"; do
    case "$t" in
      s | 's|' | 's(' | 's)')
        if [ "${#SEGW[@]}" -gt 0 ]; then
          seg && break
          if seg_sql; then HIT=sql; HINT=""; break; fi
          if [ "$GD" -gt 0 ]; then GT="$GT$NL$SEGT"; fi
        fi
        SEGW=()
        case "$t" in
          s) PLT="" ;;
          's(') GD=$((GD + 1)) ;;
          's)') if [ "$GD" -gt 0 ]; then gclose; else PLT=""; fi ;;
        esac ;;
      'w{' | 'w}')
        if [ "${#SEGW[@]}" = 0 ]; then
          if [ "$t" = 'w{' ]; then GD=$((GD + 1)); elif [ "$GD" -gt 0 ]; then gclose; fi
        fi
        SEGW[${#SEGW[@]}]="$t" ;;
      *) SEGW[${#SEGW[@]}]="$t" ;;
    esac
  done
  [ -n "$HIT" ] || exit 0
  decide "$HIT" "$J_cmd" "$HINT"
}

# ---- PreToolUse: Write / Edit (D4, Q1: writing a contract migration is allowed and marked pending) ----
pre_write() {
  local f="${J_file//\\//}" txt="$J_content" kind=sql
  [ "$J_tool" = Edit ] && txt="$J_new"
  case "$f" in *.[Ss][Qq][Ll] | *[Mm][Ii][Gg][Rr][Aa][Tt]*) ;; *) exit 0 ;; esac
  has_contract "$txt" || exit 0
  case "$f" in *[Mm][Ii][Gg][Rr][Aa][Tt]*) kind=migration-contract ;; esac
  hlog "pending $kind"
  warn_json "$J_file holds a contract statement (DROP, TRUNCATE or ALTER TABLE ... DROP). The file is written but pending, not run: do not run it in this session. Headless runs must revert it before finishing and report it as a pending proposal in the final reply."
  exit 0
}

# ---- SessionStart: the baseline (D16) ----
start_mode() {
  local f h
  [ -n "$SIDV" ] || exit 0
  hook_dir
  repo_info "$HDIR" || exit 0
  f="$GC/pb-guard/$SIDV"
  [ -e "$f" ] && exit 0
  h="$(git -C "$TOP" rev-parse -q --verify HEAD 2>/dev/null)" || h=none
  [ -n "$h" ] || h=none
  mkdir -p "$GC/pb-guard" 2>/dev/null || exit 0
  printf '%s\n' "$h" > "$f" 2>/dev/null
  exit 0
}

# ---- Stop: the end-of-turn diff (D17, D19, D28) ----
# input: DS+"B path" (a schema file at the baseline), DS+"N path" (a schema file now), DS+"M path" (an untracked migration),
# DS+"D" (git diff BASE, -U0), each followed by its lines. Output: KIND<TAB>FILE<TAB>NAME per finding.
SCH='
function nname(s) { gsub(/"/, "", s); gsub(/`/, "", s); gsub(/\[/, "", s); gsub(/\]/, "", s); return tolower(s) }
function ncols(b) { b = nname(b); gsub(/[ \t]+/, " ", b); gsub(/ ?, ?/, ",", b); gsub(/\( /, "(", b); gsub(/ \)/, ")", b); sub(/^ /, "", b); sub(/ $/, "", b); return b }
function contract(l) {
  l = tolower(l)
  if (l ~ /drop[ \t]+(table|column|database|schema)([^a-z0-9_]|$)/) return 1
  if (l ~ /(^|[^a-z0-9_])truncate([^a-z0-9_]|$)/) return 1
  if (l ~ /alter[ \t]+table[^;]*[ \t]drop([^a-z0-9_]|$)/) return 1
  return 0
}
function parse(side, file, t,   s, name, j, q, dep, c, body, cl, it, ni, k, w1) {
  gsub(/\r/, " ", t); gsub(/\t/, " ", t)
  s = tolower(t)
  while (match(s, /create[ ]+table[ ]+/)) {
    s = substr(s, RSTART + RLENGTH)
    if (match(s, /^if[ ]+not[ ]+exists[ ]+/)) s = substr(s, RLENGTH + 1)
    if (!match(s, /^[^ (]+/)) continue
    name = nname(substr(s, 1, RLENGTH)); s = substr(s, RLENGTH + 1)
    j = index(s, "(")
    if (!j) continue
    dep = 0
    for (q = j; q <= length(s); q++) { c = substr(s, q, 1); if (c == "(") dep++; else if (c == ")") { dep--; if (dep == 0) break } }
    body = substr(s, j + 1, q - j - 1); s = substr(s, q + 1)
    TB[side, name] = ncols(body); TF[side, name] = file; HAS[side, name] = 1; NAMES[name] = 1
    cl = " "; ni = 0; dep = 0; it = ""
    body = body ","
    for (k = 1; k <= length(body); k++) {
      c = substr(body, k, 1)
      if (c == "(") dep++
      if (c == ")") dep--
      if (c == "," && dep == 0) {
        sub(/^[ ]+/, "", it)
        if (match(it, /^[^ (]+/)) {
          w1 = nname(substr(it, 1, RLENGTH))
          if (w1 != "primary" && w1 != "foreign" && w1 != "unique" && w1 != "check" && w1 != "constraint" && w1 != "key" && w1 != "index") { cl = cl w1 " "; ni++ }
        }
        it = ""; continue
      }
      it = it c
    }
    COLS[side, name] = cl; NC[side, name] = ni
  }
}
# nocom LINE -> LINE without -- comments and /* */ comments (inc: inside a /* */ that began on an earlier line of the file)
function nocom(l,   o, a, d) {
  o = ""
  while (l != "") {
    if (inc) { a = index(l, "*/"); if (!a) return o; l = substr(l, a + 2); inc = 0; o = o " "; continue }
    a = index(l, "/*"); d = index(l, "--")
    if (d && (!a || d < a)) return o substr(l, 1, d - 1)
    if (!a) return o l
    o = o substr(l, 1, a - 1) " "; l = substr(l, a + 2); inc = 1
  }
  return o
}
BEGIN { DS = "\034" }
substr($0, 1, 1) == DS { cur = substr($0, 2, 1); f = substr($0, 4); df = ""; inc = 0; next }
cur == "B" || cur == "N" { BUF[cur, f] = BUF[cur, f] " " nocom($0) "\n"; next }
cur == "M" { ADD[f] = ADD[f] $0 "\n"; next }
cur == "D" {
  if (substr($0, 1, 11) == "diff --git ") { df = ""; next }
  if (substr($0, 1, 6) == "+++ b/") { df = substr($0, 7); if (substr(df, 1, 8) == ".agents/" || tolower(df) !~ /migrat/) df = ""; next }
  if (substr($0, 1, 4) == "+++ " || substr($0, 1, 4) == "--- ") { df = ""; next }
  if (df != "" && substr($0, 1, 1) == "+") ADD[df] = ADD[df] substr($0, 2) "\n"
  next
}
END {
  for (k in BUF) { split(k, kk, SUBSEP); parse(kk[1], kk[2], BUF[k]) }
  for (f in ADD) {
    t = tolower(ADD[f]); gsub(/[\t\r\n]/, " ", t); s = t
    while (match(s, /alter[ ]+table[ ]+[^ ]+[ ]+rename[ ]+to[ ]+[^ ;]+/)) {
      st = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      split(st, a, / +/); REN[nname(a[3])] = 1
    }
    s = t
    while (match(s, /rename[ ]+table[ ]+[^ ]+[ ]+to[ ]+[^ ;]+/)) {
      st = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      split(st, a, / +/); REN[nname(a[3])] = 1
    }
    m = split(ADD[f], L, "\n")
    for (i = 1; i <= m; i++) if (contract(L[i])) { l = L[i]; sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l); print "migration-contract\t" f "\t" substr(l, 1, 120); break }
  }
  for (nm in NAMES) {
    if (!HAS["B", nm]) continue
    if (HAS["N", nm]) {
      if (NC["N", nm] < NC["B", nm]) {
        split(COLS["B", nm], bc, " ")
        for (i in bc) if (bc[i] != "" && index(COLS["N", nm], " " bc[i] " ") == 0) print "schema-column-drop\t" TF["N", nm] "\t" nm "." bc[i]
      }
      continue
    }
    if (nm in REN) continue
    paired = 0
    for (n2 in NAMES) if (HAS["N", n2] && !HAS["B", n2] && !(n2 in USED) && TB["N", n2] == TB["B", nm]) { USED[n2] = 1; paired = 1; break }
    if (!paired) print "schema-drop\t" TF["B", nm] "\t" nm
  }
}'

stop_mode() {
  local bl nl f findings kinds k kind file name items="" short="" files="" b7 sid sf cnt again="" msg
  hook_dir
  repo_info "$HDIR" || exit 0
  base_of
  diff_base
  [ -n "$DB" ] || exit 0
  bl=""
  [ "$BASE" = none ] || bl="$(git -C "$TOP" -c core.quotepath=off ls-tree -r --name-only "$BASE" 2>/dev/null)"
  nl="$(git -C "$TOP" -c core.quotepath=off ls-files -co --exclude-standard 2>/dev/null)"
  findings="$(
    {
      printf '%s\n' "$bl" | while IFS= read -r f; do
        [ -n "$f" ] && is_schema "$f" || continue
        printf '%sB %s\n' "$DS" "$f"; git -C "$TOP" show "$BASE:$f" 2>/dev/null; printf '\n'
      done
      printf '%s\n' "$nl" | while IFS= read -r f; do
        [ -n "$f" ] && is_schema "$f" && [ -f "$TOP/$f" ] || continue
        printf '%sN %s\n' "$DS" "$f"; cat "$TOP/$f" 2>/dev/null; printf '\n'
      done
      git -C "$TOP" -c core.quotepath=off ls-files -o --exclude-standard 2>/dev/null | while IFS= read -r f; do
        [ -n "$f" ] && is_mig "$f" && [ -f "$TOP/$f" ] || continue
        printf '%sM %s\n' "$DS" "$f"; cat "$TOP/$f" 2>/dev/null; printf '\n'
      done
      printf '%sD -\n' "$DS"
      git -C "$TOP" -c core.quotepath=off diff --no-color --no-ext-diff --no-renames -U0 "$DB" -- 2>/dev/null
    } | awk "$SCH" 2>/dev/null
  )"
  [ -n "$findings" ] || exit 0
  b7="${BASE:0:7}"
  kinds=" "
  while IFS="$TAB" read -r kind file name; do
    [ -n "$kind" ] || continue
    case "$kinds" in *" $kind "*) ;; *) kinds="$kinds$kind " ;; esac
    case "$kind" in
      schema-drop) items="$items$NL- $kind: $file: table $name was removed"; short="$short; $kind $file $name"
        case " $files " in *" $file "*) ;; *) files="$files $file" ;; esac ;;
      schema-column-drop) items="$items$NL- $kind: $file: column $name was removed"; short="$short; $kind $file $name"
        case " $files " in *" $file "*) ;; *) files="$files $file" ;; esac ;;
      *) items="$items$NL- $kind: $file adds: $name"; short="$short; $kind $file" ;;
    esac
  done <<EOF
$findings
EOF
  short="${short#; }"
  if ! headless; then
    for k in $kinds; do hlog "warn $k"; done
    jesc "${G_PFX}irreversible changes in this session (schema or migration):$items${NL}Confirm them with the user before they are committed, pushed or run."
    printf '{"systemMessage":"%s"}\n' "$JE"
    exit 0
  fi
  sid="${SIDV:-nosession}"
  sf="$GC/pb-guard/$sid.stops"
  cnt=0
  if [ -f "$sf" ]; then IFS= read -r cnt < "$sf"; fi
  case "$cnt" in '' | *[!0-9]*) cnt=0 ;; esac
  if [ "$cnt" -ge 3 ]; then
    for k in $kinds; do hlog "stop-giveup $k"; done
    msg="${G_PFX}gave up after 3 Stop blocks; unresolved irreversible changes: $short. Report them to the user."
    printf '%s\n' "$msg" >&2
    jesc "$msg"
    printf '{"systemMessage":"%s"}\n' "$JE"
    exit 0
  fi
  mkdir -p "$GC/pb-guard" 2>/dev/null
  printf '%s\n' "$((cnt + 1))" > "$sf" 2>/dev/null
  for k in $kinds; do hlog "stop-block $k"; done
  [ "$J_active" = true ] && again=" (still there after an earlier Stop block)"
  msg="${G_PFX}BLOCKED (Stop): this session left irreversible schema or migration changes$again:$items$NL"
  if [ "$BASE" = none ]; then
    msg="${msg}Headless run: revert these changes before finishing (restore the schema files, never by rewriting history; remove the migration or move it under .agents/), then describe them as a pending proposal in your final reply."
  else
    for f in $files; do msg="$msg(restore: git checkout $b7 -- $f)$NL"; done
    msg="${msg}Headless run: revert these changes before finishing (restore the schema from $b7 with \`git checkout $b7 -- <file>\` or a revert commit, never by rewriting history; remove the migration or move it under \`.agents/\`), then describe them as a pending proposal in your final reply."
  fi
  printf '%s\n' "$msg" >&2
  exit 2
}

case "$MODE" in
  start) start_mode ;;
  stop) stop_mode ;;
esac
case "$J_tool" in
  Bash) pre_bash ;;
  Write | Edit) pre_write ;;
esac
exit 0
