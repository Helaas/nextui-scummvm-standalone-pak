#!/bin/bash
# Cross-compile ScummVM inside the pinned tg5040 toolchain container.
# Run from the ScummVM source checkout (the Makefile mounts the repo at
# /workspace and sets the CWD to /workspace/.cache/scummvm).
#
# Usage: docker-build.sh <stage-dir>   (stage dir is relative to /workspace)
set -euo pipefail

STAGE_DIR="${1:?usage: docker-build.sh <stage-dir>}"
SYSROOT=/opt/aarch64-nextui-linux-gnu/aarch64-nextui-linux-gnu/libc/usr

# The sysroot's sdl2-config hardcodes the original TrimUI build-machine
# prefix and injects an RPATH. Generate a corrected copy and point
# ScummVM's configure at it via --with-sdl-prefix.
mkdir -p /tmp/sdlfix
sed -e "s|^prefix=.*|prefix=\"$SYSROOT\"|" \
    -e "s|^exec_prefix=.*|exec_prefix=\"$SYSROOT\"|" \
    -e 's|-Wl,-rpath,[^ "]*||g' \
    "$SYSROOT/bin/sdl2-config" > /tmp/sdlfix/sdl2-config
chmod +x /tmp/sdlfix/sdl2-config

export CXXFLAGS="-mcpu=cortex-a53 -mtune=cortex-a53"
export CFLAGS="-mcpu=cortex-a53 -mtune=cortex-a53"

./configure \
	--host=aarch64-nextui-linux-gnu \
	--with-sdl-prefix=/tmp/sdlfix \
	--enable-release-mode \
	--enable-optimizations \
	--enable-vkeybd \
	--disable-cloud \
	--disable-sdlnet \
	--disable-libcurl \
	--disable-discord \
	--disable-fluidsynth \
	--disable-updates \
	--disable-tts

make -j"$(nproc)"
aarch64-nextui-linux-gnu-strip scummvm

rm -rf "/workspace/$STAGE_DIR"
make install DESTDIR="/workspace/$STAGE_DIR"

echo "==> Staged to /workspace/$STAGE_DIR"
