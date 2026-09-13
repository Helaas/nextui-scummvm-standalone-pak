# Device verification: h700 and tg5040 (2026-09-13)

## Follow-up: RG SP display flicker remains unresolved

After the smoke test, the maintainer reported brightness fading in both Game
Boy and ScummVM, including the paused Game Boy menu, but not the NextUI
launcher. Reinstalling BaseOS and NextUI did not remove it; charger removal
and minimum/maximum brightness did not help. The earlier audio/control passes
do not clear this subsequent visual issue.

Read-only inspection found minarch running with neither ScummVM nor its
power-button helper active. Six framebuffer samples taken one second apart
had identical contents for each of the two buffer pages. Display status
samples reported a fixed backlight value of 200, approximately 60 Hz and no
reported display errors. This suggests a problem downstream of rendered
pixels, but sparse samples cannot rule out all timing or scanout issues.

The pak helper makes no panel-voltage, display-timing or firmware writes.
It delegates suspend and shutdown to NextUI. Upstream H700 `poweroff_next`
does write PMIC interrupt and shutdown-control registers; no display-timing
or panel-voltage writes were found in that source. No causal link to the
helper, hardware damage, or definitive flicker diagnosis has been established.
No device settings were changed during this investigation.

## Original smoke test

The maintainer confirmed that audio returns on the RG SP after a real
power-button sleep/wake, and that the same candidate passes the requested
Smart Pro regression check. No implementation changes were needed during
this verification. This is a Freddi Fish smoke test on these two devices,
not coverage of every engine or supported handheld.

## Candidate

The h700 power-button/audio changes after `3912078`, uncommitted at the time
of testing. The candidate identifies as `v1.0.0`. The subsequent source push
keeps that version unchanged and does not publish a new release.

| Artifact | SHA-256 |
| --- | --- |
| `build/release/SCUMMVMSA.pak.zip` | `b687ea261a924d2e42ef948e568b942de54a510f9066957b86b4e14b24fe07d5` |
| `bin/scummvm` | `6576f3da991e1922a43d6cc8c7d838ffbe21677dc1bffcd432a3353814daf5e7` |
| `bin/power-button` | `09a0cba1baf45a62199cdda44983d34e2b07fc6fdeea650b18b2299a5ac49b71` |
| `launch.sh` | `1a3bd90aa78749bfdc15a21a57516a62eaecb77bb8576fc5b41d60afb00804b2` |

The RG SP already had this build. The Smart Pro was updated using a staged
copy of its installed pak, replacing its four differing files (`README.md`,
`launch.sh`, `bin/scummvm`, and the new `bin/power-button`). All 140 candidate
files passed SHA-256 comparison on each device before testing.

Smart Pro's previous pak is retained at
`/mnt/SDCARD/Emus/tg5040/.SCUMMVMSA-v1.0.0-backup-20260913`. Game files,
configuration and saves were not modified by deployment. Both games were
launched by the maintainer through NextUI.

## Checks

| Check | Result |
| --- | --- |
| `make verify` with pinned Docker toolchain | Pass for ScummVM and power-button: AArch64, stripped, no RPATH, glibc ≤ 2.28, dependency closure satisfied |
| `sh -n launch.sh`, `git diff --check` | Pass |
| ZIP integrity and contents compared with assembled pak | Pass: 140 files; no bundled SDL2, ALSA, libstdc++ or libgcc_s |
| Cached ScummVM source identity and three patches | Pinned `fed42f2068dcafc6aafa1c28c77e4c88def74b66`; all three patches reverse-check cleanly |
| h700 RG SP: power-button detection | Fresh log listens on event0; `SCUMMVM_AUDIO_SIGNALS=1` |
| h700: actual short-press sleep/wake with game sound | Pass, maintainer: "Yep audio worked"; kernel suspend returns 0, helper resumes, live ScummVM has playback PCM open afterward |
| h700: audio/runtime warnings | No audio-close timeout, audio-reopen warning or bluealsa pak-libz warning in fresh cycle |
| h700: exit cleanup | ScummVM and helper absent, NextUI running, `/tmp/stay_awake` removed |
| h700: d-pad mouse, A click, Menu, Select keyboard and return to NextUI | Pass, maintainer confirmed controls and return to NextUI ("both ok") |
| tg5040 Smart Pro: picture, audio, left-stick mouse, A click, Menu, Select keyboard, short-press sleep/wake | Pass, maintainer: "verified ok on tg5040" in response to the requested checklist |
| tg5040: runtime isolation | `SCUMMVM_AUDIO_SIGNALS` unset; original minui-power-control button-handler on event1; no h700 helper used |
| tg5040: firmware libraries | SDL2 `/usr/trimui/lib/libSDL2-2.0.so.0.3000.8`, ALSA `/usr/lib/libasound.so.2.0.0`, C++ `/usr/lib/libstdc++.so.6.0.28`, GCC runtime `/lib/libgcc_s.so.1` |
| tg5040: process/audio after power test | Same ScummVM PID 3405 alive, playback PCM open, ALSA reports RUNNING |
| tg5040: normal exit to NextUI | Pass, maintainer confirmed; ScummVM and button-handler absent, NextUI running, `/tmp/stay_awake` removed; log confirms power-control cleanup |

Device clocks differ; timestamps in their logs should not be compared
directly. The fresh h700 cycle logs suspend at 13:10:40 and helper resume at
13:10:47; Smart Pro logs candidate startup at 22:33:19 and short press at
22:33:32.

## Observed warnings and limits

The h700 firmware suspend script still reports an unavailable `mcu_pwr`
attribute and ALSA UCM configuration import errors. The observed cycle
nevertheless resumes with working sound. These are not the candidate's
audio-close/reopen warnings.

Smart Pro logs EGL configuration fallback messages and a 940-versus-1024
audio-buffer warning that also appear in its pre-update log. Two ALSA
underruns occur around the candidate's power test; the maintainer confirmed
the test passed. No claim is made that its logs are warning-free.

The 2-second shutdown path was confirmed with the earlier h700 build and was
not repeated in this session. Save/load, Bluetooth audio output, prolonged
play, repeated sleep cycles, other ScummVM engines, and the other device
models were not covered by this smoke test.
