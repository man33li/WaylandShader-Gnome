# GNOME backend: port requirements extraction

Read-only scout pass. Citations are `path:line` relative to `WaylandShader-gnome/`. Code cross-checks were made only where marked **code**. Nothing was built or run.

## 1. Documented GNOME behaviors and limits a port must preserve

| # | Behavior / limit | Doc source | Code cross-check |
|---|---|---|---|
| 1 | Targets GNOME 50 / Mutter ABI 18 only; 51, other ABI majors, GLES, GLX rejected | `docs/GNOME.md:7`; `README.md:45` | **code:** `gnome/default.nix:6-7` (assert major 50); `gnome/CMakeLists.txt:15,17-18` (`libmutter-18`, FATAL if <50 or ≥51) |
| 2 | Desktop OpenGL EGL only, not GLES | `docs/GNOME.md:103`; `README.md:40` | **code:** `gnome/native/waylandshader-effect.cpp:740-742` (must be `EGL_OPENGL_API`, "not GLES or GLX"); `src/shader_runtime.cpp:218-221` |
| 3 | Native `ClutterEffect` on `global.stage`; original windows and input routing kept | `README.md:67`; `docs/GNOME.md:84` | not verified (extension.js/native not read) |
| 4 | Per-output shader chain, history, frame counter, frame-clock timeline | `README.md:67`; `docs/GNOME.md:52`, `:44` | not verified |
| 5 | Color-only processing never animates an idle desktop | `README.md:67`; `docs/GNOME.md:52`; `README.md:269` | not verified |
| 6 | Damage expanded before culling; paint hook requires matching frame number and original framebuffer | `docs/GNOME.md:41` | not verified |
| 7 | Connector IDs mapped to monitor/CRTC/`ClutterStageView`; tiled, shared/missing CRTC, mismatched views reported as bypass and passed through | `docs/GNOME.md:40`, `:115`; `README.md:103` | not verified |
| 8 | Software cursor requested and unredirect inhibited while processing; held before first processed frame; balanced on every stop/error path | `docs/GNOME.md:54`; `README.md:103`; `README.md:268` (separately drawn cursor not shaded) | **code:** `waylandshader-effect.cpp:632-638`, `:771-773` (`meta_backend_inhibit_hw_cursor`); `extension.js:128-139` (`disable_unredirect` before first frame), `:224-227` (release on destroy) |
| 9 | FP16 sRGB working surface keeps HDR headroom; no tone-map; no HDR guarantee for arbitrary presets | `docs/GNOME.md:43`, `:105`; `README.md:105`, `:266` | **code:** `waylandshader-effect.cpp:296-300` (preserve mastering headroom), `:351` (`GL_RGBA16F`) |
| 10 | Master bypass releases GPU resources and temporal history but keeps parameter definitions; known params editable and saved while bypassed; unknown/NaN/out-of-range rejected; edits rejected during in-progress compile | `README.md:101`; `docs/GNOME.md:106`, `:218`, `:307` | not verified |
| 11 | Replacement compiles on worker; generation number discards stale results; failed replacement keeps working preset | `docs/GNOME.md:55-58`, `:74` | **code:** `waylandshader-effect.cpp:414` (`generation`), `:428` (`std::thread worker`), `:441` |
| 12 | Failures caught at C/GObject boundary; no exceptions into GJS or Clutter | `docs/GNOME.md:46` | not verified |
| 13 | Single GSettings key `configuration` holds versioned JSON; monitor profiles keyed by GNOME connector ID, not KWin UUID | `README.md:29`, `:99`; `docs/GNOME.md:20`, `:330` | **code:** `gnome/extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml:4-7` |
| 14 | Recent: last 10 successfully compiled presets, canonical paths, symlink dedupe, missing files kept, failed loads don't change list, malformed saved entries skipped, saved as `recent_presets` in v1 JSON, reported as `recentPresets` | `docs/GNOME.md:114`; `README.md:97`; `docs/GNOME.md:242` | not verified |
| 15 | Per-output failure reported as `bypass` (controller shows `Unfiltered: <reason>`), not `error` | `docs/GNOME.md:115` | not verified |
| 16 | Closing controller leaves effect running; CLI can disable after GUI closes; Browse crash does not disable renderer | `README.md:97`; `docs/GNOME.md:33`, `:310` | not verified |
| 17 | D-Bus: `org.gnome.Shell`, `/WaylandShader`, interface `org.waylandshader.Effect` | `README.md:99`; `docs/GNOME.md:27` | `gnome/extension/metadata.json:2` (uuid) |
| 18 | Extension must be enabled; GUI/mutation may enable only `waylandshader@man33li.github.com`; read-only status/outputs/parameters never enable | `README.md:95`; `docs/GNOME.md:182`; `docs/PROJECT-HANDBOOK.md:68` | not verified |
| 19 | Browse uses Qt native dialog via GTK 3 (`org.gtk.Settings.FileChooser` required); must not switch dialogs to hide the dependency | `README.md:97`; `docs/GNOME.md:107`, `:309`, `:328` | **code:** `gnome/default.nix:30`, `:35`, `:58-60` |
| 20 | Native module/ABI update needs fresh GNOME login; controller-only fix needs only relaunch; never restart live compositor | `README.md:83`; `docs/GNOME.md:171-173` | n/a (process) |
| 21 | Not ported (no Mutter equivalent): niri render-GPU selection, per-output `transfer` route | `docs/GNOME.md:117` | n/a |
| 22 | No per-window or selected-region processing; input coordinates not remapped by warping presets | `WaylandShader-Guide.txt:198-200`; `README.md:265`, `:267` | n/a |
| 23 | Slang views repaint continuously (no static-shader optimization installed) | `docs/GNOME.md:53`; `README.md:269` | not verified |
| 24 | Settings load ordering: `_settingsLoaded` stops early status callbacks from overwriting saved settings | `docs/GNOME.md:92` | not verified |
| 25 | Monitor screencasts show unfiltered scene; direct KMS scanout is the evidence for final output | `docs/GNOME.md:292`, `:311`; `README.md:229` | n/a |

## 2. Verification claims and how they were run

| Claim | Method | Where recorded | Headless? | Automated in repo? |
|---|---|---|---|---|
| GNOME CTest 2/2 (`gnome_effect_lifecycle`, `gnome_recent_presets`) | `ctest` from `gnome/CMakeLists.txt`; run by Nix `checkPhase` | `docs/GNOME.md:242` (2026-10-14 build passed 2/2), `:308`; `gnome/CMakeLists.txt:96-112`; `gnome/default.nix:49-55` | Yes (GJS plus GI typelib; no stage, no GPU render per `docs/GNOME.md:242`) [INFERENCE on headless exactness] | Yes |
| Real-GL runtime regression `shader_runtime_test` | Listed as GNOME "retained regression" | `docs/GNOME.md:21` | Yes (Mesa surfaceless EGL; skip 77) | **Not in GNOME CTest.** Only registered in root `CMakeLists.txt:50-58`; `gnome/CMakeLists.txt` has no reference |
| Bypass-parameter live regression | Manual `gjs -m gnome/tests/parameter-bypass.js <private bus>` against disposable `gnome-shell --headless` with virtual monitors | `README.md:240-246`; `docs/GNOME.md:244-286` (passed fresh sessions; failed pre-fix) | Yes, documented (`LIBGL_ALWAYS_SOFTWARE=1`, `docs/GNOME.md:262`); not CTest | Script only |
| Isolated 50.4 two-view post-paint checks (identity, Slang params, gamma/sat, bypass, small redraws, unsupported-output isolation, PQ/HDR identity) | Recorded manual sessions | `README.md:227`; `docs/GNOME.md:96`, `:303-304` | Not stated | **No**: harness removed (`docs/GNOME.md:338`) |
| GUI/Browse/Open/Cancel checks | Real session, accessibility interaction | `docs/GNOME.md:290` | No | No |
| Direct KMS scanout of primary output | Privileged capture | `README.md:229`; `docs/GNOME.md:292` | No | No |
| Cold-activation and restoration races reproduced and fixed | Recorded | `docs/GNOME.md:302`, `README.md:227` | Not stated | No |
| KWin CTest "3/3" | `ctest` in KWin build | `README.md:225`; `WaylandShader-Guide.txt:154`; `docs/PROJECT-HANDBOOK.md` §7 ladder | Yes (surfaceless) | 2 real-GL entries (`CMakeLists.txt:55-56`) plus ECM `appstreamtest` [INFERENCE from handbook §7] |

## 3. Build and packaging facts

| Item | Value | Source |
|---|---|---|
| Package version | `0.1.0` (Nix and CMake) | `gnome/default.nix:10`; `gnome/CMakeLists.txt:2` |
| Nix `pkgs` | Caller-supplied `pkgs`; default `<nixpkgs>` | `gnome/default.nix:1`; `gnome/shell.nix:1` |
| Source filter | Whole repo (`../.`), excludes `build`, `result*`, `.git`, `.cache`; `sourceRoot` set to `gnome/` | `gnome/default.nix:11-21` |
| Native build tools | cmake, ninja, pkg-config, gobject-introspection, glib, gjs, `wrapGAppsHook3`, `kdePackages.wrapQtAppsHook` | `gnome/default.nix:23-32` |
| Build inputs | mutter, gtk3, expat, isocodes, lerc, libdeflate, libevdev, libwebp, xz, qtbase, qtwayland, libepoxy, shaderLibrary, `pkgs.mutter.buildInputs` | `gnome/default.nix:33-48` |
| Test flag and check | `-DWAYLANDSHADER_BUILD_TESTS=ON`; `doCheck=true`; `ctest --output-on-failure` | `gnome/default.nix:49-55` |
| GTK wrapper merge | `dontWrapGApps=true`; `qtWrapperArgs+=gappsWrapperArgs` | `gnome/default.nix:58-61` |
| Main program | `waylandshader-gnome-controller` | `gnome/default.nix:68` |
| Dev shell | inputsFrom package plus clang-tools, qttools, gnome-shell, gjs, **pipewire** (pipewire unused by renderer per docs; not verified) | `gnome/shell.nix:3-11` |
| Mutter pin | major 50 (Nix assert); `libmutter-18` (CMake) | `gnome/default.nix:6-7`; `gnome/CMakeLists.txt:15,17-18` |
| Qt pin | Qt 6.10+ Core, Gui, Widgets, DBus | `gnome/CMakeLists.txt:12`; `README.md:39` |
| Other CMake deps | Threads, PkgConfig, epoxy, `g-ir-scanner`, `g-ir-compiler`, `glib-compile-schemas`, C++20 | `gnome/CMakeLists.txt:1-4`, `:13-16`, `:23`, `:30` |
| librashader pin | `pkgs.librashader.version == "0.10.1"` (assert) | `shader-library.nix:4-5` |
| Private lib | `pname` `waylandshader-librashader`; patch applied; `librashader.so.2` renamed to `libwaylandshader-rashader.so.2`; SONAME set via patchelf; unversioned symlink | `shader-library.nix:6-13` |
| Private lib link | `find_library(... waylandshader-rashader)` | `gnome/CMakeLists.txt:21` |
| Static shared runtime | `gnome_shader_runtime` from `../src/shader_runtime.cpp`, PIC | `gnome/CMakeLists.txt:34-37` |
| Mutter header workaround | Build-local header copies; FATAL if `ClutterPaintFlag` layout changes | `gnome/CMakeLists.txt:39-57` |
| Native library | `waylandshader_gnome` SHARED from `native/waylandshader-effect.cpp`, OUTPUT_NAME `waylandshader-gnome`, `-Wl,--no-undefined` | `gnome/CMakeLists.txt:59-67` |
| GIR namespace | `WaylandShader` 1.0; includes GObject-2.0, Clutter-18; `--library=waylandshader-gnome` | `gnome/CMakeLists.txt:69-86` |
| Typelib | `WaylandShader-1.0.typelib` via `g-ir-compiler` | `gnome/CMakeLists.txt:89-93` |
| Controller and CLI | Shared `src/controller_client.cpp` with `WAYLANDSHADER_GNOME` define; Qt Widgets GUI; CLI | `gnome/CMakeLists.txt:114-123`, `:116` |
| Lifecycle test env | `GI_TYPELIB_PATH` = Mutter GIR dir; TIMEOUT 10 s | `gnome/CMakeLists.txt:100-111` |

## 4. Install layout (`CMAKE_INSTALL_DATADIR`-relative)

| Destination | Contents | Source |
|---|---|---|
| `share/gnome-shell/extensions/waylandshader@man33li.github.com/` | Extension root | `gnome/CMakeLists.txt:125-126` |
| `…/native/` | `libwaylandshader-gnome.so`, `WaylandShader-1.0.gir`, `WaylandShader-1.0.typelib` | `gnome/CMakeLists.txt:137-138` |
| `…/` (root) | `metadata.json`, `extension.js` | `gnome/CMakeLists.txt:139` |
| `…/schemas/` | gschema XML and `gschemas.compiled` (`--strict`) | `gnome/CMakeLists.txt:128-135`, `:140-141` |
| `bindir` | `waylandshader-gnome-controller`, `waylandshader-gnomectl` | `gnome/CMakeLists.txt:118-122`, `:142` |
| `share/applications/` | `org.waylandshader.GnomeController.desktop` (`Exec=waylandshader-gnome-controller`, `OnlyShowIn=GNOME;`) | `gnome/CMakeLists.txt:143`; `gnome/org.waylandshader.GnomeController.desktop:1-9` |
| Extension metadata | uuid, `shell-version: ["50"]`, `session-modes: user, unlock-dialog`, `settings-schema`, url | `gnome/extension/metadata.json:2-8` |

Not installed by GNOME CMake: `parameter-bypass.js`, `recent-presets.js`, `effect-lifecycle.js` (tests only; `gnome/CMakeLists.txt:96-112`).

## 5. Test and fixture coverage

**`tests/shader_runtime_test.cpp`** (real GL, Mesa surfaceless EGL)

| Lines | Covers | Note |
|---|---|---|
| 152-156 | Skip (exit 77) when surfaceless EGL missing | root CMake `SKIP_RETURN_CODE 77` at `CMakeLists.txt:57` |
| 159-163 | Copies `temporal.slangp`, `temporal.slang`, `finish.slang` to temp dir | |
| 164-183 | **Generates** `base-level.slangp`/`.slang` at runtime (mipmap_input0=false, `textureLod(...,3.0)`) | |
| 184-186 | **Generates** `lookup.png` (2×2) at runtime; not in `tests/fixtures/` | |
| 51-57 | Context: GL **3.3 core** always; robust flag and LOSE_CONTEXT_ON_RESET when robust | Guide's "OpenGL 3.3 fallback" is the explicit 3.3 request plus a separate `MESA_GL_VERSION_OVERRIDE=3.3` ctest (`CMakeLists.txt:58`) |
| 195-198 | Loop robust=false, true | |
| 24-46 | Textures: RGBA16F 64×32; source full mip chain, dest 1 level; `GL_TEXTURE_MAX_LEVEL=0` (line 34) | |
| 71-119 | Two reload cycles; two outputs (11, 22); 8 frame assertions/cycle (107-111, 115-116, 118) with 0.003 tolerance | Multipass, LUT, mipmap input, history, feedback |
| 80-88 | Asserts host EGL context restored and host viewport (7,9,13,15) unchanged | |
| 112-114, 117 | Unknown parameter rejected; GAIN=3 rejected; GAIN 0.5 and 0.1 accepted | 0.1 boundary |
| 120-136 | High-LOD sample must read live base level (VHSPro banding regression) | |

Not covered by this file: GNOME native effect, frame hooks, Cogl color, gamma/saturation, Mutter mapping, extension, D-Bus.

**Fixtures** (`tests/fixtures/`, three files only)

| File | Content | Source |
|---|---|---|
| `temporal.slangp` | 2 passes; pass 0 alias `PREPASS`, scale 0.5, float FB, mipmap_input; pass 1 viewport scale, mipmap_input; `LOOKUP = lookup.png` (absent from fixtures) | `temporal.slangp:1-13` |
| `temporal.slang` | Samples `OriginalHistory1` (l18), `PassFeedback0` (l19), `textureLod(Source,…,1.0)` | `temporal.slang:17-19` |
| `finish.slang` | `#pragma parameter GAIN` 1.0 range 0.1–2.0 step 0.1 (l19); push constant (l18); `LOOKUP` (l20); mixes `PREPASS` | `finish.slang:17-20` |

GNOME lifecycle test reuses only `temporal.slangp` (`gnome/CMakeLists.txt:105`).

**Librashader patch** (`patches/librashader-gl-lifetime.patch`, headers only): 18 files under `librashader-runtime-gl/src/`. Includes new `gl/owned.rs` (l846, owning GL object collections). Touches `filter_chain/chain.rs` (l1; history init and clear across all slots, around l315-321), `gl3/` and `gl46/` for compile_program, draw_quad, framebuffer, lut_load, ubo_ring, texture_bind; `samplers.rs` (l908); `util.rs` (l955); `gl/mod.rs` (l797). The niri `gen_mipmaps` hunk claimed in `docs/GNOME.md:113` was not confirmed (headers only).

## 6. Discrepancies and stale statements

| # | Statement | Problem | Evidence |
|---|---|---|---|
| D1 | `docs/GNOME.md:21` lists `shader_runtime_test.cpp` as a GNOME retained regression | Not built or run by the GNOME CMake, CTest, or Nix checkPhase | `gnome/CMakeLists.txt:96-112`; `gnome/default.nix:49-55`; test is only in root `CMakeLists.txt:50-58` |
| D2 | `docs/GNOME.md:7` says status recorded 2026-09-11 | Same chapter documents 2026-10-14 work | `docs/GNOME.md:113`, `:242`, `:308` |
| D3 | `README.md:278` says no `LICENSE` file | File exists; handbook says MIT | `LICENSE` in repo listing; `docs/PROJECT-HANDBOOK.md:30` |
| D4 | `README.md:225` "3/3 CTest" | Two real-GL entries plus ECM appstreamtest, not three runtime tests | `CMakeLists.txt:55-56`; handbook §7 |
| D5 | Guide: "OpenGL 3.3 fallback" | Test always requests 3.3 core; separate `gl33` ctest sets Mesa override | `tests/shader_runtime_test.cpp:52-53`; `CMakeLists.txt:58` |
| D6 | `docs/GNOME.md:113` patch "gains gen_mipmaps hunk" | Not confirmed in header-only read | [INFERENCE] |
| D7 | Handbook §1 sha256 `d749aea…` for patch | Not computed | Unverified |
| D8 | Dev shell includes `pipewire` | Docs say renderer has no PipeWire path; package use not checked | `gnome/shell.nix:10`; [INFERENCE] unused |
| D9 | `README.md:95` says GNOME CLI supports all KWin CLI commands | `ctl_main.cpp` not read | Unverified |
| D10 | `README.md:45` says KWin 6.7+ rejected | Root CMake not read | Unverified (GNOME half verified at `gnome/CMakeLists.txt:17-18`) |
| D11 | Handbook says `TODO.md` on main still lists GNOME as planned | Not checked (main worktree) | `docs/PROJECT-HANDBOOK.md:32` |

## 7. Not verified in this pass

| Item | Reason |
|---|---|
| Native effect, extension.js behavior beyond rows cited | Not in target list; only cited lines checked |
| Patch hunk contents, sha256 | Headers-only scope |
| Recent-list, bypass-reason, D-Bus method names, CLI parity | Outside target files |
| Physical HDR, KMS, hotplug, VRR, power, latency | Documented as open (`docs/GNOME.md:312`); no evidence here |
| `README.md` limits section lines | Cited by section only (numbering truncated) |

*Skipped: no builds, no runs, no `ctest`, no sha256, no read of `src/`, `ctl_main.cpp`, `extension.js`, or `native/*.cpp` beyond cited lines. Risk: D1 means the GNOME package does not exercise the real-GL runtime test at all, so a port that breaks shader_runtime semantics would pass the GNOME package build.*