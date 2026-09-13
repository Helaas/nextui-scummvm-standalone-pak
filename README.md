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
> menu (default: press the ScummVM Global Menu button — see Controls) to
> save, load, and quit.

## Supported Platforms

| Platform | Device                   |
| -------- | ------------------------ |
| tg5040   | TrimUI Brick / Smart Pro |

The binary is compiled with the pinned `ghcr.io/loveretro/tg5040-toolchain`
image, whose glibc 2.28 sysroot is older than the firmware's, tuned for
Cortex-A53.

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
`bin/scummvm`, and `bin/minui-power-control` sit at the archive root.

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
   with `tg5040`.

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

ScummVM's default gamepad mapping applies (d-pad/stick = mouse, A = left
click, B = right click, Start = ScummVM Global Menu). Everything is
rebindable per game in ScummVM under **Options… → Controls**.

Power button:

- **Short press**: deep sleep / wake
- **Hold 2 s**: shut down (does **not** save — save first!)

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
