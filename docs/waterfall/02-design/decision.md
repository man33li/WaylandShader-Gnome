# Phase 2 decision: Plan B

Main planner (opus 5.5). Inputs: `plan-A.md` (sol 6.1), `plan-B.md` (opus 5.5), the five research reports, and the original sources at `b223c1a`. The final design is `design.md` and the requirements are in `../01-requirements/requirements.md`.

## Chosen plan

**Plan B.** The final design is Plan B with the imports and corrections listed below.

## Verification I ran (read-only probes, 2026-10-20)

| Claim checked | Result |
|---|---|
| Toolchain pins | `<nixpkgs>`: mutter 50.5, gnome-shell 50.5, odin `dev-2026-05`, librashader 0.10.1, gtk3 3.24.52, glib 2.88.3, kwin 6.6.6. `<nixpkgs>`, the GLF-OS flake pkgs and the running `/run/current-system` resolve to the same gnome-shell store path (`8m77m1b9…-gnome-shell-50.5`). The package is therefore ABI-matched to the live Shell. |
| Odin version "drift" (research `odin-native.md:3`, Plan B R8) | The nixpkgs `odin-dev-2026-05` binary itself prints `dev-2026-09`. There is one compiler, so no drift exists. |
| Struct layouts (both plans §4) | A C probe against the real `mutter-50.5-dev` and librashader headers printed: GObjectClass 136 (dispose 40, finalize 48), ClutterActorMetaClass 152 (set_actor 136), ClutterEffectClass 200 (paint 176), ClutterEffect 24, effect instance + pointer 32 (engine 24), GTypeInfo 72 (class_init 24, instance_size 48, instance_init 56), GTypeQuery 24, GError 16, ClutterLuminance 20 (ref 12, mastering_max 16), MtkRectangle 16, graphene_matrix_t 64 with alignment 16, ClutterPaintFlag 4, libra_image_gl_t 16, frame_gl_opt_t 40, filter_chain_gl_opt_t 16, libra_preset_opt_t 16, libra_preset_param_t 32, libra_preset_param_list_t 16. Enum values: RGBA_FP_16161616_PRE 155, TEXTURE_LOOKUP 6145, BYPASS_EFFECT 2, FILTER_NEAREST 9728, CLAMP_TO_EDGE 33071, G_SIGNAL_RUN_LAST 2, G_TYPE_STRING 64, G_TYPE_NONE 4. **Every number in both plans matched.** |
| Odin `-build-mode:dll` (both plans' top risk) | A probe `.so` built with the nixpkgs compiler has DT_INIT/DT_FINI. Its TLS is general-dynamic (`R_X86_64_DTPMOD64`), which is dlopen-safe. `dlopen` plus a call that uses the temp allocator worked. |
| Exported symbols | The Odin dll exports **its whole runtime**: `runtime::*`, `main`, `_odin_entry_point`, `__truncdfhf2`, and others. A `-Wl,--version-script` reduced the export list to the API only, and INIT and `dlopen` still worked. As written, Plan B T13 would fail, and Plan A specifies no export control at all. |
| `vendor:egl` gaps (Plan B) | Confirmed. It has no `GetCurrentDisplay/Context/Surface`, `QueryAPI`, `QueryContext`, `GetError` or `CreatePbufferSurface` (`vendor/egl/egl.odin:83–101`). |
| `GL_DEBUG` default (Plan B) | Confirmed: `GL_DEBUG :: #config(GL_DEBUG, ODIN_DEBUG)` (`vendor/OpenGL/constants.odin:3`). |
| `json.marshal` floats (Plan B) | Partly wrong. Positive `+` is stripped (`core/io/util.odin:104–106`), so the output *is* valid JSON. However, it uses fixed `'f'` notation with 16 decimals (`util.odin:97`), so `1e-20` becomes `0.0000000000000000`. That would silently drop tiny parameter values from saved GSettings. The conclusion stands: use a house writer. |
| Baseline CLI behavior (installed C++ `waylandshader-gnomectl`, private bus only) | `--help-all` is accepted by Qt's `addHelpOption` and then fails with `A command is required.`, exit 2. `-?` is not a Linux option. With no Shell, `status` exits 3 and prints the install hint. Help prints `Usage: <argv0> …`. |
| GTK 3 spin button (Plan A §3.6) | Confirmed against GTK 3.24.52: `EPSILON 1e-10` and `MAX_DIGITS 20`. Typed commits go through `gtk_spin_button_update` and then `gtk_spin_button_set_value`, which ignores changes of 1e-10 or less, and stepping does the same (`gtkspinbutton.c:62–63,1887,2355,2684`). GTK `digits` only formats the display. Qt's `QDoubleSpinBox` rounds the value to `decimals`. Neither plan reproduces the gamma/saturation 2-decimal rounding. |
| Baseline wrapper | The baseline controller wrapper has GTK's `org.gtk.Settings.FileChooser` schema on `XDG_DATA_DIRS`. T-WRAP passes on the baseline package. |

## Decisive reasons for Plan B

1. **The tests compare against the original, not against a model of it.** Native JSON and GError bytes are checked against baseline literals (B T5), the GIR is diffed against the baseline GIR (B T12), and the CLI output is diffed against the baseline binary (B T17). Plan A checks a hand-written fake GNOME Shell and semantic JSON comparison, so they confirm the author's reading of the source.
2. **Same ABI safety with less build machinery.** Plan B uses Odin `#assert`, a compile-only `_Static_assert` C file against the real headers, and a runtime `g_type_query` guard that refuses registration on a different Mutter. Plan A needs a C program that *generates* an Odin package, plus a generated collection threaded into every `odin build` and `odin test`. I measured the numbers, and the static asserts give the same guarantee.
3. **Plan B found real toolchain traps** (`vendor:egl` gaps, `GL_DEBUG`, the float writer, the `-build-mode:dll` entry and TLS). All of them were confirmed above apart from the float-writer detail.
4. **Smaller and closer to the original:** the in-process `GtkFileChooserDialog`, modal like `QFileDialog::getOpenFileName` (README.md:97, docs/GNOME.md:107); GtkBuilder XML; stock GtkSpinButton; GDBus; `vendor:OpenGL`; no libepoxy binding.
5. **Data-oriented design without speculation.** There are at most 16 outputs and the hot fields are asserted. Plan A's hot/cold SoA, resource-index arrays and separate callback records add index-stability invariants in compositor code, for item counts the DOD skill says not to optimize (`skills/dod/SKILL.md:52`).

## Rejected plan A: concrete failure points

1. **Build-time code generator** (`gnome/tools/abi-probe.c` writes `generated/abi/abi.odin`, consumed through `-collection:wsgen`, plan-A.md:40,47,226). It adds a build step, a generated source tree and a flag every compile and test must carry, for numbers that static asserts already prove.
2. **Fake Shell oracle** (`gnome/tests/protocol-fixture.odin` + `protocol.sh`, plan-A.md:43–44,281). The fixture re-implements `org.gnome.Shell`, `org.gnome.Shell.Extensions` and the effect's replies. Any misreading of `extension.js` or `controller_client.cpp` is then encoded in both the port and its test.
3. **Unpinned JSON bytes.** Plan A specifies "deterministic serialization" through `core:encoding/json` and semantic comparison (plan-A.md:86). It never identifies the fixed-16-decimal float output, so saved tiny parameter values could lose data without any test failing.
4. **Speculative layout** (plan-A.md:214–218): `Output_Hot`/`Output_Cold`/resource arrays, plus stable callback records reclaimed after disconnect, for at most 16 monitors.
5. **Re-implemented numeric widget** (plan-A.md:154): a composite of a GtkEntry and buttons that re-implements stepping, PageUp/PageDown, focus and ATK names. This adds new widget behavior and an accessibility surface. The precision problem it targets has a one-handler fix (import 4).
6. **No export control.** The ELF check is "inspect" (plan-A.md:282), and the Odin runtime symbols would be exported into gnome-shell's global symbol scope.

## Imported from Plan A (narrow)

1. **The builder owns the build files** (`gnome/CMakeLists.txt`, `default.nix`, `shell.nix`) (plan-A.md:311). Plan B gave them to the code agent, but security and ux must also register CTest entries. One owner avoids concurrent edits.
2. **An isolated-session harness script** (`gnome/tests/isolated-session.sh`, plan-A.md:284–289). It automates the documented two-terminal recipe (docs/GNOME.md:248–286) so that isolated-session tests have exact, repeatable commands. It refuses an inherited live bus or runtime directory.
3. **`lookup.png` is generated at test time**, as the C++ test does (`tests/shader_runtime_test.cpp:184–186`; plan-A.md:280). It uses `vendor:stb/image` `write_png`; `stb_image_write.a` is present in the nixpkgs Odin. This replaces Plan B's new tracked binary in the KWin-shared `tests/fixtures/` and its ImageMagick dependency.
4. **Exact typed parameter values** (plan-A.md:154 concern). The parameter spin button's `input` handler parses to f32 and calls `gtk_adjustment_set_value` directly, which compares exactly, before returning. This bypasses GtkSpinButton's 1e-10 EPSILON for typed values. A unit test covers tiny and subnormal values.
5. **Contiguous hot selection data** (plan-A.md:214). A `[dynamic]Output_View{view, expanded_frame}` (16 B, asserted) sits index-aligned with Plan B's heap `^Output`, which stays because signal handlers need stable pointers. The zero-allocation test also covers output selection.
6. **Non-ASCII JSON fixtures** (plan-A.md:86). Object keys are sorted by UTF-16 code unit, as Qt's `QJsonObject` does [INFERENCE]. The native contract test includes a non-ASCII preset-path key, pinned by the baseline bytes.

## Planner corrections to Plan B (from the probes above)

1. Add a linker version script `gnome/native/exports.map` exporting only `wayland_shader_effect_*`. T-ELF checks for exactly 15 exported symbols.
2. The CLI accepts the options the baseline accepts: `-h`, `--help`, `--help-all` (a known no-op flag, as in Qt) and `--timeout`. There is **no `-?`**. Help, usage and error output is checked against baseline goldens with argv0 normalized (T-CLI-GOLDEN). An overall-deadline case uses a 20-line GJS name owner that never replies (`hang-shell.js`).
3. Gamma and saturation commits are rounded to 2 decimals before the D-Bus call, as `QDoubleSpinBox` does.
4. Plan B's R8 is dropped (there is no compiler drift). The json.marshal rationale is restated as data loss, not invalid JSON.
5. The Wayland app_id comes from `g_set_prgname` and stays [INFERENCE], checked manually in T-GUI.

## Accepted deviations (need Main or user confirmation; recorded, not hidden)

- **D1:** The per-item tooltip in the monitor combo popup (controller_main.cpp:318) is not reproduced, because GTK 3 combo popups have no item tooltips. The combo tooltip still shows the selected id. GNOME ids equal names (extension.js:100–101), so the dropped tooltip only repeated the visible text.
- **D2:** GtkSpinButton ignores *stepping* increments of 1e-10 or less (`gtkspinbutton.c:1887`); typed values stay exact (import 4). This only affects shader parameters whose step, or span/100, is 1e-10 or less. A `shortcut:` comment marks it. The fix, if required, is the composite editor from Plan A.

Gate: this file names exactly one plan (B) and lists Plan A's failure points.
