#!/usr/bin/env bash
# Create (or update) the labels used by feedback.sh issues. Idempotent.
#   tools/setup-labels.sh OWNER/REPO
set -u
repo="${1:-}"
[ -n "$repo" ] || { echo "usage: tools/setup-labels.sh OWNER/REPO" >&2; exit 2; }
mk() { gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null && echo "label $1"; }
mk feedback 5319e7 "Proposal from playbook-feedback"
for h in claude codex opencode other; do mk "harness:$h" 1d76db "Reported from $h"; done
mk kind:bug d73a4a "A script or gate gave a wrong result"
mk kind:gap fbca04 "No guidance for a real situation"
mk kind:friction c5def5 "A rule cost time without catching anything"
mk kind:obsolete cfd3d7 "Outdated after a harness or model change"
mk kind:idea a2eeef "Improvement backed by an observation"
mk source:user 0e8a16 "The user said so"
mk source:failure b60205 "Observed failing step"
mk source:review 006b75 "Confirmed review finding"
