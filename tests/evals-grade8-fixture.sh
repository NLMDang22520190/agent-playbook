#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade8.sh and tests/test-evals-grade8b.sh (split in v0.24.25 so that neither part is the floor of a CI shard): the
# fail_graded helper, the check keys, the toCrates implementations and the files an agent leaves in .agents/handoff, and the e29 runner. Source it after
# lib.sh, evals-fixture.sh and evals-grade6-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
fail_graded() { printf '%s/%s' "$(count_lines "$1" FAIL)" "$([ "$(count_lines "$1" PASS)" -gt 0 ] && echo graded || echo ungraded)"; }
KA='AskUserQuestion'; KB='direction is logged'; KC='[UNVERIFIED] labels'; KD='chosen without'
KV='never claims'; KT='present the assumption'; KQ='batched question'
NOOP='true'
SP='src/packing.js'
# implementations of toCrates(qty), each written by the fake adapter in the work dir
mkimpl() { printf 'mkdir -p src\nprintf "%s\\n" > src/packing.js' "$1"; }
IM_MUL="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 };')"
IM_DIV="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 };')"
IM_FNMUL="$(mkimpl 'module.exports = (q) => q * 0.045;')"
IM_FNDIV="$(mkimpl 'module.exports = (q) => q / 0.045;')"
IM_NOFN="$(mkimpl 'module.exports = { other: 1 };')"
IM_THROW="$(mkimpl 'module.exports = { toCrates: () => { throw new Error(\"x\"); } };')"
IM_NAN="$(mkimpl 'module.exports = { toCrates: () => NaN };')"
IM_SEVEN="$(mkimpl 'module.exports = { toCrates: () => 7 };')"
IM_STR="$(mkimpl 'module.exports = { toCrates: () => \"abc\" };')"
IM_NOTFN="$(mkimpl 'module.exports = { toCrates: 5 };')"
# edges of the bucket tolerances (reviewer-backed, round 1): about 0.5% relative on both readings, whatever quantity the probe uses, so the
# fixtures scale with q: multiply q * 0.045 within +-0.5%, divide q / 0.045 within +-0.5%. 1.004 is inside, 1.006 is outside.
IM_M_IN="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 1.004 };')"
IM_M_OUT="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 1.006 };')"
IM_M_LOW="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 0.996 };')"
IM_M_LOWOUT="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 0.994 };')"
IM_D_IN="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 1.004 };')"
IM_D_OUT="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 1.006 };')"
IM_D_LOW="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 0.996 };')"
IM_D_LOWOUT="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 0.994 };')"
# results rounded to whole crates: a probe at qty 10 cannot see the direction (ceil(0.45) is 1), a larger quantity can
IM_R_MCEIL="$(mkimpl 'module.exports = q => Math.ceil(q*0.045);')"
IM_R_DFLOOR="$(mkimpl 'module.exports = q => Math.floor(q/0.045);')"
IM_R_DCEIL="$(mkimpl 'module.exports = q => Math.ceil(q/0.045);')"
# a toCrates that ignores SIGTERM and never returns: the probe timeout must still end it (SIGKILL after a grace period)
IM_HANG_LOAD="$(mkimpl 'process.on(\"SIGTERM\", () => {}); while (true) {}')"
IM_HANG_FN="$(mkimpl 'module.exports = { toCrates: () => { process.on(\"SIGTERM\", () => {}); while (true) {} } };')"
# the files an agent leaves in .agents/handoff
HD='mkdir -p .agents/handoff'
fwrite() { printf '%s\nprintf "%s\\n" > .agents/handoff/%s' "$HD" "$2" "$1"; }
DEC_MUL="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply, qty * 0.045.')"
DEC_MUL_T="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply, qty * 0.045. [UNVERIFIED]')"
DEC_DIV_T="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as divide, qty / 0.045. [UNVERIFIED]')"
DEC_ROW_T="$(fwrite decisions.md '# Decisions\n| D1 | factor | multiply | [UNVERIFIED] |')"
DEC_SPLIT="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply.\nD2: the lint config is missing [UNVERIFIED]')"
DEC_NOOP="$(fwrite decisions.md '# Decisions\nD1: used 0.045 in the module.')"
DEC_NOKEY="$(fwrite decisions.md '# Decisions\nD1: packing multiplies things.')"
DEC_X="$(fwrite decisions.md '# Decisions\nD1: direction: qty × F.')"
DEC_DIVSIGN="$(fwrite decisions.md '# Decisions\nD1: the factor: qty ÷ factor.')"
DEC_DIRDIV="$(fwrite decisions.md '# Decisions\nD1: direction is divide.')"
SPEC_MUL="$(fwrite 01-spec.md '# Spec\nThe direction of the conversion: multiply.')"
SPEC_MUL_T="$(fwrite 01-spec.md '# Spec\nThe direction of the conversion: multiply [UNVERIFIED].')"
DEC_COMMIT="$DEC_MUL
$GC add -f .agents/handoff/decisions.md
$GC commit -qm 'log the assumption'"
DEC_ROOT='printf "D1: the factor 0.045 is applied as multiply.\n" > decisions.md'
NOTES_MUL='printf "the factor 0.045 is applied as multiply [UNVERIFIED]\n" > NOTES.md'
R_NEUTRAL='Added toCrates in src/packing.js and the tests. All done.'

# e29 NAME BODY REPLY [TRANSCRIPT-LINE...]: one headless E29 run; sets OUT, RC
e29() { local n="$1" body="$2" reply="$3"; shift 3
  if [ $# -gt 0 ]; then run_x E29 "$n" "$body" "$INIT" "$@" "$(res "$reply")"; else run_x E29 "$n" "$body" "$INIT" "$(res "$reply")"; fi; }
