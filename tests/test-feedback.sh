#!/usr/bin/env bash
# Tests for scripts/feedback.sh (playbook improvement proposals -> GitHub issues).
# `gh` is replaced by a stub via PLAYBOOK_GH; nothing is sent anywhere.
. "$(dirname "$0")/lib.sh"
FB="$PB_ROOT/scripts/feedback.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
export PLAYBOOK_DATE="2026-10-09"
D="$PLAYBOOK_HOME/.agents/playbook-feedback"

STUB="$(mk_tmp)"
export GH_LOG="$STUB/gh.log"
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:' >> "$GH_LOG"; printf ' %s' "$@" >> "$GH_LOG"; printf '\n' >> "$GH_LOG"
case "$1 $2" in
  "repo view")
    # Visibility of the target repo. Default PRIVATE; GH_VISIBILITY="" models empty output,
    # GH_VIS_FAIL=1 models a failing query (both = unknown visibility).
    [ "${GH_VIS_FAIL:-0}" = "1" ] && { echo "could not resolve to a Repository" >&2; exit 1; }
    v="${GH_VISIBILITY-PRIVATE}"
    [ -n "$v" ] && echo "$v" ;;
  "issue list")
    if [ "${GH_DUP:-0}" = "1" ]; then printf '7\t%s\thttps://github.com/o/r/issues/7\n' "${GH_DUP_TITLE:-x}"; fi ;;
  "issue create")
    while [ $# -gt 0 ]; do
      if [ "$1" = "--body-file" ]; then { echo "BODY<<"; cat "$2"; echo ">>BODY"; } >> "$GH_LOG"; fi
      shift
    done
    [ "${GH_FAIL:-0}" = "1" ] && { echo "label not found" >&2; exit 1; }
    echo "https://github.com/o/r/issues/12" ;;
esac
exit 0
EOF
chmod +x "$STUB/gh"
export PLAYBOOK_GH="$STUB/gh"

cap() { # summary [extra args...]
  local s="$1"; shift
  run bash "$FB" capture --skill playbook-tdd --kind gap --source failure --harness codex --model test-model \
    --summary "$s" --observed "Implementer edited a snapshot file and the gate passed" \
    --expected "Snapshot files count as tests" \
    --evidence "role-gate classify tests/__snapshots__/a.snap printed code" \
    --proposal "Add __snapshots__ to the default test path regex" \
    --eval "new: E12 implementer edits a snapshot" "$@"
}
id_of() { printf '%s\n' "$1" | sed -n 's/^captured \([^ ]*\).*/\1/p'; }

echo "due with nothing pending"
run bash "$FB" due
assert_rc "nothing pending -> not due (exit 1)" 1

echo "capture"
cap "Snapshot files not treated as tests"
assert_rc "capture ok" 0
ID1="$(id_of "$OUT")"
if [ -n "$ID1" ] && [ -f "$D/pending/$ID1.md" ]; then t_ok "pending file created ($ID1)"; else t_bad "pending file created" "$OUT"; fi
assert_not_contains "capture never records the working directory" "$(cat "$D/pending/$ID1.md" 2>/dev/null)" "$(pwd)"
run bash "$FB" list
assert_contains "list shows the summary" "$OUT" "Snapshot files not treated as tests"
cap "snapshot files NOT treated as tests"
assert_rc "duplicate summary for the same skill rejected" 4

echo "validation"
cap "Missing evidence case" --evidence ""
assert_rc "empty evidence rejected" 2
cap "Web source" --source web
assert_rc "web content is not a valid source" 2
cap "Bad harness" --harness notepad
assert_rc "unknown harness rejected" 2
cap "Bad kind" --kind rant
assert_rc "unknown kind rejected" 2
cap "Secret inside" --evidence "token=ghp_abcdefghijklmnopqrstuvwx123"
assert_rc "secret-looking content rejected" 2
run bash "$FB" capture --skill playbook-tdd --kind gap --source user --harness claude --summary "No eval" \
  --observed o --expected e --evidence ev --proposal p
assert_rc "missing --eval rejected (every proposal names the eval that would catch it)" 2

echo "render"
run bash "$FB" render "$ID1"
assert_rc "render ok" 0
assert_contains "title line" "$OUT" "TITLE: [playbook-tdd] Snapshot files not treated as tests"
assert_contains "body has skill" "$OUT" "**Skill:** playbook-tdd"
assert_contains "body has harness and model" "$OUT" "codex / test-model"
assert_contains "body has playbook version" "$OUT" "Playbook version:** $(tr -d '[:space:]' < "$PB_ROOT/VERSION")"
assert_contains "body has evidence section" "$OUT" "### Evidence"
assert_contains "body has the eval" "$OUT" "E12 implementer edits a snapshot"

echo "due / mark-asked / interval"
run bash "$FB" due
assert_rc "pending and never asked -> due" 0
run bash "$FB" mark-asked
run bash "$FB" due
assert_rc "asked today -> not due" 1
PLAYBOOK_DATE="2026-10-17" run bash "$FB" due
assert_rc "8 days later (default interval 7) -> due" 0
bash "$PB_ROOT/scripts/conf.sh" set feedback_interval_days 30 --global >/dev/null
PLAYBOOK_DATE="2026-10-17" run bash "$FB" due
assert_rc "interval 30 -> not due after 8 days" 1

echo "submit"
run bash "$FB" submit "$ID1"
assert_rc "submit without a repo configured -> exit 2" 2
run bash "$FB" submit "$ID1" --repo o/r --dry-run
assert_rc "dry-run ok" 0
assert_file "dry-run keeps the item pending" "$D/pending/$ID1.md"
assert_not_contains "dry-run never creates an issue" "$(cat "$GH_LOG" 2>/dev/null)" "issue create"
run bash "$FB" submit "$ID1" --repo o/r
assert_rc "submit ok" 0
assert_contains "issue created in the given repo" "$(cat "$GH_LOG")" "issue create --repo o/r"
assert_contains "feedback label" "$(cat "$GH_LOG")" "--label feedback"
assert_contains "harness label" "$(cat "$GH_LOG")" "--label harness:codex"
assert_contains "source label" "$(cat "$GH_LOG")" "--label source:failure"
assert_contains "searched for duplicates first" "$(cat "$GH_LOG")" "issue list --repo o/r"
assert_no_path "item left pending" "$D/pending/$ID1.md"
assert_contains "sent record keeps the issue url" "$(cat "$D/sent/$ID1.md" 2>/dev/null)" "https://github.com/o/r/issues/12"

echo "submit: duplicate on GitHub"
cap "Gate misses snapshot directories"
ID2="$(id_of "$OUT")"
: > "$GH_LOG"
GH_DUP=1 GH_DUP_TITLE="[playbook-tdd] Gate misses snapshot directories" run bash "$FB" submit "$ID2" --repo o/r
assert_rc "duplicate handled ok" 0
assert_contains "reports the duplicate" "$OUT" "#7"
assert_not_contains "no new issue for a duplicate" "$(cat "$GH_LOG")" "issue create"
assert_contains "sent record points at the existing issue" "$(cat "$D/sent/$ID2.md" 2>/dev/null)" "issues/7"

echo "submit: gh failure keeps the item"
cap "Reviewer skips rerun"
ID3="$(id_of "$OUT")"
GH_FAIL=1 run bash "$FB" submit "$ID3" --repo o/r
if [ "$RC" -ne 0 ]; then t_ok "gh failure -> non-zero exit"; else t_bad "gh failure -> non-zero exit"; fi
assert_file "item stays pending after a failure" "$D/pending/$ID3.md"
PLAYBOOK_GH="$STUB/does-not-exist" run bash "$FB" submit "$ID3" --repo o/r
assert_rc "gh missing -> exit 3 (offline: keep it for later)" 3
assert_file "item still pending" "$D/pending/$ID3.md"

echo "submit --all and repo from config"
cap "Setup asks too many questions" --skill playbook-setup
bash "$PB_ROOT/scripts/conf.sh" set feedback_repo o/r --global >/dev/null
: > "$GH_LOG"
run bash "$FB" submit --all
assert_rc "submit --all ok" 0
assert_eq "both remaining items submitted" "2" "$(grep -c 'issue create' "$GH_LOG")"
assert_eq "nothing pending" "0" "$(ls "$D/pending" | wc -l | tr -d ' ')"

echo "submit: public repository guard"
fresh() { cap "$1"; id_of "$OUT"; }   # capture a new pending item and print its id
: > "$GH_LOG"

IDP="$(fresh "Guard case private repo")"
: > "$GH_LOG"
GH_VISIBILITY=PRIVATE run bash "$FB" submit "$IDP" --repo o/r
assert_rc "AC3 private repo -> submit ok" 0
assert_contains "AC3 visibility of the target repo is checked" "$(cat "$GH_LOG")" "repo view o/r"
assert_contains "AC3 private repo -> duplicate search still runs" "$(cat "$GH_LOG")" "issue list --repo o/r"
assert_contains "AC3 private repo -> issue created with labels" "$(cat "$GH_LOG")" "--label feedback"
assert_no_path "AC3 private repo -> item no longer pending" "$D/pending/$IDP.md"
assert_file "AC3 private repo -> item moved to sent" "$D/sent/$IDP.md"

IDI="$(fresh "Guard case internal repo")"
: > "$GH_LOG"
GH_VISIBILITY=INTERNAL run bash "$FB" submit "$IDI" --repo o/r
assert_rc "AC3 INTERNAL repo counts as not public -> submit ok" 0
assert_contains "AC3 INTERNAL repo -> issue created" "$(cat "$GH_LOG")" "issue create --repo o/r"

IDG="$(fresh "Guard case public repo")"
: > "$GH_LOG"
GH_VISIBILITY=PUBLIC run bash "$FB" submit "$IDG" --repo o/r
assert_rc "AC1 public repo without --allow-public -> exit 5" 5
assert_contains "AC1 refusal message mentions public" "$OUT" "public"
assert_not_contains "AC1 public repo -> no issue created" "$(cat "$GH_LOG")" "issue create"
assert_file "AC1 public repo -> item stays pending" "$D/pending/$IDG.md"

IDD="$(fresh "Guard case public dry run")"
: > "$GH_LOG"
GH_VISIBILITY=PUBLIC run bash "$FB" submit "$IDD" --repo o/r --dry-run
assert_rc "AC5 public repo --dry-run without --allow-public -> exit 5" 5
assert_not_contains "AC5 dry-run on public repo -> no issue created" "$(cat "$GH_LOG")" "issue create"
assert_file "AC5 dry-run on public repo -> item stays pending" "$D/pending/$IDD.md"

IDU="$(fresh "Guard case visibility query fails")"
: > "$GH_LOG"
GH_VIS_FAIL=1 run bash "$FB" submit "$IDU" --repo o/r
assert_rc "AC4 visibility query fails -> exit 5" 5
assert_contains "AC4 query fails -> message says visibility is unknown" "$OUT" "unknown"
assert_not_contains "AC4 query fails -> no issue created" "$(cat "$GH_LOG")" "issue create"
assert_file "AC4 query fails -> item stays pending" "$D/pending/$IDU.md"

IDE="$(fresh "Guard case visibility empty")"
: > "$GH_LOG"
GH_VISIBILITY="" run bash "$FB" submit "$IDE" --repo o/r
assert_rc "AC4 visibility query prints nothing -> exit 5" 5
assert_contains "AC4 empty answer -> message says visibility is unknown" "$OUT" "unknown"
assert_not_contains "AC4 empty answer -> no issue created" "$(cat "$GH_LOG")" "issue create"
assert_file "AC4 empty answer -> item stays pending" "$D/pending/$IDE.md"

IDO="$(fresh "Guard case public opt in")"
: > "$GH_LOG"
GH_VISIBILITY=PUBLIC run bash "$FB" submit "$IDO" --repo o/r --allow-public
assert_rc "AC2 public repo with --allow-public -> exit 0" 0
assert_contains "AC2 --allow-public -> issue created" "$(cat "$GH_LOG")" "issue create --repo o/r"
assert_no_path "AC2 --allow-public -> item no longer pending" "$D/pending/$IDO.md"
assert_file "AC2 --allow-public -> item moved to sent" "$D/sent/$IDO.md"

IDA1="$(fresh "Guard case all one")"
IDA2="$(fresh "Guard case all two")"
: > "$GH_LOG"
GH_VISIBILITY=PUBLIC run bash "$FB" submit --all
assert_rc "AC6 --all on public repo without --allow-public -> exit 5" 5
assert_contains "AC6 --all refusal mentions public" "$OUT" "public"
assert_not_contains "AC6 --all on public repo -> no issue created" "$(cat "$GH_LOG")" "issue create"
assert_not_contains "AC6 --all refuses before any item is processed (no duplicate search)" "$(cat "$GH_LOG")" "issue list"
assert_file "AC6 first item stays pending" "$D/pending/$IDA1.md"
assert_file "AC6 second item stays pending" "$D/pending/$IDA2.md"

echo "discard"
cap "Throwaway idea"
ID5="$(id_of "$OUT")"
run bash "$FB" discard "$ID5"
assert_rc "discard ok" 0
assert_file "moved to discarded" "$D/discarded/$ID5.md"
run bash "$FB" discard nope
assert_rc "discard unknown id -> exit 2" 2


echo "#11 skill names are lowercase only (locale-independent check)"
cap "Uppercase skill name" --skill Playbook-TDD
assert_rc "#11 uppercase skill name rejected" 2

t_summary
