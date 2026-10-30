#!/usr/bin/env bash
# Shared setup of the release suites (tests/test-release-tool.sh, tests/test-release.sh; v0.32.0 slice S3, AC7): a fixture repo that
# ships tools/release-gate.sh and tools/eval-delta.sh and can hold a synthetic, COMMITTED, passing release gate, so that the
# release tools (release.sh, release-pr-check.sh --gate) see a gate for the fixture commit. The gate files are pb-evals/1 files
# (a variant object with sha = the gate commit, 5 graded runs per arm and item) pooled by the real
# `tools/release-gate.sh --pool-only`, then committed (see tests/test-release-gate-check.sh). The fake runners fail if they are
# ever called: a release tool must never spend money. Source it after lib.sh (it needs mk_tmp, node and git). It is not a suite:
# run-all.sh only starts tests/test-*.sh.
RGF_TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
RGF_W="$(mk_tmp)"
mkdir -p "$RGF_W/home" "$RGF_W/tmp"
rgf_git() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false -c core.autocrlf=false "$@"; }
# rgf_prepare REPO: tools, task dirs and fake runners (AUTO="E1 E2 E3"); nothing is committed
rgf_prepare() {
  local r="$1" t
  mkdir -p "$r/tools" "$r/evals/tasks"
  cp -p "$PB_ROOT/tools/release-gate.sh" "$r/tools/release-gate.sh"
  cp -p "$PB_ROOT/tools/eval-delta.sh" "$r/tools/eval-delta.sh"
  for t in $(printf '%s' "$RGF_TASKS" | tr ',' ' '); do mkdir -p "$r/evals/tasks/$t"; printf 'x\n' > "$r/evals/tasks/$t/prompt.md"; done
  printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3"\necho "fixture runner called: $0 $*" >&2\nexit 99\n' > "$r/evals/run-evals.sh"
  printf '#!/usr/bin/env bash\necho "fixture runner called: $0 $*" >&2\nexit 99\n' > "$r/evals/run-outcome.sh"
  chmod 755 "$r/evals/run-evals.sh" "$r/evals/run-outcome.sh"
}
# rgf_jfile OUT COMMIT MODEL ITEMS [INVERT]: a pb-evals/1 file; with passes, without fails (items in INVERT: the other way round)
rgf_jfile() {
  local out="$1" commit="$2" model="$3" list="$4" inv="${5:-}" runs="" sep="" s i arm r
  for s in $(printf '%s' "$list" | tr ',' ' '); do
    i=1
    while [ "$i" -le 5 ]; do
      for arm in with without; do
        r=PASS; [ "$arm" = without ] && r=FAIL
        case ",$inv," in *",$s,"*) if [ "$r" = PASS ]; then r=FAIL; else r=PASS; fi ;; esac
        runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$arm\",\"k\":$i,\"label\":\"$s.$arm.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"}]}"
        sep=","
      done
      i=$((i + 1))
    done
  done
  printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"claude","model":"%s","arms":["with","without"],"repeat":5,"max_cost":null,"interactive":false,"started":"2026-10-27T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.30.0","sha":"%s","end_check":"ok"},"runs":[%s],"summary":[]}\n' \
    "$commit" "$model" "$commit" "$runs" > "$out"
}
# rgf_seal REPO [INVERT]: a gate for the commit at HEAD of REPO, committed as one more commit (evals/results/gate-<12 hex> only).
# With INVERT (an item such as E2) that item has a negative delta, so the real verdict is fail. Does not push.
rgf_seal() {
  local r="$1" inv="${2:-}" c d items
  c="$(git -C "$r" rev-parse HEAD)" || return 1
  d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
  items="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$r/evals/run-evals.sh" | head -n 1 | tr -s ' ' ',')"
  rgf_jfile "$d/behaviour-m1.json" "$c" m1 "$items" "$inv"
  rgf_jfile "$d/outcome-m1.json" "$c" m1 "$RGF_TASKS" "$inv"
  ( cd "$r" && env HOME="$RGF_W/home" TMPDIR="$RGF_W/tmp" bash tools/release-gate.sh --harness claude --model m1 --pool-only --out-dir "evals/results/${d##*/}" >/dev/null 2>&1 ) || return 1
  rgf_git -C "$r" add -- "evals/results/${d##*/}" && rgf_git -C "$r" commit -qm "gate results for ${c%"${c#????????????}"}"
}
