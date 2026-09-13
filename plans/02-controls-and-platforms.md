# Plan: Handheld controls and tg5050 / my355 / h700 support

## Status

- Controls implemented: label-correct SDL gamecontroller mapping per
  platform (`launch.sh`), d-pad-as-stick on stickless devices, and handheld
  keymap defaults (`keymaps/default.txt`) loaded through
  `patches/0001-posix-keymap-defaults-from-file.patch`.
- One binary now targets tg5040, tg5050, my355 and h700; SDL2, ALSA,
  libstdc++ and libgcc_s come from each firmware instead of `lib/`.
  `make package` passes and asserts none of them is bundled.
- The Brick loads `config/brick.txt` (`kbdmouse_speed=1`) through
  `SCUMMVM_CONFIG_DEFAULTS`, handled by the same patch; `launch.sh` picks
  `config/$DEVICE.txt` when present. Hands-on: the d-pad mouse was too fast on
  the Brick at the default speed but right on the H700 RG SP.
- Verification: see [Verification](#verification). Remaining items are listed
  under [Open items](#open-items).

## Controls

ScummVM's stock gamepad defaults are positional (Xbox layout), and the
TrimUI/Miyoo pads report themselves as an Xbox 360 controller, so out of the
box left click sat on the button printed **B**, right click on **A**, and
nothing moved the cursor on devices without sticks (the d-pad sends arrow keys,
which the virtual keyboard ignores).

Chosen layout (printed labels):

| Button | Action | Keymap entry |
| --- | --- | --- |
| A | Left click / GUI select | stock `LCLK`, `INTRCT` |
| B | Right click / GUI back | stock `RCLK`; `gui CLOS` |
| Y | Skip cutscene (Esc) | stock `SKIP` |
| X | Skip line (.) | stock `SKLI` |
| Menu | ScummVM global menu | `global MENU` |
| Start | Game menu (F5) | `engine-default MENU`, `standard-actions MENU` |
| Select | Virtual keyboard | stock `global VIRT` |
| L1 (hold) | Slow mouse | `global VMOUSESLOW` |
| R1 | Enter | `engine-default RETURN` |
| L2 | Pause | `engine-default PAUSE` |
| L3 / Brick F1 | Middle click | `engine-default MCLK` |
| Left stick | Mouse | stock virtual mouse |
| D-pad | Arrow keys, or the mouse on stickless devices | SDL mapping |

Engines with their own keymaps (e.g. Blade Runner, Grim, Stark) keep them;
only `standard-actions MENU` (Start) is applied across engines. The engines
that already bind `JOY_START` (alcachofa, hypno intro, nancy, phoenixvr,
toltecs) use it for their menu too, so this does not create conflicts.

### Two layers

1. **SDL gamecontroller mapping** (`SDL_GAMECONTROLLERCONFIG`, per
   `$PLATFORM`/`$DEVICE` in `launch.sh`): names buttons by label, so ScummVM's
   `JOY_A` is the button printed A. On stickless devices the d-pad hat is
   mapped to the left stick's half axes (`-lefty:h0.1,+lefty:h0.4,...`), which
   drives ScummVM's virtual mouse with no daemon involved. SDL's
   `HandleJoystickHat` supports hat → axis outputs (checked in 2.28.5). GUIDs
   carry no name CRC, so they match on SDL 2.0.22 through 2.32.
2. **Keymap defaults** (`keymaps/default.txt`): ScummVM saves game keymaps per
   target, so a seeded `scummvm.ini` cannot set defaults for every game. The
   patch overrides `OSystem_POSIX::getKeymapperDefaultBindings()` (the hook the
   Miyoo/OpenDingux ports use) to read `<keymap> <action> [<input>...]` lines
   from `$SCUMMVM_KEYMAP_DEFAULTS`. It returns a fresh object each call because
   `Keymapper::registerHardwareInputSet()` deletes the previous one. User
   remaps in the keymapper GUI still win.

spruceOS was the reference for the pad rows: its ScummVM controller db ships
the same label-named `TRIMUI Player1`/`MIYOO Player1` rows, and its
`AnbernicXXCommon.cfg` documents the `ANBERNIC-keys` numbering under the H700
SDL build that NextUI ships (identical md5 `60974a90…`). spruce enables the
Brick's `trimui_inputd` `input_dpad_to_joystick` flag instead; that flag exists
on the Brick firmware but not on the Smart Pro's, so the SDL mapping is used.

## Platform research (measured on hardware, 2026-09-13)

| | tg5040 Brick | tg5040 Smart Pro | tg5050 Smart Pro S | my355 Flip | h700 RG SP |
| --- | --- | --- | --- | --- | --- |
| `DEVICE` | `brick` | `smartpro` | `smartpros` | `my355` | `rgsp` |
| Kernel / glibc | 4.9 / 2.33 | 4.9 / 2.33 | 5.15 / 2.33 | 5.10 / 2.36 | 4.9 / 2.35 |
| Pad (SDL) | `TRIMUI Player1` 045e:028e | same | same | `MIYOO Player1` 045e:028e | `ANBERNIC-keys` |
| SDL NextUI loads | `/usr/trimui/lib` 2.30.8 (mali) | same | `/usr/lib` 2.32.6 (KMSDRM) | `/usr/lib` 2.0.22 (KMSDRM) | `.system/h700/lib` 2.28.5 (mali) |
| Power key | event1 | event1 | event2 | event2 | event0 |

- tg5050 launched games to a black screen with the first build: the bundled
  gcc 8.3 libstdc++ (up to GLIBCXX_3.4.25) shadowed the firmware's, tg5050's
  `libmali.so.0` needs GLIBCXX_3.4.26, so `libgbm`/`libEGL` failed to dlopen,
  SDL reported "KMSDRM not available" and fell back to `offscreen`. A probe
  confirmed KMSDRM initializes (1280x720) once `lib/` no longer shadows the
  firmware C++ runtime. ScummVM itself only needs GLIBCXX_3.4/CXXABI_1.3, and
  every firmware ships libstdc++.so.6 and libgcc_s.so.1.
- The bundled tg5040-sysroot SDL 2.26.1 only has the `mali` video driver, so it
  cannot drive tg5050/my355. All 149 SDL symbols ScummVM imports are exported
  by every firmware SDL above, including my355's 2.0.22.
- my355 NextUI reads controls as keyboard scancodes, but `miyoo_inputd` also
  exposes `MIYOO Player1` with the same button bitmap as the TrimUI pad.
  ScummVM's SDL reads both, so each press arrived twice: `gpio-keys-polled`
  advertises ESC, BACKSPACE, TAB, ENTER, LCTRL, LSHIFT, RSHIFT, LALT, SPACE,
  RCTRL, RALT, the arrows and PGUP/PGDN, which ScummVM's keymaps also bind
  (Space = pause, Enter = confirm, Escape = skip/close, ...). Hands-on this
  showed up as wrong keybinds. `patches/0002-sdl-ignore-keyboard-env.patch`
  drops SDL keyboard events when `SCUMMVM_IGNORE_KEYBOARD` is set, which
  `launch.sh` does on my355 only (the virtual keyboard is mouse-driven and
  keeps working).
- H700 stick count per `DEVICE` follows the h700 NextUI `platform.c`:
  two sticks on rg40xxh, rgcubexx, rg34xxsp, rg35xxh, rg35xxpro; one on
  rg40xxv; none otherwise.
- minui-power-control 3.0.0 picks its input node from `$PLATFORM` (event2 on
  tg5050/my355, event1 otherwise), which is the pad on h700 (upstream main is
  unchanged). Its suspend/shutdown scripts are generic NextUI paths
  (`$SYSTEM_PATH/bin/suspend`; `/tmp/poweroff` + terminate the pak), but the Go
  handler runs from its own extracted `arm64/` dir, so it cannot be overridden
  from the pak. On h700 the pak runs `bin/power-button` (`src/power-button.c`,
  built with the same toolchain) instead: it opens the input device whose
  EV_KEY bits include KEY_POWER (`axp2202-pek`, event0 on the RG SP), treats a
  release under 2 s as suspend (SIGSTOP the emulator, run NextUI's suspend
  script, which returns after wake, SIGCONT, 1 s cooldown) and a 2 s hold as
  shutdown (`/tmp/poweroff`, SIGTERM the emulator; the h700 launch loop then
  runs `poweroff_next`).
- Hands-on, sleep/wake and shutdown worked on h700 but audio stayed silent
  after wake: the log showed `snd_pcm_recover` treating the stopped stream as
  an underrun. NextUI's h700 `PWR_enterSleep` closes the audio device before
  sleeping for the same reason. `patches/0003-sdl-audio-suspend-signals.patch`
  makes SIGUSR1/SIGUSR2 call `MixerManager::suspendAudio()`/`resumeAudio()`
  (flagged by the handler, run from `SdlEventSource::pollEvent`) when
  `SCUMMVM_AUDIO_SIGNALS` is set. The helper sends SIGUSR1, waits (up to 2 s)
  until ScummVM no longer holds `/dev/snd/pcmC*p`, then SIGSTOP + suspend,
  SIGCONT + SIGUSR2 after wake. It also runs the suspend script with
  `NEXTUI_LD_LIBRARY_PATH`, since its resume hooks restart bluealsa, which had
  picked up the pak's bundled libz.

## Verification

| Check | Result |
| --- | --- |
| Patched build, `make package` checks | Pass |
| tg5050: launch through NextUI loop, `Using game controller: TRIMUI Player1`, firmware SDL 2.32.6 + ALSA loaded, power control on event2 | Pass |
| tg5050: injected Y leaves the launcher open (stock default would close it) | Pass |
| tg5050: injected B closes the launcher (`gui CLOS JOY_B`) | Pass (log shows ScummVM exiting and power control cleaning up); the device powered off afterwards, caused by the test harness (below) |
| my355: starts beside NativeSSH, `Using game controller: MIYOO Player1`, SDL 2.0.22, Mali init, power control on event2 | Pass (display not checked: NativeSSH holds DRM) |
| Brick: launch through NextUI loop, `Using game controller: TRIMUI Player1`, firmware SDL 2.30.8, power control on event1 | Pass |
| Brick: injected d-pad hat moves the cursor (full-speed, ~1100 px/s) | Pass (framebuffer screenshots) |
| Brick: injected Select opens the virtual keyboard; injected A on a key types it into the text field | Pass (framebuffer screenshots) |
| h700 (RG SP): starts beside NativeSSH, `Using game controller: ANBERNIC-keys`, NextUI's SDL 2.28.5, renders the launcher at 720x480, power helper skipped | Pass |
| h700: injected d-pad hat moves the cursor | Likely (cursor away from its top-left start in the post-input screenshot; the "before" capture failed) |
| h700: `power-button` dry run with injected KEY_POWER on event0: 300 ms press logs suspend, 2.6 s hold logs shutdown, helper exits with the emulator, no `/tmp/poweroff` created | Pass |
| Hands-on with Freddi Fish (Dutch) after the runtime and input fixes: tg5050 renders the game, the Brick's pointer speed is right, my355 buttons trigger single actions, h700 d-pad mouse feels right | Pass (reported by the maintainer) |
| h700: real power-button sleep/wake with patch 0003, audio returns | Pass (2026-09-13 maintainer confirmation; fresh log shows successful kernel suspend/resume, PCM reopened, no audio-handshake warning or pak-libz warning from bluealsa) |
| tg5040 Smart Pro: same candidate, picture/audio, controls, virtual keyboard and power-button sleep/wake | Pass (2026-09-13 maintainer confirmation; firmware SDL2/ALSA/C++ runtime loaded, minui-power-control on event1, h700 audio signals disabled). See [device verification](04-device-verification.md). |

Test method: packs were launched by writing `/tmp/next` and killing
`nextui.elf`, so NextUI's own loop supplied the environment (Brick, tg5050), or
beside NativeSSH with its environment (my355, h700, where NativeSSH owns the
loop). Inputs were injected with a small evdev writer; screenshots came from
`/dev/fb0` on the mali devices. Killing `nextui.elf` makes the TrimUI devices
power off once the queued command exits: a dummy `sleep` command in place of
the pak reproduced it on tg5050, so the power-offs seen after ScummVM exited on
the Brick and tg5050 are a harness artifact, not pak behavior. Don't reuse
this method; launch from the NextUI menu instead.

## Open items

- RG SP brightness flicker in Game Boy and ScummVM after the smoke test;
  cause unresolved. See [follow-up investigation](04-device-verification.md#follow-up-rg-sp-display-flicker-remains-unresolved).
- Brick Pro L4/R4 and second Menu key are beyond SDL's X360 mapping and stay
  unused.
- rg28xx (rotated panel) is untested.
