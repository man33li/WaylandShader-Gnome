# Handoff: Odin refactor of the GNOME backend

**State:** phase 4 accepted in round 5 after 4 of 5 rework rounds; build commit `f1a7b7b` on `ODIN-refactor`. See `../GATES.md` and `../04-verification/acceptance.md` (Round 5).

## Accepted deviations

- **D1:** the monitor combo popup has no per-item tooltips. GTK 3 combo popups have none; the combo's own tooltip shows the selected id.
- **D2:** GTK 3 spin buttons ignore *stepping* increments of 1e-10 or less. Typed values stay exact (verified: `1.0000001e-7` commits as exactly `f32(1.0000001e-7)`).

Both are recorded in `../02-design/decision.md`. The GUI stays GTK 3 by user decision (Clay + raylib rejected).

## Left for you

1. **T-HW** (`../01-requirements/requirements.md`): install the package system-wide, start a fresh GNOME login, and check the physical displays.
   - Shading, gamma/saturation, HDR identity, hotplug, suspend.
   - Whether the pointer is shaded with the scene: the devkit viewer can't show this for either build.
   - Small-damage redraws (a blinking text cursor).
   - Proving the native effect needs a direct KMS scanout capture, because GNOME screenshots and screencasts see the unfiltered scene (`README.md:229`).
2. **T-SAFETY and T-DOCS sign-off:** review `gnome/tests/isolated-session.sh`, the build log, and the GNOME sections of `README.md` / `docs/GNOME.md`.
3. **Merging:** `ODIN-refactor` is not pushed or merged.

## How the visual checks were run

The method is recorded in `../04-verification/visual-checks.md`. In short:
- Each disposable Shell runs through `isolated-session.sh` (`WS_DEVKIT=1` for render checks), and is driven with `waylandshader-gnomectl` on `$WS_PRIVATE_BUS`.
- Screenshots come from the xdg-desktop-portal Screenshot API.
- The GUI is driven through AT-SPI with `AT_SPI_BUS_ADDRESS` set to the host a11y bus.
- The C++ build from `b223c1a` serves as the pixel and accessibility oracle.
- Agent limits:
  - subagents cannot get desktop control;
  - omp's own Wayland screen capture is not in the released build;
  - an AT-SPI press that opens a modal GTK dialog blocks until the dialog closes, so use direct AT-SPI calls with short timeouts.

## Environment notes

- **Baseline worktree:** the C++ worktree at `/tmp/ws-baseline` (`b223c1a`) feeds the baseline-differential tests. If `/tmp` was cleared, recreate it with `git worktree add --detach /tmp/ws-baseline b223c1a`, then `nix-build gnome/default.nix -o /tmp/ws-baseline-result` inside it.
- **Role agents:** `.omp/agents/` holds the role agents, with model and effort pinned per role. This clone is used from `/home/knd/AI/dodForPonytail`, whose `.omp/agents` is a symlink to them.
- **Screenshot permission:** the portal permission was granted for unsandboxed host apps during this work. Revoke it with:

  ```sh
  gdbus call --session --dest org.freedesktop.impl.portal.PermissionStore \
    --object-path /org/freedesktop/impl/portal/PermissionStore \
    --method org.freedesktop.impl.portal.PermissionStore.DeletePermission screenshot screenshot ''
  ```

- **Install:** a native-module change needs a fresh GNOME login, never a compositor restart.
