# Requirements: Odin port of the GNOME backend

Phase 1 exit artifact (`../README.md:9`). The feature set is fixed by the original C++ GNOME build at `b223c1a`, and this port adds no features.

## Conventions

- **Sources.** Citations are repo-relative `file:line` at `b223c1a`. A `~` means the research report gave an approximate line. These abbreviations are used in this file:
  - **E**: `gnome/native/waylandshader-effect.cpp`
  - **EH**: `gnome/native/waylandshader-effect.h`
  - **R**: `src/shader_runtime.cpp`
  - **CC**: `src/controller_client.cpp`
  - **CTL**: `src/ctl_main.cpp`
  - **GUI**: `src/controller_main.cpp`
  - **XJS**: `gnome/extension/extension.js`
  - **OS**: `src/output_settings.h`
  - **NE**, **CS**, **DB**: the research reports `research/native-effect.md`, `research/control-surface.md` and `research/docs-build.md`.
- **Test classes.**
  - **headless**: runs on this machine in `nix-shell gnome/shell.nix` or the Nix sandbox, with no compositor.
  - **isolated-session**: runs on this machine in a disposable `gnome-shell --headless` (or `--devkit`) session with private XDG directories and a private D-Bus. It never touches the live compositor or the live session bus.
  - **manual**: a person observes the result and records it in `03-implementation/build-log.md`.
- **Unverified claims** are marked [INFERENCE].
- **Mapping.** Every REQ row names at least one test ID from the catalog below.

## Requirements

### Native GObject API and introspection

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-001 | The Odin library implements the unchanged C API of EH (14 functions plus `wayland_shader_effect_get_type`), and EH stays byte-identical. The GIR `WaylandShader-1.0` must equal the baseline: class `Effect` with parent `Clutter.Effect`, the same methods, transfer annotations and nullability, and the `status-changed` signal (`when="last"`, one `utf8` argument). | EH:14–147; `gnome/CMakeLists.txt:69–94`; NE §1 | T-GIR, T-UNCHANGED | headless |
| REQ-002 | The dynamic symbol table exports exactly those 15 symbols. The SONAME is `libwaylandshader-gnome.so`, the library depends on `libwaylandshader-rashader.so.2`, and it links with `-Wl,--no-undefined`. | `gnome/CMakeLists.txt:59–67`; `shader-library.nix:6–13` | T-ELF | headless |
| REQ-003 | `new()` returns an owned, ref-sunk object. It returns NULL if Engine allocation fails or if the parent-layout guard refused type registration. | E:1321–1340 | T-LIFE, T-CONTRACT | headless |
| REQ-004 | `get_status()` returns compact status JSON. If status construction fails, it returns the fixed fallback JSON (`enabled:false`, `error:"Unable to construct native status"`). | E:1342–1349 | T-CONTRACT | headless |
| REQ-005 | Status keys are `enabled, active, loading, preset, requestedPreset, recentPresets, error, parameters[], outputs[]`. Parameter rows hold `name, description, minimum, maximum, step, default, value`. Output rows hold `id, name, shaderEnabled, colorEnabled, gamma, saturation, shaderActive, colorActive`, plus `bypass` only when the output's failure text is non-empty. For fixed inputs, the bytes equal the baseline's. | E:~519–544; CC:229–354; NE §1a | T-CONTRACT, T-UNIT-COMMON | headless |
| REQ-006 | `export_settings()` returns `{version:1, enabled, preset, recent_presets, parameters:{preset:{name:value}}, outputs:{id:{…}}}`, byte-equal to the baseline, or NULL on failure. Export followed by import preserves parameter overrides and output profiles. | E:1352–1375; NE §9 obs 1 | T-CONTRACT, T-RECENT | headless |
| REQ-007 | `import_settings()` rejects non-object JSON, `version≠1` (unless the object is empty), relative preset paths, calls during a compile and calls after a renderer failure. A saved preset that is missing fails asynchronously and leaves the monitor controls live. | E:1377–1452 | T-CONTRACT | headless |
| REQ-008 | `set_outputs()` requires string `id`/`name`, integer `x`/`y`, `width`/`height` ≥1 and `scale` in [0.01, 64]. It rejects duplicate or empty ids. An unchanged inventory with a clean mapping is a no-op. | E:1454–1499; NE §9 obs 2 | T-CONTRACT | headless |
| REQ-009 | `load_preset()` requires an absolute, readable regular file, canonicalizes the path and starts an asynchronous compile. There is no `.slangp` suffix check in native code. | E:1501–1510; CS O2 | T-CONTRACT, T-BYPASS | headless, isolated-session |
| REQ-010 | `set_enabled(false)` releases the runtime and temporal history but keeps the parameter definitions. `set_enabled(true)` rebuilds the last preset. An unchanged value returns TRUE. | E:1512–1521; CS O5; README.md:101 | T-LIFE, T-BYPASS | headless, isolated-session |
| REQ-011 | `set_parameter()` has two paths. With a live runtime it uses the runtime path with rollback. While bypassed, it validates against the stored metadata and stores the override. An unknown name gives `Unknown shader parameter '<name>'`. NaN and out-of-range values are rejected. Calls are rejected while compiling or when no preset is loaded. | E:1523–1544; docs/GNOME.md:106 | T-CONTRACT, T-BYPASS, T-GL | headless, isolated-session |
| REQ-012 | The per-output shader and color toggles are independent. Gamma must be finite and in [0.1, 5]; saturation must be finite and in [0, 2]; out-of-range values get the original messages. An unknown id gives `Unknown active output: <id>`. Setting the same value is a no-op with no status emission. A shader toggle resets that output's history. | E:1547–1596, E:477; OS:6–9 | T-CONTRACT | headless |
| REQ-013 | `reset_history()` drops chains and resources and rebuilds asynchronously. `shutdown()` is idempotent. Dispose calls shutdown, and finalize frees the Engine. Mutators called after shutdown fail with the original message. | E:1598–1620, E:933–966, E:1290–1301 | T-LIFE, T-CONTRACT, T-ISO-RENDER | headless, isolated-session |
| REQ-014 | `status-changed` is emitted from an idle source on the owner main context, never during paint, and only when the JSON changed. The object holds a ref on itself around the emission. | E:546–571 | T-LIFE, T-CONTRACT | headless |
| REQ-015 | Every method checks the owner thread and the stopped state and fails with the original messages (e.g. `Native effect methods require the compositor main thread`). | E:420, E:451–455 | T-UNIT-NATIVE, T-CONTRACT | headless |
| REQ-016 | A failed mutator returns FALSE and sets a GError with domain `wayland-shader-error` and code 1. A NULL or invalid UTF-8 argument gives `Invalid UTF-8 argument`. | E:1219–1230, E:74–78 | T-CONTRACT | headless |
| REQ-017 | Recent presets: a successful load prepends the canonical path, deduplicates and caps the list at 10. Failed loads do not change the list. Import keeps only absolute, case-insensitive `.slangp` strings, deduplicates and caps at 10, and treats a malformed list as empty. The list is saved as `recent_presets` and reported as `recentPresets`. | E:56, E:865–868, E:1417–1424; docs/GNOME.md:114 | T-RECENT, T-BYPASS, T-ISO-CLI | headless, isolated-session |

### Preset lifecycle and shader runtime

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-018 | **Request:** bumps `generation`, sets `requested`/`pending`/`loading` and clears `error`. **Compile:** runs on one worker with a private shared EGL context, and completion arrives through a GSource attached to the owner main context. **Results:** stale generations are discarded silently. On success, the old runtime is retired first and the preset, recent list, last parameters and history flags are updated. On failure, the previous runtime is kept and `error` is set. If a reset happened during the compile, the last good preset is retried. **Ordering:** no load starts before the first EGL context capture. | E:777–885; docs/GNOME.md:55–58,74 | T-LIFE, T-GL, T-ISO-CLI | headless, isolated-session |
| REQ-019 | The runtime is destroyed only on the owner thread, inside its private context. If that context cannot be entered, it logs `cannot release shader objects` and leaks the chains rather than freeing them in the compositor context. | R:182–209; E:853,900,959 | T-GL, T-BAN | headless |
| REQ-020 | The private patched librashader 0.10.1 (C ABI 2) is linked directly. Preset options: `original_aspect_uniforms` and `frametime_uniforms` on. Chain options: `glsl_version` = GL version×10, DSA iff the version is ≥ 4.5, cache on, mipmaps not forced off. Presets with zero active passes are rejected. Frame: the fixed MVP `{2,0,0,0; 0,2,0,0; 0,0,0,0; -1,-1,0,1}`, direction 1, subframes 1/1, aspect, fps, frametime delta and `clear_history`. | R:348–422, R:552–573; NE §4 | T-GL, T-ABI | headless |
| REQ-021 | Parameter metadata must have finite, ordered bounds, step ≥0 and a default in range; otherwise loading fails with `Invalid shader metadata for parameter '…'`. The parameter list is the union across passes (last pass wins), sorted by name. Unknown overrides are rejected, and all chains must agree on each value. `setParameter` validates after an f32 cast, returns early when the value is unchanged, reads every chain before writing any, and rolls back on partial failure. | R:153–164, R:372–505 | T-GL | headless |
| REQ-022 | Only desktop OpenGL through EGL is supported; GLES and GLX are rejected. The context uses EGL 1.5 or KHR surfaceless, otherwise a 1×1 pbuffer. It tries GL 4.6, 4.5 and 3.3, each normal then robust, and shares the captured host context. It requires GL ≥3.3 and either GL ≥4.2 or `ARB_texture_storage`. A changed host context raises `The GNOME compositor EGL share context changed`. | R:211–291, R:341–345; E:732–755 | T-GL, T-GL33 | headless |
| REQ-023 | Fences run in both directions: host `glFenceSync` plus `glFlush`, then a private `glWaitSync` before the frame; private to host after the frame, even when the frame failed. Waits are GPU-side only, with no `glFinish` or client wait. | R:530–590 | T-GL, T-BAN | headless |
| REQ-024 | The caller's EGL display, context, draw/read surfaces and API are restored on every exit. GL bindings, scissor and sRGB state are saved and restored around the effect's GL work. GL objects are deleted in the context that created them. | R:54–123; E:131–195 | T-GL, T-ISO-RENDER | headless, isolated-session |
| REQ-025 | Error texts match the original: librashader text from `libra_error_write`, or `librashader failed (error N)`; `<op> failed (EGL error 0xNNNN)`; `Stage color conversion failed (GL 0x…)`; `Stage presentation failed (GL 0x…)`. | R:22–41; E:1045–1047, E:1189–1192 | T-UNIT-NATIVE, T-GL | headless |
| REQ-026 | The real-GL runtime regression is ported: two output keys (11 and 22), two reload cycles, normal and robust host contexts, temporal history, feedback, LUT and mipmaps, the base-level high-LOD case, the GAIN bounds and unknown name, and host context and viewport restoration. All 8 pixel expectations per cycle hold at ±0.003. `lookup.png` and `base-level.*` are generated at test time. | `tests/shader_runtime_test.cpp:24–198`; DB §5, D1 | T-GL, T-GL33 | headless |

### Rendering (Clutter stage)

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-027 | The effect attaches only to a ClutterStage. It connects `before-paint` and, when present, `gl-video-memory-purged`, which triggers a reset. `set_actor(NULL)` detaches. | E:968–1037 | T-ISO-RENDER | isolated-session |
| REQ-028 | Each connector is mapped to its monitor, CRTC and ClutterStageView. Inactive, tiled, shared-CRTC, missing and layout-mismatch cases produce the original reason text in `outputs[i].bypass`, and that output passes the scene through. Destroying a view detaches it, marks the mapping dirty and resets. | E:664–730; docs/GNOME.md:40,115 | T-ISO-RENDER | isolated-session |
| REQ-029 | `before-paint` adds a full-view redraw clip and records the expanded frame. `paint` processes only the matching view and frame and only that view's own framebuffer; otherwise it continues the scene exactly once. | E:988–1001, E:1050–1083; docs/GNOME.md:41; NE §9 obs 8 | T-ISO-RENDER | isolated-session |
| REQ-030 | The pipeline is unchanged and has no tone mapping: <ol><li>Raw blit into `RGBA_FP_16161616_PRE`.</li><li>Working color state with HDR headroom `ref·mastering_max/ref_target`, otherwise plain sRGB.</li><li>Target→sRGB conversion only when the target differs.</li><li>Source copy into an effect-owned `GL_RGBA16F` full-mip texture, with `MAX_LEVEL=0` set after the blit.</li><li>Shader run into an FP16 destination.</li><li>Final pass when the target is not sRGB or color is adjusted.</li><li>Blit back.</li></ol> | E:197–380, E:1105–1192; docs/GNOME.md:43,105 | T-ISO-RENDER, T-GL | isolated-session, headless |
| REQ-031 | The texture-lookup snippet GLSL (declarations and body) is byte-identical to the original: <ul><li>gamma applied to unpremultiplied encoded sRGB;</li><li>piecewise sRGB decode;</li><li>Rec.709 luma saturation clamped ≥0;</li><li>piecewise encode, then premultiply;</li><li>alpha ≤0 gives black.</li></ul> The gamma and saturation uniforms are written only when they change. | E:319–336, E:1166–1181 | T-UNIT-NATIVE, T-ISO-RENDER | headless, isolated-session |
| REQ-032 | Frame timing: <ul><li>`number` counts frames since the chain's first frame.</li><li>Elapsed milliseconds are measured since the output's last frame, clamped to u32.</li><li>fps comes from the frame-clock refresh rate, or is measured as 1e6/Δt with one warm-up skip.</li><li>`clear_history` is set on the first frame and on resize, toggle, reset and load, and cleared after a successful frame.</li></ul> | E:1122–1161 | T-UNIT-NATIVE, T-ISO-RENDER | headless, isolated-session |
| REQ-033 | Activity rules: <ul><li>The shader path needs a runtime, master enabled and the output's shader switch on.</li><li>The color path needs `colorEnabled`, gamma≠1 or saturation≠1, and a captured context, and it works with no preset.</li><li>With master off, no resources are allocated and the scene continues.</li><li>A repeating 1000 ms frame-clock timeline exists only for shader outputs, so color-only never animates an idle desktop.</li><li>The hardware cursor is inhibited while any output is active, balanced on every stop path.</li></ul> | E:456–470, E:630–662, E:771–774; README.md:67,269; docs/GNOME.md:52,54 | T-ISO-RENDER | isolated-session |
| REQ-034 | An output-local paint error restores the raw scene, sets `failure` (and so `bypass`), reports the error, and the other outputs keep working. A `before-paint` or vfunc-level error sets `renderer_failed`, bumps the generation and disables processing until shutdown. | E:1003–1014, E:1192–1271 | T-ISO-RENDER | isolated-session |

### Extension, D-Bus surface and settings

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-035 | `extension.js`, `metadata.json`, the gschema, the desktop file and the existing GJS tests stay unchanged. The D-Bus name, path, interface, methods, signal, error names, GSettings key `configuration`, unredirect handling and lifecycle all stay in JS. | XJS:10–230; gschema:3–7; CS §1–3 | T-UNCHANGED, T-BYPASS | headless, isolated-session |
| REQ-036 | Disabling and re-enabling the extension restores `enabled`, preset, recent list, parameters and output profiles from GSettings. | XJS:59–61,114–122; docs/GNOME.md:308 | T-ISO-CLI | isolated-session |

### D-Bus client (shared by CLI and GUI)

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-037 | The client makes asynchronous session-bus calls with a 10 000 ms timeout to `org.gnome.Shell` `/WaylandShader` `org.waylandshader.Effect`. It subscribes to `statusChanged`, `ExtensionStateChanged` and `NameOwnerChanged`, and ignores replies from a stale interface generation. When the owner goes away, it clears the status and reports a disconnection. | CC:62–115, CC:364–379; `src/controller_backend.h:7–19` | T-ISO-CLI, T-GUI | isolated-session, manual |
| REQ-038 | Errors are classified as follows: <ul><li>`ServiceUnknown`, `UnknownObject`, `UnknownMethod` and `UnknownInterface` → Unavailable, with the install hint.</li><li>Every `org.waylandshader.Error.*` name → Rejected. This includes `Unavailable`, so the CLI exits 1, as CS O1 records.</li><li>Any other bus error → Transport.</li><li>A malformed tuple or JSON → Protocol.</li><li>A FALSE reply → Rejected.</li></ul> | CC:21–58; CS O1 | T-UNIT-CLIENT, T-CLI-GOLDEN | headless |
| REQ-039 | Status validation covers every required and optional field, range and uniqueness rule, with the original messages. A candidate status is validated before it replaces the current one, and the raw JSON is kept so the CLI can reprint it. | CC:229–360 | T-UNIT-CLIENT | headless |
| REQ-040 | Read-only `status`/`parameters`/`outputs` never activate the extension. Mutations, `disable`/`toggle` and GUI startup/reconnect call `EnableExtension` only for `waylandshader@man33li.github.com`. Activation is confirmed through `GetExtensionInfo` and `ExtensionStateChanged` (state 1 is active; 2, 6 and 8 are pending), with a 10 s timeout. | CC:117–215; CTL:190; CS O3, O4 | T-ISO-CLI | isolated-session |

### CLI `waylandshader-gnomectl`

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-041 | Commands: `status`, `parameters`, `outputs`, `load FILE`, `param NAME VALUE`, `output ID_OR_NAME shader\|color on\|off`, `output ID_OR_NAME gamma\|saturation NUMBER`, `enable`, `disable`, `toggle`. Options are exactly those of the baseline: `-h`, `--help`, `--help-all` (accepted with no effect), `--timeout N` / `--timeout=N` and `--`. There is no `-?`. Help, usage and error text are byte-identical to the baseline after argv0 normalization. | CTL:23–64 | T-CLI-GOLDEN, T-UNIT-CTL | headless |
| REQ-042 | Validation: <ul><li>`--timeout` is an integer in 1–3600, default 120.</li><li>`load` needs an existing file with a case-insensitive `.slangp` suffix.</li><li>`param` needs a non-empty name and a finite number.</li><li>`output` needs `on\|off`, gamma in [0.1, 5] or saturation in [0, 2].</li><li>The selector matches an exact id first, then a unique exact name; an ambiguous or unknown selector exits 2.</li></ul> | CTL:82–136, CTL:248–270 | T-CLI-GOLDEN, T-UNIT-CTL, T-ISO-CLI | headless, isolated-session |
| REQ-043 | Exit codes: 0 success; 1 rejected, shader failure or replaced load; 2 usage; 3 unavailable, transport or protocol; 4 overall deadline, with the "operation may still finish" message. Per-call 10 s timeouts stay bus errors. | CTL:46, CTL:157–186 | T-CLI-GOLDEN, T-ISO-CLI | headless, isolated-session |
| REQ-044 | `status` prints the full status as indented JSON; `parameters` and `outputs` print arrays. Mutations print the status after success. `load` waits for `loading=false` and then requires `preset==requested`, otherwise it exits 1. `toggle` inverts `status.enabled`. | CTL:160–243, CTL:283 | T-ISO-CLI | isolated-session |

### GUI `waylandshader-gnome-controller`

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-045 | The window title is `WaylandShader — GNOME Shell Desktop Effects`, with a default size of 740×620. Labels, placeholders, tooltips, grouping and the note label are the same as the original. | GUI:67–165 | T-GUI | manual |
| REQ-046 | **Browse** opens GTK 3's in-process file chooser, titled `Choose shader preset`, with the filter `RetroArch slang presets (*.slangp)` and its initial location taken from the entry. A selection fills the field and marks it edited but never loads. Cancel leaves the text unchanged. The package wrapper supplies `org.gtk.Settings.FileChooser`. | GUI:167–174; README.md:97; docs/GNOME.md:107,309,328 | T-GUI, T-WRAP | manual, headless |
| REQ-047 | Editing the text sets the edited flag, and Return loads when Load is enabled. **Load preset** rejects non-`.slangp` paths and non-files with the original error text; otherwise it loads the canonical path. | GUI:175–177, GUI:398–413 | T-GUI, T-UNIT-GUI | manual, headless |
| REQ-048 | The **Recent ▾** menu is built from `recentPresets` and is disabled when empty. Labels are literal (no mnemonics). Choosing an entry fills and focuses the field but never loads. | GUI:503–520 | T-GUI | manual |
| REQ-049 | **Enable desktop effects** follows the status unless a mutation is pending. **Reconnect / refresh** and startup call `ensure_available(true)`, so opening the GUI can activate the extension. | GUI:179–186, GUI:218, GUI:359–372, GUI:525–528; CS O3 | T-GUI | manual |
| REQ-050 | **Monitor combo:** lists outputs by name, its tooltip is the selected id, and the placeholder is `No connected monitors`. **State label:** texts and precedence are `Saving…`, `Bypassed`, `Unfiltered: <reason>`, `Preset + color active`, `Preset active`, `Color active`, `No processing active`. **Mutations:** only one output mutation is pending at a time, and the controls stay disabled until the next status. The per-item popup tooltip is dropped; this is decision.md deviation D1. | GUI:100–106, GUI:188–191, GUI:277–345 | T-GUI, T-UNIT-GUI | manual, headless |
| REQ-051 | The gamma and saturation spin buttons show 2 decimals with step 0.05 and the ranges from OS. They commit on Enter or focus-out. Committed values are rounded to 2 decimals, as `QDoubleSpinBox` does. | GUI:120–136, GUI:198–203; OS:6–9 | T-UNIT-GUI, T-GUI | headless, manual |
| REQ-052 | Parameter editors are built from `parameters[]`: <ul><li>Range [min, max]; step = `step`, or span/100.</li><li>The tooltip shows the default and range; the label is the description, or the name if there is none.</li><li>The text is the shortest round-trip f32; parsing casts to f32; typed values are committed exactly.</li><li>Changes are debounced for 100 ms, and dirty or focused editors are not overwritten.</li><li>Stale replies are ignored, and the form is rebuilt when the parameter schema changes.</li></ul> Stepping increments of 1e-10 or less are decision.md deviation D2. | GUI:30–63, GUI:415–500, GUI:549–556 | T-UNIT-GUI, T-GUI | headless, manual |
| REQ-053 | The summary and error labels show active, disabled or enabled-but-not-active, plus `Compiling:`, `Loaded preset:`, `Outputs:` and `Effect error: …`. A Rejected error keeps the controls live. A transport or unavailable error disables them and shows `Disconnected — displayed controls may be stale.` | GUI:144–153, GUI:212–217, GUI:347–357, GUI:535–547 | T-UNIT-GUI, T-GUI | headless, manual |
| REQ-054 | Closing the GUI leaves the effect running. The desktop file's `Exec` and `OnlyShowIn=GNOME` are unchanged. The Wayland app_id is `org.waylandshader.GnomeController`, so the dash icon matches [INFERENCE for GTK 3 prgname]. | README.md:97; `gnome/org.waylandshader.GnomeController.desktop:5,9`; GUI:597 | T-GUI, T-UNCHANGED | manual, headless |

### Build, packaging and non-functional constraints

| ID | Requirement | Source | Test | Class |
|---|---|---|---|---|
| REQ-055 | `nix-build gnome/default.nix` builds and runs every headless CTest entry in `checkPhase`. The Mutter-50 Nix assert and the CMake 50.x guard are kept. | `gnome/default.nix:6–7,49–55`; `gnome/CMakeLists.txt:17–18` | T-NIX | headless |
| REQ-056 | The installed file list is identical to the baseline's: extension root, `native/` (`.so`, GIR, typelib), `schemas/`, the two binaries and their wrappers, and the desktop file. | `gnome/CMakeLists.txt:125–143`; DB §4 | T-LAYOUT | headless |
| REQ-057 | There is no Qt or C++ in the GNOME artifacts. `gnome/native/waylandshader-effect.cpp` is deleted, the GNOME CMake project has no CXX language, and no installed GNOME binary or the `.so` needs `libQt6*` or `libstdc++`. | `../README.md:5`; task scope | T-ELF, T-BAN | headless |
| REQ-058 | The KWin backend stays unchanged and keeps building. `src/`, the root `CMakeLists.txt`, `default.nix`, `shell.nix`, `tests/`, `shader-library.nix` and `patches/` are untouched, and `nix-build default.nix` succeeds. | root `CMakeLists.txt:25–58`; task scope | T-UNCHANGED, T-KWIN | headless |
| REQ-059 | The ABI pin stays: GNOME 50 / Mutter ABI 18 / Clutter-18, and private librashader 0.10.1 with `patches/librashader-gl-lifetime.patch` and SONAME `libwaylandshader-rashader.so.2`. | `gnome/default.nix:6–7`; `shader-library.nix:4–13`; docs/GNOME.md:7 | T-NIX, T-UNCHANGED, T-ELF | headless |
| REQ-060 | No new features: no new GIR symbols or properties, D-Bus members, settings keys or versions, CLI commands or options, or GUI controls. | `../README.md:5` | T-GIR, T-UNCHANGED, T-CLI-GOLDEN, T-GUI | headless, manual |
| REQ-061 | ABI safety: every Odin mirror of a C struct or enum is checked by an Odin `#assert` and by `_Static_assert` in `gnome/native/abi-check.c` against the real headers. At runtime, `get_type` refuses registration unless `g_type_query(clutter_effect_get_type())` reports class 200 and instance 24. | odin-native.md risk 1; decision.md probe | T-ABI, T-LIFE | headless |
| REQ-062 | C-boundary safety: <ul><li>Every procedure called from C is `proc "c"` and sets the boundary context.</li><li>There is no `panic`, `assert`, `unreachable`, `#no_bounds_check` or `or_panic` in native/runtime/common/glib production code, and bounds checks stay enabled.</li><li>Strings returned to GI are GLib-allocated, and GErrors are set only through `g_set_error_literal`.</li><li>Allocation failure becomes the error `Out of memory`.</li></ul> | odin-native.md §1; E:1219–1230; docs/GNOME.md:46 | T-BAN, T-CONTRACT | headless |
| REQ-063 | DOD: after warm-up there are zero Odin heap and temp allocations per frame in the `before-paint` output loop, output selection, `frame_timing` and `runtime.render`. Size asserts: `Output_View` 16, `Frame_Clock` 24, `Output_Settings` 24, `runtime.Frame` 40, plus the librashader mirrors. | `skills/dod/SKILL.md:55–64` | T-UNIT-NATIVE, T-GL, T-ABI | headless |
| REQ-064 | GL is loaded with `-define:GL_DEBUG=false`, so `glGetError` is not consumed by debug wrappers. | `vendor/OpenGL/constants.odin:3`; E:377,1045,1189 | T-BAN | headless |
| REQ-065 | Live-session safety: no step loads the new module into the live compositor or installs it into `~/.local/share` or the system. Shell-hosted tests use only the disposable session, and the GUI talks only to the private bus. | docs/GNOME.md:246–286; task constraints | T-SAFETY | manual |
| REQ-066 | `README.md` and `docs/GNOME.md` describe the Odin/GTK 3 build, dependencies and tests, and their recipes match the commands in this catalog. | DB §1–3; `../README.md:5` | T-DOCS | manual |
| REQ-067 | Physical display, AMD GPU, HDR, hotplug and suspend behavior is checked after a fresh login by the user, and only after acceptance. | docs/GNOME.md:171–173,303–312; README.md:83 | T-HW | manual |
| REQ-068 | JSON input parsing (settings import, output inventory, status in the client) accepts and rejects the same documents as Qt's `QJsonDocument::fromJson`, with the same error texts. Confirmed on the baseline: the last duplicate key wins, empty keys are kept, trailing content is rejected, depth 1024 is accepted and 1025 rejected, and unknown escapes are accepted (`\q` → `q`). The pinned Odin `json.parse` does not do this, so design.md [C6] adds the shared `common.parse_json`. | E:83 (the single `fromJson` call; E:80–105 is the helper); CC:229–354; `$ODIN_ROOT/core/encoding/json/parser.odin:35–50,179–201,261–275`; baseline captures in `03-implementation/build-log.md` | T-CONTRACT, T-UNIT-COMMON | headless |

## Test catalog

### Setup (run once, in order, from the repository root)

```sh
cd /home/knd/AI/dodForPonytail/WaylandShader-gnome
export B="$HOME/.cache/waylandshader/build-gnome" R="$HOME/.cache/waylandshader/gnome-result"
export BASE=/tmp/ws-baseline-result EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com
# S0 baseline package (C++ original, never installed or loaded into the live Shell)
git worktree add /tmp/ws-baseline b223c1a && nix-build /tmp/ws-baseline/gnome/default.nix -o "$BASE"
# S1 Odin build tree
nix-shell gnome/shell.nix --run 'cmake -S gnome -B "$B" -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build "$B" --parallel'
# S2 baseline goldens (committed under gnome/tests/golden/cli/)
nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh capture "$BASE/bin/waylandshader-gnomectl"'
```

An exit code of 77 (skip) from any test does **not** count as a pass.

### Tests

| Test ID | Exact command | Pass criterion | Class |
|---|---|---|---|
| T-UNCHANGED | `git diff --exit-code b223c1a -- gnome/extension gnome/org.waylandshader.GnomeController.desktop gnome/native/waylandshader-effect.h gnome/tests/effect-lifecycle.js gnome/tests/recent-presets.js gnome/tests/parameter-bypass.js src tests CMakeLists.txt default.nix shell.nix shader-library.nix patches` | exit 0 | headless |
| T-ABI | `nix-shell gnome/shell.nix --run 'cmake --build "$B" --target gnome_abi_check gnome_native'` | exit 0: both `abi-check.c` (`_Static_assert`) and the Odin package (`#assert`) compile | headless |
| T-ELF | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_elf$" --output-on-failure && gnome/tests/elf-check.sh "$R/$EXT/native/libwaylandshader-gnome.so" "$R/bin/.waylandshader-gnomectl-wrapped" "$R/bin/.waylandshader-gnome-controller-wrapped"'` | Both exit 0. `elf-check.sh` checks that the sorted `nm -D --defined-only` names equal `gnome/tests/golden/exports.txt` (15 names). It also checks for SONAME `libwaylandshader-gnome.so`, NEEDED `libwaylandshader-rashader.so.2`, no NEEDED `libQt6*` or `libstdc++` in any of the three files, and no RUNPATH/RPATH entry equal to `/` (the link-only `--library-path=/`, design.md §7). | headless |
| T-GIR | `diff "$BASE/$EXT/native/WaylandShader-1.0.gir" "$R/$EXT/native/WaylandShader-1.0.gir"` | No output, exit 0 | headless |
| T-LIFE | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_effect_lifecycle$" --output-on-failure'` | 1/1 passed (the existing unchanged GJS test) | headless |
| T-RECENT | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_recent_presets$" --output-on-failure'` | 1/1 passed (unchanged GJS test) | headless |
| T-CONTRACT | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_native_contract$" --output-on-failure && GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js "$BASE/$EXT/native"'` | Both exit 0. The same script passes on the Odin build and on the baseline. Assertions cover exact GError domain, code and message, NULL returns, byte-exact `export_settings()`/`get_status()` literals including a non-ASCII preset key, and the JSON-parse edge cases of design.md §8 (duplicate key, empty key, trailing content, depth 1024/1025) recorded from the baseline. The typelib path is prepended, not replaced, as `gnome/CMakeLists.txt:102` does. | headless |
| T-UNIT-COMMON | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_common_units$" --output-on-failure'` | Passed. Writer: escaping, integral/shortest/exponent numbers, UTF-16 key order, indented layout including empty containers. Parser (`common.parse_json`): the last duplicate wins, empty key kept, trailing token rejected, depth 1024 accepted and 1025 rejected, `\q` → `q`, and no leak on any error path (tracking allocator). | headless |
| T-UNIT-NATIVE | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_native_units$" --output-on-failure'` | Passed. Covers: `frame_timing` cases; zero `total_allocation_count` delta (heap and temp) over 100 `frame_timing` and 100 `select_output` calls; `engine_check` wrong-thread and stopped messages; snippet GLSL equals `gnome/tests/golden/snippet-{decl,body}.glsl`; EGL/GL/librashader error formatters. | headless |
| T-UNIT-CLIENT | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_client_units$" --output-on-failure'` | Passed. Every `accept_json` rejection branch and message; `classify` for the four Unavailable names, `org.waylandshader.Error.*` (including `.Unavailable`) → Rejected, and other → Transport. | headless |
| T-UNIT-CTL | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_ctl_units$" --output-on-failure'` | Passed. Parser cases, number parsing, selector exact id → unique name → ambiguous. | headless |
| T-UNIT-GUI | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_gui_units$" --output-on-failure'` | Passed. Pure `view.odin` functions: state-label precedence, summary text and Load validation text. 2-decimal rounding: 1.234→1.23, 1.236→1.24, 4.999→5.00, 0.1→0.10; ties are rounded away from zero, like Qt's double-conversion `'f'` formatting [INFERENCE, so exact ties are not asserted]. Also the parameter step rule, f32 shortest text, and the round trip for 1e-7, 1.0000001e-7 and the smallest subnormal f32. No GTK initialization. | headless |
| T-GL | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_shader_runtime_gl$" --output-on-failure'` | Passed (not skipped). The port of `tests/shader_runtime_test.cpp` runs with a worker-thread load and zero allocation delta over 100 `render` calls. | headless |
| T-GL33 | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_shader_runtime_gl33$" --output-on-failure'` | Passed (not skipped) with `MESA_GL_VERSION_OVERRIDE=3.3` | headless |
| T-CLI-GOLDEN | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_cli_golden$" --output-on-failure'` | Passed. `cli-golden.sh check` runs every case under `env XDG_DATA_DIRS=<empty dir> dbus-run-session`, with argv0 replaced by `@CTL@`. Stdout, stderr and exit code equal `gnome/tests/golden/cli/` for every case. The cases are: help, usage errors, no-Shell exit 3 for each command, and `--timeout 1 status` against `hang-shell.js` (exit 4). | headless |
| T-BAN | `nix-shell gnome/shell.nix --run 'ctest --test-dir "$B" -R "^gnome_ban$" --output-on-failure'` | Passed. `ban-check.sh` finds no `panic(`/`assert(`/`unreachable(` (excluding `#assert`), no `#no_bounds_check` and no `or_panic` in non-test Odin under `gnome/{native,runtime,common,glib}`. It also finds: no `gl.Finish`/`ClientWaitSync`; `GL_DEBUG=false` and the `--version-script` in `gnome/CMakeLists.txt`; no `-no-bounds-check`; no `CXX`/`Qt6` in `gnome/CMakeLists.txt`; no `gnome/native/*.cpp`; and the literal `cannot release shader objects` in `gnome/runtime`. | headless |
| T-NIX | `nix-build gnome/default.nix -o "$R"` | exit 0. `checkPhase` CTest reports every registered test passed; any skip of 77 in the sandbox is recorded and T-GL/T-GL33 are then run in `nix-shell`. | headless |
| T-LAYOUT | The block "T-LAYOUT" below | No output, exit 0 | headless |
| T-WRAP | The block "T-WRAP" below | exit 0 (already passes on `$BASE`) | headless |
| T-KWIN | `nix-build default.nix -o /tmp/ws-kwin-result` | exit 0 | headless |
| T-BYPASS | `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh "$R" -- sh -c "gjs -m gnome/tests/parameter-bypass.js \"\$WS_PRIVATE_BUS\""'` | exit 0 (the unchanged script passes; the harness tears the session down) | isolated-session |
| T-ISO-CLI | `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh "$BASE" -- gnome/tests/iso-cli.sh "$BASE/bin/waylandshader-gnomectl" > /tmp/ws-iso-base.log && gnome/tests/isolated-session.sh "$R" -- gnome/tests/iso-cli.sh "$R/bin/waylandshader-gnomectl" > /tmp/ws-iso-new.log && diff /tmp/ws-iso-base.log /tmp/ws-iso-new.log'` | Both runs exit 0 and the diff is empty. `iso-cli.sh` logs exit codes for every step and stdout for the deterministic steps; the steps are listed in design.md §8. | isolated-session |
| T-ISO-RENDER | `nix-shell gnome/shell.nix --run 'WS_DEVKIT=1 gnome/tests/isolated-session.sh "$R" -- sh -c "read -r -p \"T-ISO-RENDER checklist done? \" _"'` | Every item of the checklist in design.md §8 is observed in the devkit window and recorded in the build log. Commands go to `$WS_PRIVATE_BUS` only. | isolated-session (manual observation) |
| T-GUI | `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh "$R" -- sh -c "env WAYLAND_DISPLAY=\"\$WS_HOST_WAYLAND_SOCKET\" GSETTINGS_BACKEND=memory GTK_DEBUG=interactive \"$R/bin/waylandshader-gnome-controller\""'` | Every item of the GUI checklist in design.md §8 is observed and recorded. The controller is a client of the private bus only; accessible names are checked in the GTK Inspector. | manual |
| T-SAFETY | Review `gnome/tests/isolated-session.sh` and `03-implementation/build-log.md` | The harness sets private `XDG_*` before `dbus-run-session`, unsets `DISPLAY`/`WAYLAND_DISPLAY` for the Shell, and refuses when its child bus equals the caller's. The log shows no install into `~/.local/share` or the system and no command against the live bus. | manual |
| T-DOCS | The block "T-DOCS" below, then a review of the hits | Every remaining hit is a KWin section or dated history, and the GNOME recipes equal this catalog's commands | manual |
| T-HW | The user installs the accepted package system-wide, logs in fresh and checks the physical AMD display: shading, gamma/saturation, HDR identity, hotplug and suspend | Recorded by the user. Agents do not perform this test. | manual |

Commands that contain shell pipes (kept out of the table so they can be copied verbatim):

```sh
# T-LAYOUT
diff <(cd "$BASE" && find . | sort) <(cd "$R" && find . | sort)
# T-WRAP
d=$(grep -o '/nix/store/[^:"]*/share/gsettings-schemas/gtk+3-[^:"/]*' "$R/bin/waylandshader-gnome-controller" | head -n1) && test -f "$d/glib-2.0/schemas/org.gtk.Settings.FileChooser.gschema.xml"
# T-DOCS
grep -nE 'Qt|QFileDialog|C\+\+|libepoxy' README.md docs/GNOME.md
```

### REQ → test coverage

Every test ID used in the requirement tables appears in the catalog above. CTest names, with their registering owner given in design.md §9, are: `gnome_effect_lifecycle`, `gnome_recent_presets`, `gnome_native_contract`, `gnome_common_units`, `gnome_native_units`, `gnome_client_units`, `gnome_ctl_units`, `gnome_gui_units`, `gnome_shader_runtime_gl`, `gnome_shader_runtime_gl33`, `gnome_cli_golden`, `gnome_elf`, `gnome_ban`.
