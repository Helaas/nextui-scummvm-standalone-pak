#!/bin/sh
# Verify that the ScummVM binary and its bundled libraries can run on every
# supported firmware. Runs inside the toolchain container.
#
# Usage: verify-binary.sh <binary> <lib-dir> <glibc-ceiling>
set -eu

BINARY="${1:?usage: verify-binary.sh <binary> <lib-dir> <glibc-ceiling>}"
LIBDIR="${2:?usage: verify-binary.sh <binary> <lib-dir> <glibc-ceiling>}"
GLIBC_CEILING="${3:?usage: verify-binary.sh <binary> <lib-dir> <glibc-ceiling>}"
READELF=${CROSS_COMPILE:-aarch64-nextui-linux-gnu-}readelf

# Libraries the device firmware provides (GPU drivers + glibc).
DEVICE_LIBS=" ld-linux-aarch64.so.1 libc.so.6 libpthread.so.0 libdl.so.2 libm.so.6 librt.so.1 libEGL.so.1 libGLESv2.so.2 libGLES_CM.so.1 libMali.so libmali.so libUMP.so.3 libIMGegl.so libPVROCL.so.1 "

fail() {
	echo "Error: $*" >&2
	exit 1
}

highest_glibc() {
	$READELF -V "$1" 2>/dev/null | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -uV | tail -n 1
}

check_common() {
	f=$1
	$READELF -h "$f" | grep -q 'Machine:.*AArch64' || fail "$f is not an AArch64 ELF"

	if $READELF -d "$f" | grep -Eq '\((RPATH|RUNPATH)\)'; then
		fail "$f embeds an RPATH or RUNPATH"
	fi

	highest=$(highest_glibc "$f")
	if [ -n "$highest" ] && \
	   [ "$(printf '%s\n%s\n' "$highest" "$GLIBC_CEILING" | sort -V | tail -n 1)" != "$GLIBC_CEILING" ]; then
		fail "$f needs GLIBC_$highest, above the GLIBC_$GLIBC_CEILING ceiling"
	fi

	for needed in $($READELF -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
		case "$DEVICE_LIBS" in
			*" $needed "*) continue ;;
		esac
		[ -e "$LIBDIR/$needed" ] || fail "$f needs $needed, missing from $LIBDIR"
	done
}

# The binary itself: AArch64, dynamically linked, stripped.
check_common "$BINARY"
$READELF -l "$BINARY" | grep -q INTERP || fail "$BINARY is not dynamically linked"
$READELF -S "$BINARY" | grep -q '\.symtab' && fail "$BINARY is not stripped"

for lib in "$LIBDIR"/*.so*; do
	check_common "$lib"
done

echo "==> Verified $(basename "$BINARY"): AArch64, stripped, no RPATH, glibc <= $GLIBC_CEILING"
echo "    NEEDED closure satisfied by pak lib/ + device firmware:"
for f in "$BINARY" "$LIBDIR"/*.so*; do
	$READELF -d "$f" | sed -n "s/.*(NEEDED).*\[\(.*\)\]/    $(basename "$f"): \1/p"
done | sort -u
