#!/usr/bin/env bash
# Proposals to improve the playbook itself, collected quietly during work and sent as
# GitHub issues only after the user approved them.
#   feedback.sh capture --skill S --kind K --source SRC --harness H [--model M] \
#       --summary T --observed O --expected E --evidence EV --proposal P --eval EVAL
#   feedback.sh list
#   feedback.sh render ID              issue title + body (for the user's preview)
#   feedback.sh due                    exit 0 when it is time to ask the user, else 1
#   feedback.sh mark-asked             remember that the user was asked today
#   feedback.sh submit ID...|--all [--repo OWNER/REPO] [--dry-run] [--allow-public]
#       submit only posts to a repo confirmed PRIVATE or INTERNAL; a PUBLIC repo or unknown
#       visibility is refused (exit 5, also with --dry-run) unless --allow-public is given.
#   feedback.sh discard ID
# Storage: ~/.agents/playbook-feedback/{pending,sent,discarded}/<id>.md (key: value lines)
# Exit: 0 ok | 1 not due / submit failures | 2 usage/validation | 3 gh unavailable | 4 duplicate
#       5 submit refused: target repo is public or its visibility is unknown (no --allow-public)
# Env: PLAYBOOK_GH (gh binary, tests), PLAYBOOK_DATE (YYYY-MM-DD, tests)
set -u
. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(pb_home)/.agents/playbook-feedback"
STATE="$DIR/state"
TODAY="${PLAYBOOK_DATE:-$(date -u +%F)}"
GH="${PLAYBOOK_GH:-gh}"
VERSION="$(tr -d '[:space:]' < "$HERE/../VERSION" 2>/dev/null)"
[ -n "$VERSION" ] || VERSION="unknown"
SECRET_RE='sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|(password|passwd|secret|token|api[_-]?key)[[:space:]]*[=:]'

field() { sed -n "s/^$2: //p" "$1" | head -n 1; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
find_item() { # id [dirs...] -> path
  local id="$1" d; shift
  case "$id" in ''|*/*|*..*) return 1 ;; esac
  for d in "$@"; do [ -f "$DIR/$d/$id.md" ] && { printf '%s' "$DIR/$d/$id.md"; return 0; }; done
  return 1
}

render_body() { # file
  local f="$1"
  {
    printf '<!-- agent-playbook-feedback v1 id=%s -->\n' "$(field "$f" id)"
    printf '**Skill:** %s · **Kind:** %s · **Source:** %s\n' "$(field "$f" skill)" "$(field "$f" kind)" "$(field "$f" source)"
    printf '**Harness / model:** %s / %s · **Playbook version:** %s · **Captured:** %s\n\n' \
      "$(field "$f" harness)" "$(field "$f" model)" "$(field "$f" version)" "$(field "$f" date)"
    printf '### What happened\n%s\n\n' "$(field "$f" observed)"
    printf '### Expected\n%s\n\n' "$(field "$f" expected)"
    printf '### Evidence\n%s\n\n' "$(field "$f" evidence)"
    printf '### Proposed change\n%s\n\n' "$(field "$f" proposal)"
    printf '### Eval that would catch this\n%s\n' "$(field "$f" eval)"
  } | pb_redact
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  capture)
    skill=""; kind=""; source=""; harness=""; model="unknown"; summary=""; observed=""
    expected=""; evidence=""; proposal=""; evalx=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || pb_die "option $1 needs a value" 2
      case "$1" in
        --skill) skill="$2" ;; --kind) kind="$2" ;; --source) source="$2" ;;
        --harness) harness="$2" ;; --model) model="$2" ;; --summary) summary="$2" ;;
        --observed) observed="$2" ;; --expected) expected="$2" ;; --evidence) evidence="$2" ;;
        --proposal) proposal="$2" ;; --eval) evalx="$2" ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift 2
    done
    for pair in "skill:$skill" "kind:$kind" "source:$source" "harness:$harness" "summary:$summary" \
                "observed:$observed" "expected:$expected" "evidence:$evidence" "proposal:$proposal" "eval:$evalx"; do
      [ -n "${pair#*:}" ] || pb_die "--${pair%%:*} is required" 2
    done
    printf '%s' "$skill" | grep -Eq '^[[:lower:][:digit:]]+(-[[:lower:][:digit:]]+)*$' || pb_die "--skill must be a skill name such as playbook-tdd (or always-on)" 2
    case "$kind" in bug|gap|friction|obsolete|idea) ;; *) pb_die "--kind must be bug|gap|friction|obsolete|idea" 2 ;; esac
    case "$source" in user|failure|review) ;; *) pb_die "--source must be user|failure|review (web or file content is not a valid source)" 2 ;; esac
    case "$harness" in claude|codex|opencode|other) ;; *) pb_die "--harness must be claude|codex|opencode|other" 2 ;; esac
    for pair in "summary:$summary:100" "model:$model:60" "observed:$observed:600" "expected:$expected:600" \
                "evidence:$evidence:600" "proposal:$proposal:600" "eval:$evalx:200"; do
      name="${pair%%:*}"; rest="${pair#*:}"; val="${rest%:*}"; max="${rest##*:}"
      case "$val" in *"
"*) pb_die "--$name must be a single line" 2 ;; esac
      [ "${#val}" -le "$max" ] || pb_die "--$name is too long (${#val} > $max chars)" 2
      if printf '%s' "$val" | grep -Eiq -- "$SECRET_RE"; then pb_die "--$name looks like it contains a secret; never send secrets" 2; fi
    done
    mkdir -p "$DIR/pending" "$DIR/sent" "$DIR/discarded" || pb_die "cannot create $DIR" 3
    want="$(lower "$summary")"
    for f in "$DIR"/pending/*.md "$DIR"/sent/*.md; do
      [ -f "$f" ] || continue
      if [ "$(field "$f" skill)" = "$skill" ] && [ "$(lower "$(field "$f" summary)")" = "$want" ]; then
        echo "duplicate: $(basename "$f" .md) already has this summary for $skill" >&2
        exit 4
      fi
    done
    day="$(printf '%s' "$TODAY" | tr -d '-')"
    n=1
    while [ -e "$DIR/pending/fb-$day-$(printf '%03d' $n).md" ] || [ -e "$DIR/sent/fb-$day-$(printf '%03d' $n).md" ] \
       || [ -e "$DIR/discarded/fb-$day-$(printf '%03d' $n).md" ]; do n=$((n + 1)); done
    id="fb-$day-$(printf '%03d' $n)"
    {
      printf 'id: %s\ndate: %s\nskill: %s\nkind: %s\nsource: %s\nharness: %s\nmodel: %s\nversion: %s\n' \
        "$id" "$TODAY" "$skill" "$kind" "$source" "$harness" "$model" "$VERSION"
      printf 'summary: %s\nobserved: %s\nexpected: %s\nevidence: %s\nproposal: %s\neval: %s\n' \
        "$summary" "$observed" "$expected" "$evidence" "$proposal" "$evalx"
    } > "$DIR/pending/$id.md"
    echo "captured $id  [$skill] $summary"
    ;;

  list)
    found=0
    for f in "$DIR"/pending/*.md; do
      [ -f "$f" ] || continue
      found=1
      printf '%s  [%s] (%s, %s) %s\n' "$(field "$f" id)" "$(field "$f" skill)" "$(field "$f" kind)" "$(field "$f" harness)" "$(field "$f" summary)"
    done
    [ "$found" -eq 1 ] || echo "no pending playbook feedback"
    ;;

  render)
    f="$(find_item "${1:-}" pending sent discarded)" || pb_die "no such feedback item: ${1:-}" 2
    printf 'TITLE: [%s] %s\n\n' "$(field "$f" skill)" "$(field "$f" summary)"
    render_body "$f"
    ;;

  due)
    count=0
    for f in "$DIR"/pending/*.md; do [ -f "$f" ] && count=$((count + 1)); done
    if [ "$count" -eq 0 ]; then echo "not due: nothing pending"; exit 1; fi
    interval="$(pb_conf_get feedback_interval_days 7)"
    case "$interval" in ''|*[!0-9]*) interval=7 ;; esac
    last="$(sed -n 's/^last_asked=//p' "$STATE" 2>/dev/null | tail -n 1)"
    if [ -z "$last" ]; then echo "due: $count pending item(s), never asked"; exit 0; fi
    a="$(pb_epoch_day "$last")"; b="$(pb_epoch_day "$TODAY")"
    [ -n "$a" ] && [ -n "$b" ] || { echo "due: $count pending item(s) (could not parse dates)"; exit 0; }
    days=$(( (b - a + 43200) / 86400 ))
    if [ "$days" -ge "$interval" ]; then echo "due: $count pending item(s), last asked $days day(s) ago"; exit 0; fi
    echo "not due: last asked $days day(s) ago (interval $interval)"
    exit 1
    ;;

  mark-asked)
    mkdir -p "$DIR" || pb_die "cannot create $DIR" 3
    printf 'last_asked=%s\n' "$TODAY" > "$STATE"
    echo "noted: asked on $TODAY"
    ;;

  submit)
    repo=""; dry=0; all=0; allow_public=0; ids=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) [ $# -ge 2 ] || pb_die "--repo needs OWNER/REPO" 2; repo="$2"; shift ;;
        --dry-run) dry=1 ;;
        --allow-public) allow_public=1 ;;
        --all) all=1 ;;
        -*) pb_die "unknown option: $1" 2 ;;
        *) ids="$ids $1" ;;
      esac
      shift
    done
    [ -n "$repo" ] || repo="$(pb_conf_get feedback_repo "")"
    [ -n "$repo" ] || pb_die "no target repo: pass --repo OWNER/REPO or run: conf.sh set feedback_repo OWNER/REPO" 2
    if [ "$all" -eq 1 ]; then
      for f in "$DIR"/pending/*.md; do [ -f "$f" ] && ids="$ids $(basename "$f" .md)"; done
    fi
    [ -n "$ids" ] || { echo "nothing to submit"; exit 0; }
    if ! command -v "$GH" >/dev/null 2>&1 && [ ! -x "$GH" ]; then
      pb_die "GitHub CLI not available ($GH): items stay pending; submit later from a machine with gh" 3
    fi
    # Visibility guard: checked once, before any item is processed.
    # DECISION[D3] runs in --dry-run too, so a dry run predicts the real run.
    if [ "$allow_public" -eq 0 ]; then
      visibility="$("$GH" repo view "$repo" --json visibility --jq .visibility 2>/dev/null)" || visibility=""
      case "$visibility" in
        PRIVATE|INTERNAL) ;;
        PUBLIC) pb_die "$repo is a public repository: not submitting (items stay pending). Use a private repo, or pass --allow-public to post publicly" 5 ;;
        # DECISION[D1] unknown visibility (query failed or printed nothing) fails closed, like public.
        *) pb_die "visibility of $repo is unknown (gh repo view failed or printed nothing): not submitting (items stay pending). Pass --allow-public to post anyway" 5 ;;
      esac
    fi
    failures=0
    for id in $ids; do
      f="$(find_item "$id" pending)" || { echo "skip: $id is not pending" >&2; failures=$((failures + 1)); continue; }
      title="[$(field "$f" skill)] $(field "$f" summary)"
      dup="$("$GH" issue list --repo "$repo" --state all --search "$(field "$f" summary) in:title" --limit 20 \
              --json number,title,url --jq '.[] | "\(.number)\t\(.title)\t\(.url)"' 2>/dev/null |
             awk -F '\t' -v t="$(lower "$title")" 'tolower($2) == t { print $1 "\t" $3; exit }')"
      if [ -n "$dup" ]; then
        TAB="$(printf '\t')"
        num="${dup%%"$TAB"*}"; url="${dup#*"$TAB"}"
        echo "$id: duplicate of #$num ($url): not creating a new issue"
        if [ "$dry" -eq 0 ]; then
          printf 'issue: %s (duplicate of #%s)\n' "$url" "$num" >> "$f" && mv "$f" "$DIR/sent/$id.md"
        fi
        continue
      fi
      labels="--label feedback --label harness:$(field "$f" harness) --label kind:$(field "$f" kind) --label source:$(field "$f" source)"
      if [ "$dry" -eq 1 ]; then
        echo "would create in $repo: $title  ($labels)"
        continue
      fi
      body="$(mktemp "${TMPDIR:-/tmp}/pbfb.XXXXXX")" || pb_die "mktemp failed" 3
      render_body "$f" > "$body"
      # shellcheck disable=SC2086
      if out="$("$GH" issue create --repo "$repo" --title "$title" --body-file "$body" $labels 2>&1)"; then
        url="$(printf '%s\n' "$out" | grep -Eo 'https://[^ ]+' | tail -n 1)"
        printf 'issue: %s\n' "${url:-$out}" >> "$f" && mv "$f" "$DIR/sent/$id.md"
        echo "$id: created ${url:-$out}"
      else
        echo "$id: gh issue create failed, kept pending: $out" >&2
        failures=$((failures + 1))
      fi
      rm -f "$body"
    done
    [ "$failures" -eq 0 ] || exit 1
    ;;

  discard)
    f="$(find_item "${1:-}" pending)" || pb_die "no pending feedback item: ${1:-}" 2
    mkdir -p "$DIR/discarded" && mv "$f" "$DIR/discarded/$(basename "$f")"
    echo "discarded ${1:-}"
    ;;

  *)
    pb_die "usage: feedback.sh capture|list|render|due|mark-asked|submit|discard" 2
    ;;
esac
