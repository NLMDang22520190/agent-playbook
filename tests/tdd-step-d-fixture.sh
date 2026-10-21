#!/usr/bin/env bash
# Shared helpers of tests/test-tdd-step-d.sh, -e.sh and -f.sh (the v0.24.22 commit-gap suite, split into three so that none is the floor of a CI shard):
# mkhook, hookcmd, prep, run_red, same_idx, no_red_commit, hook_refused, hook_ok, refusal_checks, refuse_case, refuse_moved, path_forms, repl_path. Source it after lib.sh and tdd-step-fixture.sh.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
# ---------------------------------------------------------------------------------------------------------------
# mkhook NAME LINES... -> path of a hook script (the lines after a #!/bin/sh line)
mkhook() { local f; f="$(mk_tmp)/$1.sh"; shift; { printf '%s\n' '#!/bin/sh'; printf '%s\n' "$@"; } > "$f"; printf '%s\n' "$f"; }
# hookcmd HOOK [NAME] -> a test command that installs HOOK as .git/hooks/NAME (default pre-commit) and fails (RED)
hookcmd() { printf '%s' "cp .git/index '$IDXF'; cp '$1' .git/hooks/${2:-pre-commit} && chmod +x .git/hooks/${2:-pre-commit}; exit 1"; }
# prep MODE -> R (fresh repo, tests/n.test.js untracked), BL (a baseline manifest for MODE baseline, else empty), H0, N0
prep() {
  R="$(fresh)"; BL=""
  if [ "$1" = baseline ]; then dirty "$R"; BL="$(snap "$R")"; fi
  printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDXF="$(mk_tmp)/index.copy"
}
# run_red FLAG CMD... -> tdd-step red in R (FLAG is --commit or empty; --baseline BL when set)
run_red() { local flag="$1"; shift; run_in "$R" bash "$STEP" red --message "m" $flag ${BL:+--baseline "$BL"} -- "$@"; }
# the index file of R is the same as IDXF, the copy the test command (hookcmd) takes right before tdd-step stages anything
same_idx() { if cmp -s "$IDXF" "$R/.git/index"; then echo same; else echo differ; fi; }
no_red_commit() { git -C "$R" log --format=%s | grep -F "test(red)"; true; }

# hook_refused MODE LABEL HOOK PATHJ [PRE] -> 8 assertions: a pre-commit hook changes what is committed; the commit is undone
hook_refused() {
  local mode="$1" label="$2" hook="$3" pj="$4" pre="${5:-}"
  prep "$mode"
  if [ -n "$pre" ]; then ( cd "$R" && eval "$pre" ); H0="$(head_of "$R")"; fi
  IDXF="$(mk_tmp)/index.copy"; local bs0; bs0="$(bstate "$R")"
  run_red --commit sh -c "$(hookcmd "$hook")"
  assert_rc "$label ($mode): exit 1" 1
  assert_contains "$label ($mode): says nothing committed" "$(lower "$OUT")" "nothing committed"
  if [ -n "$pj" ]; then
    assert_contains "$label ($mode): names the path that differs" "$OUT" "the commit differs from what was judged: $pj"
  else
    assert_contains "$label ($mode): names the dirty baseline path the hook staged" "$OUT" "README.md"
  fi
  assert_untouched "$label ($mode): the commit is undone" "$R" "$H0" "$N0"
  assert_eq "$label ($mode): the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$label ($mode): the baseline paths are untouched" "$bs0" "$(bstate "$R")"
  assert_eq "$label ($mode): no test(red) commit in the log" "" "$(no_red_commit)"
}
# hook_ok MODE LABEL HOOK EXPECTED [PRE] -> 3 assertions: a harmless hook does not refuse the commit
hook_ok() {
  local mode="$1" label="$2" hook="$3" want="$4" pre="${5:-}"
  prep "$mode"
  if [ -n "$pre" ]; then ( cd "$R" && eval "$pre" ); fi
  run_red --commit sh -c "$(hookcmd "$hook")"
  assert_rc "$label ($mode): exit 0" 0
  assert_eq "$label ($mode): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "$label ($mode): the committed paths" "$want" "$(committed "$R")"
}
# refusal_checks LABEL FLAG WANT_SUBJECT WANT_COUNT -> 6 assertions about a refused step (R, OUT, RC from the run)
refusal_checks() {
  local label="$1" flag="$2" subj="$3" cnt="$4"
  assert_rc "$label: exit 1" 1
  assert_contains "$label: says nothing committed" "$(lower "$OUT")" "nothing committed"
  if [ -n "$flag" ]; then
    assert_not_contains "$label: no RED= line" "$OUT" "RED="
  else
    assert_not_contains "$label: the commit commands are not printed" "$OUT" "not committing (no --commit)"
  fi
  assert_eq "$label: HEAD is the commit from before tdd-step (or the test command's own)" "$subj" "$(subject "$R")"
  assert_eq "$label: commit count" "$cnt" "$(count_of "$R")"
  assert_eq "$label: no test(red) commit in the log" "" "$(no_red_commit)"
}
# refuse_case LABEL MODE FLAG TESTCMD -> 6 assertions: the test command changes the work tree, the step is refused
refuse_case() {
  local label="$1" mode="$2" flag="$3" cmd="$4"
  prep "$mode"
  run_red "$flag" sh -c "$cmd"
  refusal_checks "$label ($mode, ${flag:-print})" "$flag" "init" "$N0"
}
# refuse_moved LABEL MODE FLAG TESTCMD -> 6 assertions: the test command commits the role's file itself (subject x)
refuse_moved() {
  local label="$1" mode="$2" flag="$3" cmd="$4"
  prep "$mode"
  run_red "$flag" sh -c "$cmd"
  refusal_checks "$label ($mode, ${flag:-print})" "$flag" "x" "$((N0 + 1))"
}

# path_forms PATH -> every form in which PATH can appear in an output, longest first (so that one form that contains another is replaced whole):
# PATH itself, its $PWD form, the Windows form of pwd -W (Git Bash; absent elsewhere) and cygpath -m (C:/...). A file path uses its directory plus the base name.
path_forms() {
  local p="$1" d b
  if [ -d "$p" ]; then d="$p"; b=""; else d="$(dirname "$p")"; b="/$(basename "$p")"; fi
  {
    printf '%s\n' "$p"
    ( cd "$d" 2>/dev/null && printf '%s\n' "$PWD$b" )
    ( cd "$d" 2>/dev/null && pwd -W 2>/dev/null | sed "s|\$|$b|" )
    cygpath -m "$p" 2>/dev/null
  } | awk 'length($0) > 1 { print length($0) "\t" $0 }' | sort -rn | cut -f2- | uniq
}
# repl_path TEXT PLACEHOLDER PATH -> TEXT with PATH, in every form of path_forms, replaced by PLACEHOLDER (byte for byte otherwise)
repl_path() {
  local t="$1" ph="$2" f
  while IFS= read -r f; do [ -n "$f" ] && t="${t//"$f"/$ph}"; done <<EOF
$(path_forms "$3")
EOF
  printf '%s' "$t"
}
