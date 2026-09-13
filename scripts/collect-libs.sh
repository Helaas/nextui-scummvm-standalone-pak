#!/bin/sh
# Copy the shared-library closure of the ScummVM binary from the toolchain
# sysroot into the pak's lib dir. Runs inside the toolchain container.
#
# Usage: collect-libs.sh <binary> <lib-dir>
set -eu

BINARY="${1:?usage: collect-libs.sh <binary> <lib-dir>}"
LIBDIR="${2:?usage: collect-libs.sh <binary> <lib-dir>}"

# The main binary may also carry a vendor RPATH; normalize it too.
python3 "$(dirname "$0")/strip-rpath.py" "$BINARY" 2>/dev/null || true

TARGET_ROOT=/opt/aarch64-nextui-linux-gnu/aarch64-nextui-linux-gnu
SEARCH_DIRS="$TARGET_ROOT/libc/usr/lib $TARGET_ROOT/lib64 $TARGET_ROOT/lib"
READELF=${CROSS_COMPILE:-aarch64-nextui-linux-gnu-}readelf

# Provided by the device firmware; never bundle these. GPU drivers and glibc
# are per device, and SDL2 plus ALSA carry each platform's video, input and
# audio backends (mali on tg5040/h700, KMSDRM on tg5050/my355, NextUI's H700
# pad patch). The C++ runtime must be the firmware's too: a bundled gcc 8.3
# libstdc++ shadows the newer one tg5050's libmali needs (GLIBCXX_3.4.26), so
# KMSDRM fails to load and SDL falls back to an offscreen (black) display.
# ScummVM only needs the base GLIBCXX_3.4/CXXABI_1.3 versions. Everything else
# (codecs) is bundled.
DEVICE_LIBS=" ld-linux-aarch64.so.1 libc.so.6 libpthread.so.0 libdl.so.2 libm.so.6 librt.so.1 libEGL.so.1 libGLESv2.so.2 libGLES_CM.so.1 libMali.so libmali.so libUMP.so.3 libIMGegl.so libPVROCL.so.1 libSDL2-2.0.so.0 libasound.so.2 libstdc++.so.6 libgcc_s.so.1 "

rm -rf "$LIBDIR"
mkdir -p "$LIBDIR"

queue="$BINARY"
seen=" "
while [ -n "$queue" ]; do
	set -- $queue
	current=$1
	shift
	queue="$*"
	case "$seen" in
		*" $current "*) continue ;;
	esac
	seen="$seen$current "

	for needed in $($READELF -d "$current" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
		case "$DEVICE_LIBS" in
			*" $needed "*) continue ;;
		esac
		if [ -e "$LIBDIR/$needed" ]; then
			continue
		fi
		src=""
		for d in $SEARCH_DIRS; do
			if [ -e "$d/$needed" ]; then
				src="$d/$needed"
				break
			fi
		done
		[ -n "$src" ] || { echo "Error: $needed (needed by $current) not found in sysroot" >&2; exit 1; }
		# Dereference symlinks, store under the soname, strip.
		cp -L "$src" "$LIBDIR/$needed"
		${CROSS_COMPILE:-aarch64-nextui-linux-gnu-}strip --strip-unneeded "$LIBDIR/$needed" 2>/dev/null || true
		python3 "$(dirname "$0")/strip-rpath.py" "$LIBDIR/$needed" || true
		echo "    bundled $needed"
		queue="$queue $LIBDIR/$needed"
	done
done
