#!/usr/bin/env bash
# Log and summarise the cost of TDD role runs, per project.
#   cost.sh add --role R --tokens N [--seconds S] [--model M] [--weight Full|Lite] [--note T]
#       R = tester|implementer|reviewer|orchestrator; N, S non-negative integers.
#       Appends one row to <project>/.agents/handoff/cost.tsv (header on first use).
#   cost.sh summary     markdown table per role plus a total row; "no cost data" if empty.
# Exit: 0 ok, 2 usage/invalid input (nothing written), 3 environment.
set -u
. "$(dirname "$0")/lib.sh"

file="$(pb_root_dir)/.agents/handoff/cost.tsv"
tab="$(printf '\t')"
nl="
"

is_uint() { case "$1" in "" | *[!0-9]*) return 1 ;; esac; return 0; }
no_ctl() { case "$1" in *"$tab"* | *"$nl"*) return 1 ;; esac; return 0; }

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  add)
    role=""; tokens=""; seconds=""; model=""; weight=""; note=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || pb_die "option $1 needs a value" 2
      case "$1" in
        --role) role="$2" ;;
        --tokens) tokens="$2" ;;
        --seconds) seconds="$2" ;;
        --model) model="$2" ;;
        --weight) weight="$2" ;;
        --note) note="$2" ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift 2
    done
    case "$role" in
      tester | implementer | reviewer | orchestrator) ;;
      *) pb_die "--role must be tester, implementer, reviewer or orchestrator" 2 ;;
    esac
    is_uint "$tokens" || pb_die "--tokens must be a non-negative integer" 2
    if [ -n "$seconds" ]; then is_uint "$seconds" || pb_die "--seconds must be a non-negative integer" 2; fi
    case "$weight" in "" | Full | Lite) ;; *) pb_die "--weight must be Full or Lite" 2 ;; esac
    no_ctl "$model" || pb_die "--model must not contain a tab or newline" 2
    no_ctl "$note" || pb_die "--note must not contain a tab or newline" 2
    mkdir -p "$(dirname "$file")" || pb_die "cannot create $(dirname "$file")" 3
    if [ ! -s "$file" ]; then
      printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote\n' > "$file" || pb_die "cannot write $file" 3
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$role" "$tokens" "$seconds" "$model" "$weight" "$note" >> "$file" \
      || pb_die "cannot write $file" 3
    ;;
  summary)
    if [ ! -f "$file" ] || [ "$(wc -l < "$file" | tr -d ' ')" -lt 2 ]; then
      echo "no cost data"
      exit 0
    fi
    awk -F'\t' '
      NR == 1 { next }
      {
        r = $2; runs[r]++; tok[r] += $3; sec[r] += $4
        if ($5 != "" && index("," mods[r] ",", "," $5 ",") == 0) mods[r] = (mods[r] == "" ? $5 : mods[r] "," $5)
        tr_++; tt += $3; ts += $4
      }
      END {
        print "| role | runs | tokens | seconds | models |"
        print "|---|---|---|---|---|"
        n = split("tester implementer reviewer orchestrator", order, " ")
        for (i = 1; i <= n; i++) {
          r = order[i]
          if (runs[r] > 0) printf "| %s | %d | %d | %d | %s |\n", r, runs[r], tok[r], sec[r], mods[r]
        }
        printf "| total | %d | %d | %d | |\n", tr_, tt, ts
      }' "$file"
    ;;
  *)
    pb_die "usage: cost.sh add|summary" 2
    ;;
esac
