# Plan B: Odin port of the GNOME backend

Phase 2 design artifact (`docs/waterfall/README.md:10`). Author: adversarial planner B (opus 5.5).

Abbreviations for citations, relative to the repo root unless stated otherwise:

| Tag | Path |
|---|---|
| E / EH | `gnome/native/waylandshader-effect.cpp` / `.h` |
| R / RH | `src/shader_runtime.cpp` / `.h` |
| CC | `src/controller_client.cpp` |
| CTL | `src/ctl_main.cpp` |
| GUI | `src/controller_main.cpp` |
| CB | `src/controller_backend.h` |
| XJS | `gnome/extension/extension.js` |
| CM / NX | `gnome/CMakeLists.txt` / `gnome/default.nix` |
| ODIN | `/nix/store/lfmgkvmpihwnn96yy74m8dirrksrz074-odin-dev-2026-05/share` (the nixpkgs `odin` this repo will build with) |
| CLG | `/nix/store/fr2id25s496n8ssgybxbc033lnkldr1c-mutter-50.5/lib/mutter-18/Clutter-18.gir` |
| LRH | `/nix/store/08ikx1g0jq2097ybkpnbj39y3kn9rqg3-waylandshader-librashader-0.10.1/include/librashader/librashader.h` |

Facts I checked on this machine are cited. Anything I did not check is marked **[INFERENCE]**, and Step 1 of §7 turns it into a pass/fail gate.

---

## 1. Summary and key decisions

All five GNOME C++ components become Odin. The GNOME pieces that must stay in another language stay: the GJS extension, the GSettings schema, the public C header that g-ir-scanner parses, and the GJS tests. The build stays on CMake, so the GIR, schema, install and CTest rules carry over, and `nix-build gnome/default.nix` remains the entry point. The KWin build and every shared `src/` file stay untouched.

The plan attacks the four hard risks first:

1. **GObject subclass of `ClutterEffect` from Odin.** Odin mirrors the class and instance structs. Three independent gates verify them: Odin `#assert`, a compile-only C file that `_Static_assert`s the same numbers against the real Mutter headers, and a runtime `g_type_query` guard. The guard refuses to register the type rather than corrupt a compositor whose ABI differs from the build.
2. **GIR for an Odin `.so`.** The public header `waylandshader-effect.h` stays byte-identical and remains the scanner input. The Odin `.so` exports the same 15 symbols (14 API functions plus `wayland_shader_effect_get_type`), so the scanner's dumper works as before. A GIR diff against the C++ baseline is an acceptance test.
3. **EGL shared context, fences and worker.** The algorithm ports 1:1. The fences are GL `ARB_sync` objects (`glFenceSync`/`glWaitSync`, R:531–548, R:576–590), not `EGL_KHR_fence_sync`, so research risk 5 in `odin-native.md` does not apply. The real-GL regression is ported to Odin and runs headlessly on Mesa llvmpipe.
4. **GUI toolkit.** GTK 3 through hand-written bindings, with the layout in GtkBuilder XML. The chooser is GTK 3's in-process `GtkFileChooserDialog`, the same dialog Qt's GTK 3 platform theme showed (README.md:97, docs/GNOME.md:107, :202). The existing `wrapGAppsHook3` packaging lesson carries over unchanged.

| Decision | Chosen | Rejected alternatives (why) |
|---|---|---|
| GObject type registration | Pure Odin: `g_type_register_static_simple` plus Odin class/instance mirrors, three-layer ABI gate (§4.2) | **C shim with `G_DEFINE_TYPE`**: smaller ABI surface, but leaves a C component. Kept only as the fallback in R1 (§8). **Build-time generated Odin constants from C**: removes duplicated numbers, but adds a code generator and an Odin collection to the build. `_Static_assert` gives the same safety with no generator. |
| GIR input | Unchanged `gnome/native/waylandshader-effect.h` plus unchanged scanner flags (CM:71–88) | Hand-written GIR XML: drifts from the binary, and the scanner's runtime introspection of signals would be lost. |
| GL entry points | `vendor:OpenGL` loaded once with `eglGetProcAddress` (`ODIN/vendor/OpenGL/impl.odin:9`) | libepoxy from Odin: epoxy's API is C macros over `epoxy_*` pointers, which is awkward in Odin, and it adds a dependency the port no longer needs. |
| EGL | Own `gnome/runtime/egl.odin` foreign block (~20 procs) | `vendor:egl`: lacks `eglGetCurrentDisplay/Context/Surface`, `eglQueryAPI`, `eglQueryContext`, `eglGetError` and `eglCreatePbufferSurface` (`ODIN/vendor/egl/egl.odin:82–101`). |
| librashader | Direct link to the private `libwaylandshader-rashader.so` (as CM:21 does), with an Odin foreign block mirroring LRH | `librashader_ld.h` loader: an extra indirection the C++ build never used. |
| JSON | Parse with `core:encoding/json` (`parse_integers=false`, so every number is `f64`, matching Qt `isDouble`; `ODIN/core/encoding/json/parser.odin:31`). Emit with a ~120-line house writer that matches Qt's compact and indented output | `json.marshal`: writes `f64` as `+1.0000000000000000` (`ODIN/core/io/util.odin:94–102`, called from `marshal.odin:212`). That is not valid JSON for `JSON.parse` in extension.js, and it would also rewrite users' GSettings strings. |
| Worker thread | `core:thread`, which gives the worker an Odin context, plus `g_source_attach` completion, as E:821–831 does | `g_thread_new`: needs a manual context and manual temp-allocator teardown. |
| D-Bus client | GIO GDBus through hand-written bindings, shared by the CLI and GUI (`odin-control.md` §2) | libdbus and sd-bus: event-loop glue for no gain. |
| GUI | GTK 3, hand-written bindings, GtkBuilder XML embedded with `#load` | **GTK 4 `GtkFileDialog`**: since GTK 4.18 the FileChooser portal is the default everywhere (https://github.com/flatpak/xdg-desktop-portal-gtk/issues/505, https://docs.gtk.org/gtk4/running.html). That changes the chooser process, and GTK 4's in-process `GtkFileChooserDialog` is deprecated. **libadwaita**: an extra dependency and a look change nobody asked for. **raylib+microui**: no native chooser and no accessibility (`odin-control.md` §1). **Community odin-gtk bindings**: GTK 4 only, unpinned, not in nixpkgs. |
| Build system | Keep `gnome/CMakeLists.txt`; replace C++ targets with `add_custom_command(odin build …)` | Makefile or Nix-only phases: would rewrite working GIR, schema, install and CTest logic and the documented recipe (docs/GNOME.md:236–239). |
| CLI parsing | ~40-line hand parser that reproduces `QCommandLineParser` usage text and exit codes | `core:flags`: different help and error text, so it would not match CTL:23–64. |
| KWin and shared `src/` | Untouched, including the `WAYLANDSHADER_GNOME` branch in CB:10–27 | Deleting GNOME branches from shared files: edits KWin-compiled code that this refactor does not own. Nothing defines that macro after the cutover, so the branch costs nothing at runtime. |

Removed with no replacement: the build-local Mutter header copy (CM:39–57). It existed only because C++ rejects Mutter's forward-declared enum. Odin compiles no C, and the two C consumers (the scanner's dumper and `abi-check.c`) compile Mutter's headers as C, which the scanner already does today.

---

## 2. Module and file layout

```text
gnome/
  CMakeLists.txt                 rewritten: odin custom commands, same GIR/schema/install/ctest
  default.nix  shell.nix         Qt removed, odin added (§5)
  extension/                     UNCHANGED (extension.js, metadata.json, schemas/)
  org.waylandshader.GnomeController.desktop   UNCHANGED
  tests/
    effect-lifecycle.js recent-presets.js parameter-bypass.js   UNCHANGED
    native-contract.js           NEW GJS parity test (§6 T5)
  native/                        package waylandshader  -> libwaylandshader-gnome.so
    waylandshader-effect.h       UNCHANGED (GIR scanner input, C)
    abi-check.c                  NEW compile-only C ABI gate (never linked or shipped)
    effect.odin                  GType, class/instance mirrors, vfuncs, the 14 API exports + get_type
    boundary.odin                C-entry context, Error, GError mapping, UTF-8 text(), logging
    engine.odin                  Engine/Output/Load_Job; lifecycle, mapping, scheduling, mutators
    paint.odin                   Resources/Surface, color pipelines, before-paint, paint, frame_timing
    config.odin                  status/settings JSON writers, import/outputs parsers, recents
    mutter.odin                  Clutter/Cogl/Meta/Mtk/graphene foreign decls + mirrors
    native_test.odin             frame_timing tests + zero-allocation test
    (waylandshader-effect.cpp    DELETED)
  runtime/                       package shader_runtime (GNOME's runtime; src/shader_runtime.cpp stays for KWin)
    runtime.odin  egl.odin  libra.odin
    gltest/main.odin             real-GL regression (port of tests/shader_runtime_test.cpp) + zero-alloc
  common/                        package common (native + controller)
    json.odin  json_test.odin    Qt-compatible JSON writer (compact + indented)
    output_settings.odin         Output_Settings, ranges, adjusts_color (port of src/output_settings.h)
  glib/                          package glib: shared GLib/GObject/GIO foreign decls
    glib.odin  gobject.odin  gio.odin
  controller/
    client/  client.odin status.odin client_test.odin      package client
    ctl/     main.odin args.odin args_test.odin             -> waylandshader-gnomectl
    gui/     main.odin window.odin gtk.odin controller.ui   -> waylandshader-gnome-controller
tests/fixtures/lookup.png        NEW 2×2 RGBA (128,255,255,255) LUT for gltest (C++ generated it, shader_runtime_test.cpp:184–186)
```

What stays in C or JS, and why:

| File | Language | Reason |
|---|---|---|
| `gnome/extension/extension.js` | GJS | GNOME Shell loads extensions only as GJS modules (`odin-control.md` §5). |
| `gnome/native/waylandshader-effect.h` | C | g-ir-scanner parses C headers and builds a C dumper (https://gi.readthedocs.io/en/latest/tools/g-ir-scanner.html). It is also the ABI contract for `WaylandShader-1.0`. |
| `gnome/native/abi-check.c` | C | Compile-only proof that Odin mirrors match the real Mutter, GObject, EGL and librashader headers. It produces no shipped code. |
| `gnome/tests/*.js` | GJS | Existing regressions drive the typelib exactly as the extension does. |
| `src/*`, root `CMakeLists.txt`, `default.nix`, `tests/shader_runtime_test.cpp` | C++ | KWin backend; out of scope and must keep building. |

---

## 3. Per-component design

Every C++ feature keeps its behavior, error text and ordering. Errors are values, not exceptions (§4.5). Below, each original feature is mapped to its Odin home. The research report rows are the checklist.

Features owned by extension.js stay in GJS, unchanged: the D-Bus export, method XML and error names (XJS:10–22, :150–163), GSettings load and save (XJS:59–62, :114–122), lifecycle, the duplicate-effect guard, the output inventory, unredirect inhibition and cleanup (XJS:25–144, :193–230). The schema, metadata and desktop file also stay. The Odin side keeps all of them working by keeping the GIR API identical (T12) and the JSON identical (T5).

### 3.1 Native effect (`gnome/native`)

**Data layout** (cold except where marked hot; at most ~16 outputs):

```odin
Frame_Clock :: struct { previous_time, first_frame, expanded_frame: i64, clear_history: bool } // hot, per frame
#assert(size_of(Frame_Clock) == 32)
Output :: struct {                  // heap-allocated: signal handlers keep ^Output (E:646, E:703)
    engine: ^Engine, key: uintptr,
    view: ^Stage_View, timeline: ^Timeline, destroy_handler: c.ulong,
    resources, retired: ^Resources,
    layout: Mtk_Rectangle, scale: f64,
    settings: common.Output_Settings, clock: Frame_Clock,
    id, name, failure: string,
}
Engine :: struct {                  // fields 1:1 with E:418-444
    self: ^Effect, owner: ^GThread, main_ctx: ^GMainContext,
    stage: ^Actor, backend: ^Meta_Backend, srgb: ^Color_State,
    before_paint_handler, purge_handler: c.ulong, status_source, work_source: c.uint,
    completion: ^GSource, worker: ^thread.Thread, job: ^Load_Job,
    runtime: ^shader_runtime.Runtime, last_parameters: [dynamic]shader_runtime.Parameter,
    outputs: [dynamic]^Output, saved_outputs: map[string]common.Output_Settings,
    overrides: map[string]map[string]f64,
    preset, requested, error, pending, last_status: string, recent: [dynamic]string,
    display: egl.Display, ctx: egl.Context, draw, read: egl.Surface,
    generation: u64, next_key: uintptr,
    enabled, stopped, cursor_inhibited, mapping_dirty, loading, renderer_failed: bool,
}
Load_Job :: struct { path, error: string, overrides: map[string]f64, keys: []uintptr, generation: u64, result: ^shader_runtime.Runtime }
```

Strings and maps are owned by the heap allocator. A `set_str(&field, value)` helper frees and clones. Maps are only for cold lookups; writers sort keys at emit time (§3.3).

| Original feature (source) | Odin home |
|---|---|
| Final `ClutterEffect` type, `G_DEFINE_TYPE` (EH:14, E:499–504) | `effect.odin`: `wayland_shader_effect_get_type` (§4.2) |
| `status-changed` signal, RUN_LAST, one string (E:1317) | `class_init` → `g_signal_newv` (G_TYPE_STRING=64, G_TYPE_NONE=4) |
| dispose→shutdown; finalize frees engine; set_actor chains parent then attach; paint vfunc with catch-all → renderer_failed (E:1244–1301) | `effect.odin` vfuncs; parent class from `g_type_class_peek_parent` |
| `new()` returns NULL when the engine is missing, plus `ref_sink` (E:1330–1340) | `wayland_shader_effect_new`; also NULL when the type guard refused registration |
| `get_status` with fixed fallback literal (E:1342–1349) | `effect.odin`; the literal is copied verbatim |
| `export_settings` returns NULL on failure (E:1352–1375) | `config.odin` writer; returns NULL on allocation failure |
| `import_settings` validation order and messages, recents filter, canonical restore (E:1377–1452) | `config.odin` parse → `engine.odin` apply; `realpath` stands in for `canonicalFilePath`; the absolute string as given stands in for `absoluteFilePath` |
| `set_outputs`: validation, unchanged-inventory no-op, reset+remap (E:1454–1499) | `config.odin` parse_outputs + `engine.odin` |
| `load_preset`, `set_enabled`, `set_parameter` (live and bypassed paths), per-output setters, `reset_history`, `shutdown` (E:1501–1621) | `engine.odin` mutators; one `mutate` helper maps Error → GError |
| Owner-thread and `stopped` checks with exact messages (E:451–455) | `engine_check` |
| shader/color/active predicates (E:456–470) | `engine.odin`, same boolean expressions |
| Idle-deferred, change-only status emit with self ref/unref (E:546–571) | `notify` + `status_idle` callback |
| `queue_work` idle → sync_activity + start_load, error fallback (E:588–613) | `engine.odin` |
| Cursor inhibit and frame-clock timeline per shader output (E:630–662, E:771–774) | `sync_activity`; `new-frame` callback takes `^Output` |
| Output mapping, 4 bypass reasons, view `destroy` handler (E:664–730) | `map_outputs`; messages verbatim |
| Host context capture, GLES rejection, sRGB state (E:732–755) | `capture_context`; also calls `shader_runtime.ensure_gl_loaded()` on first capture |
| Backend discovery from the renderer view's CRTC (E:757–775) | `discover` |
| request, start_load, complete_load, reset (E:777–922) | `engine.odin`; `core:thread` worker; same generation, retire and retry rules |
| shutdown and attach, `gl-video-memory-purged` (E:933–1038) | `engine.odin` |
| Redraw: full clip plus schedule plus stage redraw (E:573–586) | `redraw` |
| `Resources`/`Surface` FP16 allocation, pipelines, snippet GLSL verbatim, uniforms cache (E:197–338) | `paint.odin`; GLSL string copied byte-for-byte |
| `copyShaderSource`: mip chain, blit, `MAX_LEVEL=0` after blit (E:339–380) | `paint.odin`, with GL binding save/restore through `defer` |
| Paint pipeline: capture, target→sRGB, FPS/warm-up, shader, final pass, present, failure restore (E:1050–1209) | `engine_paint` (outer errors) → `paint_output` (inner errors → `output.failure`); timing math in pure `frame_timing` |
| before-paint: discover, full-view clip, `expanded_frame` (E:988–1016) | `paint.odin` |

**Two-level paint error split.** C++ catches inside `paint` (E:1192–1208, sets `output.failure`, restores the raw scene) and again in the vfunc (E:1248–1267, sets `rendererFailed`). Odin makes this explicit. `paint_output` returns `Error`. `engine_paint` handles it locally (restore blit when `captured && wrote_target`, set failure, `fail()`, continue scene). Errors raised before the inner block, such as `capture_context` (E:1071), propagate to the vfunc, which sets `renderer_failed`, bumps the generation and continues the scene once (`continued` flag, E:1268–1271).

**`frame_timing` (pure, testable, hot):**

```odin
// E:1122-1160 semantics: warm-up when refresh==0, measured fps, elapsed ms clamp, first-frame numbering
frame_timing :: proc(c: ^Frame_Clock, count, now: i64, refresh: f32) -> (render: bool, fps: f32, elapsed_ms: u32, number: u64)
```

`paint_output` calls it. It commits `previous_time = now` and `clear_history = false` only after a successful render (E:1159–1160).

### 3.2 Shader runtime (`gnome/runtime`)

```odin
Parameter :: struct { name, description: string, minimum, maximum, step, default_value, value: f64 }
Frame :: struct { number: u64, source, destination, format: u32, width, height: i32, fps: f32, elapsed_ms: u32, clear_history: bool }
#assert(size_of(Frame) == 40)
Runtime :: struct {
    display: egl.Display, ctx, host: egl.Context, surface: egl.Surface, surfaceless: bool,
    max_texture_size: i32,
    keys: []uintptr, chains: []libra.Gl_Filter_Chain,  // parallel: render scans keys, touches one chain
    parameters: []Parameter, names: []cstring,         // names cloned once at load (R:395-398)
}
load :: proc(display: egl.Display, share: egl.Context, path: string, keys: []uintptr, overrides: map[string]f64) -> (^Runtime, string)
render :: proc(rt: ^Runtime, key: uintptr, f: ^Frame) -> Error          // hot, zero Odin allocations on success
set_parameter :: proc(rt: ^Runtime, name: string, value: f64) -> Error
destroy :: proc(rt: ^Runtime)                                           // R:182-209, leak+log if context cannot be entered
validate_value :: proc(p: ^Parameter, candidate: f64) -> Error          // R:153-164, f32 cast, "%.9g" text
ensure_gl_loaded :: proc()                                              // gl.load_up_to(4, 6, eglGetProcAddress), main thread only
```

| Original feature | Odin home |
|---|---|
| `Current_Context` save, enter, restore with API, and error texts (R:54–123) | `egl.odin` `Current_Context` + `defer restore` |
| Context creation: GLES rejection, surfaceless-or-pbuffer, versions 4.6/4.5/3.3 × non-robust/robust, share with host (R:211–292) | `runtime.odin` `create_context`. `epoxy_egl_version` → parse `eglQueryString(EGL_VERSION)`. `epoxy_has_egl_extension` → token search in `EGL_EXTENSIONS` |
| GL ≥ 3.3 plus `ARB_texture_storage` or 4.2; `GL_MAX_TEXTURE_SIZE` (R:341–346) | `glGetIntegerv(GL_MAJOR/MINOR_VERSION)`; `glGetStringi` extension scan |
| Preset and chain options (R:348–357) | `libra.odin` structs with `#assert` |
| Per-output preset load, metadata validation, union with last-pass-wins, sort, overrides check, get/set param, cross-chain agreement, validation chain freed when there are no outputs (R:359–453) | `load`, messages verbatim |
| `setParameter` preflight, set, rollback (R:466–505) | `set_parameter` |
| render: frame validation, host-context check, incoming fence, private context, `libra_gl_filter_chain_frame` with the fixed MVP, outgoing fence, restore, GPU wait (R:507–592) | `render` |
| Error text from `libra_error_write` or `librashader failed (error N)` (R:29–43); EGL `"%s failed (EGL error 0x%04x)"` (R:22–27) | `libra.odin` `check`, `egl.odin` `egl_error` |

### 3.3 Common (`gnome/common`)

- `output_settings.odin` ports `src/output_settings.h:5–19`: `Output_Settings{gamma, saturation: f64, shader_enabled, color_enabled: bool}` with `#assert(size_of == 24)`, `MIN_GAMMA = 0.1`, `MAX_GAMMA = 5`, `MIN_SATURATION = 0`, `MAX_SATURATION = 2`, `adjusts_color`.
- `json.odin` reproduces Qt 6 `QJsonDocument` output so persisted GSettings strings and CLI output keep their form:
  - **Keys:** objects written in sorted key order (byte order; keys are ASCII identifiers or paths). The native writers emit fixed literal key sequences: status `active, enabled, error, loading, outputs, parameters, preset, recentPresets, requestedPreset`; parameter row `default, description, maximum, minimum, name, step, value`; output row `bypass?, colorActive, colorEnabled, gamma, id, name, saturation, shaderActive, shaderEnabled`; settings `enabled, outputs, parameters, preset, recent_presets, version`. That sorted order is [INFERENCE] about Qt 6 QJsonObject (`native-effect.md` §8 also flags it). T5 compares against literals recorded from the C++ baseline, so the order is verified, not assumed.
  - **Numbers:** an integral value that fits `i64` exactly is written as an integer. Anything else uses `strconv` shortest `'g'` with C-style exponent (`1e-07`). [INFERENCE]: this matches `QByteArray::number(d,'g',FloatingPointShortest)` plus Qt 6 storing integral doubles as integers. Pinned by T5 and T6.
  - **Strings:** escape `"`, `\`, `\b\f\n\r\t`, and other `<0x20` as `\u00XX`; UTF-8 passes through.
  - `write_value(b, json.Value, indent)` gives Qt `Indented`: 4 spaces, `"k": v`, an empty array prints as `[\n<indent>]`, and a trailing newline. Used by the CLI to reprint the status (CTL:160–162, :199–200).

### 3.4 D-Bus client (`gnome/controller/client`)

This API is the contract the ux and ui agents code against:

```odin
SERVICE :: "org.gnome.Shell"; EFFECT_PATH :: "/WaylandShader"; EFFECT_INTERFACE :: "org.waylandshader.Effect"
ACTIVATION_PATH :: "/org/gnome/Shell"; ACTIVATION_INTERFACE :: "org.gnome.Shell.Extensions"; UUID :: "waylandshader@man33li.github.com"
COMPOSITOR, DESKTOP_ENVIRONMENT, EFFECT_DESCRIPTION, INSTALLATION_HINT, ACTIVATION_HINT :: … // verbatim CB:12-27
Kind   :: enum { None, Unavailable, Rejected, Protocol, Transport }
Error  :: struct { kind: Kind, message: string }
Parameter :: struct { name, description: string, minimum, maximum, step, default_value, value: f64 }
Output :: struct { id, name: string, settings: common.Output_Settings, shader_active, color_active: bool, bypass: string }
Status :: struct { enabled, active, loading: bool, preset, requested_preset, error: string,
                   recent_presets: []string, parameters: []Parameter, outputs: []Output, json: json.Object }
Reply  :: struct { fn: proc(data: rawptr, err: Error), data: rawptr }
Client :: struct { /* bus, subscriptions, generation */ status: Status, has_status: bool,
                   listener: rawptr, on_status: proc(rawptr, ^Status), on_transport_error: proc(rawptr, Error) }
init :: proc(c: ^Client) -> bool
ensure_available :: proc(c: ^Client, allow_activation: bool, r: Reply)
request_status :: proc(c: ^Client, r: Reply)
load_preset / set_enabled / set_parameter / set_output_shader_enabled / set_output_color_enabled /
set_output_gamma / set_output_saturation :: proc(c: ^Client, …, r: Reply)
accept_json :: proc(c: ^Client, json: string) -> Error   // pure: CC:229-354
classify    :: proc(remote_name, message: string, local: bool) -> Error   // pure: CC:21-35
```

| Original feature | Odin home |
|---|---|
| Subscribe to `statusChanged`, `ExtensionStateChanged`, and owner change (CC:62–87) | `g_dbus_connection_signal_subscribe` ×3. The owner change watches `org.freedesktop.DBus.NameOwnerChanged` with arg0=`org.gnome.Shell`, keeping the exact "old owner nonempty and changed" rule |
| Async call with 10000 ms timeout and interface-generation guard (CC:89–115) | `g_dbus_connection_call(…, reply_type=nil, timeout=10000)`. A per-call heap `Pending{client, path, generation, reply}` is freed in the callback |
| Error classification (CC:21–43) | `g_dbus_error_get_remote_error` + `g_dbus_error_strip_remote_error`. The four `org.freedesktop.DBus.Error.{ServiceUnknown,UnknownObject,UnknownMethod,UnknownInterface}` names map to Unavailable, `org.waylandshader.Error.*` to Rejected (keeps O1, `control-surface.md`), everything else to Transport |
| Boolean reply check (CC:45–58) | `g_variant_is_of_type(v, "(b)")` |
| ensure_available activation chain, 10 s, states 1/2/6/8 (CC:117–215) | heap `Activation{done, timer_id}`; numeric `state` accepted as `d`/`u`/`i` and converted like `QVariant::toUInt` |
| Status validation, every branch and message (CC:229–354) | `status.odin` `accept_json`; keeps the parsed `json.Object` for the CLI |

### 3.5 CLI `waylandshader-gnomectl` (`gnome/controller/ctl`)

- `args.odin` is a pure `parse(args) -> (Command, usage_error: string, exit: int)`. It accepts `-h`, `--help`, `-?`, `--timeout N`, `--timeout=N`, `--`, and options interleaved with positionals, which is QCommandLineParser's behavior. Every validation and message in CTL:58–140 is reproduced. Number parsing trims whitespace and then uses `strconv.parse_f64`/`parse_int`. [INFERENCE]: equivalent to `QString::toDouble`/`toInt`; T10 pins the cases.
- The help text is the CTL:23–49 description with `%1..%6` substituted, inside Qt's `Usage:`/`Options:`/`Arguments:` frame.
- `main.odin` runs a `GMainLoop` state machine over `client`, mirroring CTL:142–287. A deadline `g_timeout_add(timeout*1000)` exits 4. Rejected exits 1, anything else 3, usage 2. The `load` path sets `load_accepted` and re-requests status, then the same `evaluate_load` rules apply (CTL:163–180). The monitor selector tries exact id first, then a unique name; an ambiguous name is a usage error, exit 2 (CTL:249–271).
- Dropped Qt-only option: `--help-all`, which lists Qt's internal options and is not a project feature.

### 3.6 GUI `waylandshader-gnome-controller` (`gnome/controller/gui`)

- `controller.ui` (GtkBuilder, GTK 3) holds the whole static layout of GUI:67–165: title `WaylandShader — GNOME Shell Desktop Effects`, default 740×620, the intro label, the preset row (entry with placeholder and accessible name, Browse…, Recent ▾ GtkMenuButton with tooltip and accessible name, Load preset), the enable checkbox, Reconnect / refresh, the monitor row (GtkComboBoxText with mnemonic label and a state label), two toggles, Gamma and Saturation spin buttons (digits 2, step 0.05, ranges from `common`, tooltips verbatim), selectable word-wrapped summary and error labels, a scrolled GtkGrid for parameters, and the note label. Accessible names go through `<child internal-child="accessible">`, buddies through `mnemonic-widget`.
- `window.odin` ports the `SettingsWindow` state machine (GUI:221–589) with the same fields. `m_available`, `m_loading`, `m_loadPending`, `m_enablePending`, `m_pathEdited`, `m_updatingOutputs`, `m_outputPending` and the pending and selected ids are plain fields of `App`. `QSignalBlocker` becomes a `programmatic` counter that every handler checks.
- `QDoubleSpinBox` keyboardTracking(false) maps to `GtkSpinButton`'s default commit-on-activate/focus-out. `ParameterSpinBox` (GUI:32–63) becomes the `output` signal printing the shortest `f32` (`strconv` 'g' -1 32) and the `input` signal parsing, casting to `f32`, and returning `GTK_INPUT_ERROR` on failure. GTK clamps to range.
- The parameter editors' 100 ms debounce uses `g_timeout_add(100)` per editor. A `revision` counter and the dirty flag match GUI:464–486. On rebuild the editor `epoch` increments and all timers are removed. A reply whose epoch is stale returns without touching editors, matching the `QPointer` early return at GUI:477–479.
- Browse is modal `gtk_file_chooser_dialog_new` + `gtk_dialog_run`, same modality as `QFileDialog::getOpenFileName`. A filter named `RetroArch slang presets (*.slangp)` with pattern `*.slangp`. The initial folder or file comes from the entry text. A file chosen there fills the entry and sets `path_edited`.
- Recent: a `GtkMenu` of `gtk_menu_item_new_with_label(path)`. These labels are not parsed for mnemonics, so the `&`→`&&` escape of GUI:512 is unnecessary. Selecting an item fills the entry and focuses it; it never loads. The menu is disabled when empty.
- Monitor combo: `gtk_combo_box_text_append(id, name)`. With zero outputs there is one insensitive item `No connected monitors`. The combo tooltip is the selected id (GUI:273). The per-item popup tooltip (GUI:318) is not reproduced: GTK 3 combo popups have no item tooltips, and GNOME ids equal names (XJS:100–101), so it showed the visible text a second time.
- App identity: `g_set_prgname("org.waylandshader.GnomeController")` before `gtk_init`, so the Wayland app_id matches the desktop file, standing in for `setDesktopFileName` (GUI:597) [INFERENCE: GTK 3 Wayland uses prgname as app_id when no GApplication exists; T19 checks the dash icon]. No GApplication, so there is no single-instance behavior the Qt app never had.

### 3.7 Qt replacements

| Qt | Odin |
|---|---|
| `QString`, `QByteArray`, `QStringList` | `string`, `[]u8`, `[dynamic]string` (recents: remove, prepend, truncate to 10 per E:866–868) |
| `QMap`, `QSet` | `map[K]V` plus sorted emission; linear duplicate checks (n small) |
| `QJson*` | `core:encoding/json` parse + `common` writer |
| `QFileInfo` | `core:sys/posix` `stat`/`access(R_OK)`/`realpath`; absolute means a leading `/`; NUL check `strings.contains_rune(path, 0)` (R:314) |
| `QDebug`, `g_warning` | `g_log(nil, LEVEL, "%s", msg)` (nil domain, as the C++ compiled without `G_LOG_DOMAIN`) |
| `.arg` formatting | `fmt.tprintf` (temp allocator), with `%x`, `%04x`, `%.9g`; cold paths only |

---

## 4. FFI and ABI plan

### 4.1 Binding inventory and rules

- **Hand-written foreign blocks** only: `glib/` (GLib, GObject, GIO), `native/mutter.odin` (about 70 procs listed from E's call sites: Clutter, Cogl, Meta, Mtk, graphene), `runtime/egl.odin`, `runtime/libra.odin` (14 procs from LRH:1219–1479), `gui/gtk.odin` (about 45 GTK 3 procs). `vendor:OpenGL` provides GL.
- Libraries are linked by name through `foreign import x "system:mutter-clutter-18"` etc. The `-L` and `-rpath` come from pkg-config (§5). Private Mutter symbols (E:31–50) are declared exactly as the C++ declared them. `-Wl,--no-undefined` (CM:67) is kept, so a missing symbol fails the link, not the compositor.
- C macros are never mirrored as logic. `G_OBJECT_TYPE`/`*_IS_*` become `g_type_check_instance_is_a`. `g_signal_connect` becomes `g_signal_connect_data`. `g_object_new` becomes `g_object_new_with_properties(type, 0, nil, nil)`. `G_VARIANT_TYPE("(s)")` becomes a cast of a cstring.
- Variadic C functions are bound with `#c_vararg` only where unavoidable: `g_signal_emit`, `g_log`, `g_variant_new`, `g_object_get` (for the sRGB state's `context` property, E:301), `gtk_file_chooser_dialog_new`. `gboolean` arguments are passed as `b32`, doubles as `f64`.
- Strings returned as `transfer full` (`get_status`, `export_settings`) must be `g_strndup` copies, because GJS frees them with `g_free`. Never return Odin-allocated memory to C.
- Ownership rule for parallel agents: a missing declaration goes into the file the agent owns, with its own `foreign import`. Agents never edit another agent's binding file.

### 4.2 GObject subclass of `ClutterEffect`

Layouts on x86_64. Field lists come from the GIR (CLG:12532 `ActorMetaClass` = `parent_class, set_actor, set_enabled`; CLG:20604 `EffectClass` = `parent_class, pre_paint, post_paint, modify_paint_volume, paint, paint_node, pick`; `ClutterActorMeta` and `ClutterEffect` instances have only `parent_instance`). The GObject layout is GLib's stable public ABI.

```odin
GObject_Class :: struct {               // gobject/gobject.h
    g_type: GType, construct_properties: rawptr,
    constructor, set_property, get_property: rawptr,
    dispose, finalize: proc "c" (obj: ^GObject),
    dispatch_properties_changed, notify, constructed: rawptr,
    flags, n_construct_properties: uint, pspecs: rawptr, n_pspecs: uint, pdummy: [3]rawptr,
}
Actor_Meta_Class :: struct { using parent: GObject_Class,
    set_actor: proc "c" (meta: ^Actor_Meta, actor: ^Actor), set_enabled: rawptr }
Effect_Class :: struct { using parent: Actor_Meta_Class,
    pre_paint, post_paint, modify_paint_volume: rawptr,
    paint: proc "c" (effect: ^Effect, node: rawptr, pc: ^Paint_Context, flags: u32),
    paint_node, pick: rawptr }
Effect :: struct { parent_instance: [3]rawptr /* GObject = ClutterEffect, 24 B */, engine: ^Engine }
#assert(size_of(GObject_Class) == 136 && offset_of(GObject_Class, dispose) == 40 && offset_of(GObject_Class, finalize) == 48)
#assert(size_of(Actor_Meta_Class) == 152 && offset_of(Actor_Meta_Class, set_actor) == 136)
#assert(size_of(Effect_Class) == 200 && offset_of(Effect_Class, paint) == 176)
#assert(size_of(Effect) == 32)
```

Three gates:

1. **Odin `#assert`** (above). These fail compilation if a mirror is edited.
2. **`gnome/native/abi-check.c`**, compiled with `$(pkg-config --cflags libmutter-18 egl)` and the librashader include path as a CMake `OBJECT` library in `ALL`. It asserts the same literals against the real headers: `sizeof(GObjectClass)==136`, `offsetof(GObjectClass,dispose)==40`, `finalize==48`, `sizeof(ClutterActorMetaClass)==152`, `offsetof(…,set_actor)==136`, `sizeof(ClutterEffectClass)==200`, `offsetof(…,paint)==176`, `sizeof(ClutterEffect)==24`, `sizeof(ClutterLuminance)==20`, `offsetof(ClutterLuminance,ref)==12`, `mastering_max==16` (the bitfield-first record, CLG:47042), `sizeof(MtkRectangle)==16`, `sizeof(graphene_matrix_t)==64`, `sizeof(GTypeQuery)==24`, `sizeof(GError)==16`; the enums `CLUTTER_COLORSPACE_SRGB==0`, `CLUTTER_TRANSFER_FUNCTION_SRGB_PIECEWISE==0`, `CLUTTER_EFFECT_PAINT_BYPASS_EFFECT==2`, `COGL_PIXEL_FORMAT_RGBA_FP_16161616_PRE==155`, `COGL_SNIPPET_HOOK_TEXTURE_LOOKUP==6145`, `COGL_PIPELINE_FILTER_NEAREST==9728`, `COGL_PIPELINE_WRAP_MODE_CLAMP_TO_EDGE==33071`, `COGL_BUFFER_BIT_COLOR==1` (values read from the GIR on this machine); `G_TYPE_STRING==64`, `G_TYPE_NONE==4`, `G_SIGNAL_RUN_LAST==2`; every EGL constant in `egl.odin`; and `sizeof` of `frame_gl_opt_t`(40), `filter_chain_gl_opt_t`(16), `libra_preset_opt_t`(16), `libra_preset_param_t`(32), `libra_preset_param_list_t`(16), `libra_image_gl_t`(16) from LRH:189–318. Plain C accepts Mutter's forward-declared enum (the reason CM:39–57 existed), as the scanner's dumper already proves.
3. **Runtime guard in `get_type`.** Before registering, `g_type_query(clutter_effect_get_type())` must report `class_size == 200` and `instance_size == 24`. On mismatch it logs `g_critical` and returns `0`. `wayland_shader_effect_new` then returns NULL, and extension.js's `enable()` throws into `_cleanup()` (XJS:41–42, :67–70). A Mutter rebuilt with a different layout cannot reach mis-offset vfuncs. The g-ir-scanner dumper runs the same guard, so a mismatched build also fails at GIR time.

Registration:

```odin
@(export, link_name="wayland_shader_effect_get_type")
wayland_shader_effect_get_type :: proc "c" () -> GType {
    if g_once_init_enter(&type_id) {
        context = boundary_context()
        t: GType = 0
        if parent_layout_ok() { // gate 3
            t = g_type_register_static_simple(clutter_effect_get_type(), "WaylandShaderEffect",
                size_of(Effect_Class), class_init, size_of(Effect), instance_init, 0) // flags 0 = G_DEFINE_TYPE
        }
        g_once_init_leave(&type_id, t)
    }
    return type_id
}
```

`class_init` saves `parent_class = g_type_class_peek_parent(klass)` and writes the `dispose`, `finalize`, `set_actor` and `paint` pointers into `^Effect_Class`. It creates the signal with `g_signal_newv("status-changed", t, RUN_LAST, nil, nil, nil, nil, G_TYPE_NONE, 1, &[G_TYPE_STRING])`. `instance_init` allocates the `Engine`, capturing `g_thread_self()` and `g_main_context_ref_thread_default()` (E:420–421). Globals are zero-initialized `.bss` values. Nothing relies on Odin's `@(init)` or global initializers. The compiler binary contains `-init,` linker-flag strings next to `_odin_entry_point`, which suggests the dll entry (`ODIN/base/runtime/entry_unix.odin:8–19`) is wired through `-Wl,-init`. That is still [INFERENCE] until gate S1-c checks it.

### 4.3 librashader mirrors

These are `libra.odin` structs matching LRH:189–318, with `bool` = Odin `bool` (1 byte), `LIBRASHADER_API_VERSION` = `uint`, and `#assert`s matching gate 2. `libra_gl_filter_chain_frame` takes `libra_image_gl_t` **by value** (LRH:1421–1427). Odin's `"c"` convention must pass a 16-byte `{u32×4}` struct in two integer registers. That is [INFERENCE] about Odin's SysV lowering. The gltest pixel checks (T8) fail on any mismatch. The loader argument is `egl.GetProcAddress` itself (signature `proc "c" (cstring) -> rawptr`, LRH:235).

### 4.4 EGL, GL, fences and the worker

- `ensure_gl_loaded` runs `gl.load_up_to(4, 6, set_proc)` with `eglGetProcAddress` once, on the main thread, at the first `capture_context`. That precedes any worker by construction, since `start_load` requires a captured context (E:796–797). Under libglvnd the pointers are dispatch stubs valid for any current context [INFERENCE; T8 runs load on a worker and render on the host thread].
- **Always build with `-define:GL_DEBUG=false`.** `vendor:OpenGL` defaults `GL_DEBUG` to `ODIN_DEBUG` (`ODIN/vendor/OpenGL/constants.odin:3`). The debug wrappers would consume `glGetError`, which E:377, :1045 and :1189 read.
- Host context save and restore: `Host_Context` (E:131–165) and `Current_Context` (R:56–123) become structs with `enter` and `restore` procs plus `defer`. `GLBindings` (E:168–195) becomes `save_bindings()`/`restore_bindings()` with `defer`.
- Fences: `gl.FenceSync`, `gl.Flush`, `gl.WaitSync(…, gl.TIMEOUT_IGNORED)`, `gl.DeleteSync` exactly at R:531–548 and R:576–590. GPU-side waits only.
- Worker: `start_load` clones path, overrides and keys into a `Load_Job`, creates the idle `completion` source, then `thread.create_and_start_with_poly_data2(job, completion, compile_proc)`. The worker calls `shader_runtime.load(display, ctx, …)`, stores the result or a heap error in the job, then calls `g_source_attach(completion, main_ctx)` (E:821–831). It never touches `Engine`. `complete_load` does `thread.join` + `thread.destroy` (E:845). A runtime is destroyed only on the owner thread inside `Host_Context` (E:853, :900, :959).

### 4.5 Error boundary: no panics across C

- **Every C entry is `proc "c"`.** That covers the 14 exports, `get_type`, class and instance init, 4 vfuncs, 4 signal callbacks, 3 idle callbacks, the worker body, and all GDBus and GTK callbacks. Each starts with `context = boundary_context()` and `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()`. The guard is nest-safe: a JS `status-changed` handler that re-enters `get_status` gets its own region.
- `boundary_context()` is `runtime.default_context()` with `assertion_failure_proc` replaced by one that logs `g_log(CRITICAL)` and then traps. A bounds-check failure still aborts the process, like a C++ segfault, but leaves a journal line. Bounds checks stay **on**, because memory safety outranks uptime.
- `Error :: Maybe(string)`. Messages are static or `fmt.tprintf` into the temp allocator. Anything persisted (engine.error, output.failure, job.error) is cloned to the heap before the guard ends.
- Banned in `native/` and `runtime/`, and checked by the security agent with `grep -nE '\b(panic|assert|unreachable|#no_bounds_check)\b' gnome/native gnome/runtime` (no matches except `#assert`): `panic`, `assert`, `unreachable`, `#no_bounds_check`, `or_else panic`. Allocation errors from `new`/`make`/`append` are checked and become `"Out of memory"`. C++ caught `bad_alloc` at the same boundary.
- `mutate` maps an Error to `g_set_error_literal(err, g_quark_from_static_string("wayland-shader-error"), 1, msg)` and returns false (E:1218–1230). `text()` rejects NULL or invalid UTF-8 with `Invalid UTF-8 argument` (E:74–78) via `core:unicode/utf8`.
- The controller binaries are ordinary executables, so a panic ends only that process, the same as a Qt crash (docs/GNOME.md:33). They follow the same Error-value style.

### 4.6 Hot paths (DOD)

The repo has no load line. Stated assumption: **zero Odin heap or temp allocations per view per frame; outputs ≤ 16.** Hot procs: `before_paint`, the vfunc `paint`/`engine_paint`/`paint_output`, timeline `new-frame`, `frame_timing`, and `shader_runtime.render`.

- No `fmt`, no `map` access, no string building or cloning on the success path. The output is found by a linear scan of `^Output` pointers (n ≤ 16; the skill's "don't speculate" rule rules out SoA for that many items). The runtime chain is found by scanning `keys` (a parallel slice), then one chain is touched.
- Layout locks: `#assert(size_of(Frame_Clock) == 32)`, `#assert(size_of(common.Output_Settings) == 24)`, `#assert(size_of(shader_runtime.Frame) == 40)`, plus the librashader `#assert`s.
- Zero-allocation tests use `mem.Tracking_Allocator` as both `context.allocator` and `context.temp_allocator`, warm up once, then assert `total_allocation_count` is unchanged:
  - across 100 `frame_timing` calls (T7);
  - across 100 `render` calls on a real llvmpipe context (T8).

---

## 5. Build and packaging

**`gnome/CMakeLists.txt`** (rewrite; illustrative core):

```cmake
project(WaylandShaderGNOME VERSION 0.1.0 LANGUAGES C)        # C only for abi-check.c
find_program(ODIN odin REQUIRED)
pkg_check_modules(MUTTER REQUIRED IMPORTED_TARGET libmutter-18)  # + existing 50.x guard (CM:17-19)
pkg_check_modules(NATIVE_LIBS REQUIRED libmutter-18 mutter-clutter-18 mutter-cogl-18 mutter-mtk-18 graphene-gobject-1.0 egl gio-2.0)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)
find_library(LIBRASHADER_LIBRARY waylandshader-rashader REQUIRED)   # CM:20-21 kept
get_filename_component(LIBRASHADER_DIR ${LIBRASHADER_LIBRARY} DIRECTORY)
set(ODIN_FLAGS -o:speed -vet -strict-style -define:GL_DEBUG=false)
# -L and matching -Wl,-rpath for every NATIVE_LIBS_LIBRARY_DIRS entry and LIBRASHADER_DIR
set(NATIVE_LDFLAGS "-Wl,--no-undefined -Wl,-soname,libwaylandshader-gnome.so ${NATIVE_L} ${NATIVE_RPATH}")
add_library(gnome_abi_check OBJECT native/abi-check.c)               # gate 2, in ALL
target_link_libraries(gnome_abi_check PRIVATE PkgConfig::MUTTER)
target_include_directories(gnome_abi_check PRIVATE ${LIBRASHADER_INCLUDE_DIR})
add_custom_command(OUTPUT libwaylandshader-gnome.so
    COMMAND ${ODIN} build ${CMAKE_CURRENT_SOURCE_DIR}/native -build-mode:dll
            -out:${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so ${ODIN_FLAGS}
            "-extra-linker-flags:${NATIVE_LDFLAGS}"
    DEPENDS ${NATIVE_ODIN_SOURCES} VERBATIM)   # file(GLOB CONFIGURE_DEPENDS native/*.odin runtime/*.odin common/*.odin glib/*.odin)
# GIR/typelib commands CM:69-94 unchanged except: library path = ${CMAKE_CURRENT_BINARY_DIR},
#   DEPENDS libwaylandshader-gnome.so and native/waylandshader-effect.h
# controller/ctl and controller/gui: same pattern, without -build-mode:dll
# install: install(FILES libwaylandshader-gnome.so …/native), install(PROGRAMS the two binaries), the rest = CM:137-143
```

**GIR generation:** same scanner invocation (CM:71–88). The dumper links `-lwaylandshader-gnome` from the build dir. It calls the Odin `wayland_shader_effect_get_type`, which runs gate 3 and `class_init`, and introspects the `status-changed` signal. `shared-library="libwaylandshader-gnome.so"`, as in the baseline GIR. The SONAME is set explicitly to match the CMake default.

**Commands:**

```bash
# dev (inside: nix-shell gnome/shell.nix)
cmake -S gnome -B "$HOME/.cache/waylandshader/build-gnome" -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON
cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel
ctest --test-dir "$HOME/.cache/waylandshader/build-gnome" --output-on-failure
# package and KWin regression
nix-build gnome/default.nix -o "$HOME/.cache/waylandshader/gnome-result"
nix-build default.nix -o /tmp/ws-kwin-result
```

**`gnome/default.nix` changes** (everything else stays, including the Mutter 50 assert at NX:6–7, the source filter, `sourceRoot`, `passthru` and `meta`):

```nix
nativeBuildInputs = with pkgs; [ cmake ninja pkg-config gobject-introspection glib gjs odin wrapGAppsHook3 ];
buildInputs = with pkgs; [ mutter gtk3 expat isocodes lerc libdeflate libevdev libwebp xz libGL shaderLibrary ]
              ++ pkgs.mutter.buildInputs;       # - qtbase qtwayland libepoxy
nativeCheckInputs = with pkgs; [ dbus mesa ];   # T11 dbus-run-session; T8 llvmpipe
preCheck = ''
  export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json LIBGL_ALWAYS_SOFTWARE=1
'';
# removed: kdePackages.wrapQtAppsHook, dontWrapGApps, preFixup qtWrapperArgs merge (NX:56-61):
# wrapGAppsHook3 now wraps both binaries directly, still supplying org.gtk.Settings.FileChooser
```

nixpkgs' `odin` wraps the compiler with `clang-wrapper-18.1.8` and `lld` on PATH (checked in the wrapper script), so NIX_LDFLAGS also apply. The explicit pkg-config `-L`/`-rpath` keep the build working in `nix-shell` too. `gnome/shell.nix`: drop `clang-tools` and `kdePackages.qttools`, the C++/Qt tooling; keep the rest.

---

## 6. Test plan

The environments named below:
- **headless**: runs in the Nix sandbox `checkPhase`, or in `nix-shell` on the host with no display.
- **isolated**: a disposable GNOME Shell started by the documented recipe (docs/GNOME.md:248–286: private XDG dirs, `dbus-run-session`, `gnome-shell --headless --virtual-monitor …`, `LIBGL_ALWAYS_SOFTWARE=1`).
- **manual**: a human looks.

The live compositor never loads a new module.

| ID | Command | Proves | Env |
|---|---|---|---|
| T1 | `cmake --build` (compiles `abi-check.c`) | Odin mirrors equal the real Mutter, GObject, EGL and librashader headers (gate 2) | headless |
| T2 | (inside T3–T5) `Effect.new()` non-null | runtime layout guard passes on the installed Mutter (gate 3); Odin dll loads under `dlopen` (TLS, init) | headless |
| T3 | `ctest -R gnome_effect_lifecycle` (unchanged CM:100–105) | GI ownership, pending-load disable delivered after GC, shutdown | headless |
| T4 | `ctest -R gnome_recent_presets` (unchanged) | recents filter, order, dedup, cap 10, malformed → empty | headless |
| T5 | `ctest -R gnome_native_contract`: `gjs -m gnome/tests/native-contract.js <native dir>` | **Parity with C++**: exact GError messages, domain and code for `set_outputs` (missing scale, duplicate id, non-integer geometry), gamma and saturation bounds and NaN, unknown output, `set_parameter` without a preset, relative `load_preset`, import version/object/relative-preset errors, mutators after `shutdown`. **Byte-exact** `export_settings()` and `get_status()` strings for a fixed config (gamma 0.1, saturation 2, parameter 1e-7 and 0.5, recents) equal literals recorded from the C++ baseline | headless; **must also pass on the baseline build** first (§7 Step 0) |
| T6 | `ctest -R gnome_common_units`: `odin test gnome/common` | JSON writer: escaping, integral/shortest/exponent numbers, indented layout incl. empty containers | headless |
| T7 | `ctest -R gnome_native_units`: `odin test gnome/native` | `frame_timing`: warm-up at refresh 0, measured fps, elapsed clamp, numbering from first frame; **zero-allocation** over 100 calls | headless |
| T8 | `ctest -R gnome_shader_runtime_gl` and `_gl33` (`MESA_GL_VERSION_OVERRIDE=3.3`): `shader-runtime-gltest ../tests/fixtures`, `SKIP_RETURN_CODE 77` | Port of `shader_runtime_test.cpp`: worker-thread load with a shared context, 2 outputs × 2 reload cycles, the 8 pixel expectations per cycle at ±0.003 (:107–118), host context and viewport restored (:80–86), MISSING/GAIN=3 rejected, GAIN 0.5/0.1 accepted, base-level high-LOD sampling (:120–136), robust and non-robust host contexts; **zero-allocation** over 100 `render` calls | headless (llvmpipe); skips 77 if Mesa surfaceless is missing, in which case run in `nix-shell` on the host |
| T9 | `ctest -R gnome_client_units`: `odin test gnome/controller/client` | every `accept_json` rejection branch and message (CC:236–348); `classify` for the 4 Unavailable names, `org.waylandshader.Error.*`→Rejected (keeps O1), other→Transport | headless |
| T10 | `ctest -R gnome_ctl_units`: `odin test gnome/controller/ctl` | arg parser: every usage error → 2 with exact text, `--timeout` 0/3601/x, `load` non-.slangp, param NaN, output on/off and bounds, `--help` → 0 | headless |
| T11 | `ctest -R gnome_ctl_no_service`: `dbus-run-session -- sh -c 'waylandshader-gnomectl status; test $? -eq 3'` | client and CLI end to end on a real bus: ServiceUnknown → Unavailable → exit 3 | headless |
| T12 | `diff <(grep -v shared-library $BASE/…/native/WaylandShader-1.0.gir) <(grep -v shared-library build/WaylandShader-1.0.gir)` | GIR namespace API consumed by extension.js is identical | headless (needs baseline) |
| T13 | `nm -D --defined-only build/libwaylandshader-gnome.so` | only the 15 `wayland_shader_effect_*` symbols plus Odin's entry points are exported | headless |
| T14 | `nix-build default.nix` | KWin backend still builds; its CTest unchanged | headless |
| T15 | `nix-build gnome/default.nix` | full package incl. T1–T11 in `checkPhase` | headless |
| T16 | `gjs -m gnome/tests/parameter-bypass.js "$private_bus"` (docs/GNOME.md:278–282) | real stage: preset compiles and is active, bypassed edits persist, invalid edits rejected, re-enable applies, recents | isolated |
| T17 | In the T16 session: `DBUS_SESSION_BUS_ADDRESS=$private_bus waylandshader-gnomectl {status,outputs,parameters,output Virtual-1 gamma 1.2,output Virtual-1 saturation 0,output Virtual-1 color on,param GAIN 0.5,load <fixture>,toggle,disable,enable}` plus `--timeout 1 load` during compile → 4. Repeat the same script with the baseline package's `waylandshader-gnomectl` in a second disposable session and `diff` the stdout and exit codes | CLI, D-Bus and native parity on a live stage | isolated |
| T18 | `gnome-shell --devkit` with the same private-XDG recipe, viewed in its nested window: saturation 0 → grayscale; gamma 2; temporal fixture animates; per-output shader/color toggles; master disable restores the scene; unmappable output shows `Unfiltered:` | pixels actually processed [INFERENCE: devkit shows the post-effect view framebuffer] | isolated (window on live desktop; module loaded only in the disposable Shell) |
| T19 | Run the GUI with `WAYLAND_DISPLAY` from the live desktop, `DBUS_SESSION_BUS_ADDRESS=$private_bus`, `GSETTINGS_BACKEND=memory`. Check Browse/Cancel/reopen/select a path with spaces (docs/GNOME.md:290), Recent fills but does not load, Load, Enter-to-load, enable checkbox, monitor combo and state labels, gamma/saturation commit, parameter debounce, disconnect text after stopping the disposable Shell, Orca/Accerciser names, dash icon (app_id) | GUI behavior list (`control-surface.md` §5) | manual; the controller is only a client of the disposable bus |
| T20 | Fresh login on the user's machine after acceptance | physical display, AMD, HDR and hotplug | manual, user-owned; not performed by agents |

---

## 7. Work breakdown

**Step 0, baseline (builder Astra).** `git worktree add /tmp/ws-baseline b223c1a && nix-build /tmp/ws-baseline/gnome/default.nix -o /tmp/ws-baseline-result`. Keep its GIR (T12), `waylandshader-gnomectl` (T17), and native dir. The security agent writes T5, runs it against `/tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native`, and pastes the recorded `export_settings`/`get_status` literals into the test.

**Step 1, spikes (code agent; gate for everything else).**
- **S1.** A minimal `gnome/native` (type registration, gates 1–3, `new`, `get_status` returning `{}`, `shutdown`) plus the GIR/typelib commands plus `gjs -e` import. Checks:
  - (a) `gnome_abi_check` compiles;
  - (b) g-ir-scanner succeeds;
  - (c) `readelf -d` shows INIT/FINI, or confirm no dependence;
  - (d) `readelf -r` TLS relocations are general-dynamic, and GJS `dlopen` works;
  - (e) `nm -D` export set;
  - (f) `-build-mode:dll` accepted by dev-2026-05 (the string is present in the compiler binary along with `shared` and `dynamic`).
- **S2.** A gltest skeleton that creates a surfaceless llvmpipe context in the sandbox (`nix-build`) and in `nix-shell`.

Failures trigger the R1, R2 or R7 fallbacks below.

**Step 2, parallel (disjoint file sets; nobody edits another set; missing decls go in one's own files per §4.1).**

| Agent | Files (create, edit or delete) | Done when |
|---|---|---|
| **code** (sol 6.1) | `gnome/native/{effect,engine,paint,config,mutter,native_test}.odin`; `gnome/runtime/{runtime,egl,libra}.odin`, `gnome/runtime/gltest/main.odin`; `gnome/common/*`; `gnome/glib/{glib,gobject}.odin`; `gnome/CMakeLists.txt`, `gnome/default.nix`, `gnome/shell.nix`; `tests/fixtures/lookup.png` (`magick -size 2x2 xc:'rgb(128,255,255)' PNG32:tests/fixtures/lookup.png`); delete `gnome/native/waylandshader-effect.cpp` | T1–T4, T6–T8, T12–T15 pass |
| **security** (sol 6.1) | `gnome/native/boundary.odin` (exact API: `boundary_context() -> runtime.Context`, `Error :: Maybe(string)`, `text(cstring) -> (string, Error)`, `set_gerror(^^GError, string)`, `log_warning(string)`, `log_critical(string)`); `gnome/native/abi-check.c`; `gnome/glib/gio.odin`; `gnome/controller/client/*`; `gnome/tests/native-contract.js`; review gate: ban-grep §4.5, T13, ownership of `transfer full` strings | T5 (on baseline and Odin), T9, T11 pass; ban-grep clean |
| **ux** (sonnet 5.5) | `gnome/controller/ctl/*`; docs: `docs/GNOME.md` (component table rows 13–18, language paragraph :35, :74, :80, :92, :107, :202, :236–242, :300–301, :328, :339) and `README.md` GNOME lines (:27, :39, :97, :231–246, :255–257): Qt→Odin/GTK 3 wording, build recipe, new tests | T10, T11, T17 pass; docs match the shipped commands |
| **ui** (sonnet 5.5) | `gnome/controller/gui/{main,window,gtk}.odin`, `gnome/controller/gui/controller.ui` | builds; T19 checklist passes |

**Step 3, integration (builder).** `nix-build gnome/default.nix` (T15) and `nix-build default.nix` (T14), with the log recorded in `docs/waterfall/03-implementation/build-log.md`.

**Step 4, isolated sessions (builder or reviewers).** T16–T19. T20 stays the user's.

---

## 8. Risks, ranked

| # | Risk | Likelihood / impact | Mitigation | Fallback |
|---|---|---|---|---|
| R1 | Class or instance layout or vfunc offset mismatch crashes GNOME Shell | low after gates / session-fatal | §4.2 gates 1–3; the runtime guard refuses registration on a different Mutter; tests only in isolated Shells | Replace only type registration with a ~40-line `gnome/native/effect-type.c` (`G_DEFINE_TYPE`, vfuncs forward to `@(export)` Odin procs). Everything else stays Odin. |
| R2 | g-ir-scanner dumper or GJS cannot load the Odin dll (TLS model, missing `.init_array` entry, exported `main` from `entry_unix.odin:20–23`) | medium / blocks GJS | S1 checks (c)–(f) on day 1; code avoids `@(init)` and global initializers; `main` in a dlopen'd dll is shadowed by the executable's [INFERENCE] | If TLS is the cause: `-no-thread-local` with worker temp-allocator use removed (heap only off the main thread). If init is the cause: call `runtime._startup_runtime` from `get_type`'s once-block. |
| R3 | Odin panic (bounds, assertion) aborts the compositor | low / session-fatal | §4.5 ban list, Error values, allocation checks, critical log before trap; all native logic exercised by T3–T8 and T16–T18 before any real-session install | none needed beyond fixing the bug; the same class of fault crashed the C++ build |
| R4 | librashader ABI (by-value struct, bool layout, 0.10.1 ABI 2) | medium / wrong pixels or crash in isolated runs | LRH mirrors + gate-2 `sizeof`s + T8 pixel expectations | declare `frame` with an explicit pointer shim in C only if Odin's by-value lowering is wrong (T8 fails) [INFERENCE: unlikely] |
| R5 | JSON form differs from Qt (key order, numbers): rewrites users' GSettings once, CLI output differs | medium / cosmetic, plus one extra dconf write | baseline literals in T5, T6, T17 diff | adjust the writer until T5 passes; the functional contract is unchanged either way |
| R6 | GTK 3 hand bindings (variadic chooser, gboolean, signal signatures) | medium / GUI-only | builder XML keeps the FFI to about 45 calls; T19 | none needed; the controller is a separate process (docs/GNOME.md:33) |
| R7 | Mesa llvmpipe not loadable in the Nix sandbox | medium / T8 skips (77) in `nix-build` | vendor JSON env in `preCheck` | run T8 in `nix-shell` on the host (safe: own process, no compositor contact); record in build-log |
| R8 | Odin revision drift (`odin version` dev-2026-09 vs nixpkgs dev-2026-05, GATES.md:6) | low / compile differences | build only through the repo's `pkgs.odin`; no features newer than dev-2026-05 | pin `odin` via `overrideAttrs` in `gnome/default.nix` |
| R9 | GTK 3 app_id under Wayland is not the desktop id | low / wrong dash icon | `g_set_prgname` before `gtk_init`; T19 | create a `GtkApplication` with `G_APPLICATION_NON_UNIQUE` and the same id |
| R10 | Live-session safety | — | never install into `~/.local/share` or the system during development; every Shell-hosted check uses the disposable recipe; GUI checks talk to the private bus with `GSETTINGS_BACKEND=memory` | — |

---

Not checked: Mutter's C headers (no `-dev` output was available here, so layouts come from the GIR and are proven by gate 2 at build time); every `[INFERENCE]` item; no Odin code was compiled. Risk to know: whether `-build-mode:dll` loads cleanly under GJS `dlopen` (S1) is the one gate that can reshape the native plan (R2 fallback), so it runs before any porting work.
