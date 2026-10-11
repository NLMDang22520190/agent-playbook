#!/usr/bin/env bash
# Log and summarise the cost of TDD role runs, per project.
#   cost.sh add --role R --tokens N [--seconds S] [--model M] [--weight Full|Lite] [--note T]
#               [--phase spec|red|green|review|fix|release] [--rework N] [--majors N] [--task ID]
#       R = tester|implementer|reviewer|orchestrator; N, S non-negative integers.
#       --rework N = rework round (0 = first pass); --majors N = review majors found.
#       Appends one row to <project>/.agents/handoff/cost.tsv (header on first use).
#       --task ID = a task id, [A-Za-z0-9._-]+, used by calibrate to group the rows of one task.
#       A new file gets eleven columns (phase, rework, majors, task last). An existing file with
#       an old header (seven columns, or the v0.22.3 ten) keeps it, and its new rows keep their field count.
#   cost.sh summary [--json]
#       markdown table per role plus a total row, a table per phase, and the line
#       "rework rounds: N, review majors: M"; --json prints the totals as one JSON object.
#       "no cost data" if empty.
#   cost.sh calibrate
#       advisory only, writes nothing: per weight (Full, Lite) the tasks that have a review row with a
#       recorded majors value: tasks, average tokens, review majors per task (sum over the review
#       rows), rework per task (max in the task). Rows without a task id are skipped.
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
    phase=""; rework=""; majors=""; phase_set=0; rework_set=0; majors_set=0
    task=""; task_set=0
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || pb_die "option $1 needs a value" 2
      case "$1" in
        --role) role="$2" ;;
        --tokens) tokens="$2" ;;
        --seconds) seconds="$2" ;;
        --model) model="$2" ;;
        --weight) weight="$2" ;;
        --note) note="$2" ;;
        --phase) phase="$2"; phase_set=1 ;;
        --rework) rework="$2"; rework_set=1 ;;
        --majors) majors="$2"; majors_set=1 ;;
        --task) task="$2"; task_set=1 ;;
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
    if [ "$phase_set" = 1 ]; then
      case "$phase" in
        spec | red | green | review | fix | release) ;;
        *) pb_die "--phase must be spec, red, green, review, fix or release" 2 ;;
      esac
    fi
    if [ "$rework_set" = 1 ]; then is_uint "$rework" || pb_die "--rework must be a non-negative integer" 2; fi
    if [ "$majors_set" = 1 ]; then is_uint "$majors" || pb_die "--majors must be a non-negative integer" 2; fi
    if [ "$task_set" = 1 ]; then
      case "$task" in "" | *[!A-Za-z0-9._-]*) pb_die "--task must match [A-Za-z0-9._-]+" 2 ;; esac
    fi
    no_ctl "$model" || pb_die "--model must not contain a tab or newline" 2
    no_ctl "$note" || pb_die "--note must not contain a tab or newline" 2
    mkdir -p "$(dirname "$file")" || pb_die "cannot create $(dirname "$file")" 3
    if [ ! -s "$file" ]; then
      printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote\tphase\trework\tmajors\ttask\n' > "$file" || pb_die "cannot write $file" 3
    fi
    hdr="$(head -n 1 "$file")"
    case "$hdr" in
      *"${tab}task"*) fmt=11 ;;
      *"${tab}phase"*) fmt=10 ;;
      *) fmt=7 ;;
    esac
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ "$fmt" = 7 ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$role" "$tokens" "$seconds" "$model" "$weight" "$note" >> "$file" \
        || pb_die "cannot write $file" 3
      echo "old cost.tsv format: phase/rework/majors not recorded (task not recorded either)"
    elif [ "$fmt" = 10 ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$role" "$tokens" "$seconds" "$model" "$weight" "$note" "$phase" "$rework" "$majors" >> "$file" \
        || pb_die "cannot write $file" 3
      echo "old cost.tsv format: task not recorded"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$role" "$tokens" "$seconds" "$model" "$weight" "$note" "$phase" "$rework" "$majors" "$task" >> "$file" \
        || pb_die "cannot write $file" 3
    fi
    ;;
  summary)
    json=0
    if [ $# -gt 0 ]; then
      { [ "$1" = "--json" ] && [ $# -eq 1 ]; } || pb_die "usage: cost.sh summary [--json]" 2
      json=1
    fi
    if [ ! -f "$file" ] || [ "$(wc -l < "$file" | tr -d ' ')" -lt 2 ]; then
      echo "no cost data"
      exit 0
    fi
    awk -F'\t' -v json="$json" '
      NR == 1 { next }
      {
        r = $2; runs[r]++; tok[r] += $3; sec[r] += $4
        if ($5 != "" && index("," mods[r] ",", "," $5 ",") == 0) mods[r] = (mods[r] == "" ? $5 : mods[r] "," $5)
        tr_++; tt += $3; ts += $4
        rw += $9; mj += $10
        p = $8
        if (p != "") { ptok[p] += $3; psec[p] += $4 }
      }
      END {
        nr = split("tester implementer reviewer orchestrator", order, " ")
        np = split("spec red green review fix release", porder, " ")
        if (json == 1) {
          printf "{\"runs\":%d,\"tokens\":%d,\"seconds\":%d,\"rework_rounds\":%d,\"review_majors\":%d,\"roles\":{", tr_, tt, ts, rw, mj
          sep = ""
          for (i = 1; i <= nr; i++) {
            r = order[i]
            if (runs[r] > 0) { printf "%s\"%s\":{\"runs\":%d,\"tokens\":%d,\"seconds\":%d}", sep, r, runs[r], tok[r], sec[r]; sep = "," }
          }
          printf "},\"phases\":{"
          sep = ""
          for (i = 1; i <= np; i++) {
            p = porder[i]
            if (p in ptok) { printf "%s\"%s\":{\"tokens\":%d,\"seconds\":%d}", sep, p, ptok[p], psec[p]; sep = "," }
          }
          printf "}}\n"
          exit
        }
        print "| role | runs | tokens | seconds | models |"
        print "|---|---|---|---|---|"
        for (i = 1; i <= nr; i++) {
          r = order[i]
          if (runs[r] > 0) printf "| %s | %d | %d | %d | %s |\n", r, runs[r], tok[r], sec[r], mods[r]
        }
        printf "| total | %d | %d | %d | |\n", tr_, tt, ts
        print ""
        print "| phase | tokens | seconds |"
        print "|---|---|---|"
        for (i = 1; i <= np; i++) {
          p = porder[i]
          if (p in ptok) printf "| %s | %d | %d |\n", p, ptok[p], psec[p]
        }
        print ""
        printf "rework rounds: %d, review majors: %d\n", rw, mj
      }' "$file"
    ;;
  calibrate)
    [ $# -eq 0 ] || pb_die "usage: cost.sh calibrate" 2
    if [ ! -f "$file" ] || [ "$(wc -l < "$file" | tr -d ' ')" -lt 2 ]; then
      echo "no cost data"
      exit 0
    fi
    awk -F'\t' '
      NR == 1 { next }
      $11 == "" { next }
      {
        t = $11
        if (!(t in seen)) { seen[t] = 1; order[++nt] = t }
        tok[t] += $3
        if ($6 != "" && wt[t] == "") wt[t] = $6
        if ($9 + 0 > rw[t]) rw[t] = $9 + 0
        if ($8 == "review" && $10 != "") { hasrev[t] = 1; mj[t] += $10 }
      }
      END {
        skipped = 0
        for (i = 1; i <= nt; i++) {
          t = order[i]
          if (!hasrev[t]) { skipped++; continue }
          w = wt[t]
          if (w != "Full" && w != "Lite") continue
          n[w]++; stok[w] += tok[t]; smj[w] += mj[t]; srw[w] += rw[t]
          if (w == "Full" && mj[t] > 0) fullmaj = 1
        }
        nw = split("Full Lite", ws, " ")
        for (i = 1; i <= nw; i++) {
          w = ws[i]
          if (n[w] > 0) printf "%s: tasks %d, tokens %d, review majors %d, rework %d (per task, average)\n", w, n[w], int(stok[w] / n[w]), int(smj[w] / n[w]), int(srw[w] / n[w])
        }
        printf "skipped %d task(s) without review data\n", skipped
        if (n["Full"] >= 5 && !fullmaj) printf "advice: Full reviews found no majors in %d tasks; similar changes may be Lite\n", n["Full"]
      }' "$file"
    ;;
  *)
    pb_die "usage: cost.sh add|summary|calibrate" 2
    ;;
esac
