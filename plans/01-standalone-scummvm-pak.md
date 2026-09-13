# Plan: Standalone ScummVM pak for NextUI

## Status

- Scaffold complete: Makefile, launch.sh, pak.json, scripts, CI workflows,
  README. ScummVM checkout (fed42f20 / v2026.3.0) and minui-power-control
  3.0.0 (sha256-verified) fetch cleanly.
- `make package` was interrupted mid-compile (partial objects in
  `.cache/scummvm`). Resume with `make package`; use `make distclean` first
  for a from-scratch build.
- Not yet done: first successful package, on-device testing, GitHub repo push.

## Goal

A reproducible build that produces `SCUMMVMSA.pak.zip`: a standalone ScummVM
pak for NextUI, cross-compiled inside the pinned tg5040 toolchain Docker image.
Modeled on [Helaas/nextui-gppx-pak](https://github.com/Helaas/nextui-gppx-pak)
(same Makefile structure, verify step, pak.json metadata, CI build/release
workflows). Power button support comes from
[ben16w/minui-power-control](https://github.com/ben16w/minui-power-control).

This is a *type 3* pak per NextUI's `PAKS.md` (bundled standalone emulator):
no minarch integration, no save states from the NextUI menu, no consistent
in-game menu. It exists alongside the libretro `ScummVM.pak`
(laesetuc/minui-scummvm) as an alternative with the full ScummVM GUI,
per-game options, virtual keyboard, GUI launcher, and proper engine coverage.

## Research summary (verified against device + toolchain)

### Device (TrimUI Smart Pro, tg5040, connected via adb)

- aarch64, kernel 4.9.191, PowerVR GE8300 (libEGL/libGLESv2 in `/usr/lib`).
- `/usr/trimui/lib` has TrimUI-patched SDL2 2.30.8 (`mali` video driver) plus
  SDL2_image/mixer/ttf and SDL 1.2.
- Gamepad is `TRIMUI Player1`, USB VID:PID `045e:028e` (Xbox 360 IDs) —
  covered by SDL2's built-in gamecontroller mapping, no extra DB needed.
- Power button is `/dev/input/event1` (handled by minui-power-control).
- Existing `ScummVM.pak` on the SD card is the **libretro** core — our pak
  must use a distinct tag: **`SCUMMVMSA`**.
- ROM convention in use: `/Roms/<Game> (SCUMMVM)/` folders containing a
  `.scummvm` file (holds the game ID, e.g. `scumm:monkey`) and an `.m3u`
  pointing at the `.scummvm` file.

### Toolchain (`ghcr.io/loveretro/tg5040-toolchain@sha256:f131c6af…`)

- `aarch64-nextui-linux-gnu-gcc` 8.3.0 (crosstool-NG), glibc 2.28 sysroot —
  older than every supported firmware's glibc, so binaries run everywhere.
- Sysroot includes SDL2 2.26.1 dev files (`sdl2-config`, headers, libs) with
  the `mali` video driver, plus zlib, libpng, libjpeg, freetype, mad, vorbis,
  ogg, theora, FLAC, sndfile, samplerate, bz2, lzma, zstd, alsa, evdev.
- ScummVM 2026.3.0 requires only C++11 → gcc 8.3 is sufficient.

### minui-power-control 3.0.0

- Release asset is a single makeself self-extracting binary
  (sha256 `9ea701b145b876a8f65b4152f1d6bf273069d16ad5aa8d91e615639f43e10c6e`).
- Usage: `minui-power-control <emulator-process-name> &` started right before
  the emulator; it finds the emulator PID, watches the power button
  (short press = deep sleep, 2 s hold = shutdown) and exits with the emulator.
- Same pattern as the device's PSP.pak.

## Build design

```
Makefile
├── checkout   Clone scummvm @ v2026.3.0 (commit fed42f20) into .cache/scummvm
├── deps       Download minui-power-control 3.0.0 into .cache, verify sha256
├── build      Docker: configure + make + strip + make install (staging)
├── verify     scripts/verify-binary.sh: AArch64, glibc ≤ 2.28, NEEDED closure
├── package    Assemble SCUMMVMSA.pak → build/release/SCUMMVMSA.pak.zip
└── deploy     adb push pak to /mnt/SDCARD/Emus/tg5040/ (local testing)
```

ScummVM configure (inside container, cross-compile):

- `--host=aarch64-nextui-linux-gnu`
- `--enable-release --disable-debug --enable-optimizations`
- `--disable-cloud --disable-sdlnet --disable-libcurl --disable-discord`
  (no networking on device; keeps deps minimal)
- `--disable-fluidsynth` (no soundfont on device)
- default (stable) engine set
- SDL2 detected via the sysroot's `sdl2-config`
- CPU flags: `-mcpu=cortex-a53 -mtune=cortex-a53` (runs on A53 + A55)

### Pak layout (archive root)

```
launch.sh                  # entry point
pak.json                   # Pak Store metadata
LICENSE  README.md
bin/scummvm                # stripped binary
bin/minui-power-control    # pinned makeself binary (power button daemon)
lib/*.so                   # SDL2 + codec libs from the toolchain sysroot
share/scummvm/             # themes, engine data (.dat), translations
```

`lib/` deliberately excludes GPU libs (libEGL/libGLESv2 come from the
device's `/usr/lib`) and glibc core libs (device firmware is newer).

### launch.sh behavior

1. Log to `$LOGS_PATH/SCUMMVMSA.txt` (NextUI convention).
2. `HOME=$USERDATA_PATH/SCUMMVMSA-scummvm`, saves in `$SAVES_PATH/SCUMMVMSA`.
3. `LD_LIBRARY_PATH=$PAK_DIR/lib:/usr/trimui/lib:…`
4. Resolve `$ROM`: `.m3u` → follow to `.scummvm` (up to 3 hops) → game ID =
   file contents, game dir = its folder. No/invalid ROM → ScummVM GUI launcher.
5. `echo 1 > /tmp/stay_awake` (no idle sleep mid-game), removed on exit.
6. `minui-power-control scummvm &` then run
   `scummvm --fullscreen --config=… --savepath=… --themepath=… --extrapath=…
   -p "$GAME_DIR" "$GAME_ID"`.
7. On exit, cleanup runs and NextUI returns to the menu.

### Verification (scripts/verify-binary.sh, runs in container)

- ELF is AArch64 EXEC, stripped.
- No RPATH/RUNPATH.
- Highest GLIBC_ symbol ≤ 2.28.
- Every `NEEDED` resolves from pak `lib/` or a device-provided allowlist
  (libc, libpthread, libdl, libm, librt, ld-linux, libEGL, libGLESv2,
  libasound, …).

### CI

- `build.yml`: PR + dispatch, `ubuntu-24.04-arm` runner, `make package`,
  uploads `SCUMMVMSA.pak.zip` artifact. Generous timeout (full ScummVM build).
- `release.yml`: push to main → build → if `pak.json` version has no release
  yet, publish GitHub Release with the zip and changelog notes from pak.json.

## Steps

1. ✅ Research (this document)
2. Scaffold repo files
3. `make package` locally (Docker)
4. `make deploy` → test on device: launch game, controls, power button
   sleep/shutdown, save/load, quit back to NextUI menu
5. `gh repo create` + push (ask before git mutations)
6. Verify CI build, tag v1.0.0 release

## Open questions / risks

- ScummVM GUI scale/perf on 1024x768 (Brick) vs 1280x720 (Smart Pro) — tune
  defaults after on-device test.
- Full build time on 4-core CI runners — mitigate with high timeout; consider
  trimming engines later if needed.
- Audio crackling (libretro pak needed fixed CPU speed) — watch during test.
