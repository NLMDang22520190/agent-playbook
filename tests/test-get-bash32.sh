#!/usr/bin/env bash
# Tests for tools/get-bash32.sh (v0.23.0 AC4.1): build bash 3.2.57 from the GNU tarball into ~/.local/bin/bash3.2 so
# tools/bsd-check.sh can run the suites under the bash macOS ships.
# Nothing here touches the network or the real home: HOME is a mk_tmp dir, the source is a file:// fixture tarball whose
# sha256 the test passes in PB_BASH32_SHA256 (accepted only together with a file:// source), and a fake cc/make on PATH
# "builds" by writing a script. The real $HOME/.local/bin/bash3.2 is recorded before and after and must not change (E3).
#   PB_BASH32_SRC     file:///path/to/bash-3.2.57.tar.gz   (the tarball itself)
#   PB_BASH32_SHA256  its sha256 (only with a file:// source)
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/get-bash32.sh"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) t_skip 40 "AC4.1 get-bash32 cases need a bare PATH (not possible on Git Bash)"; t_summary; exit $? ;;
esac

REAL_HOME="$HOME"
real_state() { # state of the real bash3.2: absent, or checksum + size + mtime
  local f="$REAL_HOME/.local/bin/bash3.2"
  if [ -e "$f" ] || [ -L "$f" ]; then printf 'present %s %s\n' "$(cksum < "$f" 2>/dev/null)" "$(ls -ld "$f" 2>/dev/null)"; else echo absent; fi
}
REAL_BEFORE="$(real_state)"
W="$(mk_tmp)"

sha_of() { # FILE -> sha256 hex
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

echo "AC4.1 the tool exists and documents its pin"
assert_file "AC4.1 tools/get-bash32.sh exists" "$TOOL"
SCRIPT="$(cat "$TOOL" 2>/dev/null)"
HDR="$(grep '^#' "$TOOL" 2>/dev/null)"
assert_contains "AC4.1 it names the GNU source (bash-3.2.57.tar.gz)" "$SCRIPT" "bash-3.2.57.tar.gz"
assert_contains "AC4.1 it names https://ftp.gnu.org/gnu/bash/" "$SCRIPT" "https://ftp.gnu.org/gnu/bash/"
if printf '%s\n' "$SCRIPT" | grep -Eq '(^|[^0-9a-fA-F])[0-9a-f]{64}([^0-9a-fA-F]|$)'; then t_ok "AC4.1 a pinned sha256 (64 hex digits) is in the script"; else t_bad "AC4.1 a pinned sha256 (64 hex digits) is in the script" "no 64-hex constant found in $TOOL"; fi
assert_contains "AC4.1 header: the keyring URL" "$HDR" "https://ftp.gnu.org/gnu/gnu-keyring.gpg"
assert_contains "AC4.1 header: the .sig file" "$HDR" ".sig"
assert_contains "AC4.1 header: gpg verification step" "$HDR" "gpg"
assert_contains "AC4.1 header: says the pin is the sha256 of the tarball" "$(printf '%s' "$HDR" | tr 'A-Z' 'a-z')" "sha256"
assert_contains "AC4.1 CFLAGS has -std=gnu89" "$SCRIPT" "-std=gnu89"
for f in implicit-function-declaration implicit-int int-conversion incompatible-pointer-types; do
  assert_contains "AC4.1 CFLAGS has -Wno-error=$f" "$SCRIPT" "-Wno-error=$f"
done
assert_contains "AC4.1 it installs to .local/bin/bash3.2" "$SCRIPT" "bash3.2"

# ---- fixture: a tarball, a fake cc and make, a bare PATH ----
FX="$W/fx"; mkdir -p "$FX/src/bash-3.2.57"
cat > "$FX/src/bash-3.2.57/configure" <<'CFG'
#!/bin/sh
# fake configure: records how it was called
echo "configure args: $* CFLAGS=${CFLAGS:-}" >> "${FAKE_LOG:-/dev/null}"
echo "all:" > Makefile
exit 0
CFG
chmod +x "$FX/src/bash-3.2.57/configure"
( cd "$FX/src" && tar -czf "$FX/bash-3.2.57.tar.gz" bash-3.2.57 )
: > "$FX/bash-3.2.57.tar.gz.sig"
GOODSHA="$(sha_of "$FX/bash-3.2.57.tar.gz")"
SRC="file://$FX/bash-3.2.57.tar.gz"

FAKEBIN="$W/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/cc" <<'CC'
#!/bin/sh
echo "cc $* CFLAGS=${CFLAGS:-}" >> "${FAKE_LOG:-/dev/null}"
exit 0
CC
cat > "$FAKEBIN/make" <<'MK'
#!/bin/sh
echo "make $* CFLAGS=${CFLAGS:-}" >> "${FAKE_LOG:-/dev/null}"
d=.
while [ $# -gt 0 ]; do case "$1" in -C) d="$2"; shift ;; esac; shift; done
cd "$d" || exit 1
printf '#!/bin/sh\necho "GNU bash, version 3.2.57(1)-release (fake)"\n' > bash
chmod +x bash
exit 0
MK
cat > "$FAKEBIN/curl" <<'CU'
#!/bin/sh
echo "curl $*" >> "${NET_LOG:-/dev/null}"
exit 22
CU
cp "$FAKEBIN/curl" "$FAKEBIN/wget"
chmod +x "$FAKEBIN/cc" "$FAKEBIN/make" "$FAKEBIN/curl" "$FAKEBIN/wget"

# BARE: the basic tools only; no cc, gcc, make, curl, wget unless a case adds them
BARE="$W/bare"; mkdir -p "$BARE"
for t in dirname basename mktemp rm ln cat mkdir cp chmod sed grep tr head tail uname env sh bash cut wc sort ls rmdir true false sleep \
         tar gzip gunzip sha256sum shasum openssl mv awk date printf od find id readlink touch uniq tee dd expr install cmp xargs pwd stat; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in /*) ln -s "$p" "$BARE/$t" 2>/dev/null || cp "$p" "$BARE/$t" 2>/dev/null ;; esac
done

# fresh_home NAME -> a HOME for a case (no bash3.2 in it)
fresh_home() { local h="$W/home-$1"; mkdir -p "$h"; printf '%s\n' "$h"; }
# gb HOME SRC SHA [LOGPATH] -> runs the tool with the fakes in front of BARE; SHA empty = unset
gb() {
  local h="$1" src="$2" sha="$3"
  if [ -n "$sha" ]; then
    run env -i PATH="$FAKEBIN:$BARE" HOME="$h" TMPDIR="$W" FAKE_LOG="$W/fake.log" NET_LOG="$W/net.log" PB_BASH32_SRC="$src" PB_BASH32_SHA256="$sha" "$BASH_BIN" "$TOOL"
  else
    run env -i PATH="$FAKEBIN:$BARE" HOME="$h" TMPDIR="$W" FAKE_LOG="$W/fake.log" NET_LOG="$W/net.log" PB_BASH32_SRC="$src" "$BASH_BIN" "$TOOL"
  fi
}
BASH_BIN="$(command -v bash)"

echo "AC4.1 success: installs HOME/.local/bin/bash3.2 and prints its path"
H="$(fresh_home ok)"; rm -f "$W/fake.log"
gb "$H" "$SRC" "$GOODSHA"
assert_rc "AC4.1 a matching checksum: exit 0" 0
assert_file "AC4.1 HOME/.local/bin/bash3.2 is installed" "$H/.local/bin/bash3.2"
if [ -x "$H/.local/bin/bash3.2" ]; then t_ok "AC4.1 the installed bash3.2 is executable"; else t_bad "AC4.1 the installed bash3.2 is executable"; fi
assert_contains "AC4.1 the output has the installed path" "$OUT" "$H/.local/bin/bash3.2"
assert_eq "AC4.1 the installed file is what the (fake) build produced" "GNU bash, version 3.2.57(1)-release (fake)" "$("$H/.local/bin/bash3.2" 2>/dev/null)"
LOG="$(cat "$W/fake.log" 2>/dev/null)"
assert_contains "AC4.1 the fake make ran" "$LOG" "make "
assert_contains "AC4.1 the build saw CFLAGS with -std=gnu89" "$LOG" "-std=gnu89"
for f in implicit-function-declaration implicit-int int-conversion incompatible-pointer-types; do
  assert_contains "AC4.1 the build saw CFLAGS with -Wno-error=$f" "$LOG" "-Wno-error=$f"
done
assert_not_contains "AC4.1 the offline fixture run never called curl or wget" "$(cat "$W/net.log" 2>/dev/null)" "curl"

echo "AC4.1 a checksum mismatch: exit 1, nothing installed, nothing built"
H="$(fresh_home bad)"; rm -f "$W/fake.log"
BADSHA="$(printf '%s' "$GOODSHA" | tr '0-9a-f' '1-9a-f0')"
gb "$H" "$SRC" "$BADSHA"
assert_rc "AC4.1 wrong checksum: exit 1" 1
assert_no_path "AC4.1 wrong checksum: no bash3.2 installed" "$H/.local/bin/bash3.2"
assert_not_contains "AC4.1 wrong checksum: make was not run" "$(cat "$W/fake.log" 2>/dev/null)" "make "
assert_contains "AC4.1 wrong checksum: the message says checksum or sha256" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "sha256"

echo "AC4.1 PB_BASH32_SHA256 is accepted only together with a file:// source"
H="$(fresh_home https)"; rm -f "$W/net.log" "$W/fake.log"
gb "$H" "https://example.invalid/bash-3.2.57.tar.gz" "$GOODSHA"
if [ "$RC" -ne 0 ]; then t_ok "AC4.1 https source + PB_BASH32_SHA256: refused (exit $RC)"; else t_bad "AC4.1 https source + PB_BASH32_SHA256: refused" "exit 0; output: $OUT"; fi
assert_no_path "AC4.1 https source + PB_BASH32_SHA256: nothing installed" "$H/.local/bin/bash3.2"
assert_not_contains "AC4.1 https source + PB_BASH32_SHA256: no download was attempted" "$(cat "$W/net.log" 2>/dev/null)" "curl"
assert_contains "AC4.1 https source + PB_BASH32_SHA256: the message names file://" "$OUT" "file://"
H="$(fresh_home nosrc)"; rm -f "$W/net.log"
run env -i PATH="$FAKEBIN:$BARE" HOME="$H" TMPDIR="$W" FAKE_LOG="$W/fake.log" NET_LOG="$W/net.log" PB_BASH32_SHA256="$GOODSHA" "$BASH_BIN" "$TOOL"
if [ "$RC" -ne 0 ]; then t_ok "AC4.1 PB_BASH32_SHA256 with no PB_BASH32_SRC (the real GNU URL): refused (exit $RC)"; else t_bad "AC4.1 PB_BASH32_SHA256 with no PB_BASH32_SRC: refused" "exit 0; output: $OUT"; fi
assert_no_path "AC4.1 PB_BASH32_SHA256 with no source: nothing installed" "$H/.local/bin/bash3.2"
assert_not_contains "AC4.1 PB_BASH32_SHA256 with no source: no download was attempted" "$(cat "$W/net.log" 2>/dev/null)" "curl"
H="$(fresh_home nosha)"; rm -f "$W/fake.log"
gb "$H" "$SRC" ""
assert_rc "AC4.1 a file:// source without PB_BASH32_SHA256 is checked against the pin, which the fixture does not match: exit 1" 1
assert_no_path "AC4.1 file:// source, no PB_BASH32_SHA256: nothing installed" "$H/.local/bin/bash3.2"

echo "AC4.1 no C compiler or no make: exit 2 with a hint"
NOCC="$W/nocc"; mkdir -p "$NOCC"; cp "$FAKEBIN/make" "$NOCC/make"; chmod +x "$NOCC/make"
H="$(fresh_home nocc)"
run env -i PATH="$NOCC:$BARE" HOME="$H" TMPDIR="$W" FAKE_LOG="$W/fake.log" PB_BASH32_SRC="$SRC" PB_BASH32_SHA256="$GOODSHA" "$BASH_BIN" "$TOOL"
assert_rc "AC4.1 no cc and no gcc: exit 2" 2
assert_contains "AC4.1 no cc: the hint names cc" "$OUT" "cc"
assert_contains "AC4.1 no cc: the hint says how to install a compiler" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "install"
assert_no_path "AC4.1 no cc: nothing installed" "$H/.local/bin/bash3.2"
NOMAKE="$W/nomake"; mkdir -p "$NOMAKE"; cp "$FAKEBIN/cc" "$NOMAKE/cc"; chmod +x "$NOMAKE/cc"
H="$(fresh_home nomake)"
run env -i PATH="$NOMAKE:$BARE" HOME="$H" TMPDIR="$W" FAKE_LOG="$W/fake.log" PB_BASH32_SRC="$SRC" PB_BASH32_SHA256="$GOODSHA" "$BASH_BIN" "$TOOL"
assert_rc "AC4.1 no make: exit 2" 2
assert_contains "AC4.1 no make: the hint names make" "$OUT" "make"
assert_contains "AC4.1 no make: the hint says how to install it" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "install"
assert_no_path "AC4.1 no make: nothing installed" "$H/.local/bin/bash3.2"
GCCONLY="$W/gcconly"; mkdir -p "$GCCONLY"; cp "$FAKEBIN/cc" "$GCCONLY/gcc"; cp "$FAKEBIN/make" "$GCCONLY/make"; chmod +x "$GCCONLY/gcc" "$GCCONLY/make"
H="$(fresh_home gcconly)"
run env -i PATH="$GCCONLY:$BARE" HOME="$H" TMPDIR="$W" FAKE_LOG="$W/fake.log" PB_BASH32_SRC="$SRC" PB_BASH32_SHA256="$GOODSHA" "$BASH_BIN" "$TOOL"
assert_rc "AC4.1 gcc without cc is enough: exit 0" 0
assert_file "AC4.1 gcc without cc: installed" "$H/.local/bin/bash3.2"

echo "AC4.1 the tool left no temp dirs behind and the real home is untouched (E3)"
LEFT="$(ls "$W" | grep -c 'pbbash32\|pbget\|bash-3.2.57' )"
assert_eq "AC4.1 no build dir is left in TMPDIR" "0" "$LEFT"
assert_eq "AC4.1 the real \$HOME/.local/bin/bash3.2 is exactly as before" "$REAL_BEFORE" "$(real_state)"

t_summary
