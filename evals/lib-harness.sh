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
#   pbh_without_refusal WORKROOT HOME 0 when the without arm can run in WORKROOT; else prints why (a user rules file or an
#                                     instruction file above WORKROOT holds the playbook block) and returns 2
#   pbh_leak_prompt HEADING           prints the prompt of the leak probe: is the block headed HEADING in the agent's context?
#   pbh_probe_answer FILE             YES, NO or UNKNOWN: the first word of the last stream-json result text of FILE, else of its text

# stream-json (needs --verbose with -p) puts tool calls such as the Skill call into the transcript;
# flags as listed by `claude --help` in Claude Code 2.1.295. DECISION[D3]: the claude and codex presets are best guesses.
pbh_preset_cmd() {
  case "$1" in
    claude)   printf '%s' 'cd "$1" && claude -p --output-format stream-json --verbose "$(cat "$2")"' ;;
    codex)    printf '%s' 'cd "$1" && codex exec "$(cat "$2")"' ;;
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

# DECISION[D6]: only Claude Code (settings file) and --cmd (adapter-defined) can run the without arm in v0.26.0
pbh_arm_supported() {
  [ "$2" = with ] && return 0
  case "$1" in
    codex)
      printf '%s\n' 'no documented per-run switch removes ~/.codex/AGENTS.md or the playbook skills without editing ~/.codex/config.toml'
      return 2 ;;
    opencode)
      printf '%s\n' 'no documented per-run switch removes ~/.config/opencode/AGENTS.md'
      return 2 ;;
  esac
  return 0
}

pbh_json_str() {
  printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
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
# only), while a transcript written from Git Bash keeps the POSIX form, so both forms count (Windows CI)
pbh_iso_check() {
  printf '%s\n' "${2:-}" "${3:-}" "${4:-}" "${5:-}" | node -e '
const fs = require("fs"), a = process.argv.slice(1);
let raw = ""; try { raw = fs.readFileSync(0, "utf8"); } catch (e) {}
const sl = raw.split("\n"), homes = [...new Set([a[1], sl[0]].filter(Boolean))];
const ok = [...new Set(a.slice(2, 5).concat(sl.slice(1, 4)).filter(Boolean))], names = a.slice(5);
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const H = "(?:~|\\$HOME|\\$\\{HOME\\}" + homes.map(h => "|" + esc(h)).join("") + ")";
const pats = [new RegExp(H + "/\\.agents(?=$|[/\\s\"\\x27;|&)`])"), /\.claude\/skills\/playbook-/, new RegExp(H + "/\\.claude/CLAUDE\\.md")];
if (names.length) pats.push(new RegExp("(?:^|[/\\s\"\\x27=])(?:" + names.map(esc).join("|") + ")/SKILL\\.md"));
const isPb = s => typeof s === "string" && (/(^|:)playbook-/.test(s) || names.indexOf(s) >= 0);
const bad = s => { if (typeof s !== "string") return false; for (const p of ok) s = s.split(p).join("<ok>"); return pats.some(r => r.test(s)); };
let fail = false;
for (const line of fs.readFileSync(a[0], "utf8").split("\n")) {
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
  node -e '
const fs = require("fs");
let raw = "", t = null;
try { raw = fs.readFileSync(process.argv[1], "utf8"); } catch (e) {}
for (const l of raw.split("\n")) {
  let o; try { o = JSON.parse(l); } catch (e) { continue; }
  if (o && o.type === "result" && typeof o.result === "string") t = o.result;
}
if (t === null) t = raw;
const m = /^[^A-Za-z]*(yes|no)\b/i.exec(t);
process.stdout.write(m ? m[1].toUpperCase() : "UNKNOWN");' "$1" 2>/dev/null || printf 'UNKNOWN'
}
