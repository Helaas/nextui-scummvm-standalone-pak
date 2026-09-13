# nextui-scummvm-standalone-pak

NextUI emulator pak bundling **standalone ScummVM** — the full ScummVM
experience (GUI launcher, per-game options, keymapper, virtual keyboard)
instead of the libretro core.

ScummVM runs hundreds of classic point-and-click adventure games (LucasArts,
Sierra, Humongous Entertainment, Revolution, …). See the
[compatibility list](https://www.scummvm.org/compatibility/).

## Why standalone?

The libretro [ScummVM.pak](https://github.com/laesetuc/minui-scummvm) is
great for jumping straight into a game, but the standalone build gives you:

- The full ScummVM GUI: add/edit games, per-game graphics/audio/control options
- The keymapper GUI — rebind any action to any button, per game
- The virtual keyboard (for typing save names)
- Modern ScummVM defaults and the complete set of stable engines

Power button **deep sleep** and **shutdown** are provided by
[minui-power-control](https://github.com/ben16w/minui-power-control).

> [!NOTE]
> NextUI menu integration does not apply to standalone emulators: no save
> states from the NextUI menu, no in-game NextUI options. Use ScummVM's own
> menu (press **Menu** — see Controls) to
> save, load, and quit.

## Supported Platforms

| Platform | Device                                                                 |
| -------- | ---------------------------------------------------------------------- |
| tg5040   | TrimUI Brick / Brick Pro / Smart Pro                                   |
| tg5050   | TrimUI Smart Pro S                                                     |
| my355    | Miyoo Flip                                                             |
| h700     | Anbernic H700 devices ([unofficial NextUI port](https://github.com/pvaibhav/NextUI/tree/h700)) |

One binary serves every platform. It is compiled with the pinned
`ghcr.io/loveretro/tg5040-toolchain` image, whose glibc 2.28 sysroot is older
than every firmware's, tuned for Cortex-A53 (which also runs on the A55
devices). SDL2, ALSA, and the C++ runtime are not bundled: each firmware's own
SDL2 supplies the right video and input backend (mali on tg5040/h700, KMSDRM on
tg5050/my355), and its GPU driver needs the firmware's libstdc++.

## Building

Requires Docker.

```sh
# Build ScummVM and create build/release/SCUMMVMSA.pak.zip
make package

# Cross-compile only (stages into build/stage)
make build

# Check the binary's architecture, RPATH, glibc ceiling, and library closure
make verify

# Push the assembled pak to a device connected over adb
make deploy

# Clean build artifacts (preserves cached source)
make clean

# Clean everything including cached source
make distclean
```

`make package` verifies the binary and asserts that `launch.sh`, `pak.json`,
`bin/scummvm`, `bin/minui-power-control`, and `keymaps/default.txt` sit at the
archive root, and that no SDL2, ALSA, libstdc++, or libgcc_s slipped into
`lib/`.

The build applies `patches/*.patch` to the ScummVM checkout:

- `0001` lets the POSIX backend read handheld keymap defaults from the file
  named by `SCUMMVM_KEYMAP_DEFAULTS` (see `keymaps/default.txt`) and config
  defaults from `SCUMMVM_CONFIG_DEFAULTS` (per device, see `config/brick.txt`).
- `0002` makes the SDL backend ignore keyboard events when
  `SCUMMVM_IGNORE_KEYBOARD` is set. The Miyoo Flip reports its buttons both as
  a gamepad and as keys, which would otherwise trigger two actions per press.

## Installation

### Via Pak Store (Recommended)

1. Open **Pak Store** on your NextUI device.
2. Search for **SCUMMVMSA** and tap **Install**.
3. Pak Store downloads `SCUMMVMSA.pak.zip` and extracts it into
   `Emus/<platform>/SCUMMVMSA.pak/` for your device.

### Manual Installation

1. Download `SCUMMVMSA.pak.zip` from the
   [latest release](https://github.com/Helaas/nextui-scummvm-standalone-pak/releases).
2. Extract the contents of the archive into
   `Emus/<platform>/SCUMMVMSA.pak/` on your SD card, replacing `<platform>`
   with `tg5040`, `tg5050`, `my355`, or `h700`.

   The archive has no enclosing folder, so create `SCUMMVMSA.pak/` first. It
   contains `launch.sh`, `pak.json`, `LICENSE`, `README.md`, `bin/`, `lib/`,
   and `share/`.

## Games

Place each game in its own folder under a folder suffixed with `(SCUMMVMSA)`
so NextUI associates it with this pak, and add a `.scummvm` shortcut file
containing the game's ScummVM ID:

```
Roms/
└── ScummVM (SCUMMVMSA)/
    └── The Secret of Monkey Island/
        ├── The Secret of Monkey Island.scummvm   ← contains: scumm:monkey
        ├── MONKEY.000
        └── MONKEY.001
```

The game ID (`engine:game`, e.g. `scumm:monkey`) comes from the
[ScummVM compatibility list](https://www.scummvm.org/compatibility/) — or
launch the pak on any folder without a shortcut to open the ScummVM GUI
launcher and use **Add Game…**, which detects IDs for you.

A `.m3u` file pointing at the `.scummvm` file also works (same convention as
the libretro pak), so both paks can share one set of game folders.

Saves go to `Saves/SCUMMVMSA/` on the SD card. ScummVM's config lives in
`.userdata/<platform>/SCUMMVMSA-scummvm/`.

## Controls

Buttons follow their printed labels and NextUI's conventions:

| Button     | Action                                          |
| ---------- | ----------------------------------------------- |
| A          | Left click / select in menus                    |
| B          | Right click / back in menus                     |
| Y          | Skip cutscene (Esc)                             |
| X          | Skip line (.)                                   |
| Menu       | ScummVM menu (save, load, options, quit)        |
| Start      | The game's own menu (F5)                        |
| Select     | Virtual keyboard                                |
| L1 (hold)  | Slow, precise mouse                             |
| R1         | Enter                                           |
| L2         | Pause (Space)                                   |
| L3 / F1    | Middle click                                    |
| Left stick | Mouse                                           |
| D-pad      | Arrow keys (menus, keyboard-driven games)       |

On devices without analog sticks (TrimUI Brick; Anbernic RG28XX, RG34XX,
RG35XX Plus/2024, RG35XX SP, RG SP) the **d-pad moves the mouse** instead. The
Brick starts at half ScummVM's default pointer speed; change it on any device
under **Options… → Controls → Pointer Speed**.

A few engines ship their own control schemes (for example Blade Runner,
Grim Fandango, and The Longest Journey) and keep them, apart from Start
opening the game menu. Everything is rebindable, globally or per game, in
ScummVM under **Options… → Keymaps**; your changes override the pak's defaults.

### Typing with the virtual keyboard

1. Press **Select** to open the keyboard (ScummVM also opens it when a game
   asks for text).
2. Move the cursor over a key with the left stick (d-pad on stickless
   devices; hold **L1** for precision) and press **A**. The text appears in
   the field at the top; **↵** sends Enter and **←** deletes.
3. Press the green **✓** to send the text to the game, or the red **✗** to
   cancel.

### Power button

On tg5040, tg5050, and my355:

- **Short press**: deep sleep / wake
- **Hold 2 s**: shut down (does **not** save — save first!)

minui-power-control does not support the h700 port, so the pak leaves the
power button alone there: save and quit through the ScummVM menu.

## Releasing

The **Build** workflow runs `make package` on every pull request and attaches
`SCUMMVMSA.pak.zip` to the run as an artifact.

To publish, bump `version` in `pak.json`, add a `changelog` entry for that
version, and merge to `main`. The **Release** workflow builds the archive
and, if no release with that tag exists yet, creates one with
`SCUMMVMSA.pak.zip` attached and the changelog entry as its notes.

## Versions

- ScummVM is pinned to
  [`fed42f2`](https://github.com/scummvm/scummvm/commit/fed42f2068dcafc6aafa1c28c77e4c88def74b66)
  (v2026.3.0) for reproducible builds.
- minui-power-control is pinned to
  [3.0.0](https://github.com/ben16w/minui-power-control/releases/tag/3.0.0)
  (sha256-verified at build time).

## Acknowledgements

- [ScummVM](https://www.scummvm.org/) (GPLv3)
- [minui-power-control](https://github.com/ben16w/minui-power-control) by ben16w
- [NextUI](https://github.com/LoveRetro/NextUI)
- Pak structure modeled on
  [nextui-gppx-pak](https://github.com/Helaas/nextui-gppx-pak)

## License

MIT (this packaging repo). ScummVM itself is
[GPLv3](https://github.com/scummvm/scummvm/blob/master/COPYING).
