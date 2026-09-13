# Handoff: SCUMMVMSA pak (state as of 2026-09-13)

**Subsequent issue:** the maintainer reports RG SP brightness flicker in
Game Boy and ScummVM after reinstalling BaseOS/NextUI. Cause unresolved;
the audio/control smoke-test passes below do not clear this visual issue.
See [the follow-up investigation](04-device-verification.md#follow-up-rg-sp-display-flicker-remains-unresolved).

## TL;DR

- Commit `3912078` (merged PR #1) is released as **v1.0.0** on GitHub (the
  Release workflow published it on the merge push). It covers the handheld
  controls, tg5040/tg5050/my355/h700 support, the firmware C++ runtime fix, the
  Brick pointer speed and the Flip keyboard fix.
- **Unreleased changes on `main`:** h700 power button support (`src/power-button.c`)
  plus audio resume after sleep (`patches/0003-sdl-audio-suspend-signals.patch`).
  Built and deployed to the RG SP; the maintainer confirmed audio comes back
  after a real power-button sleep/wake on 2026-09-13.
- The same candidate passed the maintainer's tg5040 Smart Pro regression
  check on 2026-09-13. Both devices' 140 pak files match the local package.
- To ship it: **bump `pak.json` `version` and
  add a changelog entry** (e.g. `v1.0.1`). The Release workflow skips
  publishing when a release for the current version already exists.

## Repository state

| Item | State |
| --- | --- |
| Branch | `main`, tracking `origin/main`; default branch on GitHub is `main`; `scaffold` deleted |
| Changes after `3912078` | h700 power-button/audio support, device verification and unresolved flicker investigation |
| Release | `v1.0.0` (Latest), built from `3912078` |
| CI | v1.0.0 Build and Release succeeded; the h700 change set passed local compatibility checks and device smoke tests; its push triggers a fresh build |

Unreleased changes (all part of the h700 power work):

- `src/power-button.c` (new): power key helper for h700.
- `patches/0003-sdl-audio-suspend-signals.patch` (new): SIGUSR1/SIGUSR2 close
  and reopen ScummVM's audio device when `SCUMMVM_AUDIO_SIGNALS` is set.
- `Makefile`: `helpers` target (builds `build/helpers/power-button` with the
  pinned toolchain), `verify` also checks the helper, `package` ships
  `bin/power-button` and asserts it is in the archive.
- `launch.sh`: exports `NEXTUI_LD_LIBRARY_PATH` (NextUI's path before the pak's
  `lib/` is prepended); on h700 exports `SCUMMVM_AUDIO_SIGNALS=1` and starts
  `power-button scummvm &` instead of minui-power-control.
- `README.md`, `plans/02-controls-and-platforms.md`: document the above.
- `plans/03-handoff.md`, `plans/04-device-verification.md`: handoff, measured
  results and unresolved RG SP flicker follow-up.

## How the pak works (orientation)

- **Build:** one binary for all four platforms from the pinned tg5040 toolchain
  (glibc 2.28 sysroot, Cortex-A53). `make package` = checkout → patches →
  build → collect libs → helpers → verify → zip. Patches in `patches/` are
  applied idempotently by `scripts/docker-build.sh`; the three patches apply
  cleanly to pristine sources and reproduce the build checkout.
- **Firmware-provided libraries (never bundled):** SDL2, ALSA, libstdc++,
  libgcc_s, GPU drivers, glibc. `lib/` holds codecs only. `make package` fails
  if SDL2/ALSA/libstdc++/libgcc_s end up in `lib/`.
- **Controls:** `launch.sh` sets `SDL_GAMECONTROLLERCONFIG` per
  `$PLATFORM`/`$DEVICE` so buttons match printed labels; stickless devices map
  the d-pad hat to the left stick (virtual mouse). `keymaps/default.txt` holds
  the handheld keymap defaults (patch 0001, `SCUMMVM_KEYMAP_DEFAULTS`).
  `config/<DEVICE>.txt` holds per-device config defaults (patch 0001,
  `SCUMMVM_CONFIG_DEFAULTS`); only `config/brick.txt` (`kbdmouse_speed=1`)
  exists.
- **my355:** `SCUMMVM_IGNORE_KEYBOARD=1` (patch 0002), because the Flip reports
  every button both as a gamepad and as keyboard keys.
- **Power button:** minui-power-control 3.0.0 on tg5040/tg5050/my355. On h700
  its Go handler opens `event1` (the pad), so the pak uses `power-button`: it
  opens the input device whose EV_KEY bits include `KEY_POWER` (event0,
  `axp2202-pek`). Short press: SIGUSR1 → wait until ScummVM has no
  `/dev/snd/pcmC*p` open (≤ 2 s) → SIGSTOP → `$SYSTEM_PATH/bin/suspend` (run
  with `NEXTUI_LD_LIBRARY_PATH`; returns after wake) → SIGCONT → SIGUSR2, then a
  1 s cooldown. 2 s hold: `/tmp/poweroff` + SIGTERM ScummVM; the h700 launch
  loop runs `poweroff_next`. `POWER_BUTTON_DRY_RUN=1` logs instead of acting.

Full rationale, device research and the verification table are in
`plans/02-controls-and-platforms.md`.

## Verification status

| Area | Status |
| --- | --- |
| Controls, d-pad mouse, virtual keyboard (Brick screenshots) | Verified |
| tg5050 display (firmware libstdc++ fix, KMSDRM probe) | Verified; maintainer confirmed game renders |
| Brick pointer speed, Flip single-action buttons, h700 mouse | Maintainer confirmed |
| h700 power button: short press sleeps/wakes, 2 s hold powers off | Maintainer confirmed (with the build before the audio fix) |
| h700 audio after wake | **Pass (2026-09-13).** Maintainer confirmed sound returns after a real power-button sleep/wake. Fresh log shows successful kernel suspend/resume; ScummVM had reopened `/dev/snd/pcmC0D0p`, with no audio-handshake warning. The bluealsa pak-libz warning is also gone. |
| h700 `power-button` detection/timing | Dry run with injected KEY_POWER passed |
| tg5040 Smart Pro with the h700 power/audio candidate | **Pass (2026-09-13).** Maintainer confirmed the requested picture/audio, controls, virtual keyboard and sleep/wake check. Runtime uses firmware SDL2/ALSA/C++ libraries and minui-power-control on event1; `SCUMMVM_AUDIO_SIGNALS` is unset. |
| Controls and normal exit on h700 / tg5040 | Maintainer confirmed both; SSH checks show NextUI running, emulator and power helpers exited, `/tmp/stay_awake` removed. |

Detailed candidate identity, checks and limitations:
[04-device-verification.md](04-device-verification.md).

## Devices and deployment

Builds at the smoke test (installed via a stage-and-swap into
`/mnt/SDCARD/Emus/<platform>/SCUMMVMSA.pak`):

| Device | Platform / `DEVICE` | Build on device |
| --- | --- | --- |
| TrimUI Smart Pro | tg5040 / `smartpro` | **unreleased** h700 power + audio build, regression checked |
| TrimUI Brick | tg5040 / `brick` | v1.0.0 content |
| TrimUI Smart Pro S | tg5050 / `smartpros` | v1.0.0 content |
| Miyoo Flip | my355 / `my355` | v1.0.0 content |
| Anbernic RG SP | h700 / `rgsp` | **unreleased** h700 power + audio build |

The maintainer subsequently reinstalled BaseOS/NextUI on the RG SP while
investigating flicker; recheck its installed files before further comparisons.

Every device has Freddi Fish (Dutch, `scumm:freddi`, from the maintainer's own
disc) in the NextUI layout: `Roms/ScummVM (SCUMMVMSA).disabled/<Game>/` with
the game files, `.scummvm` and `.m3u`, plus a `Roms/<Game> (SCUMMVMSA)/`
shortcut folder and `.media` artwork.

Device IPs and SSH passwords are not recorded here (public repo); ask the
maintainer. Notes for working with them:

- Smart Pro rollback copy from this verification:
  `/mnt/SDCARD/Emus/tg5040/.SCUMMVMSA-v1.0.0-backup-20260913`.

- **Never** start a pak by writing `/tmp/next` and killing `nextui.elf` on the
  TrimUI devices: once the queued command exits, the device powers off
  (reproduced with a dummy `sleep` command). Ask the maintainer to launch from
  the NextUI menu, or run ScummVM beside NextUI/NativeSSH using that process's
  environment (`/proc/<pid>/environ`).
- my355 and h700 are reached through the NativeSSH pak. The Flip's host key
  changes on every reboot (remove the stale `known_hosts` entry after the
  maintainer confirms), and DHCP addresses have moved during testing.
- SSH logins occasionally fail with "Permission denied" once and succeed on
  retry.
- Useful checks: the pak log is `.userdata/<platform>/logs/SCUMMVMSA.txt`;
  `/dev/fb0` dumps work as screenshots on the mali devices (Brick, h700), not
  on KMSDRM (tg5050, my355). Input can be tested by writing `input_event`
  structs to the pad's evdev node (a small helper built with the toolchain;
  the earlier copy lived in the session scratchpad and is gone).

## Next steps

1. RG SP audio retest and Smart Pro regression check passed on 2026-09-13;
   optionally re-check the RG SP's 2 s shutdown with the audio candidate.
2. If audio still fails, check `SCUMMVMSA.txt` for "Audio device still open
   after 2 s" (helper) or "Could not reopen the audio device after resume"
   (ScummVM); the fallback is NextUI's own approach of fully quitting audio
   before sleep, which is what patch 0003 already does via `suspendAudio()`.
3. Investigate the RG SP flicker before publishing a new release. The source
   changes are being committed/pushed without a version bump; `v1.0.0`
   already exists, so the Release workflow builds but skips publication.
   When ready to release, bump `pak.json` and add a changelog entry.
4. Remaining open items (from plan 02): Brick Pro L4/R4 and second Menu key
   are unmapped (beyond SDL's X360 mapping); rg28xx rotated panel untested;
   optionally propose capability-based power key detection upstream to
   minui-power-control so h700 would not need the pak's helper.
