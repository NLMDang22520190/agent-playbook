#!/usr/bin/env bash
# get-bash32.sh: build bash 3.2.57 (the bash macOS ships) from the GNU source and install it as ~/.local/bin/bash3.2,
# so tools/bsd-check.sh can run the suites under it. Prints the installed path.
#
# Source:  https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz  (PB_BASH32_SRC overrides it; a file:///path/to/tarball
#          source is allowed, mainly for tests)
# Pin:     PIN below is the sha256 of that tarball. It was derived once, so that nobody has to trust a mirror:
#   1. download bash-3.2.57.tar.gz and bash-3.2.57.tar.gz.sig from https://ftp.gnu.org/gnu/bash/
#   2. download the GNU keyring https://ftp.gnu.org/gnu/gnu-keyring.gpg
#   3. gpg --no-default-keyring --keyring ./gnu-keyring.gpg --verify bash-3.2.57.tar.gz.sig bash-3.2.57.tar.gz
#      -> "Good signature from Chet Ramey <chet@cwru.edu>", key fingerprint 7C01 35FB 088A AF6C 66C6  50B9 BB58 69F0 64EA 74AB
#   4. sha256sum bash-3.2.57.tar.gz (or shasum -a 256) -> the PIN below
# At run time the script needs no gpg: it only compares the sha256 of the download with the PIN. A mismatch exits 1 and
# installs nothing.
# PB_BASH32_SHA256 replaces the pin and is accepted ONLY together with a file:// source (tests); with the https source it
# is refused, so the environment cannot weaken the check of a real download.
# Needs a C compiler (cc or gcc) and make; without them it exits 2 with a hint.
set -u

PIN="3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4"
DEFAULT_SRC="https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz"
SRC="${PB_BASH32_SRC:-$DEFAULT_SRC}"
EXPECT="$PIN"

die() { printf 'get-bash32: %s\n' "$2" >&2; exit "$1"; }

case "$SRC" in
  file://*) [ -n "${PB_BASH32_SHA256:-}" ] && EXPECT="$PB_BASH32_SHA256" ;;
  *) [ -n "${PB_BASH32_SHA256:-}" ] && die 1 "PB_BASH32_SHA256 is accepted only with a file:// PB_BASH32_SRC; refusing to weaken the pin for $SRC" ;;
esac

CC_BIN=""
if command -v cc >/dev/null 2>&1; then CC_BIN="cc"; elif command -v gcc >/dev/null 2>&1; then CC_BIN="gcc"; fi
[ -n "$CC_BIN" ] || die 2 "no C compiler (cc or gcc) found; install one (macOS: xcode-select --install, Debian/Ubuntu: apt install build-essential)"
command -v make >/dev/null 2>&1 || die 2 "make not found; install it (macOS: xcode-select --install, Debian/Ubuntu: apt install make)"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else openssl dgst -sha256 "$1" | sed 's/^.*= *//'; fi
}

BASE="${TMPDIR:-/tmp}"
BASE="${BASE%/}"
WORK="$(mktemp -d "$BASE/pbbash32.XXXXXX")" || die 3 "cannot make a temp dir under $BASE"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TARBALL="$WORK/bash-3.2.57.tar.gz"
case "$SRC" in
  file://*) cp "${SRC#file://}" "$TARBALL" || die 1 "cannot read ${SRC#file://}" ;;
  *)
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$TARBALL" "$SRC" || die 1 "download failed: $SRC"
    elif command -v wget >/dev/null 2>&1; then wget -q -O "$TARBALL" "$SRC" || die 1 "download failed: $SRC"
    else die 2 "neither curl nor wget found; install one of them"; fi ;;
esac

GOT="$(sha_of "$TARBALL")"
[ "$GOT" = "$EXPECT" ] || die 1 "sha256 mismatch for $SRC: expected $EXPECT, got $GOT; nothing was installed"

tar -xzf "$TARBALL" -C "$WORK" || die 1 "cannot extract the tarball"
TREE="$WORK/bash-3.2.57"
[ -d "$TREE" ] || die 1 "the tarball has no bash-3.2.57 directory"

# The tarball ships a y.tab.c that is older than its (patched) parse.y, so a real build must regenerate the parser: touch
# parse.y when a yacc is available (macOS: Xcode tools; Debian/Ubuntu: apt install bison). Without one, touch the shipped
# files so make does not fail on the missing tool; a real build then stops with a compile error and the hint below.
if command -v yacc >/dev/null 2>&1 || command -v bison >/dev/null 2>&1 || command -v byacc >/dev/null 2>&1; then
  touch "$TREE/parse.y"
else
  YACC_MISSING=1
  for f in y.tab.c y.tab.h; do [ -f "$TREE/$f" ] && touch "$TREE/$f"; done
fi
# gnu89 and the -Wno-error flags: bash 3.2 is K&R-era C and modern compilers reject it otherwise.
export CFLAGS="-std=gnu89 -O2 -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"
export CC="$CC_BIN"
LOG="$WORK/build.log"
if ! { cd "$TREE" && ./configure --without-bash-malloc >"$LOG" 2>&1 && make >>"$LOG" 2>&1; }; then
  tail -n 30 "$LOG" >&2
  [ "${YACC_MISSING:-0}" = 1 ] && printf 'get-bash32: no yacc/bison found: install bison (macOS: xcode-select --install, Debian/Ubuntu: apt install bison)\n' >&2
  die 1 "build failed (log tail above); nothing was installed"
fi
[ -x "$TREE/bash" ] || die 1 "the build produced no bash binary"

DEST="$HOME/.local/bin"
mkdir -p "$DEST" || die 1 "cannot make $DEST"
cp "$TREE/bash" "$DEST/bash3.2.new" || die 1 "cannot copy to $DEST"
chmod +x "$DEST/bash3.2.new"
mv -f "$DEST/bash3.2.new" "$DEST/bash3.2" || die 1 "cannot install $DEST/bash3.2"
printf '%s\n' "$DEST/bash3.2"
