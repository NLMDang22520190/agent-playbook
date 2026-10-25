#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade12.sh (E2), tests/test-evals-grade12c.sh (E13) and tests/test-evals-grade12b.sh (E6), v0.26.0 lane N
# (spec .agents/handoff/01-spec.md AC1-AC5, AC10, AC15). Source it after lib.sh, evals-fixture.sh, evals-grade6-fixture.sh and evals-grade8-fixture.sh.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
# Every run uses --cmd with a fake adapter that runs a BODY in the work dir (files the "agent" leaves) and then prints a stream-json transcript.
# Each grader check is found by e_state with a fixed key phrase that its check text must contain; the keys are listed in each suite header, and no
# check text of a scenario may contain the key of another check of the same scenario (e_state returns the first line holding the key).

# xr E NAME MODE BODY [TRANSCRIPT-LINE...]: one run of scenario E (MODE int = --interactive, head = headless); BODY runs in the work dir, then the
# transcript lines are printed (none: the log is plain text, not stream-json). Sets OUT, RC and XW (the workroot; the work dir is $XW/E).
xr() { local e="$1" n="$2" m="$3" body="$4"; shift 4
  if [ $# -gt 0 ]; then jl "x12$e$n" "$@"; else : > "$J/x12$e$n.json"; fi
  mk_adapter "x12$e$n" "$body
cat $J/x12$e$n.json"
  XW="$(mk_tmp)"
  if [ "$m" = int ]; then run bash "$RUNNER" --interactive --cmd "bash $A/x12$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"
  else run bash "$RUNNER" --cmd "bash $A/x12$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; fi; }
# rj TEXT -> the stream-json result line whose final reply is TEXT (JSON-escaped by node)
rj() { R12="$1" node -e 'process.stdout.write(JSON.stringify({type:"result",subtype:"success",is_error:false,result:process.env.R12}))'; }
# aqj QUESTION LABEL DESCRIPTION [QUESTION LABEL DESCRIPTION...] -> one AskUserQuestion tool_use line; each question has the given option plus
# "Other" / "Something else" (words that match no keyword of the graders)
aqj() { node -e 'const a=process.argv.slice(1),qs=[];for(let i=0;i<a.length;i+=3)qs.push({question:a[i],header:"Q"+(qs.length+1),options:[{label:a[i+1],description:a[i+2]},{label:"Other",description:"Something else"}],multiSelect:false});process.stdout.write(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"q1",name:"AskUserQuestion",input:{questions:qs}}]}}))' "$@"; }
# tool calls of the transcript
RD() { tu Read "{\"file_path\":\"$1\"}"; }
WR() { tu Write "{\"file_path\":\"$1\",\"content\":\"x\"}"; }
ED() { tu Edit "{\"file_path\":\"$1\",\"old_string\":\"a\",\"new_string\":\"b\"}"; }
GRP() { tu Grep '{"pattern":"total","path":"src"}'; }
BS() { tu Bash "$(node -e 'process.stdout.write(JSON.stringify({command:process.argv[1]}))' "$1")"; }
# wf NAME LINE... -> $J/NAME holds the lines; cpto NAME DEST -> a BODY line that copies $J/NAME to DEST in the work dir (parents made)
wf() { local n="$1"; shift; printf '%s\n' "$@" > "$J/$n"; }
cpto() { printf "mkdir -p '%s' && cp '%s' '%s'" "$(dirname "$2")" "$J/$1" "$2"; }
# PLAIN TEXT: a BODY whose log is plain text (no stream-json line)
plain() { printf "echo '%s'" "$1"; }
# no_fail E LABEL: the run is graded (a PASS line) and has no "<E> FAIL" line at all (a good transcript is never failed)
no_fail() { assert_eq "$2" "0/graded" "$(fail_graded "$1")"; }
# section_of E -> the text of the "## E ..." section of scenarios.md, lines joined by spaces
section_of() { awk -v h="## $1 " 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$PB_ROOT/evals/scenarios.md" | tr '\n' ' '; }
