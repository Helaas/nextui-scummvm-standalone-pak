#!/bin/bash
# Cross-compile ScummVM inside the pinned tg5040 toolchain container.
# Run from the ScummVM source checkout (the Makefile mounts the repo at
# /workspace and sets the CWD to /workspace/.cache/scummvm).
#
# Usage: docker-build.sh <stage-dir> <giflib-tarball> <libmpeg2-tarball>
#        (all paths relative to /workspace)
set -euo pipefail

USAGE="usage: docker-build.sh <stage-dir> <giflib-tarball> <libmpeg2-tarball>"
STAGE_DIR="${1:?$USAGE}"
GIFLIB_TAR="${2:?$USAGE}"
MPEG2_TAR="${3:?$USAGE}"
SYSROOT=/opt/aarch64-nextui-linux-gnu/aarch64-nextui-linux-gnu/libc/usr
CPU_FLAGS="-mcpu=cortex-a53 -mtune=cortex-a53"

# Codecs the sysroot lacks, built as static libraries so the pak needs no
# extra lib/ entries: giflib (Phoenix VR) and libmpeg2 (QD Engine,
# Alcachofa). Without them configure silently skips those engines.
DEPS=/tmp/deps
rm -rf /tmp/deps-src "$DEPS"
mkdir -p /tmp/deps-src/giflib /tmp/deps-src/libmpeg2 "$DEPS/include" "$DEPS/lib"

echo "==> Building giflib (static)"
tar -xzf "/workspace/$GIFLIB_TAR" -C /tmp/deps-src/giflib --strip-components=1
make -C /tmp/deps-src/giflib -j"$(nproc)" libgif.a \
	CC=aarch64-nextui-linux-gnu-gcc AR=aarch64-nextui-linux-gnu-ar \
	OFLAGS="-O2 $CPU_FLAGS"
cp /tmp/deps-src/giflib/gif_lib.h "$DEPS/include/"
cp /tmp/deps-src/giflib/libgif.a "$DEPS/lib/"

echo "==> Building libmpeg2 (static)"
tar -xzf "/workspace/$MPEG2_TAR" -C /tmp/deps-src/libmpeg2 --strip-components=1
(
	cd /tmp/deps-src/libmpeg2
	# The 2008 release's config.sub predates aarch64.
	cp /usr/share/misc/config.sub /usr/share/misc/config.guess .auto/
	./configure --host=aarch64-nextui-linux-gnu --prefix="$DEPS" \
		--disable-shared --enable-static --disable-sdl --without-x \
		CFLAGS="-O2 $CPU_FLAGS"
	make -C libmpeg2 -j"$(nproc)" install
	make -C include install
)

# The sysroot's sdl2-config hardcodes the original TrimUI build-machine
# prefix and injects an RPATH. Generate a corrected copy and point
# ScummVM's configure at it via --with-sdl-prefix.
mkdir -p /tmp/sdlfix
sed -e "s|^prefix=.*|prefix=\"$SYSROOT\"|" \
    -e "s|^exec_prefix=.*|exec_prefix=\"$SYSROOT\"|" \
    -e 's|-Wl,-rpath,[^ "]*||g' \
    "$SYSROOT/bin/sdl2-config" > /tmp/sdlfix/sdl2-config
chmod +x /tmp/sdlfix/sdl2-config

# Apply the pak's ScummVM patches once; a patch that already reverses
# cleanly is in place from an earlier build of this checkout.
for patch in /workspace/patches/*.patch; do
	[ -e "$patch" ] || continue
	if git apply --reverse --check "$patch" 2>/dev/null; then
		echo "==> Patch already applied: $(basename "$patch")"
	else
		echo "==> Applying $(basename "$patch")"
		git apply "$patch"
	fi
done

export CXXFLAGS="$CPU_FLAGS"
export CFLAGS="$CPU_FLAGS"

# Hpl1 (Penumbra) is left out: its hardware renderer needs desktop OpenGL,
# which none of these GLES2-only GPUs provide (it crashes on first use),
# and its TinyGL fallback is garbled and runs at 5-6 fps on the Brick.
./configure \
	--host=aarch64-nextui-linux-gnu \
	--prefix=/usr \
	--with-sdl-prefix=/tmp/sdlfix \
	--with-gif-prefix="$DEPS" \
	--with-mpeg2-prefix="$DEPS" \
	--enable-gif \
	--enable-mpeg2 \
	--disable-engine=hpl1 \
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
