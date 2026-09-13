#!/bin/sh
# Copy the shared-library closure of the ScummVM binary from the toolchain
# sysroot into the pak's lib dir. Runs inside the toolchain container.
#
# Usage: collect-libs.sh <binary> <lib-dir>
set -eu

BINARY="${1:?usage: collect-libs.sh <binary> <lib-dir>}"
LIBDIR="${2:?usage: collect-libs.sh <binary> <lib-dir>}"

TARGET_ROOT=/opt/aarch64-nextui-linux-gnu/aarch64-nextui-linux-gnu
SEARCH_DIRS="$TARGET_ROOT/libc/usr/lib $TARGET_ROOT/lib64 $TARGET_ROOT/lib"
READELF=${CROSS_COMPILE:-aarch64-nextui-linux-gnu-}readelf

# Provided by the device firmware (GPU drivers + glibc); never bundle these.
# Everything else (SDL2, codecs, libstdc++, libgcc_s, ...) is bundled so the
# pak is independent of firmware library versions.
DEVICE_LIBS=" ld-linux-aarch64.so.1 libc.so.6 libpthread.so.0 libdl.so.2 libm.so.6 librt.so.1 libEGL.so.1 libGLESv2.so.2 libGLES_CM.so.1 libMali.so libmali.so libUMP.so.3 libIMGegl.so libPVROCL.so.1 "

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
		echo "    bundled $needed"
		queue="$queue $LIBDIR/$needed"
	done
done
