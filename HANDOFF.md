# Handoff: WaylandShader GNOME backend (Odin version and the next task)

All future work on this project starts in this folder: `/home/knd/AI/dodForPonytail/WaylandShader-gnome`. GitHub: `man33li/WaylandShader-Gnome`, remote `github`.

To start the next task, run this from this folder:
`omp "Read HANDOFF.md, then do its Next task."`

## State (2026-10-20)

**Odin port:** done and accepted. Branch `ODIN-refactor` is pushed. It took 5 review rounds and 4 reworks.

The whole record is in `docs/waterfall/`:
- `GATES.md`: every gate and decision. Read it first.
- `01-requirements/requirements.md`: the requirement IDs and the test catalog with exact commands.
- `02-design/`: both plans, the decision and the design.
- `03-implementation/build-log.md`.
- `04-verification/`: the reviews, the acceptance and `visual-checks.md` (how the render and GUI checks were done).
- `05-maintenance/`: `handoff.md` (the user's open items) and `benchmark.md` (compositor CPU, GPU and VRAM, client latency and memory, closure size, compared with the C++ original).

**Results:**
- `nix-build gnome/default.nix` passes 18/18 CTest.
- The KWin build is unaffected.
- Runtime cost equals the C++ original within noise; the CLI and GUI are lighter.
- The runtime closure is 1.3 GiB, against 1.5 GiB for C++.

**Not done yet (user):**
- Installing it on the system: `/etc/nixos/flake.nix:27` still points at `ref=gnome-backend` in `/home/knd/AI/WaylandShader-gnome`, which has `ODIN-refactor` fetched.
- The hardware test T-HW and the T-SAFETY/T-DOCS sign-offs.
- Merging. Accepted deviations D1 and D2 are in `02-design/decision.md`.

**Oracle:**
- The C++ original at `b223c1a` is checked out at `/tmp/ws-baseline` and built at `/tmp/ws-baseline-result`.
- If `/tmp` was cleared, recreate it: `git worktree add --detach /tmp/ws-baseline b223c1a`, then run `nix-build gnome/default.nix -o /tmp/ws-baseline-result` in that worktree.

**Safety:**
- A live GNOME 50.5 Wayland session runs on this machine. Never load a native module into it, never enable the extension on the live bus, never restart the compositor.
- Run every Shell-hosted check through `gnome/tests/isolated-session.sh`.

## Next task: a Rust version, as the next test of the packaged workflow

**Goal:** port the GNOME backend to Rust with the same contract the Odin port met:
- the native `ClutterEffect` library behind the unchanged `WaylandShader-1.0` GIR API;
- the shader runtime, using the private patched librashader 0.10.1;
- the D-Bus client;
- `waylandshader-gnomectl`;
- the GTK 3 controller.

Constraints:
   - `git mv docs/waterfall docs/waterfall-odin` and keep it as reference. Point the README `Load:` line's benchmark link at the new path.
- No new features.
- The KWin backend keeps building.

**How:** use the installed waterfall workflow. Write nothing in the prompt or in project docs about how to run it beyond this file. This run is the first real use of the packaged workflow, and that is part of what it tests.

1. **Branch:** `RUST-refactor` from `ODIN-refactor`.
   - `git mv docs/waterfall docs/waterfall-odin` and keep it as reference.
   - Then scaffold a fresh `docs/waterfall/`.
   - The Odin sources stay on their branch and are replaced in the Rust branch (clean cutover).
2. **Oracle:** the C++ build at `b223c1a` is the primary oracle. The Odin build (`nix-build gnome/default.nix` on `ODIN-refactor`) is a second implementation to cross-check against.
3. **Tests to reuse:** the language-neutral tests from `docs/waterfall-odin/01-requirements/requirements.md`:
   - the GJS contract tests: native contract, parser corpus, path, BOM;
   - the CLI goldens and `iso-cli.sh`;
   - the GIR, ELF, layout and wrapper checks;
   - the isolated-session harness and the visual-check method.

   Port the language-specific unit, GL and accessibility tests.
4. **Performance:** rerun the method in `docs/waterfall-odin/05-maintenance/benchmark.md` for C++, Odin and Rust. The README `Load:` line is the target.
5. **Packaging:** `gnome/default.nix` must keep the runtime closure free of build tools. Check it with `nix path-info -Sh` and `disallowedReferences`.

**Known facts that save time:**
- librashader is itself a Rust crate. This project ships a patched private build (`patches/librashader-gl-lifetime.patch`, SONAME `libwaylandshader-rashader.so.2`), and the patch's behavior must be kept.
- Odin embedded source paths in its binaries; the equivalent check for a Rust build is the same `nix path-info` / `disallowedReferences` test.
- Main-session visual checks work:
  - screenshots through the xdg-desktop-portal Screenshot API (already permitted on this machine);
  - the GUI is driven through AT-SPI;
  - the devkit viewer shows the effect's real framebuffer;
  - GNOME screenshots show the unfiltered scene.
