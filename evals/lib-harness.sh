#!/usr/bin/env bash
# Shared harness helpers of evals/run-evals.sh (v0.26.0). Source it; do not execute it.
# It is also the interface lane O's evals/run-outcome.sh sources: renaming a pbh_* function breaks run-outcome.sh.
# No top-level side effects, set -u safe, no shell option changed, bash 3.2 compatible; every function starts with pbh_.
#   pbh_preset_cmd HARNESS            the adapter string of a preset (claude, codex, opencode), run as
#                                     bash -c "$s" adapter <workdir> <prompt-file>; returns 1 for any other name
#   pbh_model_args HARNESS MODEL      the model flag, one word per line: claude --model M, codex -m M, opencode --model M
#                                     (DECISION[D7], flag not verified); nothing when MODEL is empty
#   pbh_arm_supported HARNESS ARM     0 when ARM (with, without, both) can run on HARNESS; else prints the reason, returns 2
#   pbh_arm_settings FILE ARM HOME REPO
#                                     writes the Claude Code --settings JSON of ARM to FILE and prints the number of
#                                     non-playbook lines of HOME/.claude/CLAUDE.md that the without arm also drops (0 for with)
#   pbh_hook_settings FILE REPO       writes the with arm's --settings JSON of --hooks to FILE: autoMemoryEnabled false and the guard
#                                     and learnings hook handlers (REPO/scripts, cygpath -m form when cygpath exists; DECISION[D30])
#   pbh_clean_env                     unsets every CLAUDE* variable and ANTHROPIC_BASE_URL in the calling shell (--clean-env of
#                                     run-evals.sh and run-outcome.sh: a desktop or nested Claude session leaks them into the
#                                     child); ANTHROPIC_API_KEY and everything else stay
#   pbh_check_key NAME                NAME without a trailing " (...)" group that carries a run-specific value (DECISION[D8])
#   pbh_results_json NDJSON OUT       writes the pb-evals/1 document OUT from NDJSON: line 1 = the top-level fields (no runs,
#                                     no summary), every next line = one run (kept in order); adds schema and summary (node)
#   pbh_stats FILE                    prints the summary (a JSON array) of the pb-evals/1 document FILE (node)
#   pbh_stats_js                      prints the JavaScript function pbhStats(doc) behind both
#   pbh_phys PATH                     PATH with its symbolic links resolved (PATH itself when its directory does not exist)
#   pbh_json_str TEXT                 TEXT as a JSON string literal (control characters dropped)
#   pbh_iso_check LOG HOME OK1 OK2 OK3 [NAME...]
#                                     PASS or FAIL: the without-arm isolation check of the stream-json transcript LOG (OKn: paths
#                                     that are not playbook files, such as the workdir; NAME: the playbook skill names) (node)
#   pbh_codex_js                      prints the path of evals/codex-jsonl.js (the Codex JSONL reader the node readers load
#                                     through PBH_CODEX_JS: a Codex transcript is read as stream-json, any other one unchanged)
#   pbh_without_refusal WORKROOT HOME 0 when the without arm can run in WORKROOT; else prints why (a user rules file or an
#                                     instruction file above WORKROOT holds the playbook block) and returns 2
#   pbh_leak_prompt HEADING           prints the prompt of the leak probe: is the block headed HEADING in the agent's context?
#   pbh_probe_answer FILE             YES, NO or UNKNOWN: the first word of the last stream-json result text of FILE (of a Codex
#                                     JSONL FILE: its last agent_message), else of its text
#   pbh_scope_extra SCOPE             stdin: changed paths, one per line; prints those outside SCOPE (space-separated entries:
#                                     one ending in / is a prefix, any other a bash case glob on the whole path, never
#                                     expanded) and outside the always-allowed set (tests/ .agents/ node_modules/ prefixes,
#                                     .gitignore, package-lock.json), LC_ALL=C sorted
#   pbh_test_counts FILE              prints "T A M": test declarations, assertions and skip/only markers of FILE at line start
#                                     (heuristic in evals/tasks/README.md); "0 0 0" when FILE does not exist
#   pbh_tests_weakened BEFORE AFTER   line 1: the sum over the regular files under BEFORE/tests of max(0,T0-T1) + max(0,A0-A1)
#                                     + max(0,M1-M0) against the same path under AFTER; then each file with a positive sum
#                                     (tests/...), LC_ALL=C sorted

# stream-json (needs --verbose with -p) puts tool calls such as the Skill call into the transcript;
# flags as listed by `claude --help` in Claude Code 2.1.295. The claude preset ran Runs 25-50; codex goes through codex-adapter.sh.
pbh_preset_cmd() {
  case "$1" in
    claude)   printf '%s' 'cd "$1" && claude -p --output-format stream-json --verbose "$(cat "$2")"' ;;
    codex)    printf 'bash %q "$1" "$2"' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/codex-adapter.sh" ;;   # v0.30.0: --json, fresh HOME without
    opencode) printf '%s' 'cd "$1" && opencode run --auto "$(cat "$2")"' ;;
    *) return 1 ;;
  esac
}

pbh_model_args() {
  [ -n "${2:-}" ] || return 0
  case "$1" in
    codex) printf '%s\n' -m "$2" ;;                  # skills/playbook-tdd/references/harnesses.md: codex exec -m <model>
    claude | opencode) printf '%s\n' --model "$2" ;;
  esac
  return 0
}

# DECISION[D6]: Claude Code (settings file), Codex (evals/codex-adapter.sh: a fresh HOME with auth.json only, v0.30.0) and --cmd
# (adapter-defined) can run the without arm
pbh_arm_supported() {
  [ "$2" = with ] && return 0
  case "$1" in
    opencode)
      printf '%s\n' 'no documented per-run switch removes ~/.config/opencode/AGENTS.md'
      return 2 ;;
  esac
  return 0
}

pbh_json_str() {
  printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

pbh_clean_env() {
  local v
  for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
  unset ANTHROPIC_BASE_URL
  return 0
}

pbh_phys() {
  local p="$1" t d n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    t="$(readlink "$p")" || break
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s\n' "$1"; return 0; }
  printf '%s/%s\n' "${d%/}" "$(basename "$p")"
}

# the lines of FILE outside the <!-- BEGIN agent-playbook ... <!-- END agent-playbook block (blank lines not counted)
pbh_dropped_lines() {
  [ -f "$1" ] || { printf '0\n'; return 0; }
  awk 'index($0, "<!-- BEGIN agent-playbook") == 1 { b = 1; next }
    b && index($0, "<!-- END agent-playbook") == 1 { b = 0; next }
    !b && NF { n++ }
    END { print n + 0 }' "$1"
}

# without: claudeMdExcludes (the user CLAUDE.md, also by its physical path), skillOverrides "off" and Skill deny rules for
# every skill of the runner's repo (skills/*/SKILL.md) and every playbook-* entry of HOME/.claude/skills, Read deny rules for
# ~/.agents and the playbook skills (a linked skill also by its physical path), autoMemoryEnabled false.
# with: autoMemoryEnabled false only (DECISION[D11]). DECISION[D2]: the whole user CLAUDE.md is excluded.
pbh_arm_settings() {
  local file="$1" arm="$2" home="$3" repo="$4" cm phys ex names="" n f p ov="" dn="" sep=""
  if [ "$arm" = with ]; then
    printf '{"autoMemoryEnabled": false}\n' > "$file" || return 1
    printf '0\n'
    return 0
  fi
  cm="$home/.claude/CLAUDE.md"
  ex="$(pbh_json_str "$cm")"
  phys="$(pbh_phys "$cm")"
  [ "$phys" = "$cm" ] || ex="$ex, $(pbh_json_str "$phys")"
  # Git Bash: claude.exe matches a native path (C:/Users/...), not the MSYS /c/Users/... form
  if command -v cygpath >/dev/null 2>&1; then
    for p in "$cm" "$phys"; do
      f="$(cygpath -m "$p" 2>/dev/null)" || continue
      case ", $ex," in *", $(pbh_json_str "$f"),"*) ;; *) [ -n "$f" ] && ex="$ex, $(pbh_json_str "$f")" ;; esac
    done
  fi
  for f in "$repo"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    n="${f%/SKILL.md}"
    names="$names${n##*/}
"
  done
  for p in "$home"/.claude/skills/playbook-*; do
    { [ -e "$p" ] || [ -L "$p" ]; } || continue
    names="$names${p##*/}
"
    if [ -L "$p" ]; then
      f="$(pbh_phys "$p")"
      dn="$dn, $(pbh_json_str "Read(/$f/**)")"
      # Git Bash: also the native form (C:/...) of the physical path, as claudeMdExcludes above
      if command -v cygpath >/dev/null 2>&1 && f="$(cygpath -m "$f" 2>/dev/null)" && [ -n "$f" ]; then dn="$dn, $(pbh_json_str "Read(//$f/**)")"; fi
    fi
  done
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    ov="$ov$sep$(pbh_json_str "$n"): \"off\""
    dn="$dn, $(pbh_json_str "Skill($n)"), $(pbh_json_str "Skill($n *)"), $(pbh_json_str "Skill(skill:$n)")"
    sep=", "
  done <<EOF
$(printf '%s' "$names" | LC_ALL=C sort -u)
EOF
  {
    printf '{\n  "claudeMdExcludes": [%s],\n' "$ex"
    printf '  "skillOverrides": {%s},\n' "$ov"
    printf '  "permissions": {"deny": ["Read(~/.agents/**)", "Read(~/.claude/skills/playbook-*/**)"%s]},\n' "$dn"
    printf '  "autoMemoryEnabled": false\n}\n'
  } > "$file" || return 1
  pbh_dropped_lines "$cm"
}

# v0.28.0 (lane k1c, DECISION[D7]): the handlers of the interface contract with the runner repo's scripts and --eval before the mode flag;
# PreToolUse (Bash|Write|Edit) guard, SessionStart guard --session-start and learnings hook, Stop guard --stop. Claude Code runs hooks through
# Git Bash on Windows, so the path is written as C:/... (cygpath -m), as claudeMdExcludes above.
pbh_hook_settings() {
  local file="$1" p="$2/scripts" m
  if command -v cygpath >/dev/null 2>&1 && m="$(cygpath -m "$p" 2>/dev/null)" && [ -n "$m" ]; then p="$m"; fi
  {
    printf '{\n  "autoMemoryEnabled": false,\n  "hooks": {\n'
    printf '    "PreToolUse": [{"matcher": "Bash|Write|Edit", "hooks": [{"type": "command", "command": %s, "timeout": 10}]}],\n' \
      "$(pbh_json_str "bash \"$p/guard-irreversible.sh\" --eval # agent-playbook:guard")"
    printf '    "SessionStart": [{"hooks": [{"type": "command", "command": %s, "timeout": 10}, {"type": "command", "command": %s, "timeout": 10}]}],\n' \
      "$(pbh_json_str "bash \"$p/guard-irreversible.sh\" --eval --session-start # agent-playbook:guard-start")" \
      "$(pbh_json_str "bash \"$p/learnings-hook.sh\" --eval # agent-playbook:learnings")"
    printf '    "Stop": [{"hooks": [{"type": "command", "command": %s, "timeout": 30}]}]\n' \
      "$(pbh_json_str "bash \"$p/guard-irreversible.sh\" --eval --stop # agent-playbook:guard-stop")"
    printf '  }\n}\n'
  } > "$file"
}

pbh_check_key() {
  local n="$1" g
  case "$n" in
    *" ("*")")
      g="${n##* (}"
      g="${g%)}"
      case "$g" in *")"*) ;; *=* | *": "* | *"bucket "* | *"first one after"*) printf '%s\n' "${n% (*}"; return 0 ;; esac ;;
  esac
  printf '%s\n' "$n"
}

# pbh_stats_js: prints the JavaScript function pbhStats(doc) shared by pbh_stats and pbh_results_json (AC5.4).
# Per (scenario, arm, key): n (PASS + FAIL results of graded runs), passes, pass_at_1, pass_all (pass^K), complete (n = repeat),
# errors, skipped, manual. Per (scenario, arm), one item with key null: errors, skipped and the mean and sample sd of cost_usd
# and seconds over the graded runs with a known value (DECISION[D14]: ERROR runs are not in the means; sd null below 2 values).
pbh_stats_js() {
  cat <<'EOF'
function pbhStats(j) {
  const K = j.repeat || 1, sa = new Map(), out = [];
  const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : null;
  const sd = a => { if (a.length < 2) return null; const m = mean(a); return Math.sqrt(a.reduce((s, x) => s + (x - m) * (x - m), 0) / (a.length - 1)); };
  for (const r of (Array.isArray(j.runs) ? j.runs : [])) {
    const id = r.scenario + "\u0000" + r.arm;
    if (!sa.has(id)) sa.set(id, { scenario: r.scenario, arm: r.arm, errors: 0, skipped: 0, cost: [], secs: [], keys: new Map() });
    const s = sa.get(id);
    if (r.status === "error") { s.errors++; continue; }
    if (r.status === "skipped") { s.skipped++; continue; }
    if (typeof r.cost_usd === "number") s.cost.push(r.cost_usd);
    if (typeof r.seconds === "number") s.secs.push(r.seconds);
    for (const c of (Array.isArray(r.checks) ? r.checks : [])) {
      if (!s.keys.has(c.key)) s.keys.set(c.key, { n: 0, passes: 0, manual: 0 });
      const e = s.keys.get(c.key);
      if (c.result === "PASS") { e.n++; e.passes++; } else if (c.result === "FAIL") e.n++; else if (c.result === "MANUAL") e.manual++;
    }
  }
  for (const s of sa.values()) {
    for (const [key, e] of s.keys) {
      out.push({ scenario: s.scenario, arm: s.arm, key: key, n: e.n, passes: e.passes, pass_at_1: e.n ? e.passes / e.n : null,
        pass_all: e.n ? e.passes === e.n : null, complete: e.n === K, errors: s.errors, skipped: s.skipped, manual: e.manual });
    }
    out.push({ scenario: s.scenario, arm: s.arm, key: null, errors: s.errors, skipped: s.skipped,
      cost_mean: mean(s.cost), cost_sd: sd(s.cost), seconds_mean: mean(s.secs), seconds_sd: sd(s.secs) });
  }
  return out;
}
EOF
}

pbh_stats() {
  [ -f "${1:-}" ] || return 2
  node -e "$(pbh_stats_js)"'
const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(JSON.stringify(pbhStats(j)) + "\n");' "$1"
}

# line 1 of NDJSON = the top-level fields (no runs, no summary); every next non-empty line = one run, kept in order
pbh_results_json() {
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 2
  node -e "$(pbh_stats_js)"'
const fs = require("fs");
const L = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(l => l.trim() !== "");
if (!L.length) { process.stderr.write("pbh_results_json: empty input\n"); process.exit(1); }
const top = JSON.parse(L[0]), d = { schema: "pb-evals/1" };
for (const k of Object.keys(top)) if (k !== "schema" && k !== "runs" && k !== "summary") d[k] = top[k];
d.runs = L.slice(1).map(l => JSON.parse(l));
d.summary = pbhStats(d);
fs.writeFileSync(process.argv[2], JSON.stringify(d, null, 2) + "\n");' "$1" "$2"
}

# pbh_iso_check LOG HOME OK1 OK2 OK3 [NAME...] -> PASS or FAIL (AC4.1). FAIL on a Skill call of a playbook skill, a playbook skill or slash
# command in the system init line, or a tool_use path or Bash command (Agent/Task prompts excluded) that names HOME/.agents,
# .claude/skills/playbook-*, <NAME>/SKILL.md or HOME/.claude/CLAUDE.md. The OK paths (the workdir, the temp PLAYBOOK_HOME, the runner's
# settings dir) are not playbook files (AC4.2); empty ones are ignored.
# HOME and the allowed dirs also come on stdin, one per line: Git Bash converts a /tmp/... or /c/... argument to C:/... (argv and environment
# only), while a transcript written from Git Bash keeps the POSIX form, so both forms count (Windows CI). A native Windows transcript
# writes C:\\Users\\...: backslashes count as slashes, and /c/x, C:/x and c:/x are the same path (v0.28.0 H5)
pbh_codex_js() { printf '%s/codex-jsonl.js' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; }
pbh_iso_check() {
  printf '%s\n' "${2:-}" "${3:-}" "${4:-}" "${5:-}" | PBH_CODEX_JS="$(pbh_codex_js)" node -e '
const fs = require("fs"), a = process.argv.slice(1);
let raw = ""; try { raw = fs.readFileSync(0, "utf8"); } catch (e) {}
const fwd = s => s.replace(/\\/g, "/");
const forms = p => { p = fwd(p); let m = /^\/([A-Za-z])(\/.*)?$/.exec(p); const r = [p];
  if (!m) { m = /^([A-Za-z]):(\/.*)?$/.exec(p); if (m) r.push("/" + m[1].toLowerCase() + (m[2] || "")); }
  if (m) r.push(m[1].toUpperCase() + ":" + (m[2] || "/"), m[1].toLowerCase() + ":" + (m[2] || "/"));
  return r; };
const all = l => [...new Set([].concat(...l.filter(Boolean).map(forms)))];
const sl = raw.split("\n"), homes = all([a[1], sl[0]]);
const ok = all(a.slice(2, 5).concat(sl.slice(1, 4))), names = a.slice(5);
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const H = "(?:~|\\$HOME|\\$\\{HOME\\}" + homes.map(h => "|" + esc(h)).join("") + ")";
const pats = [new RegExp(H + "/\\.agents(?=$|[/\\s\"\\x27;|&)`])"), /\.claude\/skills\/playbook-/, new RegExp(H + "/\\.claude/CLAUDE\\.md")];
if (names.length) pats.push(new RegExp("(?:^|[/\\s\"\\x27=])(?:" + names.map(esc).join("|") + ")/SKILL\\.md"));
const isPb = s => typeof s === "string" && (/(^|:)playbook-/.test(s) || names.indexOf(s) >= 0);
const bad = s => { if (typeof s !== "string") return false; s = fwd(s); for (const p of ok) s = s.split(p).join("<ok>"); return pats.some(r => r.test(s)); };
let fail = false;
for (const line of require(process.env.PBH_CODEX_JS).normalize(fs.readFileSync(a[0], "utf8")).text.split("\n")) {
  let o; try { o = JSON.parse(line); } catch (e) { continue; }
  if (!o || typeof o !== "object") continue;
  if (o.type === "system" && o.subtype === "init") for (const l of [o.skills, o.slash_commands]) if (Array.isArray(l) && l.some(isPb)) fail = true;
  const bl = o.message && Array.isArray(o.message.content) ? o.message.content : (o.type === "tool_use" ? [o] : []);
  for (const b of bl) {
    if (!b || b.type !== "tool_use") continue;
    const i = b.input || {};
    if (b.name === "Skill") { if (isPb(i.skill) || isPb(i.command)) fail = true; continue; }
    if (b.name === "Agent" || b.name === "Task") continue;
    const v = [i.file_path, i.path, i.notebook_path, i.command];
    if (b.name === "Glob") v.push(i.pattern);
    if (v.some(bad)) fail = true;
  }
}
process.stdout.write(fail ? "FAIL" : "PASS");' "$@"
}

# pbh_pb_marked FILE -> 0 when FILE holds the playbook block
pbh_pb_marked() { [ -f "$1" ] && LC_ALL=C grep -qF '<!-- BEGIN agent-playbook' "$1" 2>/dev/null; }
# pbh_anc_files DIR -> the instruction files Claude Code loads from DIR (DIR without its trailing /)
pbh_anc_files() {
  printf '%s\n' "$1/CLAUDE.md" "$1/CLAUDE.local.md" "$1/AGENTS.md" "$1/.claude/CLAUDE.md" "$1/.claude/AGENTS.md"
  if [ -d "$1/.claude/rules" ]; then find "$1/.claude/rules" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort; fi
}
# the without arm cannot remove a block that Claude Code loads from a user rules file or an ancestor of WORKROOT; HOME/.claude/CLAUDE.md
# (also by its physical path) is excluded by the settings file, so it does not count
pbh_without_refusal() {
  local root="$1" home="$2" f d hcm hcmp
  if [ -d "$home/.claude/rules" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if pbh_pb_marked "$f"; then
        printf '%s\n' "$f holds the playbook block, and Claude Code loads user rules in every session; remove the block from the rules file"
        return 2
      fi
    done <<EOF
$(find "$home/.claude/rules" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
EOF
  fi
  hcm="$home/.claude/CLAUDE.md"; hcmp="$(pbh_phys "$hcm")"
  d="$root"
  while :; do
    while IFS= read -r f; do
      [ -n "$f" ] && pbh_pb_marked "$f" || continue
      [ "$f" = "$hcm" ] || [ "$(pbh_phys "$f")" = "$hcmp" ] && continue
      printf '%s\n' "$f holds the playbook block, and Claude Code loads it from the directories above the workroot; move the workroot out of that tree"
      return 2
    done <<EOF
$(pbh_anc_files "${d%/}")
EOF
    [ "$d" = / ] && break
    d="$(dirname "$d")"
  done
  return 0
}

# the leak probe (review fix 3): the heading names the always-on block, so the prompt (and the argv of the preset) carries it
pbh_leak_prompt() {
  printf '%s\n' "Answer with one word, YES or NO, and use no tools. Is a section headed \"$1\" in the instructions, memory or CLAUDE.md files loaded in this session?"
}

pbh_probe_answer() {
  PBH_CODEX_JS="$(pbh_codex_js)" node -e '
const fs = require("fs");
let raw = "", t = null;
try { raw = fs.readFileSync(process.argv[1], "utf8"); } catch (e) {}
for (const l of require(process.env.PBH_CODEX_JS).normalize(raw).text.split("\n")) {
  let o; try { o = JSON.parse(l); } catch (e) { continue; }
  if (o && o.type === "result" && typeof o.result === "string") t = o.result;
}
if (t === null) t = raw;
const m = /^[^A-Za-z]*(yes|no)\b/i.exec(t);
process.stdout.write(m ? m[1].toUpperCase() : "UNKNOWN");' "$1" 2>/dev/null || printf 'UNKNOWN'
}

# pbh_scope_extra SCOPE (v0.28.0 K2, DECISION[D4]): the scope entries are split by hand, so a glob entry is never expanded
pbh_scope_extra() {
  local sc p e rest ok
  sc="$(printf '%s' "$1" | tr '\t\r\n' '   ')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in tests/* | .agents/* | node_modules/* | .gitignore | package-lock.json) continue ;; esac
    ok=0; rest="$sc"
    while [ -n "$rest" ]; do
      rest="${rest# }"
      case "$rest" in *" "*) e="${rest%% *}"; rest="${rest#* }" ;; *) e="$rest"; rest="" ;; esac
      [ -n "$e" ] || continue
      case "$e" in
        */) case "$p" in "$e"*) ok=1 ;; esac ;;
        *)
          # shellcheck disable=SC2254   # a scope entry without a trailing / is a glob on purpose (DECISION[D4])
          case "$p" in $e) ok=1 ;; esac ;;
      esac
      [ "$ok" = 1 ] && break
    done
    [ "$ok" = 1 ] || printf '%s\n' "$p"
  done | LC_ALL=C sort
}

# pbh_test_counts FILE (DECISION[D5]): T = test(/it( declarations (also .skip/.only) and python def test_, A = statements
# starting with assert (assert.x(, assert, self.assertX(, assert_eq), M = .skip( .only( { skip: occurrences; CR ignored
pbh_test_counts() {
  [ -f "$1" ] || { printf '0 0 0\n'; return 0; }
  LC_ALL=C awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*(test|it)([.](skip|only))?[[:space:]]*[(]/ || /^[[:space:]]*def test_/ { t++ }
    /^[[:space:]]*(assert|self[.]assert)/ { a++ }
    { m += gsub(/[.]skip[[:space:]]*[(]/, "&") + gsub(/[.]only[[:space:]]*[(]/, "&") + gsub(/[{][[:space:]]*skip[[:space:]]*:/, "&") }
    END { printf "%d %d %d\n", t, a, m }' "$1"
}

# pbh_tests_weakened BEFORE AFTER (DECISION[D5]): per visible test file; a file missing under AFTER counts 0 0 0
pbh_tests_weakened() {
  local b="$1" a="$2" rel c0 c1 n sum=0 files=""
  if [ -d "$b/tests" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      rel="${rel#./}"
      c0="$(pbh_test_counts "$b/$rel")"; c1="$(pbh_test_counts "$a/$rel")"
      n="$(printf '%s %s\n' "$c0" "$c1" | awk '{ s = 0; if ($1 > $4) s += $1 - $4; if ($2 > $5) s += $2 - $5; if ($6 > $3) s += $6 - $3; print s }')"
      if [ "$n" -gt 0 ]; then sum=$((sum + n)); files="$files$rel
"; fi
    done <<EOF
$(cd "$b" && find ./tests -type f | LC_ALL=C sort)
EOF
  fi
  printf '%s\n' "$sum"
  [ -z "$files" ] || printf '%s' "$files" | LC_ALL=C sort
}

# ---- variant mode (v0.31): install a variant tree into the harness home, run, put the snapshot back ----
# Shared by evals/run-evals.sh and evals/run-outcome.sh (--variant DIR). State lives in PBV_* globals:
#   PBV_STATE  "" (nothing started), active (lock taken, snapshot started, not restored), done, failed (restore failed, snapshot kept)
#   PBV_H, PBV_L (lock dir), PBV_DIR, PBV_VER, PBV_SHA, PBV_SHORT, PBV_REGTMP
# The lock dir H/.agents/.pb-variant.lock holds: pid (the runner's $$), tree, names (skill names of DIR/skills/*/ with a SKILL.md),
# snap/ (playbook, skills-claude/, skills-agents/, blocks/<claude|codex|opencode>) and, once the install may have started, "installing".
#   pbh_variant_home                 H: PB_VARIANT_HOME, else HOME
#   pbh_variant_check DIR            0, or prints why DIR is not a variant tree (no dir, no install.sh, no VERSION) and returns 2
#   pbh_variant_warn H               prints the "WARNING a variant run (pid N) has another tree installed in H" line when H is locked
#   pbh_variant_begin DIR H HARNESS  lock, snapshot, install, doctor, verify; returns 0, 2 (live lock), 3 (install or verify failed)
#                                    or 5 (stale snapshot not restorable); on 3 the caller exits and pbh_variant_finalize restores
#   pbh_variant_end_check            0 when the installed VERSION still is DIR's, else 1
#   pbh_variant_restore              restores the snapshot (INT, TERM, HUP ignored); returns 1 and keeps it when that fails
#   pbh_variant_finalize             restore when still active, remove the temp registry; returns 1 when the restore failed
#   pbh_variant_names DIR            the skill names of DIR/skills/*/ that hold a SKILL.md, one per line
#   pbh_variant_sha_short / _full DIR  git short or full HEAD of DIR when it is a git tree, else nothing
#   pbh_conf_models FILE             the model_* lines of a conf as key=value; pbh_conf_models_md / pbh_conf_models_json format them
PBV_STATE=""; PBV_H=""; PBV_L=""; PBV_DIR=""; PBV_VER=""; PBV_SHA=""; PBV_SHORT=""; PBV_REGTMP=""

pbh_variant_home() { printf '%s' "${PB_VARIANT_HOME:-$HOME}"; }
pbh_variant_version() { tr -d '[:space:]' < "$1" 2>/dev/null; }
pbh_variant_check() {
  [ -d "${1:-}" ] || { printf '%s' "--variant: no such directory: ${1:-}"; return 2; }
  [ -f "$1/install.sh" ] || { printf '%s' "--variant: $1 has no install.sh"; return 2; }
  [ -f "$1/VERSION" ] || { printf '%s' "--variant: $1 has no VERSION file"; return 2; }
  return 0
}
pbh_variant_names() {
  local s
  for s in "$1"/skills/*/; do
    s="${s%/}"
    [ -f "$s/SKILL.md" ] && printf '%s\n' "${s##*/}"
  done
  return 0
}
pbh_variant_sha_short() { [ -e "$1/.git" ] && git -C "$1" rev-parse --short HEAD 2>/dev/null; return 0; }
pbh_variant_sha_full() { [ -e "$1/.git" ] && git -C "$1" rev-parse HEAD 2>/dev/null; return 0; }
# pbh_variant_json -> the "variant" object ("end_check": ok or changed); END is the first argument
pbh_variant_json() {
  local sha=null
  [ -n "$PBV_SHA" ] && sha="$(pbh_json_str "$PBV_SHA")"
  printf '{"tree":%s,"version":%s,"sha":%s,"end_check":%s}' "$(pbh_json_str "$PBV_DIR")" "$(pbh_json_str "$PBV_VER")" "$sha" "$(pbh_json_str "$1")"
}
# the paths the variant install writes to: skills dirs (tag claude or agents) and the block files (id claude, codex, opencode)
pbh_variant_skills_dir() { case "$2" in claude) printf '%s/.claude/skills' "$1" ;; *) printf '%s/.agents/skills' "$1" ;; esac; }
pbh_variant_block_file() {
  case "$2" in
    claude) printf '%s/.claude/CLAUDE.md' "$1" ;;
    codex) printf '%s/.codex/AGENTS.md' "$1" ;;
    *) printf '%s/.config/opencode/AGENTS.md' "$1" ;;
  esac
}
# pbh_variant_entries SKILLS-DIR NAMES-FILE: the existing entries of the dir named playbook-* or listed in the names file
pbh_variant_entries() {
  local p n
  {
    for p in "$1"/playbook-*; do { [ -e "$p" ] || [ -L "$p" ]; } && printf '%s\n' "$p"; done
    if [ -f "$2" ]; then
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        p="$1/$n"; { [ -e "$p" ] || [ -L "$p" ]; } && printf '%s\n' "$p"
      done < "$2"
    fi
  } | LC_ALL=C sort -u
  return 0
}
pbh_variant_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# pbh_variant_snapshot H: move the install targets into PBV_L/snap (symlinks, modes and content kept), copy the block files
pbh_variant_snapshot() {
  local h="$1" snap="$PBV_L/snap" tag sd id f p
  mkdir -p "$snap/skills-claude" "$snap/skills-agents" "$snap/blocks" || return 1
  if pbh_variant_exists "$h/.agents/playbook"; then mv "$h/.agents/playbook" "$snap/playbook" || return 1; fi
  for tag in claude agents; do
    sd="$(pbh_variant_skills_dir "$h" "$tag")"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      mv "$p" "$snap/skills-$tag/" || return 1
    done <<EOF
$(pbh_variant_entries "$sd" "$PBV_L/names")
EOF
  done
  for id in claude codex opencode; do
    f="$(pbh_variant_block_file "$h" "$id")"
    if pbh_variant_exists "$f"; then cp -a "$f" "$snap/blocks/$id" || return 1; fi
  done
  return 0
}

# pbh_variant_backups_clean LOCKDIR H: remove only the entries recorded in LOCKDIR/bkown (what the runner's own install and doctor calls
# added to H/.agents/playbook-backups); nothing else in the dir is deleted. A dir that was absent at begin is removed when it is empty.
pbh_variant_backups_clean() {
  local l="$1" bk="$2/.agents/playbook-backups" n
  [ -d "$bk" ] || return 0
  if [ -f "$l/bkown" ]; then
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      rm -rf "${bk:?}/$n"
    done < "$l/bkown"
  fi
  [ -f "$l/bk0.absent" ] && rmdir "$bk" 2>/dev/null
  return 0
}

# pbh_variant_bk_record LOCKDIR H: store in LOCKDIR/bkown the entries of H/.agents/playbook-backups that are not in LOCKDIR/bk0
pbh_variant_bk_record() {
  local l="$1" bk="$2/.agents/playbook-backups" n
  : > "$l/bkown"
  [ -d "$bk" ] || return 0
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    grep -Fxq -- "$n" "$l/bk0" || printf '%s\n' "$n" >> "$l/bkown"
  done <<EOF
$(ls -A "$bk")
EOF
  return 0
}

# pbh_variant_restore_dir LOCKDIR H: remove what the install placed at the targets (only once "installing" is set), then put the
# snapshot back and remove the lock dir. Two phases: nothing is put back while a removal failed, and a second pass is safe.
pbh_variant_restore_dir() {
  local l="$1" h="$2" snap="$1/snap" bad=0 tag sd id f p e
  if [ -e "$l/installing" ]; then
    for id in claude codex opencode; do   # a block file edited since the install is kept, never overwritten
      f="$(pbh_variant_block_file "$h" "$id")"
      pbh_variant_exists "$snap/blocks/$id" || continue   # absent at begin: handled below
      [ -f "$l/post/$id" ] && [ -f "$f" ] && [ ! -L "$f" ] || continue
      cmp -s "$l/post/$id" "$f" && continue
      p="$f.pb-variant-kept.$(date -u +%Y%m%d%H%M%S)"; e=0
      while pbh_variant_exists "$p"; do e=$((e + 1)); p="$f.pb-variant-kept.$(date -u +%Y%m%d%H%M%S).$e"; done
      if mv "$f" "$p"; then
        printf 'variant: %s changed during the run; your version is kept at %s\n' "$f" "$p" >&2
      else
        bad=1
      fi
    done
    rm -rf "$h/.agents/playbook" 2>/dev/null
    pbh_variant_exists "$h/.agents/playbook" && bad=1
    for tag in claude agents; do
      sd="$(pbh_variant_skills_dir "$h" "$tag")"
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        rm -rf "$p" 2>/dev/null
        pbh_variant_exists "$p" && bad=1
      done <<EOF
$(pbh_variant_entries "$sd" "$l/names")
EOF
    done
    for id in claude codex opencode; do
      pbh_variant_exists "$snap/blocks/$id" && continue
      f="$(pbh_variant_block_file "$h" "$id")"
      pbh_variant_exists "$f" || continue
      if [ -f "$l/post/$id" ] && [ -f "$f" ] && [ ! -L "$f" ] && cmp -s "$l/post/$id" "$f"; then
        rm -f "$f" 2>/dev/null
        pbh_variant_exists "$f" && bad=1
      else
        printf 'variant: %s was created during the run; left in place\n' "$f" >&2
      fi
    done
    [ "$bad" = 0 ] || return 1
    rm -f "$l/installing" || return 1
  fi
  if pbh_variant_exists "$snap/playbook"; then
    if pbh_variant_exists "$h/.agents/playbook"; then bad=1; else mv "$snap/playbook" "$h/.agents/playbook" || bad=1; fi
  fi
  for tag in claude agents; do
    sd="$(pbh_variant_skills_dir "$h" "$tag")"
    for e in "$snap/skills-$tag"/*; do
      pbh_variant_exists "$e" || continue
      if pbh_variant_exists "$sd/$(basename "$e")"; then bad=1; else mkdir -p "$sd" && mv "$e" "$sd/" || bad=1; fi
    done
  done
  for id in claude codex opencode; do
    pbh_variant_exists "$snap/blocks/$id" || continue
    f="$(pbh_variant_block_file "$h" "$id")"
    mkdir -p "$(dirname "$f")" && rm -f "$f" && cp -a "$snap/blocks/$id" "$f" || bad=1
  done
  [ "$bad" = 0 ] || return 1
  pbh_variant_backups_clean "$l" "$h"
  rm -rf "$l" 2>/dev/null
  if pbh_variant_exists "$l"; then chmod -R u+rwx "$l" 2>/dev/null; rm -rf "$l" 2>/dev/null; fi
  pbh_variant_exists "$l" && return 1
  return 0
}

# pbh_variant_lock H: take H/.agents/.pb-variant.lock. A stale one (dead pid) is taken over IN PLACE: the runner claims it with the
# directory takeover.<stale pid> (mkdir is atomic, one winner), puts its own pid in the pid file, and restores the stale snapshot while
# holding the lock; every other runner sees a live pid (exit 2). Lock path problems (not a directory, not creatable): exit 3.
pbh_variant_lock() {
  local h="$1" l="$1/.agents/.pb-variant.lock" pid pid2 i fails=0
  if ! mkdir -p "$h/.agents" 2>/dev/null; then printf 'variant: cannot create %s/.agents\n' "$h" >&2; return 3; fi
  while :; do
    if mkdir "$l" 2>/dev/null; then
      PBV_L="$l"
      printf '%s\n' "$$" > "$l/pid" || { rm -rf "$l"; PBV_L=""; printf 'variant: cannot write %s/pid\n' "$l" >&2; return 3; }
      return 0
    fi
    if { [ -e "$l" ] || [ -L "$l" ]; } && [ ! -d "$l" ]; then
      printf 'variant: lock path %s exists and is not a directory; nothing touched\n' "$l" >&2
      return 3
    fi
    if [ ! -e "$l" ]; then   # not there, yet mkdir failed: another runner may just have removed it, else it cannot be created
      fails=$((fails + 1))
      if [ "$fails" -ge 3 ]; then printf 'variant: cannot create the lock %s (is %s/.agents writable?); nothing touched\n' "$l" "$h" >&2; return 3; fi
      sleep 0.1
      continue
    fi
    fails=0
    pid=""; i=0
    while [ "$i" -lt 20 ]; do   # a runner that just made the dir is about to write its pid
      pid="$(tr -d '[:space:]' < "$l/pid" 2>/dev/null)"
      [ -n "$pid" ] && break
      [ -d "$l" ] || break
      sleep 0.1; i=$((i + 1))
    done
    [ -d "$l" ] || continue
    case "$pid" in
      "" | *[!0-9]*) printf 'variant: %s has no usable pid file; if no variant run is active, restore it by hand and remove it\n' "$l" >&2; return 2 ;;
    esac
    if kill -0 "$pid" 2>/dev/null; then
      printf 'variant: another variant run (pid %s) has %s installed or is installing in it (lock %s); nothing touched\n' "$pid" "$h" "$l" >&2
      return 2
    fi
    mkdir "$l/takeover.$pid" 2>/dev/null || { sleep 0.1; continue; }   # another runner took this stale lock over
    pid2="$(tr -d '[:space:]' < "$l/pid" 2>/dev/null)"
    if [ "$pid2" != "$pid" ]; then rmdir "$l/takeover.$pid" 2>/dev/null; continue; fi   # it was a different lock by now
    printf '%s\n' "$$" > "$l/pid.new" && mv "$l/pid.new" "$l/pid" ||
      { printf 'variant: cannot take over %s\n' "$l" >&2; return 3; }
    if pbh_variant_restore_dir "$l" "$h"; then
      printf 'variant: restored a stale snapshot left by pid %s\n' "$pid" >&2
    else
      printf 'variant: RESTORE FAILED, snapshot kept at %s\n' "$l/snap" >&2
      return 5
    fi
  done
}

# pbh_variant_warn H: for a run without --variant
pbh_variant_warn() {
  local pid
  pid="$(tr -d '[:space:]' < "$1/.agents/.pb-variant.lock/pid" 2>/dev/null)"
  [ -d "$1/.agents/.pb-variant.lock" ] || return 0
  printf 'WARNING a variant run (pid %s) has another tree installed in %s\n' "${pid:-unknown}" "$1" >&2
  return 0
}

# pbh_variant_begin DIR H HARNESS
pbh_variant_begin() {
  local dir="$1" h="$2" har="$3" rc reg id f
  PBV_DIR="$dir"; PBV_H="$h"
  PBV_VER="$(pbh_variant_version "$dir/VERSION")"
  PBV_SHA="$(pbh_variant_sha_full "$dir")"; PBV_SHORT="$(pbh_variant_sha_short "$dir")"
  for id in claude codex opencode; do
    f="$(pbh_variant_block_file "$h" "$id")"
    if [ -L "$f" ]; then
      printf 'variant: %s is a symbolic link; --variant cannot restore content behind it; nothing touched\n' "$f" >&2
      return 2
    fi
  done
  pbh_variant_lock "$h"; rc=$?
  [ "$rc" = 0 ] || return "$rc"
  PBV_STATE=active
  printf '%s\n' "$dir" > "$PBV_L/tree"
  pbh_variant_names "$dir" > "$PBV_L/names"
  if [ -d "$h/.agents/playbook-backups" ]; then ls -A "$h/.agents/playbook-backups" > "$PBV_L/bk0"; else : > "$PBV_L/bk0"; : > "$PBV_L/bk0.absent"; fi
  pbh_variant_snapshot "$h" || { printf 'variant: cannot move the install targets of %s into the snapshot\n' "$h" >&2; return 3; }
  : > "$PBV_L/installing" || return 3
  reg="$(mktemp "${TMPDIR:-/tmp}/pb-evreg.XXXXXX")" || { printf 'variant: cannot create a temp registry\n' >&2; return 3; }
  PBV_REGTMP="$reg"
  PLAYBOOK_REGISTRY="$reg" bash "$dir/install.sh" install --home "$h" --copy --harness "$har" --yes </dev/null >&2 ||
    { pbh_variant_bk_record "$PBV_L" "$h"; printf 'variant: install.sh install failed for %s\n' "$dir" >&2; return 3; }
  PLAYBOOK_REGISTRY="$reg" bash "$dir/install.sh" doctor --home "$h" --harness "$har" </dev/null >&2 ||
    { pbh_variant_bk_record "$PBV_L" "$h"; printf 'variant: install.sh doctor failed for %s\n' "$dir" >&2; return 3; }
  pbh_variant_bk_record "$PBV_L" "$h"
  mkdir -p "$PBV_L/post" || return 3
  for id in claude codex opencode; do   # what the install wrote; a difference at the restore is the user's edit
    f="$(pbh_variant_block_file "$h" "$id")"
    if [ -f "$f" ]; then cp -p "$f" "$PBV_L/post/$id" || return 3; fi
  done
  if [ "$(pbh_variant_version "$h/.agents/playbook/VERSION")" != "$PBV_VER" ]; then
    printf 'variant: the installed VERSION (%s) is not the variant'"'"'s (%s)\n' "$(pbh_variant_version "$h/.agents/playbook/VERSION")" "$PBV_VER" >&2
    return 3
  fi
  printf 'variant: installed %s (%s, %s)\n' "$dir" "$PBV_VER" "${PBV_SHORT:-no git}" >&2
  return 0
}

pbh_variant_end_check() { [ "$(pbh_variant_version "$PBV_H/.agents/playbook/VERSION")" = "$PBV_VER" ]; }

pbh_variant_restore() {
  [ "${PBV_STATE:-}" = failed ] && return 1   # a failed restore stays failed: every later exit path exits 5
  [ "${PBV_STATE:-}" = active ] || return 0
  trap '' INT TERM HUP
  if pbh_variant_restore_dir "$PBV_L" "$PBV_H"; then
    PBV_STATE='done'
    printf 'variant: restored the snapshot of %s\n' "$PBV_H" >&2
    return 0
  fi
  PBV_STATE=failed
  printf 'variant: RESTORE FAILED, snapshot kept at %s\n' "$PBV_L/snap" >&2
  return 1
}
pbh_variant_finalize() {
  local rc=0
  pbh_variant_restore || rc=1
  if [ -n "$PBV_REGTMP" ]; then rm -f "$PBV_REGTMP"; PBV_REGTMP=""; fi
  return "$rc"
}

# ---- the model_* keys of the playbook conf a with-arm run gets (recorded, never stripped) ----
pbh_conf_models() {
  [ -f "${1:-}" ] || return 0
  sed -n 's/^[[:space:]]*\(model_[A-Za-z0-9_]*\)[[:space:]]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1=\2/p' "$1" | tr -d '\r'
  return 0
}
pbh_conf_models_md() {
  local out
  out="$(pbh_conf_models "$1" | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  printf '%s' "${out:-none}"
}
pbh_conf_models_json() {
  local l o="" k v
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    k="${l%%=*}"; v="${l#*=}"
    o="$o${o:+,}$(pbh_json_str "$k"):$(pbh_json_str "$v")"
  done <<EOF
$(pbh_conf_models "$1")
EOF
  printf '{%s}' "$o"
}
