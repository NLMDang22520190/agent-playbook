#!/usr/bin/env bash
# Count which report parts reach the merged pull-request bodies of a repo. Prints numbers only.
#   tools/report-usage.sh OWNER/REPO [--limit N] [--since YYYY-MM-DD]
# Runs `gh pr list --repo R --state merged --limit N --json number,body,mergedAt` (N defaults to 100; --since adds
# --search merged:>=DATE and also drops any PR merged before DATE) and prints "merged PRs: T", then one row per part,
# "<label> C/T P%": C of the T bodies contain it (P rounded half up, "-" when T is 0). Parts: a Weight: line (a line that
# starts with Weight after markdown marks), [VERIFIED], [INFERRED], [UNVERIFIED], the headings ## Not checked,
# ## Pre-mortem and ## Request coverage (at a line start), **Playbook feedback:** and **Models used:**.
# It never prints a body, a title or the repo name. The JSON is parsed with awk, not jq (jq may be missing on CI, L-0004).
# gh is $PLAYBOOK_GH when set.
# Exit: 0 ok, 2 usage, 3 gh missing, failed or printed no JSON array (message on stderr).
set -u
export LC_ALL=C

usage() { echo "usage: tools/report-usage.sh OWNER/REPO [--limit N] [--since YYYY-MM-DD]"; }
bad() { usage >&2; exit 2; }

repo=""; limit=100; since=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --limit) [ $# -ge 2 ] || bad; limit="$2"; shift ;;
    --since) [ $# -ge 2 ] || bad; since="$2"; shift ;;
    -*) bad ;;
    *) [ -z "$repo" ] || bad; repo="$1" ;;
  esac
  shift
done
[ -n "$repo" ] || bad
case "$repo" in /* | */ | */*/* | *[!A-Za-z0-9._/-]*) bad ;; ?*/?*) ;; *) bad ;; esac
case "$limit" in '' | 0* | *[!0-9]*) bad ;; esac
if [ -n "$since" ]; then
  case "$since" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) bad ;; esac
fi

gh="${PLAYBOOK_GH:-gh}"
command -v "$gh" >/dev/null 2>&1 || { echo "report-usage: gh not found (install the GitHub CLI and run gh auth login)" >&2; exit 3; }
set -- pr list --repo "$repo" --state merged --limit "$limit" --json number,body,mergedAt
[ -z "$since" ] || set -- "$@" --search "merged:>=$since"
json="$("$gh" "$@")" || { rc=$?; echo "report-usage: gh pr list failed (exit $rc)" >&2; exit 3; }

printf '%s\n' "$json" | awk -v since="$since" '
  # Raw newlines are only whitespace between JSON tokens: join the lines with a space (one-true-awk split() would
  # also split at a newline and shift the string fields below).
  { sub(/\r$/, ""); s = s $0 " " }
  # rec: count the parts of one PR body (JSON escapes still in place, \\ and \" already replaced)
  function rec(   b, k, nl, j, ln, hit) {
    if (since != "" && substr(merged, 1, 10) < since) return
    total++
    b = body
    gsub(/\\n/, "\n", b); gsub(/\\r/, "", b); gsub(/\\t/, " ", b)
    for (k = 1; k <= NP; k++) hit[k] = 0
    for (k = 1; k <= NP; k++) if (sub_[k] != "" && index(b, sub_[k])) hit[k] = 1
    nl = split(b, ln, "\n")
    for (j = 1; j <= nl; j++) {
      if (ln[j] ~ /^[ \t>*_#`-]*Weight[*_`]*:/) hit[1] = 1
      if (ln[j] ~ /^[ \t]*## Not checked/) hit[5] = 1
      if (ln[j] ~ /^[ \t]*## Pre-mortem/) hit[6] = 1
      if (ln[j] ~ /^[ \t]*## Request coverage/) hit[8] = 1
    }
    for (k = 1; k <= NP; k++) c[k] += hit[k]
  }
  END {
    NP = 9
    lab[1] = "Weight: line";           sub_[1] = ""
    lab[2] = "[VERIFIED]";             sub_[2] = "[VERIFIED]"
    lab[3] = "[INFERRED]";             sub_[3] = "[INFERRED]"
    lab[4] = "[UNVERIFIED]";           sub_[4] = "[UNVERIFIED]"
    lab[5] = "## Not checked";         sub_[5] = ""
    lab[6] = "## Pre-mortem";          sub_[6] = ""
    lab[7] = "**Playbook feedback:**"; sub_[7] = "**Playbook feedback:**"
    lab[8] = "## Request coverage";    sub_[8] = ""
    lab[9] = "**Models used:**";       sub_[9] = "**Models used:**"
    t = s; sub(/^[ \t]+/, "", t)
    if (substr(t, 1, 1) != "[") exit 3
    # Hide escaped backslashes and quotes; every quote left is JSON structure, so splitting on it puts the string
    # contents (keys and values) in the even fields and the structure between them in the odd fields.
    gsub(/\\\\/, sprintf("%c", 1), s)
    gsub(/\\"/, sprintf("%c", 2), s)
    n = split(s, f, "\"")
    total = 0; key = ""; body = ""; merged = ""; seen = 0; isval = 0
    for (i = 1; i <= n; i++) {
      if (i % 2 == 1) {
        if (seen && index(f[i], "}")) { rec(); seen = 0; body = ""; merged = "" }
        isval = (f[i] ~ /:[ \t]*$/)
      } else if (isval) {
        if (key == "body") body = f[i]; else if (key == "mergedAt") merged = f[i]
      } else { key = f[i]; seen = 1 }
    }
    if (since != "") printf "merged PRs: %d (merged on or after %s)\n", total, since
    else printf "merged PRs: %d\n", total
    for (k = 1; k <= NP; k++) {
      p = "-"; if (total > 0) p = int(c[k] * 100 / total + 0.5) "%"
      printf "%-24s %4d/%-4d %4s\n", lab[k], c[k], total, p
    }
  }
' || { echo "report-usage: gh did not print a JSON array of pull requests" >&2; exit 3; }
