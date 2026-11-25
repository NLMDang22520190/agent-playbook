#!/usr/bin/env bash
# Tests for v0.38 Q9 slice S3 (docs/v0.38-q9-s3-spec.md AC2..AC20): `learn.sh verify L-NNNN`, the optional `- Verified:`
# line, `stale` ageing from it, `checklist ROLE [--dates]`, the new `check` problem, and the SKILL.md / review.md text.
# PB_SKILL_MD / PB_REVIEW_MD point the text checks at other copies (default: the repo files).
# Every expected string is written out here, never built from the output of the command under test.
. "$(dirname "$0")/lib.sh"
LEARN="$PB_ROOT/scripts/learn.sh"
HOOK="$PB_ROOT/scripts/learnings-hook.sh"
RV="${PB_REVIEW_MD:-$PB_ROOT/skills/playbook-learn/references/review.md}"
SK="${PB_SKILL_MD:-$PB_ROOT/skills/playbook-learn/SKILL.md}"
SKDIR="$(dirname "$SK")"
export PLAYBOOK_HOME="$(mk_tmp)"
unset LEARN_MAX_ENTRIES LEARN_MAX_LINES PLAYBOOK_DATE PB_EVAL_HOOKS
ERRF="$(mk_tmp)/err"
VT="$(mk_tmp)"   # TMPDIR of every verify run: must be empty afterwards
VS="$(mk_tmp)"   # scratch of this suite
F=.agents/LEARNINGS.md
CR="$(printf '\r')"
TAB="$(printf '\t')"

newrepo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; bash "$LEARN" init >/dev/null 2>&1; }
# addent DATE add-args...: add with a fixed date (never `date`)
addent() { local d="$1"; shift; PLAYBOOK_DATE="$d" bash "$LEARN" add "$@" >/dev/null 2>&1; }
# fix1: the fixture of AC1 (L-0001 tester src/**, L-0002 all, L-0003 old entry without Role, L-0004 retired)
fix1() {
  newrepo
  addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user --scope 'src/**' --role tester
  addent 2026-01-01 --title T2 --rule R2 --why w --evidence e --source user
  printf '\n### L-0003 · 2026-02-02 · T3\n- Status: active\n- Rule: R3\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: project-wide\n' >> "$F"
  addent 2026-01-01 --title T4 --rule R4 --why w --evidence e --source user
  PLAYBOOK_DATE=2026-01-01 bash "$LEARN" retire L-0004 --reason gone >/dev/null 2>&1
}
# one1: a repo with the single entry L-0001 (T1, project-wide, Role all) dated 2026-01-01
one1() { newrepo; addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user; }
# vr DATE args...: learn.sh run with PLAYBOOK_DATE=DATE and a private TMPDIR; sets VO (stdout), VE (stderr), VRC
vr() { local d="$1"; shift; VO="$(PLAYBOOK_DATE="$d" TMPDIR="$VT" bash "$LEARN" "$@" 2>"$ERRF")"; VRC=$?; VE="$(cat "$ERRF")"; }
vtmp() { if [ -z "$(ls -A "$VT")" ]; then echo empty; else echo "left:$(ls -A "$VT")"; fi; }
ck() { if [ -f "$1" ]; then cksum < "$1"; else echo nofile; fi; }
snap() { cp "$F" "$VS/before"; }
nlines() { wc -l < "$1" | tr -d ' '; }
cnt() { grep -c -e "$1" "$2" || true; }
# blk ID [FILE]: the block of entry ID (heading to the line before the next heading)
blk() { ID="$1" awk 'index($0, "### " ENVIRON["ID"] " ") == 1 { on = 1; print; next } /^### / { on = 0 } on { print }' "${2:-$F}"; }
# insafter ID ANCHOR TEXT [FILE]: put TEXT after the first line of block ID that starts with ANCHOR
insafter() {
  ID="$1" AN="$2" TX="$3" awk '
    /^### / { on = (index($0, "### " ENVIRON["ID"] " ") == 1); done = 0 }
    { print }
    on && !done && index($0, ENVIRON["AN"]) == 1 { print ENVIRON["TX"]; done = 1 }
  ' "${4:-$F}" > "$VS/ins" && cat "$VS/ins" > "${4:-$F}"
}
crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$VS/crlf" && cat "$VS/crlf" > "$1"; }
# prevline ID: the line just before the first Verified line of block ID
prevline() { blk "$1" "${2:-$F}" | awk '/^- Verified:/ { print prev; exit } { prev = $0 }'; }
lastbyte() { tail -c1 "$1" | od -An -c | tr -d ' '; }
same() { if [ "$1" = "$2" ]; then echo same; else echo changed; fi; }

echo "AC2 verify inserts one line after Role"
fix1; snap
vr 2026-11-10 verify L-0001
assert_eq "AC2 verify L-0001: exit 0, stdout, empty stderr" "0|verified L-0001|" "$VRC|$VO|$VE"
assert_eq "AC2 the diff is exactly one added line (line 20 is the Role of L-0001)" "$(printf '20a21\n> - Verified: 2026-11-10')" "$(diff "$VS/before" "$F")"
assert_eq "AC2 the line before it is '- Role: tester'" "- Role: tester" "$(prevline L-0001)"
vr 2026-11-11 verify L-0002
assert_eq "AC2 verify L-0002: exit 0, stdout" "0|verified L-0002" "$VRC|$VO"
assert_eq "AC2 L-0002: the line before is '- Role: all'" "- Role: all" "$(prevline L-0002)"
vr 2026-11-12 verify L-0003
assert_eq "AC2 verify L-0003 (old entry without Role): exit 0" "0|verified L-0003" "$VRC|$VO"
assert_eq "AC2 L-0003: the line before is '- Scope: project-wide'" "- Scope: project-wide" "$(prevline L-0003)"
assert_eq "AC2 header and the retired entry are unchanged" "$(head -n 11 "$VS/before" | cksum)|$(blk L-0004 "$VS/before" | cksum)" "$(head -n 11 "$F" | cksum)|$(blk L-0004 | cksum)"
assert_eq "AC2 each verified entry has exactly one Verified line" "1 1 1 0" "$(for i in 1 2 3 4; do blk "L-000$i" | grep -c '^- Verified:' || true; done | tr '\n' ' ' | sed 's/ $//')"
newrepo
printf '\n### L-0009 · 2026-03-03 · Broken\n- Status: active\n- Rule: R9\n\n### L-0010 · 2026-03-04 · Next\n- Status: active\n- Rule: R10\n- Scope: project-wide\n- Role: all\n' >> "$F"
snap
vr 2026-11-10 verify L-0009
assert_eq "AC2 a hand-made block with neither Role nor Scope: exit 0" "0|verified L-0009" "$VRC|$VO"
assert_eq "AC2 the line goes last in the block, after the last non-blank line" "$(printf '### L-0009 · 2026-03-03 · Broken\n- Status: active\n- Rule: R9\n- Verified: 2026-11-10')" "$(blk L-0009)"
assert_eq "AC2 the next block is unchanged" "$(blk L-0010 "$VS/before" | cksum)" "$(blk L-0010 | cksum)"
newrepo
addent 2026-01-01 --title T --rule 'Rule one.' --why w --evidence e --source user --scope 'src/**' --role tester
vr 2026-11-10 verify L-0001
assert_eq "AC2 field order after add --role then verify" "Status Rule Why Evidence Source Scope Role Verified " "$(blk L-0001 | sed -n 's/^- \([A-Za-z]*\):.*/\1/p' | tr '\n' ' ')"

echo "AC3 verify replaces the first Verified line"
fix1
vr 2026-11-10 verify L-0001
snap; N0="$(nlines "$F")"
vr 2026-11-20 verify L-0001
assert_eq "AC3 re-verify: exit 0, stdout" "0|verified L-0001" "$VRC|$VO"
assert_eq "AC3 the diff is one changed line at the same position" "$(printf '21c21\n< - Verified: 2026-11-10\n---\n> - Verified: 2026-11-20')" "$(diff "$VS/before" "$F")"
assert_eq "AC3 the line count is unchanged" "$N0" "$(nlines "$F")"
K1="$(ck "$F")"; vr 2026-11-20 verify L-0001
assert_eq "AC3 the same day again: file byte-identical" "$K1" "$(ck "$F")"
fix1
insafter L-0001 '- Role:' "$(printf -- '- Verified: 2026-01-05\n- Verified: 2026-01-06')"
vr 2026-11-20 verify L-0001
assert_eq "AC3 two Verified lines: the first is replaced, the second stays" "0|$(printf -- '- Verified: 2026-11-20\n- Verified: 2026-01-06')" "$VRC|$(blk L-0001 | grep '^- Verified:')"
fix1
insafter L-0001 '- Role:' '- Verified: soon'
vr 2026-11-20 verify L-0001
assert_eq "AC3 a malformed first Verified line is repaired by verify" "0|- Verified: 2026-11-20" "$VRC|$(blk L-0001 | grep '^- Verified:')"

echo "AC4 errors"
errcase() { # NAME RC ERR DATE args...
  local name="$1" erc="$2" eerr="$3" d="$4" before after; shift 4
  before="$(ck "$F")"; vr "$d" "$@"; after="$(ck "$F")"
  assert_eq "$name" "$erc|$eerr||same|empty" "$VRC|$VE|$VO|$(same "$before" "$after")|$(vtmp)"
}
USG='error: usage: learn.sh verify L-NNNN'
fix1
errcase "AC4 no argument: usage, exit 2" 2 "$USG" 2026-11-10 verify
errcase "AC4 two arguments: usage" 2 "$USG" 2026-11-10 verify L-0001 L-0002
errcase "AC4 L-1: usage" 2 "$USG" 2026-11-10 verify L-1
errcase "AC4 l-0001: usage" 2 "$USG" 2026-11-10 verify l-0001
errcase "AC4 L-00001: usage" 2 "$USG" 2026-11-10 verify L-00001
errcase "AC4 L-0001x: usage" 2 "$USG" 2026-11-10 verify L-0001x
errcase "AC4 an id with metacharacters: usage" 2 "$USG" 2026-11-10 verify 'L-0001; touch PWNED'
errcase "AC4 an empty id: usage" 2 "$USG" 2026-11-10 verify ''
assert_eq "AC4 no PWNED file was created" "no" "$([ -e PWNED ] && echo yes || echo no)"
for BD in abc 2026-13-01 2026-00-10 2026-10-32 2026-10-00 26-10-09 2026-10-09x 2026-02-30 2026-02-29 2025-04-31; do
  errcase "AC4 PLAYBOOK_DATE=$BD: exit 2, exact message" 2 "error: invalid PLAYBOOK_DATE: $BD (expected a real date, YYYY-MM-DD)" "$BD" verify L-0001
done
errcase "AC4 a bad date beats a missing entry" 2 "error: invalid PLAYBOOK_DATE: abc (expected a real date, YYYY-MM-DD)" abc verify L-0099
errcase "AC4 no such entry" 2 "error: no such entry: L-0099" 2026-11-10 verify L-0099
insafter L-0004 '- Role:' '- Verified: 2026-01-05'
errcase "AC4 a retired entry (with a Verified line): exit 2, file unchanged" 2 "error: L-0004 is retired; verify applies to active entries" 2026-11-10 verify L-0004
printf '\n### L-0007 · 2026-01-01 · T7\n- Status: pending\n- Rule: R7\n\n### L-0008 · 2026-01-01 · T8\n- Rule: R8\n' >> "$F"
errcase "AC4 Status pending: not active" 2 "error: L-0007 is not active" 2026-11-10 verify L-0007
errcase "AC4 no Status line: not active" 2 "error: L-0008 is not active" 2026-11-10 verify L-0008
printf '\n### L-0011 · 2026-01-01 · T11\n- Status: active\n- Status: retired (x; 2026-01-01)\n- Rule: R11\n- Scope: project-wide\n- Role: all\n' >> "$F"
vr 2026-11-10 verify L-0011
assert_eq "AC4 the first Status line decides (active, then a retired line): verify runs" "0|verified L-0011" "$VRC|$VO"
vr 2024-02-29 verify L-0002
assert_eq "AC4 2024-02-29 (a real leap day) is accepted" "0|verified L-0002|- Verified: 2024-02-29" "$VRC|$VO|$(blk L-0002 | grep '^- Verified:')"
fix1
printf '\n### L-0001 · 2026-03-03 · Twice\n- Status: active\n- Rule: R1b\n' >> "$F"
errcase "AC4 two headings with the same id: ambiguous" 2 "error: ambiguous entry id: L-0001 appears 2 times" 2026-11-10 verify L-0001
rm -f "$F"
errcase "AC4 a missing file beats a bad date" 2 "error: .agents/LEARNINGS.md not found" abc verify L-0001
errcase "AC4 usage beats a missing file" 2 "$USG" 2026-11-10 verify

echo "AC5 one entry, CRLF and the final newline"
fix1
git add -A >/dev/null 2>&1; git commit -q -m fx
parts() { # DIR FILE -> cksum of the header and of each block, joined with |
  local dir="$1" i out=""; rm -rf "$dir"; mkdir -p "$dir"
  D="$dir" awk '/^### / { n++ } { print > (ENVIRON["D"] "/p" (n + 0)) }' "$2"
  for i in 0 1 2 3 4; do out="$out$(cksum < "$dir/p$i" 2>/dev/null | tr ' ' '_')|"; done
  printf '%s' "$out"
}
snap; PB="$(parts "$VS/pa" "$F")"; N0="$(nlines "$F")"
vr 2026-11-10 verify L-0002
PA="$(parts "$VS/pb" "$F")"
CMP=""; for i in 1 2 3 4 5; do
  a="$(printf '%s' "$PB" | cut -d'|' -f"$i")"; b="$(printf '%s' "$PA" | cut -d'|' -f"$i")"
  if [ "$a" = "$b" ]; then CMP="$CMP="; else CMP="$CMP!"; fi
done
assert_eq "AC5 only the block of L-0002 changed (header, L-0001, L-0003, L-0004 equal)" "==!==" "$CMP"
assert_eq "AC5 the line count grew by one" "$((N0 + 1))" "$(nlines "$F")"
assert_eq "AC5 git diff --numstat in insert mode" "1${TAB}0${TAB}.agents/LEARNINGS.md" "$(git diff --numstat)"
git add -A >/dev/null 2>&1; git commit -q -m v1
vr 2026-11-11 verify L-0002
assert_eq "AC5 git diff --numstat in replace mode" "1${TAB}1${TAB}.agents/LEARNINGS.md" "$(git diff --numstat)"
assert_eq "AC5 a file that had a final newline still has one" '\n' "$(lastbyte "$F")"
# CRLF file
fix1; crlf "$F"; snap
vr 2026-11-10 verify L-0002
assert_eq "AC5 CRLF: verify succeeds" "0|verified L-0002" "$VRC|$VO"
assert_eq "AC5 CRLF: every line still ends in CR LF (no LF-only line)" "$(nlines "$F")" "$(grep -c "$CR\$" "$F" || true)"
assert_eq "AC5 CRLF: the new line is '- Verified: 2026-11-10' + CR" "1" "$(grep -c -x -e "- Verified: 2026-11-10$CR" "$F" || true)"
assert_eq "AC5 CRLF: all other lines verbatim" "$(ck "$VS/before")" "$(grep -v '^- Verified:' "$F" | cksum)"
# no final newline, anchor not last
newrepo
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
addent 2026-01-01 --title T2 --rule R2 --why w --evidence e --source user
printf '%s' "$(cat "$F")" > "$VS/nolf" && cat "$VS/nolf" > "$F"
git add -A >/dev/null 2>&1; git commit -q -m nolf
vr 2026-03-01 verify L-0001
assert_eq "AC5 no final LF, anchor not last, insert: still no final LF" "l" "$(lastbyte "$F")"
assert_eq "AC5 no final LF, insert: numstat 1 0" "1${TAB}0${TAB}.agents/LEARNINGS.md" "$(git diff --numstat)"
git add -A >/dev/null 2>&1; git commit -q -m nolf2
vr 2026-03-02 verify L-0001
assert_eq "AC5 no final LF, replace: still no final LF, numstat 1 1" "l|1${TAB}1${TAB}.agents/LEARNINGS.md" "$(lastbyte "$F")|$(git diff --numstat)"
# no final newline, anchor is the last line
newrepo
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
printf '%s' "$(cat "$F")" > "$VS/nolf" && cat "$VS/nolf" > "$F"
cp "$F" "$VS/before"
git add -A >/dev/null 2>&1; git commit -q -m nolf3
vr 2026-03-01 verify L-0001
{ cat "$VS/before"; printf '\n- Verified: 2026-03-01'; } > "$VS/exp"
assert_eq "AC5 anchor is the last line of an unterminated file: before + LF + new line, no final LF" "$(ck "$VS/exp")|1" "$(ck "$F")|$(lastbyte "$F")"
assert_eq "AC5 that case is numstat 2 1" "2${TAB}1${TAB}.agents/LEARNINGS.md" "$(git diff --numstat)"
# CRLF without a final LF
newrepo
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
crlf "$F"
printf '%s' "$(cat "$F")" > "$VS/crnolf" && cat "$VS/crnolf" > "$F"
cp "$F" "$VS/before"
vr 2026-03-01 verify L-0001
{ cat "$VS/before"; printf '\n- Verified: 2026-03-01\r'; } > "$VS/exp"
assert_eq "AC5 CRLF without final LF: old anchor ends CR LF, new line ends CR, no LF" "$(ck "$VS/exp")" "$(ck "$F")"
newrepo
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
crlf "$F"
printf '%s' "$(cat "$F")" > "$VS/crnolf" && cat "$VS/crnolf" > "$F"
SZ="$(wc -c < "$F" | tr -d ' ')"; head -c "$((SZ - 1))" "$F" > "$VS/before"; cat "$VS/before" > "$F"
vr 2026-03-01 verify L-0001
{ cat "$VS/before"; printf '\n- Verified: 2026-03-01'; } > "$VS/exp"
assert_eq "AC5 CRLF file whose last line has no CR: LF-only added line (recorded, not an error)" "$(ck "$VS/exp")" "$(ck "$F")"

echo "AC6 safe write"
SPD="$(mk_tmp)"
fix1
mv "$F" "$SPD/real.md"
ln -s "$SPD/real.md" "$F" 2>/dev/null
if [ -L "$F" ]; then
  vr 2026-11-10 verify L-0002
  assert_eq "AC6a the symlink is still a symlink" "link" "$([ -L "$F" ] && echo link || echo file)"
  assert_eq "AC6a the target has exactly one new Verified line" "1" "$(cnt '^- Verified: 2026-11-10$' "$SPD/real.md")"
else
  rm -f "$F"; t_skip 2 "AC6a symlinks cannot be created here"
fi
fix1
chmod 640 "$F" 2>/dev/null
if [ "$(ls -l "$F" | awk '{print $1}')" = "-rw-r-----" ]; then
  vr 2026-11-10 verify L-0002
  assert_eq "AC6b the file mode is unchanged by verify" "-rw-r-----" "$(ls -l "$F" | awk '{print $1}')"
else
  t_skip 1 "AC6b chmod has no effect here"
fi
REALAWK="$(command -v awk)"
STUB="$(mk_tmp)"; CNT="$STUB/count"
cat > "$STUB/awk" <<'EOS'
#!/bin/sh
echo x >> "$AWKCOUNT"
n=$(wc -l < "$AWKCOUNT" | tr -d ' ')
if [ -n "${FAILAT:-}" ] && [ "$n" = "$FAILAT" ]; then exit 1; fi
exec "$REALAWK" "$@"
EOS
chmod +x "$STUB/awk" 2>/dev/null
stubrun() { # FAILAT args... ; sets VO VE VRC NCALLS
  local fa="$1"; shift; : > "$CNT"
  VO="$(PATH="$STUB:$PATH" AWKCOUNT="$CNT" REALAWK="$REALAWK" FAILAT="$fa" PLAYBOOK_DATE=2026-11-10 TMPDIR="$VT" bash "$LEARN" "$@" 2>"$ERRF")"; VRC=$?
  VE="$(cat "$ERRF")"; NCALLS="$(nlines "$CNT")"
}
: > "$CNT"; PATH="$STUB:$PATH" AWKCOUNT="$CNT" REALAWK="$REALAWK" awk 'BEGIN{exit 0}' 2>/dev/null
if [ "$(nlines "$CNT")" -gt 0 ]; then
  fix1; cp "$F" "$VS/orig"
  stubrun "" verify L-0099; P="$NCALLS"
  stubrun "" verify L-0001; C="$NCALLS"; cp "$VS/orig" "$F"
  K0="$(ck "$F")"
  stubrun "$P" verify L-0001
  assert_eq "AC6c read phase fails: exit 3, cannot read" "3|error: cannot read .agents/LEARNINGS.md" "$VRC|$VE"
  assert_eq "AC6c read phase fails: file unchanged" "$K0" "$(ck "$F")"
  assert_eq "AC6c read phase fails: no temp file left" "empty" "$(vtmp)"
  assert_eq "AC6c read phase fails: stdout has no 'verified'" "" "$VO"
  stubrun "$C" verify L-0001
  assert_eq "AC6c write phase fails: exit 3, cannot write" "3|error: cannot write .agents/LEARNINGS.md" "$VRC|$VE"
  assert_eq "AC6c write phase fails: file unchanged" "$K0" "$(ck "$F")"
  assert_eq "AC6c write phase fails: no temp file left" "empty" "$(vtmp)"
  assert_eq "AC6c write phase fails: stdout has no 'verified'" "" "$VO"
else
  t_skip 8 "AC6c a stub awk cannot be run through PATH here"
fi

echo "AC7 line budget and entry cap"
newrepo; addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
assert_eq "AC7 setup: one fresh entry is 20 lines" "20" "$(nlines "$F")"
LEARN_MAX_ENTRIES=1 vr 2026-11-10 verify L-0001
assert_eq "AC7a LEARN_MAX_ENTRIES=1 with one active entry: verify exits 0" "0|verified L-0001" "$VRC|$VO"
newrepo; addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
LEARN_MAX_LINES=20 vr 2026-11-10 verify L-0001
assert_eq "AC7b insert past the budget: exit 0, stdout, exact warning" "0|verified L-0001|warning: 21 lines exceeds the 20-line budget (merge/retire entries)" "$VRC|$VO|$VE"
assert_eq "AC7b the line was added" "1" "$(cnt '^- Verified: 2026-11-10$' "$F")"
CK="$(LEARN_MAX_LINES=20 bash "$LEARN" check 2>&1)"; CKRC=$?
assert_eq "AC7b check: exit 1 and the exact problem line" "1|1" "$CKRC|$(printf '%s\n' "$CK" | grep -cxF 'problem: 21 lines exceeds the 20-line budget (merge/retire entries)')"
LEARN_MAX_LINES=20 vr 2026-11-12 verify L-0001
assert_eq "AC7d replace mode in a file already over budget: exit 0, no warning" "0|verified L-0001|" "$VRC|$VO|$VE"
newrepo; addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
LEARN_MAX_LINES=21 vr 2026-11-10 verify L-0001
assert_eq "AC7c insert to exactly the budget: exit 0, no warning" "0|verified L-0001|" "$VRC|$VO|$VE"
CK="$(LEARN_MAX_LINES=21 bash "$LEARN" check 2>&1)"; CKRC=$?
assert_eq "AC7c check at the same budget: exit 0" "0" "$CKRC"
newrepo
export LEARN_MAX_ENTRIES=2
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
addent 2026-01-01 --title T2 --rule R2 --why w --evidence e --source user
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" add --title T3 --rule R3 --why w --evidence e --source user >/dev/null 2>&1; A1=$?
vr 2026-11-10 verify L-0001
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" add --title T3 --rule R3 --why w --evidence e --source user >/dev/null 2>&1; A2=$?
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" retire L-0001 --reason x >/dev/null 2>&1
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" add --title T3 --rule R3 --why w --evidence e --source user >/dev/null 2>&1; A3=$?
unset LEARN_MAX_ENTRIES
assert_eq "AC7e the active cap is untouched by verify: add 5, verify, add 5, retire, add 0" "5|0|5|0" "$A1|$VRC|$A2|$A3"

echo "AC8 retire, add, candidate"
fix1
vr 2026-11-10 verify L-0001; snap
PLAYBOOK_DATE=2026-11-12 bash "$LEARN" retire L-0001 --reason x >/dev/null 2>&1
D="$(diff "$VS/before" "$F")"
assert_eq "AC8a retire changes only the Status line" "2|1|1" "$(printf '%s\n' "$D" | grep -c '^[<>]')|$(printf '%s\n' "$D" | grep -c '^< - Status: active$')|$(printf '%s\n' "$D" | grep -c '^> - Status: retired (x; 2026-11-12)$')"
assert_eq "AC8a the Verified line stays on the retired entry" "- Verified: 2026-11-10" "$(blk L-0001 | grep '^- Verified:')"
vr 2026-11-13 verify L-0001
assert_eq "AC8a verify of the retired entry: exit 2" "2|error: L-0001 is retired; verify applies to active entries" "$VRC|$VE"
fix1; K0="$(ck "$F")"
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" add --title T --rule 'Other rule.' --why w --evidence e --source user --verified 2026-01-01 >/dev/null 2>"$ERRF"; ARC=$?
assert_eq "AC8b add --verified: exit 2, unknown option, file unchanged" "2|error: unknown option: --verified|same" "$ARC|$(cat "$ERRF")|$(same "$K0" "$(ck "$F")")"
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" candidate add --title T --rule 'Cand rule.' --why w --evidence e --source user --verified x >/dev/null 2>"$ERRF"; ARC=$?
assert_eq "AC8b candidate add --verified: exit 2, unknown option, file unchanged" "2|error: unknown option: --verified|same" "$ARC|$(cat "$ERRF")|$(same "$K0" "$(ck "$F")")"
assert_eq "AC8c entries made by add have no Verified line" "0" "$(cnt '^- Verified:' "$F")"
newrepo; RA="$R"
PLAYBOOK_DATE=2026-10-09 bash "$LEARN" add --title 'Twin title' --rule 'Twin rule.' --why 'Twin why.' --evidence 'Twin evidence' --source review --scope 'lib/**' --role reviewer >/dev/null 2>&1
newrepo; RB="$R"
PLAYBOOK_DATE=2026-10-09 bash "$LEARN" candidate add --title 'Twin title' --rule 'Twin rule.' --why 'Twin why.' --evidence 'Twin evidence' --source review --scope 'lib/**' --role reviewer >/dev/null 2>&1
PLAYBOOK_DATE=2026-10-09 bash "$LEARN" candidate promote C-0001 >/dev/null 2>&1
assert_eq "AC8d twin: add and candidate add + promote give byte-identical files without Verified" "same|0" "$(same "$(ck "$RA/$F")" "$(ck "$RB/$F")")|$(cnt Verified "$RB/$F")"
newrepo
CAND=.agents/handoff/learn-candidates.md
PLAYBOOK_DATE=2026-10-09 bash "$LEARN" candidate add --title 'Cand title' --rule 'Cand rule.' --why w --evidence e --source user --role tester >/dev/null 2>&1
insafter C-0001 '- Role:' '- Verified: 2026-01-01' "$CAND"
cp "$CAND" "$VS/cand_before"
PLAYBOOK_DATE=2026-10-09 bash "$LEARN" candidate promote C-0001 >/dev/null 2>&1; PRC=$?
D="$(diff "$VS/cand_before" "$CAND")"
assert_eq "AC8e promote ignores a hand-made Verified line: exit 0, entry without it" "0|0" "$PRC|$(cnt Verified "$F")"
assert_eq "AC8e the candidate file differs by exactly its Status line" "2|1|1|1" "$(printf '%s\n' "$D" | grep -c '^[<>]')|$(printf '%s\n' "$D" | grep -c '^< - Status:')|$(printf '%s\n' "$D" | grep -c '^> - Status:')|$(cnt '^- Verified: 2026-01-01$' "$CAND")"
assert_eq "AC8f the shared S4 functions never mention Verified" "0" "$(awk '/^# S4-BEGIN/ { on = 1; next } /^# S4-END/ { on = 0 } on' "$PB_ROOT/scripts/learn.sh" | grep -c Verified || true)"

echo "AC9 stale ages from Verified"
stl() { local d="$1"; shift; SO="$(PLAYBOOK_DATE="$d" bash "$LEARN" stale "$@" 2>"$ERRF")"; SRC=$?; SE="$(cat "$ERRF")"; }
SUM1='stale: 1 of 1 active entries listed (older than 180 days)'
SUM0='stale: 0 of 1 active entries listed (older than 180 days)'
one1; vr 2026-03-01 verify L-0001; stl 2026-11-17
assert_eq "AC9a verified 2026-03-01: 261 days since verified" "0|$(printf 'L-0001 · 2026-01-01 · T1: 261 days since verified 2026-03-01\n%s' "$SUM1")" "$SRC|$SO"
one1; vr 2026-08-01 verify L-0001; stl 2026-11-17
assert_eq "AC9a verified 2026-08-01 (108 days): not listed" "$SUM0" "$SO"
one1; vr 2026-05-21 verify L-0001; stl 2026-11-17
assert_eq "AC9b exactly 180 days: not listed" "$SUM0" "$SO"
one1; vr 2026-05-20 verify L-0001; stl 2026-11-17
assert_eq "AC9b 181 days: listed" "$(printf 'L-0001 · 2026-01-01 · T1: 181 days since verified 2026-05-20\n%s' "$SUM1")" "$SO"
one1; vr 2026-11-10 verify L-0001; stl 2026-11-17 --days 6
assert_eq "AC9b --days 6 lists a 7-day-old verification" "$(printf 'L-0001 · 2026-01-01 · T1: 7 days since verified 2026-11-10\nstale: 1 of 1 active entries listed (older than 6 days)')" "$SO"
stl 2026-11-17 --days 7
assert_eq "AC9b --days 7 does not" "stale: 0 of 1 active entries listed (older than 7 days)" "$SO"
OLD="$(printf 'L-0001 · 2026-01-01 · T1: 320 days old\n%s' "$SUM1")"
for BADV in '- Verified: soon' '- Verified: 2026-02-30' '- Verified: 2026-11-10 x' '- Verified:2026-11-10'; do
  one1; insafter L-0001 '- Role:' "$BADV"; stl 2026-11-17
  assert_eq "AC9c '$BADV' falls back to the heading date (old wording)" "$OLD" "$SO"
done
one1; insafter L-0001 '- Role:' "$(printf -- '- Verified: soon\n- Verified: 2026-11-10')"; stl 2026-11-17
assert_eq "AC9c the second Verified line is ignored" "$OLD" "$SO"
one1; insafter L-0001 '- Status:' '- Verified: 2026-03-01'; stl 2026-11-17
assert_eq "AC9d Verified before Scope/Role gives the same result" "$(printf 'L-0001 · 2026-01-01 · T1: 261 days since verified 2026-03-01\n%s' "$SUM1")" "$SO"
one1; insafter L-0001 '- Role:' '- Verified: 2025-12-01'; stl 2026-11-17
assert_eq "AC9d Verified earlier than the heading date still counts as written (351)" "$(printf 'L-0001 · 2026-01-01 · T1: 351 days since verified 2025-12-01\n%s' "$SUM1")" "$SO"
one1; insafter L-0001 '- Role:' '- Verified: 2026-12-01'; stl 2026-11-17
assert_eq "AC9d a future Verified date is not listed" "$SUM0" "$SO"
newrepo
printf '\n### L-0007 foo\n- Status: active\n- Rule: R7\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: project-wide\n- Role: all\n- Verified: 2026-03-01\n' >> "$F"
stl 2026-11-17
assert_eq "AC9e unusable heading with a valid Verified: aged from Verified" "0|1|1" "$SRC|$(printf '%s\n' "$SO" | grep -c '261 days since verified 2026-03-01')|$(printf '%s\n' "$SO" | grep -cxF "$SUM1")"
newrepo
printf '\n### L-0007 foo\n- Status: active\n- Rule: R7\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: project-wide\n- Role: all\n' >> "$F"
stl 2026-11-17
assert_eq "AC9e unusable heading without Verified: no age" "0|0|1" "$SRC|$(printf '%s\n' "$SO" | grep -c 'days old\|days since')|$(printf '%s\n' "$SO" | grep -cxF "$SUM0")"
one1; PLAYBOOK_DATE=2026-01-02 bash "$LEARN" retire L-0001 --reason x >/dev/null 2>&1
insafter L-0001 '- Role:' '- Verified: 2026-01-05'; stl 2026-11-17
assert_eq "AC9f a retired entry is never listed" "stale: 0 of 0 active entries listed (older than 180 days)" "$SO"
newrepo; addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user --scope 'nope/**'
vr 2026-03-01 verify L-0001; stl 2026-11-17
assert_eq "AC9g the scope reason follows the Verified age" "$(printf 'L-0001 · 2026-01-01 · T1: 261 days since verified 2026-03-01; scope matches no tracked file\n%s' "$SUM1")" "$SO"
one1; vr 2026-03-01 verify L-0001; stl 2026-11-17; LFOUT="$SO"
K0="$(ck "$F")"; LS0="$(git ls-files -s)"; stl 2026-11-17
assert_eq "AC9i stale is read-only" "same|same" "$(same "$K0" "$(ck "$F")")|$(same "$LS0" "$(git ls-files -s)")"
crlf "$F"; stl 2026-11-17
assert_eq "AC9i a CRLF file gives the same result as the LF file" "$LFOUT" "$SO"

echo "AC10 checklist"
G1="$(printf -- '- [ ] R1 (L-0001, scope: src/**)\n- [ ] R2 (L-0002, scope: project-wide)\n- [ ] R3 (L-0003, scope: project-wide)')"
G2="$(printf -- '- [ ] R2 (L-0002, scope: project-wide)\n- [ ] R3 (L-0003, scope: project-wide)')"
cl() { CO="$(bash "$LEARN" checklist "$@" 2>"$ERRF")"; CRC=$?; CE="$(cat "$ERRF")"; }
fix1; vr 2026-11-10 verify L-0001; vr 2026-11-12 verify L-0003
cl tester;      assert_eq "AC10a default tester output ignores Verified" "$G1" "$CO"
cl implementer; assert_eq "AC10a default implementer output" "$G2" "$CO"
cl reviewer;    assert_eq "AC10a default reviewer output" "$G2" "$CO"
cl tester --dates
assert_eq "AC10b tester --dates" "$(printf -- '- [ ] R1 (L-0001, scope: src/**, verified 2026-11-10)\n- [ ] R2 (L-0002, scope: project-wide, added 2026-01-01)\n- [ ] R3 (L-0003, scope: project-wide, verified 2026-11-12)')" "$CO"
cl implementer --dates
assert_eq "AC10b implementer --dates" "$(printf -- '- [ ] R2 (L-0002, scope: project-wide, added 2026-01-01)\n- [ ] R3 (L-0003, scope: project-wide, verified 2026-11-12)')" "$CO"
K0="$(ck "$F")"; cl tester --dates
assert_eq "AC10g --dates is read-only" "$K0" "$(ck "$F")"
cl tester --dates --dates
assert_eq "AC10f --dates twice is the same as once" "0|$(printf -- '- [ ] R1 (L-0001, scope: src/**, verified 2026-11-10)\n- [ ] R2 (L-0002, scope: project-wide, added 2026-01-01)\n- [ ] R3 (L-0003, scope: project-wide, verified 2026-11-12)')" "$CRC|$CO"
fix1
insafter L-0001 '- Role:' "$(printf -- '- Verified: 2026-11-10\n- Verified: 2026-11-01')"
insafter L-0002 '- Role:' "$(printf -- '- Verified: soon\n- Verified: 2026-11-10')"
cl tester --dates
assert_eq "AC10c the first Verified line wins; a malformed first line falls back to 'added'" "$(printf -- '- [ ] R1 (L-0001, scope: src/**, verified 2026-11-10)\n- [ ] R2 (L-0002, scope: project-wide, added 2026-01-01)\n- [ ] R3 (L-0003, scope: project-wide, added 2026-02-02)')" "$CO"
newrepo
printf '\n### L-0007 foo\n- Status: active\n- Rule: R7\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: project-wide\n- Role: all\n\n### L-0008 bar\n- Status: active\n- Rule: R8\n- Why: w\n- Evidence: e\n- Source: user\n- Scope: project-wide\n- Role: all\n- Verified: 2026-03-01\n' >> "$F"
cl implementer
assert_eq "AC10c default mode with unusable headings" "$(printf -- '- [ ] R7 (L-0007, scope: project-wide)\n- [ ] R8 (L-0008, scope: project-wide)')" "$CO"
cl implementer --dates
assert_eq "AC10c unusable heading: no suffix without Verified, 'verified' with it" "$(printf -- '- [ ] R7 (L-0007, scope: project-wide)\n- [ ] R8 (L-0008, scope: project-wide, verified 2026-03-01)')" "$CO"
newrepo
cl tester --dates
assert_eq "AC10d an empty file with --dates: the old words" "0|no learnings for tester" "$CRC|$CO"
fix1; PLAYBOOK_DATE=2026-01-01 bash "$LEARN" retire L-0001 --reason x >/dev/null 2>&1
insafter L-0001 '- Role:' '- Verified: 2026-11-10'
cl tester --dates
assert_eq "AC10d a retired entry is never listed" "$(printf -- '- [ ] R2 (L-0002, scope: project-wide, added 2026-01-01)\n- [ ] R3 (L-0003, scope: project-wide, added 2026-02-02)')" "$CO"
fix1; crlf "$F"; vr 2026-11-12 verify L-0003
cl tester; assert_eq "AC10e CRLF default: exactly one line (L-0003)" "1" "$(printf '%s\n' "$CO" | wc -l | tr -d ' ')"
EXP="$(printf -- '- [ ] R3\r (L-0003, scope: project-wide\r, verified 2026-11-12)')"
cl tester --dates
assert_eq "AC10e CRLF --dates: the suffix sits after the CR and holds none" "$EXP" "$CO"
cl implementer; assert_eq "AC10e CRLF implementer: exactly one line" "1" "$(printf '%s\n' "$CO" | wc -l | tr -d ' ')"
grep -v '^- Verified:' "$F" > "$VS/nov" && cat "$VS/nov" > "$F"
cl tester --dates
assert_eq "AC10e CRLF without Verified: 'added' from the heading" "$(printf -- '- [ ] R3\r (L-0003, scope: project-wide\r, added 2026-02-02)')" "$CO"
fix1
cl --dates tester;      assert_eq "AC10f --dates before the role: the old usage error" "2|error: usage: learn.sh checklist tester|implementer|reviewer|" "$CRC|$CE|$CO"
for BADA in --bogus extra; do
  cl tester "$BADA"
  assert_eq "AC10f checklist tester $BADA: exit 2, unknown option, empty stdout" "2|error: unknown option: $BADA (usage: learn.sh checklist ROLE [--dates])|" "$CRC|$CE|$CO"
done
for BADR in janitor Tester; do
  cl "$BADR"
  assert_eq "AC10f checklist $BADR: the old usage message" "2|error: usage: learn.sh checklist tester|implementer|reviewer|" "$CRC|$CE|$CO"
done
cl
assert_eq "AC10f checklist without a role: the old usage message" "2|error: usage: learn.sh checklist tester|implementer|reviewer|" "$CRC|$CE|$CO"
rm -f "$F"
cl tester --bogus
assert_eq "AC10f argument parsing comes before the file check (--bogus, no file)" "2|error: unknown option: --bogus (usage: learn.sh checklist ROLE [--dates])|" "$CRC|$CE|$CO"
cl tester extra
assert_eq "AC10f argument parsing comes before the file check (extra, no file)" "2|error: unknown option: extra (usage: learn.sh checklist ROLE [--dates])|" "$CRC|$CE|$CO"
cl tester
assert_eq "AC10f no file, no extra argument: not found, as today" "2|error: .agents/LEARNINGS.md not found|" "$CRC|$CE|$CO"

echo "AC11 check"
CKV() { CKO="$(bash "$LEARN" check 2>/dev/null)"; CKRC=$?; }
fix1; vr 2026-11-10 verify L-0001; vr 2026-11-12 verify L-0003
CKV
assert_eq "AC11b two verified entries: the summary counts the added lines, exit 0, no problem" "0|learnings: 3 active, 1 retired, 48 lines (.agents/LEARNINGS.md); entry lines: 28 active, 8 retired" "$CKRC|$CKO"
fix1
insafter L-0001 '- Role:' '- Verified: 2026-11-10'
insafter L-0003 '- Scope:' '- Verified: 2026-11-12'
insafter L-0004 '- Role:' '- Verified: 2026-11-13'
CKV
assert_eq "AC11b Verified on active, retired and old entries: exit 0, no problem, exact summary" "0|learnings: 3 active, 1 retired, 49 lines (.agents/LEARNINGS.md); entry lines: 28 active, 9 retired" "$CKRC|$CKO"
HDR='problem: malformed Verified line(s) (one "- Verified: YYYY-MM-DD" per entry):'
for BADV in '- Verified: soon' '- Verified: 2026-1-5' '- Verified:2026-11-10' '- Verified: 2026-11-10 x' '- Verified:'; do
  one1; insafter L-0001 '- Role:' "$BADV"; CKV
  assert_eq "AC11c '$BADV': exit 1, header line, the bad line indented" "1|1|1" "$CKRC|$(printf '%s\n' "$CKO" | grep -cxF "$HDR")|$(printf '%s\n' "$CKO" | grep -cxF "  $BADV")"
done
one1; insafter L-0001 '- Role:' "$(printf -- '- Verified: 2026-11-10\n- Verified: 2026-11-11')"; CKV
assert_eq "AC11c two valid Verified lines in one entry: exit 1, named with its heading" "1|1" "$CKRC|$(printf '%s\n' "$CKO" | grep -cxF '  ### L-0001 · 2026-01-01 · T1 (more than one Verified line)')"
one1; { head -n 1 "$F"; echo '- Verified: x'; tail -n +2 "$F"; } > "$VS/hdr" && cat "$VS/hdr" > "$F"; CKV
assert_eq "AC11c a '- Verified: x' line in the header comment is not counted" "0|0" "$CKRC|$(printf '%s\n' "$CKO" | grep -c 'malformed Verified')"
newrepo
addent 2026-01-01 --title T1 --rule R1 --why w --evidence e --source user
addent 2026-01-01 --title T2 --rule R2 --why w --evidence e --source user
awk '/^- Role: all$/ && !d { print "- Role: janitor"; d = 1; next } { print }' "$F" > "$VS/rl" && cat "$VS/rl" > "$F"
insafter L-0002 '- Role:' '- Verified: soon'
CKO="$(LEARN_MAX_ENTRIES=1 LEARN_MAX_LINES=10 bash "$LEARN" check 2>/dev/null)"; CKRC=$?
ln_of() { printf '%s\n' "$CKO" | grep -nE -e "$1" | head -n 1 | cut -d: -f1; }
LA="$(ln_of '^problem: [0-9]+ lines exceeds')"; LB="$(ln_of '^problem: unknown Role')"; LC="$(ln_of '^problem: malformed Verified')"; LD="$(ln_of '^problem: 2 active entries exceeds the cap of 1')"; LE="$(ln_of '^learnings: ')"
ORD=bad; if [ -n "$LA" ] && [ -n "$LB" ] && [ -n "$LC" ] && [ -n "$LD" ] && [ -n "$LE" ] && [ "$LA" -lt "$LB" ] && [ "$LB" -lt "$LC" ] && [ "$LC" -lt "$LD" ] && [ "$LD" -lt "$LE" ]; then ORD=ok; fi
assert_eq "AC11d output order: lines budget, Role, Verified, active cap, summary" "ok|1" "$ORD|$CKRC"
assert_eq "AC11d each problem is printed once" "1 1 1 1" "$(printf '%s\n' "$CKO" | grep -c '^problem: [0-9]* lines exceeds') $(printf '%s\n' "$CKO" | grep -c '^problem: unknown Role') $(printf '%s\n' "$CKO" | grep -c '^problem: malformed Verified') $(printf '%s\n' "$CKO" | grep -c '^problem: 2 active entries')"
K0="$(ck "$F")"; CKV
assert_eq "AC11e check is read-only" "$K0" "$(ck "$F")"

echo "AC12 the hook is unchanged and prints the Verified line"
assert_eq "AC12 the hook never names Verified" "0" "$(cnt Verified "$HOOK")"
assert_eq "AC12 the hook is byte-identical to the one before the slice (cksum)" "2274795459 8653" "$(cksum < "$HOOK" | awk '{ print $1 " " $2 }')"
fix1; vr 2026-11-10 verify L-0001
insafter L-0004 '- Role:' '- Verified: 2026-11-11'
K0="$(ck "$F")"; LSA="$(ls -A .agents | tr '\n' ' ')"
HO="$(CLAUDE_PROJECT_DIR="$R" bash "$HOOK" --eval </dev/null 2>/dev/null)"
assert_eq "AC12 the hook output has the verified line once and not the retired one" "1|0" "$(printf '%s\n' "$HO" | grep -cxF -e '- Verified: 2026-11-10')|$(printf '%s\n' "$HO" | grep -cxF -e '- Verified: 2026-11-11')"
printf '%s\n' "$HO" > "$VS/hookout"
assert_eq "AC12 the block of L-0001 in the output equals the block in the file" "$(blk L-0001 | cksum)" "$(blk L-0001 "$VS/hookout" | cksum)"
assert_eq "AC12 the Verified line follows the Role line of its entry in the output" "- Role: tester" "$(prevline L-0001 "$VS/hookout")"
assert_eq "AC12 the hook changed no file" "same|$LSA" "$(same "$K0" "$(ck "$F")")|$(ls -A .agents | tr '\n' ' ')"

echo "AC13 usage and static markers"
USE="$(bash "$LEARN" bogus 2>&1 >/dev/null)"
assert_contains "AC13 usage lists verify last" "$USE" "init|add|retire|check|checklist|stale|candidate|trust|untrust|trusted|verify"
assert_eq "AC13 BEGIN and END markers at column 0 are equal in number and at least one" "ok" "$(awk '/^# S3-BEGIN/ { b++ } /^# S3-END/ { e++ } END { print (b == e && b >= 1) ? "ok" : "bad " b+0 " " e+0 }' "$LEARN")"
VL="$(grep -nE '^  verify\)' "$LEARN" | head -n 1 | cut -d: -f1)"
BL="$(grep -n '^# S3-BEGIN' "$LEARN" | head -n 1 | cut -d: -f1)"
EL="$(grep -n '^# S3-END' "$LEARN" | head -n 1 | cut -d: -f1)"
SC=""; if [ -n "$VL" ]; then SC="$(awk -v s="$VL" 'NR > s && /^    ;;$/ { print NR; exit }' "$LEARN")"; fi
OKM=bad; if [ -n "$VL" ] && [ -n "$BL" ] && [ -n "$EL" ] && [ -n "$SC" ] && [ "$BL" -eq $((VL - 1)) ] && [ "$EL" -eq $((SC + 1)) ]; then OKM=ok; fi
assert_eq "AC13 S3-BEGIN sits right before '  verify)' and S3-END right after its ';;'" "ok" "$OKM"
assert_eq "AC13 exactly one '  verify)' branch" "1" "$(grep -cE '^  verify\)' "$LEARN" || true)"
assert_eq "AC13 no eval, bash -c or sh -c between the S3 markers" "0" "$(awk '/^# S3-BEGIN/ { on = 1; next } /^# S3-END/ { on = 0 } on' "$LEARN" | grep -cE '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|bash -c|sh -c' || true)"
assert_eq "AC13 the head comment names verify and 'checklist ROLE [--dates]'" "1|1" "$(sed -n '1,40p' "$LEARN" | grep -c 'verify' | awk '{ print ($1 > 0) }')|$(sed -n '1,40p' "$LEARN" | grep -cF 'checklist ROLE [--dates]' | awk '{ print ($1 > 0) }')"
assert_eq "AC20 learn.sh has none of the non-portable constructs" "0" "$(grep -cE 'local -n|\$\{[A-Za-z_]+,,\}|mapfile|readarray|flock|readlink -f|sed -[i] ' "$LEARN" || true)"

echo "AC14 text is data, never shell"
newrepo
RULE='Use $(touch PWNED2) and `touch PWNED2` and "dq" and '"'"'sq'"'"' and \ and *'
WHY='Why $(touch PWNED2) `touch PWNED2` "dq" '"'"'sq'"'"' \ *'
EVID='Ev $(touch PWNED2) `touch PWNED2` "dq" '"'"'sq'"'"' \ *'
PLAYBOOK_DATE=2026-01-01 bash "$LEARN" add --title 'Inject $(touch PWNED2)' --rule "$RULE" --why "$WHY" --evidence "$EVID" --source user >/dev/null 2>&1
snap
vr 2026-03-01 verify L-0001
VRC1="$VRC"
stl 2026-11-17
CLRC="$(bash "$LEARN" checklist implementer --dates >/dev/null 2>&1; echo $?)"
LEFT=""; for D in . .agents; do [ ! -e "$D/PWNED2" ] || LEFT="$LEFT $D/PWNED2"; done
assert_eq "AC14 verify, stale and checklist --dates ran and created no PWNED2" "0|0|0|" "$VRC1|$SRC|$CLRC|$LEFT"
assert_eq "AC14 every other line of the entry is byte-for-byte unchanged" "$(ck "$VS/before")" "$(grep -v '^- Verified:' "$F" | cksum)"
SP="$(mk_tmp)/a b"; mkdir -p "$SP"
VO="$(PLAYBOOK_DATE=2026-03-02 TMPDIR="$SP" bash "$LEARN" verify L-0001 2>"$ERRF")"; VRC=$?
assert_eq "AC14 a TMPDIR with a space works and leaves nothing behind" "0|verified L-0001|0" "$VRC|$VO|$(ls -A "$SP" | wc -l | tr -d ' ')"

echo "AC15 SKILL.md text"
flat() { if [ -f "$1" ]; then tr '\n' ' ' < "$1" | tr -s ' '; fi; }
has() { if printf '%s\n' "$2" | grep -qiE -e "$3"; then t_ok "$1"; else t_bad "$1" "no match for: $3"; fi; }
hasF() { if printf '%s\n' "$2" | grep -qF -e "$3"; then t_ok "$1"; else t_bad "$1" "missing text: $3"; fi; }
hasnt() {
  if [ ! -f "$4" ]; then t_bad "$1" "file missing: $4"; return; fi
  if printf '%s\n' "$2" | grep -qiE -e "$3"; then t_bad "$1" "unexpected match for: $3"; else t_ok "$1"; fi
}
SF="$(flat "$SK")"; RF="$(flat "$RV")"
SW="$(wc -w < "$SK" | tr -d ' ')"
if [ "$SW" -le 700 ]; then t_ok "AC15a SKILL.md is at most 700 words ($SW)"; else t_bad "AC15a SKILL.md is at most 700 words" "got $SW"; fi
assert_eq "AC15a word-budgets has exactly one playbook-learn line, 700" "1 700" "$(awk '$1 == "skills/playbook-learn/SKILL.md" { n++; v = $2 } END { print n + 0, v }' "$PB_ROOT/evals/word-budgets")"
if grep 'TW_LW' "$PB_ROOT/tests/test-content.sh" | grep -q -e '-le 700'; then t_ok "AC15a test-content.sh keeps the -le 700 ceiling"; else t_bad "AC15a test-content.sh keeps the -le 700 ceiling"; fi
has "AC15b names verify L-0007" "$SF" 'verify L-0007'
has "AC15b stale ages from the verify date" "$SF" 'stale[^.]{0,40}ages from'
has "AC15b verify needs the user's confirmation" "$SF" 'user confirms[^.]{0,80}verify|verify[^.]{0,120}user'
hasF "AC15b the line budget sentence counts Role and Verified" "$SF" 'Every line, `- Role:` and `- Verified:` included, counts toward the line budget'
hasnt "AC15b the old 'It is written as' sentence is gone" "$SF" 'It is written as' "$SK"
assert_eq "AC15c exactly one line names references/candidates.md and one names references/review.md" "1|1" "$(grep -c 'references/candidates\.md' "$SK")|$(grep -c 'references/review\.md' "$SK")"
assert_eq "AC15c '## Review' is the last section" "## Review" "$(grep '^## ' "$SK" | tail -n 1)"
SECW="$(awk '/^## Review/ { on = 1 } on { print }' "$SK" | wc -w | tr -d ' ')"
if [ "$SECW" -ge 1 ] && [ "$SECW" -le 40 ]; then t_ok "AC15c the Review section is 1..40 words ($SECW)"; else t_bad "AC15c the Review section is 1..40 words" "got $SECW"; fi
SL="$(wc -l < "$SK" | tr -d ' ')"
if [ "$SL" -le 300 ]; then t_ok "AC15c SKILL.md is at most 300 lines ($SL)"; else t_bad "AC15c SKILL.md is at most 300 lines" "got $SL"; fi
MISS=""
for P in $(grep -Eo '(references|roles|templates)/[A-Za-z0-9._-]+\.md' "$SK" | sort -u); do [ -f "$SKDIR/$P" ] || MISS="$MISS $P"; done
assert_eq "AC15c every file named in SKILL.md exists" "" "$MISS"
assert_eq "AC15c SKILL.md is printable ASCII only" "0" "$(LC_ALL=C grep -c '[^ -~]' "$SK" || true)"
assert_eq "AC15d no SKILL.md line starts with a stray dot" "0" "$(grep -cE '^[[:space:]]*\.[[:space:]]' "$SK" || true)"
hasnt "AC15e a non-interactive run never promotes or drops" "$SF" 'non-interactive[^.]{0,120}(promote|drop)' "$SK"
if [ -z "${PB_SKILL_MD:-}" ] && [ -z "${PB_REVIEW_MD:-}" ]; then
  run bash "$PB_ROOT/evals/run-checks.sh" --only skills
  assert_rc "AC15f evals/run-checks.sh --only skills is green" 0
  run bash "$PB_ROOT/evals/run-checks.sh" --only budgets
  assert_rc "AC15f evals/run-checks.sh --only budgets is green" 0
else
  t_skip 2 "AC15f run-checks (a scratch copy is under test)"
fi

echo "AC16 review.md text"
RW=0; if [ -f "$RV" ]; then RW="$(wc -w < "$RV" | tr -d ' ')"; fi
if [ "$RW" -ge 200 ] && [ "$RW" -le 700 ]; then t_ok "AC16a review.md has 200..700 words ($RW)"; else t_bad "AC16a review.md has 200..700 words" "got $RW"; fi
assert_eq "AC16a review.md is printable ASCII only" "0" "$(LC_ALL=C grep -c '[^ -~]' "$RV" || true)"
has "AC16b names the command" "$RF" '\$L verify L-'
hasF "AC16b the exact no-write sentence lists verify" "$RF" 'Run no init, add, retire, verify, trust or untrust while you review.'
hasF "AC16b the Stale entries line says 'still true, verify'" "$RF" 'still true, verify'
assert_eq "AC16b the VERIFY label line carries the command" "1" "$(grep -cE '^- VERIFY:.*verify L-NNNN' "$RV" || true)"
assert_eq "AC16b the VERIFY label line asks for the user's confirmation first" "1" "$(grep -cE '^- VERIFY:[^.]{0,80}(if|once|after)[^.]{0,40}user confirms[^.]{0,40}verify L-NNNN' "$RV" || true)"
hasnt "AC16b no 'verify command exists yet'" "$RF" 'no verify command exists yet' "$RV"
hasnt "AC16b no 'no verify command' stopgap" "$RF" 'no (learn\.sh )?verify command' "$RV"
assert_eq "AC16c exactly four label lines" "4" "$(grep -cE '^- (MERGE|RETIRE|REWRITE|VERIFY):' "$RV" || true)"
has "AC16c VERIFY keeps a read-only check" "$RF" 'git ls-files|grep'
has "AC16c a wrong entry still leads to retire" "$RF" '(wrong|incorrect|no longer (true|valid|holds)|outdated|false).{0,200}retire'
has "AC16c commands wait for the user's approval of each item" "$RF" "Never run an item's commands until the user approves that item"
assert_eq "AC16d review.md never says 'Verified' in capitals" "0" "$(grep -cF 'Verified' "$RV" || true)"

cd "$PB_ROOT" || exit 3
t_summary
