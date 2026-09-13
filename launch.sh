#!/bin/sh
PAK_DIR="$(dirname "$0")"
EMU_TAG="$(basename "$PAK_DIR")"
EMU_TAG="${EMU_TAG%.*}"

USERDATA_DIR="$USERDATA_PATH/$EMU_TAG-scummvm"
[ -f "$USERDATA_DIR/debug" ] && set -x

rm -f "$LOGS_PATH/$EMU_TAG.txt"
exec >>"$LOGS_PATH/$EMU_TAG.txt"
exec 2>&1

echo "$0" "$@"

ROM="$1"
mkdir -p "$USERDATA_DIR" "$SAVES_PATH/$EMU_TAG"

export PATH="$PAK_DIR/bin:$PATH"
export HOME="$USERDATA_DIR"
export LD_LIBRARY_PATH="$PAK_DIR/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"

# ── Resolve the ROM to a ScummVM game directory + target ─────────────────────
# NextUI hands us a file from /Roms/<folder> (<TAG>)/. Community convention:
# a .scummvm file whose contents are the ScummVM game ID (e.g. scumm:monkey),
# optionally referenced by a .m3u playlist. Follow .m3u chains (max 3 hops).
GAME_DIR=""
GAME_ID=""
resolve_rom() {
	_rom="$1"
	_depth="$2"
	[ "$_depth" -gt 3 ] && return
	case "$_rom" in
		*.scummvm)
			if [ -f "$_rom" ]; then
				GAME_ID="$(sed 's/[[:space:]]//g' "$_rom")"
				GAME_DIR="$(dirname "$_rom")"
			fi
			;;
		*.m3u)
			if [ -f "$_rom" ]; then
				_entry="$(grep -v '^#' "$_rom" | sed -e 's/\r$//' -e '/^[[:space:]]*$/d' | head -n 1)"
				case "$_entry" in
					/*) resolve_rom "$_entry" $((_depth + 1)) ;;
					*)  resolve_rom "$(dirname "$_rom")/$_entry" $((_depth + 1)) ;;
				esac
			fi
			;;
	esac
}
resolve_rom "$ROM" 0

# ── Launch ───────────────────────────────────────────────────────────────────
echo 1 > /tmp/stay_awake

cleanup() {
	rm -f /tmp/stay_awake
}
trap cleanup EXIT INT TERM HUP QUIT

# Power button sleep/shutdown (standalone emulators have no native support)
if command -v minui-power-control >/dev/null 2>&1; then
	chmod +x "$PAK_DIR/bin/minui-power-control"
	minui-power-control scummvm &
else
	echo "minui-power-control not found in $PAK_DIR/bin"
fi

cd "$USERDATA_DIR"
if [ -n "$GAME_ID" ] && [ -n "$GAME_DIR" ]; then
	echo "Launching '$GAME_ID' from '$GAME_DIR'"
	scummvm --fullscreen \
		--config="$USERDATA_DIR/scummvm.ini" \
		--savepath="$SAVES_PATH/$EMU_TAG" \
		--extrapath="$PAK_DIR/share/scummvm" \
		--themepath="$PAK_DIR/share/scummvm" \
		--path="$GAME_DIR" \
		"$GAME_ID"
else
	echo "No game shortcut found in '$ROM'; starting the ScummVM launcher"
	scummvm --fullscreen \
		--config="$USERDATA_DIR/scummvm.ini" \
		--savepath="$SAVES_PATH/$EMU_TAG" \
		--extrapath="$PAK_DIR/share/scummvm" \
		--themepath="$PAK_DIR/share/scummvm"
fi
