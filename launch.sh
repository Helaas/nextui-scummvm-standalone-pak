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
echo "platform=${PLATFORM:-unknown} device=${DEVICE:-unknown}"

ROM="$1"
mkdir -p "$USERDATA_DIR" "$SAVES_PATH/$EMU_TAG"

export PATH="$PAK_DIR/bin:$PATH"
export HOME="$USERDATA_DIR"
# lib/ holds codecs only. SDL2, ALSA and the C++ runtime come from the
# firmware (already on NextUI's library path): each platform's SDL carries its
# own video and input backend (mali on tg5040/h700, KMSDRM on tg5050/my355,
# NextUI's pad patch on h700), and its GPU driver needs the firmware's
# libstdc++ (tg5050's libmali fails to load against an older bundled one).
# Keep NextUI's own path for system scripts run from the pak (e.g. suspend).
export NEXTUI_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
[ "$PLATFORM" = "tg5040" ] && export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/trimui/lib"

# ── Controls ─────────────────────────────────────────────────────────────────
# SDL gamecontroller mapping for the built-in pad, named by printed label, so
# ScummVM's "Joy A" is the button marked A and JOY_GUIDE is Menu. Devices
# without analog sticks drive the left stick from the d-pad instead, which is
# what moves ScummVM's virtual mouse. The GUIDs carry no name CRC, so they
# match on every SDL version the firmwares ship (2.0.22 through 2.32).
DPAD_BUTTONS="dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,"
DPAD_AS_STICK="-lefty:h0.1,+lefty:h0.4,-leftx:h0.8,+leftx:h0.2,"
PAD=""
case "$PLATFORM" in
	tg5040 | tg5050 | my355)
		# TRIMUI/MIYOO Player1 (xpad IDs 045e:028e): NextUI's JOY_A=1 B=0 X=3 Y=2
		PAD_NAME="TRIMUI Player1"
		if [ "$PLATFORM" = "my355" ]; then
			PAD_NAME="MIYOO Player1"
			# The Flip's buttons also arrive as keys from gpio-keys-polled (A is
			# Space, Start Enter, Menu Escape, ...); ignore them so a press maps
			# to one action (handled by the pak's ScummVM patch).
			export SCUMMVM_IGNORE_KEYBOARD=1
		fi
		PAD="030000005e0400008e02000014010000,$PAD_NAME,a:b1,b:b0,x:b3,y:b2,back:b6,start:b7,guide:b8,leftshoulder:b4,rightshoulder:b5,lefttrigger:a2,righttrigger:a5,leftstick:b9,rightstick:b10,"
		if [ "$DEVICE" = "brick" ]; then
			# No sticks; b9/b10 are the F1/F2 keys
			PAD="$PAD$DPAD_AS_STICK"
		else
			PAD="${PAD}leftx:a0,lefty:a1,rightx:a3,righty:a4,$DPAD_BUTTONS"
		fi
		;;
	h700)
		# ANBERNIC-keys under NextUI's H700 SDL: ESC/VOL-/VOL+ enumerate first as
		# b0-b2, and the stick-click keys interleave with the triggers, so the
		# numbering above MENU depends on the model's stick count.
		PAD="19000000010000000100000000010000,ANBERNIC-keys,a:b3,b:b4,x:b6,y:b5,leftshoulder:b7,rightshoulder:b8,back:b9,start:b10,guide:b11,"
		case "$DEVICE" in
			rg40xxh | rgcubexx | rg34xxsp | rg35xxh | rg35xxpro)
				PAD="${PAD}leftstick:b12,lefttrigger:b13,righttrigger:b14,rightstick:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,$DPAD_BUTTONS"
				;;
			rg40xxv)
				PAD="${PAD}leftstick:b12,lefttrigger:b13,righttrigger:b14,leftx:a0,lefty:a1,$DPAD_BUTTONS"
				;;
			*)
				PAD="${PAD}lefttrigger:b12,righttrigger:b13,$DPAD_AS_STICK"
				;;
		esac
		;;
esac
if [ -n "$PAD" ]; then
	export SDL_GAMECONTROLLERCONFIG="${PAD}platform:Linux,"
fi

# Handheld keymap defaults (Menu = ScummVM menu, Start = game menu, ...),
# loaded by the pak's ScummVM patch; per-game remaps still override them.
export SCUMMVM_KEYMAP_DEFAULTS="$PAK_DIR/keymaps/default.txt"
# Device defaults take precedence over platform defaults; saved ScummVM
# options still override either (e.g. slower pointers on Brick and h700).
if [ -f "$PAK_DIR/config/$DEVICE.txt" ]; then
	export SCUMMVM_CONFIG_DEFAULTS="$PAK_DIR/config/$DEVICE.txt"
elif [ -f "$PAK_DIR/config/$PLATFORM.txt" ]; then
	export SCUMMVM_CONFIG_DEFAULTS="$PAK_DIR/config/$PLATFORM.txt"
fi

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

# Power button sleep/shutdown (standalone emulators have no native support).
case "$PLATFORM" in
	tg5040 | tg5050 | my355)
		if command -v minui-power-control >/dev/null 2>&1; then
			chmod +x "$PAK_DIR/bin/minui-power-control"
			minui-power-control scummvm &
		else
			echo "minui-power-control not found in $PAK_DIR/bin"
		fi
		;;
	h700)
		# minui-power-control's handler reads a fixed input node, which is the
		# pad on H700 (the power key is on axp2202-pek). The pak's helper finds
		# the device reporting KEY_POWER and uses NextUI's suspend script.
		# H700's ALSA driver does not recover a PCM left open across suspend, so
		# the helper has ScummVM close its audio first (SIGUSR1/SIGUSR2, via the
		# pak's ScummVM patch) and reopen it after wake.
		export SCUMMVM_AUDIO_SIGNALS=1
		chmod +x "$PAK_DIR/bin/power-button"
		power-button scummvm &
		;;
	*)
		echo "No power button support for ${PLATFORM:-this platform}; save and quit from ScummVM's menu"
		;;
esac

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
