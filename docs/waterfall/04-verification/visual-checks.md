# Visual checks: T-ISO-RENDER and T-GUI (main agent, 2026-10-20)

Build under test: `6f6709d` (rework round 3), package `/nix/store/9hfbxb7zaj…-waylandshader-gnome-0.1.0`. Oracle: the C++ baseline package `/nix/store/1jgbzwzc…-waylandshader-gnome-0.1.0` (`b223c1a`), run in the same harness.

## Method

- **Sessions:** every Shell ran through `gnome/tests/isolated-session.sh` (private bus, `XDG_*` and runtime dir). Nothing touched the live Shell or the live session bus.
  - **Render checks:** `WS_DEVKIT=1`. The Mutter devkit viewer shows only its own virtual monitor (`Meta-2`), and it streams that view's real framebuffer.
  - **GUI checks:** headless session. The controller ran on the live desktop (`WAYLAND_DISPLAY` = host socket) but used only the private bus.
- **Screenshots:** the xdg-desktop-portal Screenshot API, with the user's one-time GNOME permission grant. omp's own Wayland capture is not compiled into this release (`capture: false`).
  - Measurements are mean HSL saturation, mean luma and mean RGB of a 400×300 background patch in the viewer, taken with ImageMagick. Pixel equality uses `magick compare -metric AE`.
- **Accessibility:** driven directly through AT-SPI with GJS scripts, with each call capped at 3 s.
  - The controller ran with `AT_SPI_BUS_ADDRESS` set to the host a11y bus. The baseline Qt controller was read on the private session's a11y bus, with a manually started `at-spi2-registryd`.
- **Stage screenshots don't show the effect.** A screenshot of the nested Shell's stage (through its own portal) shows the unfiltered scene for both builds. The effect paints only into the view's original framebuffer, so render checks use the devkit viewer.

## T-ISO-RENDER

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Saturation 0 turns the output gray; gamma 2 brightens it; 1/1 equals effect off | PASS | saturation 0.465 → 0 (luma 0.653 → 0.662). Gamma 2: luma 0.653 → 0.769. Color on at 1/1 against color off: 0 differing pixels |
| 2 | Color-only processing idles; a temporal preset renders continuously | PASS | Shell CPU: color-only 0.0 %, temporal preset 13.3 %, disabled 0.0 % |
| 3 | Per-output shader/color toggles are independent | PASS | Meta-0 saturation 0 left Meta-2 untouched. With its shader off, Meta-2 equals the unfiltered mean RGB (0.229, 0.296, 0.628). With Meta-0's shader off, Meta-2 stays shaded (0.131, 0.535, 1.0). The `outputs` flags match |
| 4 | Master `disable` restores the scene and `active=false`; `enable` rebuilds | PASS | After disable: `active:false`, `enabled:false`, and the image stats equal color-off. After enable: `active:true` |
| 5 | A failed replacement keeps the running preset; with rapid loads the newer wins | PASS | Broken preset: exit 1, compile error reported, `preset` unchanged, image unchanged. Back-to-back loads in both orders: the second load wins |
| 6 | The pointer is shaded with the scene | NOT OBSERVABLE | The devkit viewer draws the pointer itself. The pointer stays unshaded under GAIN 0.1 for **both** the baseline and the port, so the viewer cannot show this. It moves to T-HW |
| 7 | Small damaged regions show no unfiltered patches | NOT OBSERVED | No blinking text cursor on Meta-2 in the viewer. Covered headlessly by the T-GL partial-redraw case only |
| 8 | Bypass reason for an unsupported output | NOT REPRODUCED | All virtual outputs are supported |
| 9 | `gnome-extensions disable` removes the effect cleanly | PASS | `State: INACTIVE`, CLI `status` exits 3, image equals unfiltered. `enable` makes it ACTIVE again with settings restored |
| 10 | No WaylandShader CRITICAL/WARNING in the Shell stderr | PASS | The only CRITICAL lines come from `mutter-devkit`'s own a11y registration |
| — | Baseline parity of rendered output | PASS | Same preset and settings on the baseline: shader-only (0.130, 0.534, 1.0) against the port's (0.131, 0.535, 1.0). Temporal + saturation 0.5 is solid white on **both**: the unbounded FP16 feedback term times the color stage, which is original behavior |

## T-GUI

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Title, size, texts | PASS | Odin and Qt windows compared side by side: same title, intro, buttons, labels, summary, note and parameter rows. The only differences are toolkit widget styling (GTK +/− spin buttons, the `Recent ▾` glyph) |
| 2 | Browse: cancel, reopen, choose a path with spaces; fills but does not load | PASS | Dialog title `Choose shader preset`, filter `RetroArch slang presets (*.slangp)`, opened in the entry's folder with the entry's file preselected. Cancel left the text unchanged. Choosing `tiny preset.slangp` filled the field, and `preset` stayed `temporal2.slangp` |
| 3 | Recent fills and focuses without loading; Load and Return-to-load; non-`.slangp` error | PASS | Recent: the field was filled and focused, `preset`/`requestedPreset` unchanged. Load and Return each loaded the path. The error text `Choose an existing .slangp preset file.` equals `controller_main.cpp:402` |
| 4 | Enable checkbox; Reconnect activates the extension | PASS | Checkbox off → `enabled:false`, on → `active:true`. With the extension disabled, Reconnect → `State: ACTIVE` |
| 5 | Monitor combo names; state-label texts | PASS | Items `Meta-0`, `Meta-1`. Labels seen: `Preset active`, `Preset + color active`, `Color active`, `No processing active`, `Bypassed`. `Saving…` is too brief to capture; `Unfiltered:` can't be reproduced |
| 6 | Gamma/saturation commit on Enter and focus-out with 2-decimal rounding | PASS | Focus-out `1.234` → bus `1.23`; Enter `0.456` → bus `0.46` |
| 7 | 100 ms debounce, a focused editor is not overwritten, tiny value is exact | PASS | Bus at 50 ms: old value; at 550 ms: new value. An external `0.7` did not overwrite a focused editor showing `1.5`, and it updated after focus left. `1.0000001e-7` committed as exactly `f32(1.0000001e-7)` |
| 8 | Stopping the Shell shows `Disconnected — …` | PASS | Only the Shell was killed; the bus stayed up. Label `Disconnected — displayed controls may be stale. Use Reconnect / refresh.` and error text equal the baseline (`controller_client.cpp:83`). Effect controls disabled; Reconnect, Browse and Close enabled |
| 9 | Accessible names for the entry, Recent, combo and spin buttons | **FAIL (G-1)** | Entry, Recent, Monitor, Gamma and Saturation are named. **Parameter spin buttons have an empty accessible name** (only a labelled-by relation to the label and the tooltip as description). The baseline Qt spin is named `Gain` (from its buddy label) |
| 10 | app_id `org.waylandshader.GnomeController` | PASS | AT-SPI application name `org.waylandshader.GnomeController` |
| 11 | Closing the window leaves `status.active` unchanged | PASS | `active`, `enabled`, `preset` identical before and after Close |

Minor observation (not a REQ): closing the window logged one `Gdk-WARNING: Tried to unmap the parent of a popup`.

## Findings for the main reviewer

- **G-1 (REQ-045 accessibility, T-GUI 9):** give each parameter spin button an accessible name equal to its visible label text (description, or the name when there is none), as the Qt buddy label did. Required regression: an automated AT-SPI or `gtk_widget_get_accessible` name check for a parameter editor.

## Recheck after rework round 4 (commit `f1a7b7b`, package `/tmp/ws-r4-result`)

T-GUI 9 rerun with the same method (headless isolated session, controller on the live desktop, host a11y bus, preset with parameters `GAIN` "Gain" and `TINY` "Tiny"):

- AT-SPI now lists the spin buttons as `Gamma`, `Saturation`, `Tiny`, `Gain`.
- `Gain`: name `Gain`, description `GAIN\nDefault: 1; range: 0.100000001 to 2`, labelled-by `Gain`. This equals the Qt baseline's name, description and labelled-by relation.
- `Tiny`: name `Tiny`, labelled-by `Tiny`.

**G-1: PASS.**
