# Benchmark: Odin port against the C++ original (2026-10-20)

Packages:
- C++ `b223c1a`: `/nix/store/1jgbzwzc…-waylandshader-gnome-0.1.0`.
- Odin, the accepted `ODIN-refactor` build: `/nix/store/njp9almx…` for run 1, and the rebuild with the reference fix below, `b4hc3j24…`, for run 2. Their sources differ only in `gnome/default.nix`.

Method:
- **Isolation:** `gnome/tests/isolated-session.sh` in a `/tmp` copy with two changes: `LIBGL_ALWAYS_SOFTWARE` is removed, so the Shell renders on the AMD GPU through `amdgpu` (`radeonsi`), and the monitors are `1920x1080@60` + `2560x1440@60`. The live session was not involved.
- **Order:** C++, Odin, C++, Odin.
- **Windows:** each scenario gets 5 s of warm-up, then 3 windows of 10 s.
- **CPU:** utime+stime of the gnome-shell process from `/proc/<pid>/stat`, at 0.1 % resolution.
- **GPU:** gnome-shell's DRM fdinfo, with each DRM client counted once. GPU time is `drm-engine-gfx`; VRAM is the resident VRAM.
- **Preset:** `tests/fixtures/temporal.slangp`, a two-pass preset with history, feedback, mipmaps and a LUT, on both outputs.

## Compositor (gnome-shell process)

| Scenario | CPU C++ | CPU Odin | GPU C++ (ms/s) | GPU Odin (ms/s) | VRAM C++ (MiB) | VRAM Odin (MiB) | RSS C++ (MiB) | RSS Odin (MiB) |
|---|---|---|---|---|---|---|---|---|
| Extension disabled | 0.31 % | 0.34 % | 0.00 | 0.00 | 205.6 | 204.6 | 250 | 246 |
| Color only, idle desktop | 0.07 % | 0.03 % | 0.01 | 0.01 | 433.3 | 432.3 | 249 | 245 |
| Preset on both outputs | 7.88 % | 7.89 % | 67.1 | 66.0 | 727.8 | 734.3 | 306 | 301 |
| Preset + color | 8.03 % | 7.95 % | 70.6 | 69.3 | 697.9 | 719.3 | 305 | 301 |

- **Spread:** per-window GPU time ranged from 63.7 to 68.3 ms/s with the preset, for both builds. The differences between builds are smaller than that spread.
- **Master bypass:** after a preset, bypass releases VRAM back to about 210 MiB in **both** builds, but with a delay. Each build was observed both still holding about 700 MiB for 30 s and already released, so averages over these windows aren't meaningful.
- **What the GPU time covers:** gnome-shell's whole GPU time, that is the effect plus the stage repaint it forces. An idle desktop doesn't repaint at all.

## Clients

| | C++ | Odin |
|---|---|---|
| `waylandshader-gnomectl --help` (hyperfine, 40 runs ×2) | 4.73 ms | 2.59 ms |
| `waylandshader-gnomectl status` | 6.39 ms | 5.49 ms |
| Controller RSS / threads | 66.8 MiB / 13–14 | 42.9 MiB / 7–8 |
| Controller startup CPU / idle CPU | 100 ms / 0 | 150 ms / 0 |

## Footprint

| | C++ | Odin before the fix | Odin after the fix |
|---|---|---|---|
| Package | 788 KiB | 1.4 MiB | 1.4 MiB |
| Runtime closure | 1.5 GiB | 3.3 GiB | 1.3 GiB |

- **Cause:** Odin embeds core-library source paths (used in panic and bounds-check messages). Nix treated them as a runtime dependency on the compiler and its LLVM/GCC closure.
- **Fix:** `gnome/default.nix` strips the reference with `remove-references-to`, and `disallowedReferences = [ pkgs.odin ]` makes any regression fail the build. The fixed package passes 18/18 CTest.

## Not measured

- Frame count. Both builds are assumed to have rendered at the full 60 Hz on both outputs; equal CPU and GPU time supports this.
- Heavy real-world presets.
- Physical displays.
- Build time, because the two builds run different test suites.
