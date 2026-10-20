# Design: Odin port of the GNOME backend

Phase 2 exit artifact (`../README.md:10`). This is Plan B (`plan-B.md`) with the amendments chosen in `decision.md` applied, and it is self-contained for the builder. Requirement and test IDs refer to `../01-requirements/requirements.md`. Imports from Plan A are tagged **[A1]…[A6]**; planner corrections are tagged **[C1]…[C5]**. Citations use the abbreviations of requirements.md. Anything unverified is marked [INFERENCE] and is turned into a spike or test gate in §9.

## 1. Decisions

| Topic | Decision |
|---|---|
| Scope | All five GNOME C++ components become Odin: native effect `.so`, shader runtime, D-Bus client, CLI and GUI. Unchanged: `extension.js`, metadata, schema, desktop file, public header `waylandshader-effect.h`, existing GJS tests, everything KWin uses (`src/`, root build, `tests/`), `shader-library.nix` and `patches/`. |
| GObject subclass | Pure Odin, registered with `g_type_register_static_simple`. Three gates: an Odin `#assert`; the compile-only `gnome/native/abi-check.c` with `_Static_assert` against real headers; and a runtime `g_type_query` guard that refuses registration on another layout. |
| GIR | The unchanged header is the scanner input, with the same scanner flags (`gnome/CMakeLists.txt:71–88`). The dumper links the Odin `.so`. |
| Exports | A linker version script `gnome/native/exports.map` exports `wayland_shader_effect_*` only **[C1]**. |
| GL | `vendor:OpenGL`, loaded once via `eglGetProcAddress`, built with `-define:GL_DEBUG=false`. No libepoxy. |
| EGL | Own foreign block in `gnome/runtime/egl.odin`, because `vendor:egl` lacks current-context, query, error and pbuffer procedures. |
| librashader | Direct link to the private `libwaylandshader-rashader.so`, with an Odin foreign block mirroring `librashader.h` 0.10.1. |
| JSON | Parsing uses `core:encoding/json` with `parse_integers=false`. Output uses a house writer that reproduces Qt 6 compact and indented output; keys are sorted by UTF-16 code unit **[A6]**. `json.marshal` is unusable because it writes floats as fixed 16-decimal numbers. |
| Worker | `core:thread` plus a GSource completion, as at E:821–831. |
| D-Bus client | GDBus through hand-written bindings, shared by the CLI and GUI. |
| GUI | GTK 3 with hand-written bindings. The layout is GtkBuilder XML embedded with `#load`. Browse uses the in-process `GtkFileChooserDialog`, matching the dialog Qt's GTK 3 theme showed. |
| Build | Keep `gnome/CMakeLists.txt` (C only) and replace the C++ targets with `odin build` custom commands. `nix-build gnome/default.nix` remains the entry point. |
| Ownership | The builder owns the build files **[A1]**. Agents never edit another agent's files. |

## 2. Verified environment (probes, 2026-10-20)

| Fact | Value |
|---|---|
| Nix package versions | `<nixpkgs>` = GLF-OS flake pkgs: mutter 50.5, gnome-shell 50.5 (the same store path as the running system), odin `dev-2026-05` (the binary reports `dev-2026-09` **[C4]**), librashader 0.10.1, gtk3 3.24.52, glib 2.88.3, kwin 6.6.6 |
| Headers | `nixpkgs#mutter.dev` exists. The probe compiled against `$(pkg-config --cflags libmutter-18 mutter-clutter-18)` inside `mkShell { buildInputs = [mutter] ++ mutter.buildInputs; }` |
| Odin store path | `/nix/store/lfmgkvmpihwnn96yy74m8dirrksrz074-odin-dev-2026-05` (`share/` holds `base core vendor`) |
| dll mode | `odin build . -build-mode:dll` gives DT_INIT/DT_FINI, general-dynamic TLS and a working `dlopen` (temp allocator used). With `-extra-linker-flags:"-Wl,--version-script=… -Wl,--no-undefined -Wl,-soname,…"`, `nm -D --defined-only` shows only the API, and INIT is kept. |
| Layouts | Listed in §5.2; all measured from real headers |
| Baseline CLI | `-h` exits 0. `-?` gives `Unknown option '?'.` and exit 2. `--help-all` gives `A command is required.` and exit 2. With no Shell on a private bus, `status` exits 3 with the install hint. The usage line prints argv0 as invoked. |

## 3. File layout

```text
gnome/
  CMakeLists.txt  default.nix  shell.nix     builder: Odin custom commands, same GIR/schema/install, CTest list in §8
  extension/  org.waylandshader.GnomeController.desktop      UNCHANGED
  native/                         package waylandshader -> libwaylandshader-gnome.so
    waylandshader-effect.h        UNCHANGED (scanner input, C API contract)
    waylandshader-effect.cpp      DELETED at cutover
    exports.map                   { global: wayland_shader_effect_*; local: *; };
    abi-check.c                   compile-only C ABI gate (never linked or shipped)
    effect.odin                   GType, class/instance mirrors, vfuncs, 14 exports + get_type
    boundary.odin                 C-entry context, Error, GError mapping, UTF-8 text(), logging
    engine.odin                   Engine/Output/Load_Job, lifecycle, mapping, scheduling, mutators
    paint.odin                    Resources/Surface, color pipelines, before-paint, paint, frame_timing, select_output
    config.odin                   status/settings writers, import/outputs parsers, recents
    mutter.odin                   Clutter/Cogl/Meta/Mtk/graphene foreign decls + mirrors
    native_test.odin              frame_timing, select_output, engine_check, GLSL golden, formatters, zero-alloc
  runtime/                        package shader_runtime
    runtime.odin  egl.odin  libra.odin
    gltest/main.odin              real-GL regression (port of tests/shader_runtime_test.cpp)
  common/                         package common
    json.odin  json_test.odin  output_settings.odin
  glib/                           package glib: glib.odin gobject.odin gio.odin
  controller/
    client/  client.odin status.odin client_test.odin
    ctl/     main.odin args.odin args_test.odin                 -> waylandshader-gnomectl
    gui/     main.odin window.odin gtk.odin controller.ui view.odin view_test.odin -> waylandshader-gnome-controller
  tests/
    effect-lifecycle.js recent-presets.js parameter-bypass.js    UNCHANGED
    native-contract.js  hang-shell.js
    cli-golden.sh  iso-cli.sh  isolated-session.sh  elf-check.sh  ban-check.sh
    golden/exports.txt  golden/snippet-decl.glsl  golden/snippet-body.glsl  golden/cli/*
```

Packages import each other with relative paths (`import "../common"`), so no `-collection` flags are needed. No file is added under the shared `tests/` tree **[A3]**.

Files that stay in another language, and why:

| File | Language | Reason |
|---|---|---|
| `gnome/extension/extension.js` | GJS | Shell extensions are GJS modules. The extension owns the D-Bus export, GSettings persistence, unredirect and lifecycle (XJS:10–230). |
| `gnome/native/waylandshader-effect.h` | C | g-ir-scanner parses C headers. This file is also the `WaylandShader-1.0` ABI contract. |
| `gnome/native/abi-check.c` | C | Compile-only proof that the Odin mirrors match the headers. |
| `gnome/tests/*.js` | GJS | They drive the typelib exactly as the extension does. |
| `gnome/tests/*.sh` | sh | Test orchestration only; none of them is installed. |

## 4. Components

Errors are values, not exceptions (§5.6). Messages and their ordering are copied verbatim from the cited C++ source.

### 4.1 Native effect (`gnome/native`)

**Data layout:**

```odin
Output_View :: struct { view: ^Stage_View, expanded_frame: i64 }   // hot: scanned every before-paint/paint [A5]
#assert(size_of(Output_View) == 16)
Frame_Clock :: struct { previous_time, first_frame: i64, clear_history: bool }  // hot, the selected output only
#assert(size_of(Frame_Clock) == 24)
Output :: struct {                  // heap-allocated: signal handlers keep ^Output (E:646, E:703)
    engine: ^Engine, key: uintptr,
    timeline: ^Timeline, destroy_handler: c.ulong,
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
    outputs: [dynamic]^Output, views: [dynamic]Output_View,      // index-aligned; rebuilt only in map_outputs/set_outputs
    saved_outputs: map[string]common.Output_Settings, overrides: map[string]map[string]f64,
    preset, requested, error, pending, last_status: string, recent: [dynamic]string,
    display: egl.Display, ctx: egl.Context, draw, read: egl.Surface,
    generation: u64, next_key: uintptr,
    enabled, stopped, cursor_inhibited, mapping_dirty, loading, renderer_failed: bool,
}
Load_Job :: struct { path, error: string, overrides: map[string]f64, keys: []uintptr, generation: u64, result: ^shader_runtime.Runtime }
```

Strings and maps use the heap allocator. `set_str(&field, value)` frees the old value and clones the new one. Maps are used only for cold lookups, and the writers sort keys when they emit.

**Feature map:**

| Original feature (source) | Odin home |
|---|---|
| Final `ClutterEffect` type (EH:14, E:499–504) | `effect.odin` `wayland_shader_effect_get_type` (§5.3) |
| `status-changed`, RUN_LAST, one string (E:1317) | `class_init` → `g_signal_newv` (G_TYPE_STRING 64, G_TYPE_NONE 4, RUN_LAST 2) |
| dispose→shutdown; finalize frees the engine; `set_actor` chains the parent then attaches; paint vfunc catch-all → `renderer_failed` (E:1244–1301) | `effect.odin` vfuncs. The parent class comes from `g_type_class_peek_parent`. |
| `new()` returns NULL without an engine, plus `ref_sink` (E:1321–1340) | `wayland_shader_effect_new`, which also returns NULL when the guard refused registration |
| `get_status` with the fixed fallback literal (E:1342–1349) | `effect.odin`, with the literal copied verbatim |
| `export_settings`, NULL on failure (E:1352–1375) | `config.odin` writer |
| `import_settings` validation order, messages, recents filter, canonical restore (E:1377–1452) | `config.odin` parses, `engine.odin` applies. `realpath` stands in for `canonicalFilePath`; the given absolute string stands in for `absoluteFilePath`. |
| `set_outputs` validation, unchanged no-op, reset+remap (E:1454–1499) | `config.odin` `parse_outputs` + `engine.odin` |
| `load_preset`, `set_enabled`, `set_parameter` (live and bypassed), per-output setters, `reset_history`, `shutdown` (E:1501–1621) | `engine.odin` mutators. One `mutate` helper maps an Error to a GError. |
| Owner-thread and `stopped` checks (E:451–455) | `engine_check` |
| shader/color/active predicates (E:456–470) | `engine.odin`, same boolean expressions |
| Idle-deferred, change-only status emission with self ref/unref (E:546–571) | `notify` + `status_idle` |
| `queue_work` idle → sync_activity + start_load (E:588–613) | `engine.odin` |
| Cursor inhibit; frame-clock timeline per shader output (E:630–662, E:771–774) | `sync_activity`. The `new-frame` callback takes `^Output`. |
| Output mapping, bypass reasons, view `destroy` handler (E:664–730) | `map_outputs`, messages verbatim. Rebuilds `views` in the same order as `outputs`. |
| Host context capture, GLES rejection, sRGB state (E:732–755) | `capture_context`. The first capture also calls `shader_runtime.ensure_gl_loaded()`. |
| Backend discovery from the renderer view's CRTC (E:757–775) | `discover` |
| request, start_load, complete_load, reset (E:777–922) | `engine.odin` with the `core:thread` worker; same generation, retire and retry rules |
| shutdown, attach, `gl-video-memory-purged` (E:933–1038) | `engine.odin` |
| Redraw: full clip plus schedule plus stage redraw (E:573–586) | `redraw` |
| `Resources`/`Surface` FP16 allocation, pipelines, snippet GLSL verbatim, uniform cache (E:197–338) | `paint.odin`. The GLSL is copied byte-for-byte from E:320–330, and `native_test` compares it with `golden/snippet-*.glsl`. |
| `copyShaderSource`: mip chain, blit, `MAX_LEVEL=0` after the blit (E:339–380) | `paint.odin`, saving and restoring GL bindings with `defer` |
| Paint: capture, target→sRGB, FPS/warm-up, shader, final pass, present, failure restore (E:1050–1209) | `engine_paint` (outer errors) → `paint_output` (inner errors → `output.failure`). Timing is in the pure `frame_timing`. |
| before-paint: discover, full-view clip, `expanded_frame` (E:988–1016) | `paint.odin`, writing `views[i].expanded_frame` |

**Two-level paint errors.** `paint_output` returns an `Error`. `engine_paint` handles it locally: it blits the raw scene back when `captured && wrote_target`, sets `failure`, calls `fail()` and continues the scene. Errors raised before the inner block (e.g. `capture_context`, E:1071) reach the vfunc, which sets `renderer_failed`, bumps the generation and continues the scene once (`continued` flag, E:1268–1271).

**Pure hot procedures:**

```odin
frame_timing  :: proc(c: ^Frame_Clock, count, now: i64, refresh: f32) -> (render: bool, fps: f32, elapsed_ms: u32, number: u64) // E:1122-1160
select_output :: proc(views: []Output_View, view: ^Stage_View, frame: i64) -> int   // -1 if none; E:1079-1083
```

`paint_output` sets `previous_time = now` and `clear_history = false` only after a successful render (E:1159–1160).

### 4.2 Shader runtime (`gnome/runtime`)

```odin
Parameter :: struct { name, description: string, minimum, maximum, step, default_value, value: f64 }
Frame :: struct { number: u64, source, destination, format: u32, width, height: i32, fps: f32, elapsed_ms: u32, clear_history: bool }
#assert(size_of(Frame) == 40)
Runtime :: struct {
    display: egl.Display, ctx, host: egl.Context, surface: egl.Surface, surfaceless: bool,
    max_texture_size: i32,
    keys: []uintptr, chains: []libra.Gl_Filter_Chain,   // parallel: render scans keys, touches one chain
    parameters: []Parameter, names: []cstring,          // names cloned once at load (R:395-398)
}
load          :: proc(display: egl.Display, share: egl.Context, path: string, keys: []uintptr, overrides: map[string]f64) -> (^Runtime, string)
render        :: proc(rt: ^Runtime, key: uintptr, f: ^Frame) -> Error   // hot; zero Odin allocations on success
set_parameter :: proc(rt: ^Runtime, name: string, value: f64) -> Error
destroy       :: proc(rt: ^Runtime)                                       // R:182-209; leak+log if the context cannot be entered
validate_value :: proc(p: ^Parameter, candidate: f64) -> Error           // R:153-164; f32 cast; "%.9g" text
ensure_gl_loaded :: proc()                                                // gl.load_up_to(4, 6, …eglGetProcAddress), main thread, once
```

| Original feature | Odin home |
|---|---|
| `CurrentContext` save/enter/restore with API, and its error texts (R:54–123) | `egl.odin` `Current_Context` + `defer restore` |
| Context creation: GLES rejection, surfaceless or pbuffer, 4.6/4.5/3.3 × normal/robust, share with host (R:211–292) | `runtime.odin` `create_context`. `epoxy_egl_version` becomes a parse of `eglQueryString(EGL_VERSION)`; `epoxy_has_egl_extension` becomes a token search in `EGL_EXTENSIONS`. |
| GL ≥3.3 plus `ARB_texture_storage` or 4.2; `GL_MAX_TEXTURE_SIZE` (R:341–346) | `glGetIntegerv(MAJOR/MINOR_VERSION)` plus a `glGetStringi` extension scan |
| Preset and chain options (R:348–357) | `libra.odin` structs with `#assert` |
| Per-output load, metadata validation, union (last pass wins), sort, override check, get/set param, cross-chain agreement, validation chain freed with no outputs (R:359–453) | `load`, messages verbatim |
| `setParameter` preflight, set, rollback (R:466–505) | `set_parameter` |
| render: frame validation, host-context check, incoming fence, private context, `libra_gl_filter_chain_frame` with the fixed MVP, outgoing fence, restore, GPU wait (R:507–592) | `render` |
| Error text from `libra_error_write` or `librashader failed (error N)` (R:29–43); EGL `"%s failed (EGL error 0x%04x)"` (R:22–27) | `libra.odin` `check`, `egl.odin` `egl_error` |

### 4.3 Common (`gnome/common`)

- **`output_settings.odin`** ports OS:5–19: `Output_Settings{gamma, saturation: f64, shader_enabled, color_enabled: bool}` with `#assert(size_of == 24)`, `MIN_GAMMA 0.1`, `MAX_GAMMA 5`, `MIN_SATURATION 0`, `MAX_SATURATION 2` and `adjusts_color`.
- **`json.odin`** reproduces Qt 6 `QJsonDocument` output byte-for-byte:
  - **Keys:** object keys are sorted by UTF-16 code unit, as `QJsonObject` sorts [INFERENCE; pinned by T-CONTRACT with a non-ASCII key] **[A6]**. The native writers emit fixed literal key sequences: status `active, enabled, error, loading, outputs, parameters, preset, recentPresets, requestedPreset`; parameter row `default, description, maximum, minimum, name, step, value`; output row `bypass?, colorActive, colorEnabled, gamma, id, name, saturation, shaderActive, shaderEnabled`; settings `enabled, outputs, parameters, preset, recent_presets, version`.
  - **Numbers:** a value that is integral and fits `i64` exactly is written as an integer. Anything else uses shortest `'g'` with a C-style exponent (`1e-07`). Non-finite values are written as `null` [INFERENCE about Qt; pinned by T-CONTRACT and T-UNIT-COMMON].
  - **Strings:** escape `"`, `\`, `\b\f\n\r\t`, and other characters below 0x20 as `\u00XX`. UTF-8 passes through.
  - **`write_value(b, json.Value, indent)`** gives Qt `Indented` output: 4 spaces, `"k": v`, an empty array as `[\n<indent>]`, and a trailing newline. The CLI reprints status with it (CTL:160–162, :199–200).

### 4.4 D-Bus client (`gnome/controller/client`): API frozen before Step 2

```odin
SERVICE :: "org.gnome.Shell"; EFFECT_PATH :: "/WaylandShader"; EFFECT_INTERFACE :: "org.waylandshader.Effect"
ACTIVATION_PATH :: "/org/gnome/Shell"; ACTIVATION_INTERFACE :: "org.gnome.Shell.Extensions"; UUID :: "waylandshader@man33li.github.com"
COMPOSITOR, DESKTOP_ENVIRONMENT, EFFECT_DESCRIPTION, INSTALLATION_HINT, ACTIVATION_HINT :: … // verbatim src/controller_backend.h:12-27 (GNOME branch)
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
close :: proc(c: ^Client)                      // unsubscribe; pending callbacks become no-ops
ensure_available :: proc(c: ^Client, allow_activation: bool, r: Reply)
request_status :: proc(c: ^Client, r: Reply)
load_preset / set_enabled / set_parameter / set_output_shader_enabled / set_output_color_enabled /
set_output_gamma / set_output_saturation :: proc(c: ^Client, …, r: Reply)
accept_json :: proc(c: ^Client, json: string) -> Error          // pure: CC:229-354
classify    :: proc(remote_name, message: string, local: bool) -> Error  // pure: CC:21-35
```

| Original feature | Odin home |
|---|---|
| Subscriptions to `statusChanged`, `ExtensionStateChanged` and owner change (CC:62–87) | `g_dbus_connection_signal_subscribe` ×3. The owner change watches `NameOwnerChanged` with arg0=`org.gnome.Shell`, keeping the "old owner non-empty and changed" rule. |
| Async call, 10 000 ms timeout, interface-generation guard (CC:89–115) | `g_dbus_connection_call(…, timeout=10000)`. A per-call heap `Pending{client, path, generation, reply}` is freed in its callback. |
| Error classification (CC:21–43) | `g_dbus_error_get_remote_error` + `strip_remote_error`. The four `org.freedesktop.DBus.Error.{ServiceUnknown,UnknownObject,UnknownMethod,UnknownInterface}` names → Unavailable; `org.waylandshader.Error.*` → Rejected (keeps CS O1); everything else → Transport. |
| Boolean reply check (CC:45–58) | `g_variant_is_of_type(v, "(b)")`. A false value → Rejected. |
| `ensure_available` activation chain, 10 s, states 1/2/6/8 (CC:117–215) | Heap `Activation{done, timer_id}`. A numeric `state` is accepted as `d`/`u`/`i` and converted like `QVariant::toUInt`. |
| Status validation, every branch and message (CC:229–354) | `status.odin` `accept_json`. It validates the whole candidate first, then replaces the status and keeps the parsed object for the CLI. |

### 4.5 CLI `waylandshader-gnomectl` (`gnome/controller/ctl`)

- `args.odin` is a pure `parse(args) -> (Command, usage_error: string, exit: int)`. It accepts exactly the baseline's options **[C2]**: `-h`, `--help`, `--help-all` (known and ignored, as in Qt's `addHelpOption`), `--timeout N`, `--timeout=N`, `--`, and options interleaved with positionals. **There is no `-?`**; it produces `Unknown option '?'.` and exit 2. Every validation and message of CTL:58–140 is reproduced. Numbers are trimmed and then parsed with `strconv.parse_f64`/`parse_int` [INFERENCE: equivalent to `QString::toDouble`/`toInt`; pinned by T-CLI-GOLDEN and T-UNIT-CTL].
- The help text is the CTL:23–49 description with `%1..%6` substituted, inside Qt's `Usage: <argv0> [options] command [arguments…]` / `Options:` / `Arguments:` frame. The `Options:` block lists `-h, --help`, `--help-all` and `--timeout <seconds>` with Qt's column layout and wrapping. The baseline golden is the authority.
- `main.odin` runs a `GMainLoop` state machine over `client`, mirroring CTL:142–287. The overall deadline `g_timeout_add(timeout*1000)` is armed before the availability check and exits 4. Rejected exits 1, usage 2, everything else 3. On the `load` path, `load_accepted` is set and the status is requested again, then the CTL:163–180 rules apply. The monitor selector tries the exact id, then a unique exact name; an ambiguous name exits 2 (CTL:249–271).

### 4.6 GUI `waylandshader-gnome-controller` (`gnome/controller/gui`)

- **`controller.ui`** (GtkBuilder, GTK 3) holds the whole static layout of GUI:67–165:
  - the title `WaylandShader — GNOME Shell Desktop Effects`, default size 740×620, and the intro label;
  - the preset row: an entry with placeholder and accessible name, Browse…, a Recent ▾ GtkMenuButton with tooltip and accessible name, and Load preset;
  - the enable checkbox and Reconnect / refresh;
  - the monitor row: a GtkComboBoxText with a mnemonic label, plus the state label;
  - two toggles, and the Gamma and Saturation spin buttons (digits 2, step 0.05, ranges from `common`, tooltips verbatim);
  - selectable, word-wrapped summary and error labels, a scrolled GtkGrid for parameters, and the note label.
  
  Accessible names are set through `<child internal-child="accessible">` and buddies through `mnemonic-widget`.
- **`view.odin`** (ux) holds the pure functions; it uses no GTK:
  - `state_label(output, saving, pending) -> string` (GUI:294–301);
  - `summary_text(status) -> string` (GUI:535–547);
  - `load_error(path) -> string` (GUI:398–413);
  - `round2(f64) -> f64`;
  - `parameter_step(p) -> f64`, which returns `step`, or span/100, or 1;
  - `format_f32(f64) -> string` (shortest round-trip f32);
  - `parse_f32(string) -> (f32, bool)`;
  - `parameter_tooltip(p) -> string`, `parameter_label(p) -> string`.
- **`window.odin`** (ui) ports the `SettingsWindow` state machine (GUI:221–589) with the same fields. `available`, `loading`, `load_pending`, `enable_pending`, `path_edited`, `updating_outputs`, `output_pending` and the pending/selected ids are plain fields of `App`. `QSignalBlocker` becomes a `programmatic` counter that every handler checks.
- **Gamma and saturation** are `GtkSpinButton`s that commit on activate or focus-out, GTK's default. The `input` handler parses the text, applies `view.round2` and returns that value, so the committed value equals what `QDoubleSpinBox` with 2 decimals would send **[C3]**.
- **Parameter editors** are `GtkSpinButton`s:
  - The `output` handler prints `view.format_f32(value)`.
  - The `input` handler parses with `view.parse_f32`. On failure it returns `GTK_INPUT_ERROR`. On success it calls `gtk_adjustment_set_value(adj, f64(value))` before returning `TRUE` with `*new_value = value`. This bypasses GTK's 1e-10 EPSILON, so typed values commit exactly **[A4]**.
  - GTK clamps values to the range.
  - A `// shortcut: GTK 3 ignores stepping increments ≤ 1e-10 (gtkspinbutton.c:1887); replace with an entry+buttons editor if such parameters must step` comment marks deviation D2.
- **Debounce.** Each parameter editor has its own 100 ms debounce via `g_timeout_add(100)`. A `revision` counter and a dirty flag match GUI:464–486. A rebuild increments the editor `epoch` and removes all timers. A reply with a stale epoch returns without touching the editors (GUI:477–479).
- **Browse** is a modal `gtk_file_chooser_dialog_new("Choose shader preset", …)` run with `gtk_dialog_run`, the same modality as `QFileDialog::getOpenFileName`. It has a filter named `RetroArch slang presets (*.slangp)` with pattern `*.slangp`, and its initial file or folder comes from the entry. A chosen file fills the entry and sets `path_edited`; it never loads.
- **Recent** is a `GtkMenu` of `gtk_menu_item_new_with_label(path)` items. These labels are not parsed for mnemonics. Choosing an item fills the entry and focuses it but never loads. The menu is disabled when empty.
- **Monitor combo:** `gtk_combo_box_text_append(id, name)`. With zero outputs it holds one insensitive item, `No connected monitors`. The combo tooltip is the selected id (GUI:273). Per-item popup tooltips are not reproduced (deviation D1).
- **App identity:** `g_set_prgname("org.waylandshader.GnomeController")` before `gtk_init` [INFERENCE: GTK 3 on Wayland uses prgname as the app_id when there is no GApplication; checked in T-GUI]. There is no GApplication, so there is no single-instance behavior, which the Qt app never had either.
- **Closing** cancels local client and chooser work and destroys the widgets. It never disables the effect.

### 4.7 Qt replacements

| Qt | Odin |
|---|---|
| `QString`, `QByteArray`, `QStringList` | `string`, `[]u8`, `[dynamic]string` (recents: remove, prepend, truncate to 10, E:866–868) |
| `QMap`, `QSet` | `map[K]V` with sorted emission; linear duplicate checks (n is small) |
| `QJson*` | `core:encoding/json` for parsing, the `common` writer for output |
| `QFileInfo` | `core:sys/posix` `stat`/`access(R_OK)`/`realpath`. Absolute means a leading `/`. The NUL check is `strings.contains_rune(path, 0)` (R:314). |
| `qWarning`, `g_warning` | `g_log(nil, LEVEL, "%s", msg)`; the C++ compiled without `G_LOG_DOMAIN` |
| `.arg` formatting | `fmt.tprintf` on the temp allocator, cold paths only |

## 5. FFI and ABI

### 5.1 Binding rules

- **Hand-written foreign blocks only:** `glib/{glib,gobject,gio}.odin`; `native/mutter.odin` (about 70 procs taken from E's call sites); `runtime/egl.odin`; `runtime/libra.odin` (14 procs); `gui/gtk.odin` (about 45 GTK 3 procs). `vendor:OpenGL` provides GL, and `vendor:stb/image` `write_png` is used by gltest only.
- **Linking:** libraries are linked by name (`foreign import x "system:mutter-clutter-18"`); `-L` and `-Wl,-rpath` come from pkg-config (§7). The private Mutter symbols (E:31–50) are declared exactly as the C++ declared them. `-Wl,--no-undefined` is kept.
- **No macros as logic.** `G_OBJECT_TYPE` and `*_IS_*` become `g_type_check_instance_is_a`; `g_signal_connect` becomes `g_signal_connect_data`; `g_object_new` becomes `g_object_new_with_properties(type, 0, nil, nil)`.
- **Variadics** use `#c_vararg` only where unavoidable: `g_signal_emit`, `g_log`, `g_variant_new`, `g_object_get` (the sRGB state's `context`, E:301), `gtk_file_chooser_dialog_new`. `gboolean` is `b32` and doubles are `f64`.
- **Strings returned as `transfer full`** (`get_status`, `export_settings`) are `g_strndup` copies. Odin-allocated memory is never returned to C.
- **Missing declarations** go in the file the agent owns, with its own `foreign import`.

### 5.2 Layouts (x86_64, measured from mutter-50.5-dev, glib 2.88.3 and librashader 0.10.1 headers)

```odin
GObject_Class :: struct {
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
    paint: proc "c" (effect: ^Effect, node: rawptr, pc: ^Paint_Context, flags: u32),  // ClutterPaintFlag is 4 bytes
    paint_node, pick: rawptr }
Effect :: struct { parent_instance: [3]rawptr /* ClutterEffect, 24 B */, engine: ^Engine }
#assert(size_of(GObject_Class) == 136 && offset_of(GObject_Class, dispose) == 40 && offset_of(GObject_Class, finalize) == 48)
#assert(size_of(Actor_Meta_Class) == 152 && offset_of(Actor_Meta_Class, set_actor) == 136)
#assert(size_of(Effect_Class) == 200 && offset_of(Effect_Class, paint) == 176)
#assert(size_of(Effect) == 32 && offset_of(Effect, engine) == 24)
```

`abi-check.c` asserts these numbers against the real headers.

| Group | Asserted values |
|---|---|
| GObject classes | `sizeof(GObjectClass)==136`, dispose 40, finalize 48; `sizeof(ClutterActorMetaClass)==152`, set_actor 136; `sizeof(ClutterEffectClass)==200`, paint 176; `sizeof(ClutterEffect)==24` |
| GLib records | `sizeof(GTypeQuery)==24`, `sizeof(GError)==16` |
| Clutter, Mtk, graphene | `sizeof(ClutterLuminance)==20` (ref 12, mastering_max 16); `sizeof(MtkRectangle)==16`; `sizeof(graphene_matrix_t)==64`, `_Alignof==16`; `sizeof(ClutterPaintFlag)==4` |
| Enums | `COGL_PIXEL_FORMAT_RGBA_FP_16161616_PRE==155`, `COGL_SNIPPET_HOOK_TEXTURE_LOOKUP==6145`, `CLUTTER_EFFECT_PAINT_BYPASS_EFFECT==2`, `COGL_PIPELINE_FILTER_NEAREST==9728`, `COGL_PIPELINE_WRAP_MODE_CLAMP_TO_EDGE==33071`, `G_SIGNAL_RUN_LAST==2`, `G_TYPE_STRING==64`, `G_TYPE_NONE==4` |
| librashader records | `libra_image_gl_t` 16, `frame_gl_opt_t` 40, `filter_chain_gl_opt_t` 16, `libra_preset_opt_t` 16, `libra_preset_param_t` 32, `libra_preset_param_list_t` 16, `libra_viewport_t` 16, `libra_preset_ctx_t` 8 |
| Other | every EGL constant used in `egl.odin`; `CLUTTER_COLORSPACE_SRGB==0` and `CLUTTER_TRANSFER_FUNCTION_SRGB_PIECEWISE==0` (values read from the Clutter GIR by Plan B, confirmed at compile time) |

The file is built as CMake `OBJECT` library `gnome_abi_check` in `ALL`, with `$(pkg-config --cflags libmutter-18 egl)` and the librashader include directory. The ClutterPaintFlag forward-declaration workaround (`gnome/CMakeLists.txt:39–57`) is removed, because plain C accepts that header.

### 5.3 Registration and the runtime guard

```odin
@(export, link_name="wayland_shader_effect_get_type")
wayland_shader_effect_get_type :: proc "c" () -> GType {
    if g_once_init_enter(&type_id) {
        context = boundary_context()
        t: GType = 0
        if parent_layout_ok() { // g_type_query(clutter_effect_get_type()): class_size==200 && instance_size==24, else g_critical
            t = g_type_register_static_simple(clutter_effect_get_type(), "WaylandShaderEffect",
                size_of(Effect_Class), class_init, size_of(Effect), instance_init, 0)
        }
        g_once_init_leave(&type_id, t)
    }
    return type_id
}
```

- **`class_init`** saves `parent_class = g_type_class_peek_parent(klass)` and writes `dispose`, `finalize`, `set_actor` and `paint`. It creates the signal with `g_signal_newv("status-changed", t, RUN_LAST, nil, nil, nil, nil, G_TYPE_NONE, 1, &[G_TYPE_STRING])`.
- **`instance_init`** allocates the Engine, capturing `g_thread_self()` and `g_main_context_ref_thread_default()` (E:420–421).
- **Initialization:** nothing relies on `@(init)` or on global initializers; globals are zero-initialized `.bss`.
- **Guard behavior:** on a mismatch, `new()` returns NULL and `enable()` throws into `_cleanup()` (XJS:41–42, :67–70). The scanner's dumper runs the same guard.

### 5.4 librashader mirrors

`libra.odin` mirrors `librashader.h` 0.10.1 (lines 189–318), with C `bool` as Odin `bool`. `libra_gl_filter_chain_frame` takes `libra_image_gl_t` (16 B, `{u32×4}`) **by value**, and the `"c"` convention must pass it in two integer registers [INFERENCE; Spike S2 checks this with a pixel result]. The loader argument is `egl.GetProcAddress` (`proc "c" (cstring) -> rawptr`).

### 5.5 EGL, GL, fences and the worker

- **GL loading.** `ensure_gl_loaded` runs `gl.load_up_to(4, 6, set_proc)` once, on the main thread, at the first `capture_context`. That precedes any worker, because `start_load` requires a captured context (E:796–797). The pointers are libglvnd dispatch stubs valid for any current context [INFERENCE; T-GL loads on a worker and renders on the main thread].
- **GL_DEBUG.** The build always uses `-define:GL_DEBUG=false`, so the debug wrappers never consume the `glGetError` results read at E:377, :1045 and :1189.
- **Context and bindings.** `Host_Context` (E:131–165) and `Current_Context` (R:56–123) are structs with `enter`/`restore` plus `defer`. `GLBindings` (E:168–195) becomes `save_bindings`/`restore_bindings` with `defer`.
- **Fences.** `gl.FenceSync`, `gl.Flush`, `gl.WaitSync(…, gl.TIMEOUT_IGNORED)` and `gl.DeleteSync`, exactly as at R:531–548 and R:576–590. Waits are GPU-side only.
- **Worker.**
  - `start_load` clones the path, overrides and keys into a `Load_Job`, creates the idle `completion` source, then calls `thread.create_and_start_with_poly_data2(job, completion, compile_proc)` (`core/thread/thread.odin:393`).
  - The worker calls `shader_runtime.load(display, ctx, …)`, stores the result or a heap error in the job, unbinds its context, then calls `g_source_attach(completion, main_ctx)`. It never touches the Engine.
  - `complete_load` runs `thread.join` + `thread.destroy` before reading the job.
  - A runtime is destroyed only on the owner thread, inside `Host_Context` (E:853, :900, :959).
  - `shutdown` sets `stopped`, joins the worker and only then destroys the completion source and the Engine.

### 5.6 Error boundary: no panics across C

- **Entry points.** Every C entry is `proc "c"`: the 14 exports, `get_type`, class and instance init, 4 vfuncs, the signal callbacks, the idle callbacks, the worker body, and all GDBus and GTK callbacks. Each one starts with `context = boundary_context()` and `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()`. The guard nests safely when a JS `status-changed` handler re-enters `get_status`.
- **`boundary_context()`** is `runtime.default_context()` with `assertion_failure_proc` replaced by one that logs `g_log(CRITICAL)` and then traps. Bounds checks stay **on**.
- **Error values.** `Error :: Maybe(string)`. Messages are static or `fmt.tprintf` on the temp allocator. Anything persisted (`engine.error`, `output.failure`, `job.error`) is cloned to the heap before the guard ends.
- **Banned constructs.** `panic`, `assert`, `unreachable`, `#no_bounds_check` and `or_panic` are banned in the non-test code of native/runtime/common/glib (checked by `ban-check.sh`). Allocation errors from `new`/`make`/`append` are checked and become `"Out of memory"`.
- **GError mapping.** `mutate` maps an Error to `g_set_error_literal(err, g_quark_from_static_string("wayland-shader-error"), 1, msg)` and returns false (E:1218–1230). `text()` rejects NULL or invalid UTF-8 with `Invalid UTF-8 argument` (E:74–78).
- **Controller binaries** are ordinary executables, and use the same Error-value style.

## 6. Hot paths (DOD)

Load assumption (no load line exists in the repo): **zero Odin heap or temp allocations per view per frame, with at most 16 outputs.**

- **Hot procedures:** `before_paint` (loop over `views`), the paint vfunc → `select_output` → `engine_paint` → `paint_output`, the timeline `new-frame` callback, `frame_timing`, and `shader_runtime.render`.
- **Success path:** no `fmt`, no `map` access, no string building. `select_output` scans the contiguous 16-byte `views` and dereferences only the chosen `^Output` **[A5]**. The runtime scans `keys` and touches one chain. There is no SoA beyond that, because 16 items do not justify it (`skills/dod/SKILL.md:52`).
- **Layout locks:** `Output_View` 16, `Frame_Clock` 24, `Output_Settings` 24, `runtime.Frame` 40, plus the librashader `#assert`s (§5.2).
- **Zero-allocation tests** use `mem.Tracking_Allocator` as both `context.allocator` and `context.temp_allocator`. After one warm-up call, `total_allocation_count` must not change over 100 `frame_timing` calls and 100 `select_output` calls (T-UNIT-NATIVE), and over 100 `render` calls on llvmpipe (T-GL). Driver, Cogl and librashader allocations are not measured.

## 7. Build and packaging

**`gnome/CMakeLists.txt`** (builder). Core shape:

```cmake
project(WaylandShaderGNOME VERSION 0.1.0 LANGUAGES C)
find_program(ODIN odin REQUIRED)
pkg_check_modules(MUTTER REQUIRED IMPORTED_TARGET libmutter-18)     # + existing 50.x guard (lines 17-19)
pkg_check_modules(NATIVE_LIBS REQUIRED libmutter-18 mutter-clutter-18 mutter-cogl-18 mutter-mtk-18 graphene-gobject-1.0 egl gio-2.0)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)
find_path(LIBRASHADER_INCLUDE_DIR librashader.h PATH_SUFFIXES librashader REQUIRED)
find_library(LIBRASHADER_LIBRARY waylandshader-rashader REQUIRED)
set(ODIN_FLAGS -o:speed -vet -strict-style -define:GL_DEBUG=false)
# -L and a matching -Wl,-rpath for every NATIVE_LIBS_LIBRARY_DIRS entry and the librashader directory
set(NATIVE_LDFLAGS "-Wl,--no-undefined -Wl,-soname,libwaylandshader-gnome.so -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/native/exports.map ${NATIVE_L} ${NATIVE_RPATH}")
add_library(gnome_abi_check OBJECT native/abi-check.c)
target_link_libraries(gnome_abi_check PRIVATE PkgConfig::MUTTER)
target_include_directories(gnome_abi_check PRIVATE ${LIBRASHADER_INCLUDE_DIR})
file(GLOB NATIVE_ODIN_SOURCES CONFIGURE_DEPENDS native/*.odin runtime/*.odin common/*.odin glib/*.odin)
add_custom_command(OUTPUT libwaylandshader-gnome.so
    COMMAND ${ODIN} build ${CMAKE_CURRENT_SOURCE_DIR}/native -build-mode:dll
            -out:${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so ${ODIN_FLAGS}
            "-extra-linker-flags:${NATIVE_LDFLAGS}"
    DEPENDS ${NATIVE_ODIN_SOURCES} native/exports.map VERBATIM)
add_custom_target(gnome_native ALL DEPENDS libwaylandshader-gnome.so)
# GIR/typelib: lines 69-94 unchanged except library path = ${CMAKE_CURRENT_BINARY_DIR}; DEPENDS gnome_native + header
# ctl, gui and runtime/gltest: same pattern without -build-mode:dll; each lists its full recursive Odin sources
# install: install(FILES libwaylandshader-gnome.so …/native), install(PROGRAMS the two binaries); the rest = lines 125-143
```

- **GIR.** The scanner invocation is unchanged (`gnome/CMakeLists.txt:71–88`), including `--fallback-library-path=` when it is advertised. The dumper calls the Odin `get_type`, which runs the guard and `class_init`. The output keeps `shared-library="libwaylandshader-gnome.so"`.
- **Odin tests.** `odin test <pkg> -define:GL_DEBUG=false -define:ODIN_TEST_THREADS=1 "-extra-linker-flags:<that package's libs>"` for `common`, `native`, `controller/client`, `controller/ctl` and `controller/gui`.
- **CTest list.** The builder registers the CTest entries of §8.

**`gnome/default.nix`.** Everything stays except the following, including the Mutter 50 assert (lines 6–7), the source filter, `sourceRoot`, `passthru` and `meta`:

```nix
nativeBuildInputs = with pkgs; [ cmake ninja pkg-config gobject-introspection glib gjs odin wrapGAppsHook3 ];
buildInputs = with pkgs; [ mutter gtk3 expat isocodes lerc libdeflate libevdev libwebp xz libGL shaderLibrary ]
              ++ pkgs.mutter.buildInputs;            # removed: kdePackages.qtbase, qtwayland, libepoxy
nativeCheckInputs = with pkgs; [ dbus mesa ];        # dbus-run-session for gnome_cli_golden; llvmpipe for gltest
preCheck = ''
  export HOME=$TMPDIR __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json LIBGL_ALWAYS_SOFTWARE=1
'';
# removed: kdePackages.wrapQtAppsHook, dontWrapGApps, the preFixup qtWrapperArgs merge (lines 56-61).
# wrapGAppsHook3 now wraps both binaries directly (still .<name>-wrapped, so T-LAYOUT holds).
```

**`gnome/shell.nix`:** drop `clang-tools` and `kdePackages.qttools`; keep `gnome-shell`, `gjs` and `pipewire`. Odin comes in through `inputsFrom`.

**Docs** (ux): `README.md` GNOME lines (27, 39, 97, 231–246, 255–257) and `docs/GNOME.md` (component table, language paragraph at 35, and lines 74, 80, 92, 107, 202, 236–242, 300–301, 328 and 339). Change the Qt wording to Odin/GTK 3, update the build recipe to the requirements.md catalog commands, and add the new tests. Record the cutover in the existing history table, with no new changelog.

## 8. Test implementation

Exact commands and pass criteria are in the requirements.md catalog. This section specifies the test files.

| CTest name | Command registered by the builder | Owner of the test code |
|---|---|---|
| `gnome_effect_lifecycle`, `gnome_recent_presets` | unchanged (`gnome/CMakeLists.txt:100–111`); library dir = binary dir | n/a |
| `gnome_native_contract` | `env GI_TYPELIB_PATH=<mutter-18 gir dir> gjs -m tests/native-contract.js <binary dir>`, TIMEOUT 10 | security |
| `gnome_common_units`, `gnome_native_units`, `gnome_client_units`, `gnome_ctl_units`, `gnome_gui_units` | `odin test <pkg> …` | code, code, security, ux, ux |
| `gnome_shader_runtime_gl`, `_gl33` (env `MESA_GL_VERSION_OVERRIDE=3.3`) | `<bin>/shader-runtime-gltest <src>/../tests/fixtures`, `SKIP_RETURN_CODE 77` | code |
| `gnome_cli_golden` | `tests/cli-golden.sh check <bin>/waylandshader-gnomectl` | ux |
| `gnome_elf` | `tests/elf-check.sh <bin>/libwaylandshader-gnome.so <bin>/waylandshader-gnomectl <bin>/waylandshader-gnome-controller` | security |
| `gnome_ban` | `tests/ban-check.sh <src>` | security |

**Test files:**

- **`native-contract.js`** (GJS, argv[0] = native dir, like `effect-lifecycle.js`). It checks exact GError domain, code and message for:
  - `set_outputs`: missing scale, duplicate id, non-integer geometry, width 0;
  - gamma and saturation bounds and NaN, and an unknown output;
  - `set_parameter` with no preset, and a relative `load_preset`;
  - import with a non-object, version 2 and a relative preset;
  - every mutator after `shutdown()`.
  
  It also requires a byte-exact `export_settings()` and `get_status()` for a fixed configuration: two outputs, gamma 0.1, saturation 2, overrides 1e-7 and 0.5 under a preset key containing `é` and a non-BMP character, and recents. The literals are recorded by running the script against the baseline native dir. **The script must pass on the baseline first** (T-CONTRACT runs both).
- **`cli-golden.sh capture|check <ctl>`** runs each line of `golden/cli/cases.txt` under `env XDG_DATA_DIRS=$(mktemp -d) dbus-run-session --`. It writes or compares `<n>.out`, `<n>.err` and `<n>.code`, with the invoked ctl path replaced by `@CTL@`. Fixed fixtures go in `/tmp/ws-cli-golden/`: `a.slangp`, `A.SLANGP`, `b.txt`, and a missing path. The cases are:
  - `--help`, `-h`, `-?`, `--help-all`, no arguments, unknown command;
  - wrong arity for every command;
  - `--timeout` values 0, 3601, `x`, 5 and `=7`;
  - `load` with a missing file, a non-slangp file and a valid file (exit 3, no Shell);
  - `param` with an empty name, NaN and a valid value;
  - `output` with bad on/off, gamma 0.05/5.1 and saturation -1/2.1;
  - every valid command with no Shell (exit 3);
  - `--timeout 1 status` while `hang-shell.js` owns the name (exit 4).
- **`hang-shell.js`:** GJS that owns `org.gnome.Shell` and exports `/WaylandShader` with the `org.waylandshader.Effect` XML (copied from XJS:10–22). Its `statusAsync(params, invocation)` never returns. Readiness is detected with `gdbus wait --session --timeout 5 org.gnome.Shell`.
- **`elf-check.sh <lib> <ctl> <gui>`:**
  - `nm -D --defined-only <lib>` names, sorted with `LC_ALL=C sort`, must equal `golden/exports.txt`. That file holds `wayland_shader_effect_` + {`export_settings, get_status, get_type, import_settings, load_preset, new, reset_history, set_enabled, set_output_color_enabled, set_output_gamma, set_output_saturation, set_output_shader_enabled, set_outputs, set_parameter, shutdown`}, in `LC_ALL=C` order.
  - The lib has SONAME `libwaylandshader-gnome.so` and NEEDED `libwaylandshader-rashader.so.2`.
  - None of the three files has a NEEDED matching `libQt6|libstdc++`.
- **`ban-check.sh <src>`:** the T-BAN greps listed in requirements.md.
- **`isolated-session.sh <package-result> -- <cmd…>`** **[A2]** automates docs/GNOME.md:248–286:
  1. Create a `mktemp -d` root with `runtime` (mode 700), `config`, `data`, `cache` and `state`.
  2. Record `WS_HOST_WAYLAND_SOCKET=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` and the caller's bus address.
  3. Export the private `XDG_*` variables, `XDG_DATA_DIRS=<pkg>/share:…`, `GSETTINGS_BACKEND=keyfile`, `LIBGL_ALWAYS_SOFTWARE=1`, `XDG_SESSION_TYPE=wayland` and `XDG_CURRENT_DESKTOP=GNOME`, then unset `DISPLAY` and `WAYLAND_DISPLAY`.
  4. Under `dbus-run-session`: refuse if `$DBUS_SESSION_BUS_ADDRESS` equals the caller's; enable only the extension with `gsettings`; start `gnome-shell --wayland --headless --no-x11 --wayland-display waylandshader-check --virtual-monitor 640x480@60 --virtual-monitor 800x600@75`. With `WS_DEVKIT=1`, use `--devkit` instead of `--headless`, with `WAYLAND_DISPLAY=$WS_HOST_WAYLAND_SOCKET` so the devkit viewer opens as a window on the live desktop while the module loads only in the disposable Shell [INFERENCE: the 50.5 `--devkit` flag exists per `gnome-shell --help`; verify its viewer behavior in S4].
  5. Wait up to 60 s for `GetExtensionInfo` to report state 1.
  6. Export `WS_PRIVATE_BUS`, run the command, then stop only the Shell PID it started, wait for it, and remove the root.
  
  The script's exit status is the command's. It never runs `killall` or touches dconf of the live session.
- **`iso-cli.sh <ctl>`** writes `/tmp/ws-iso-cli/probe.slangp` (one pass with `#pragma parameter GAIN "Gain" 1.0 0.1 2.0 0.1`) and `broken.slangp` (a shader that fails to compile). It prints `== <step> exit=<code>` followed by stdout, with argv0 normalized:
  1. `status`, `outputs`, `parameters`;
  2. `output <first id> gamma 1.2`, `saturation 0`, `color on`, `shader off`, `shader on`;
  3. `output nonexistent gamma 1` (exit only);
  4. `load probe.slangp`, `param GAIN 0.5`, `param GAIN 3`, `param UNKNOWN 1`;
  5. `load broken.slangp`, then `status` (the previous preset is kept and `error` is set);
  6. `disable`; `toggle` and `enable` (exit only); then poll `status` until `loading` is false (≤30 s) and print it;
  7. `gnome-extensions disable waylandshader@man33li.github.com`, then `status` (exit 3; read-only, no activation);
  8. `enable` (activates), poll, then `status` (settings restored: REQ-036, REQ-040).

**T-ISO-RENDER checklist** (devkit window; CLI against `$WS_PRIVATE_BUS`):

1. With no preset, `output <id> saturation 0` turns only that output gray and `gamma 2` brightens the midtones. Back at 1/1, the output looks identical to the effect disabled.
2. Color-only on an idle desktop: the CPU use of the disposable Shell stays at its idle level (`top -p <shell pid>`). After loading a temporal preset it renders continuously.
3. Shader and color toggles on each output are independent. The other output is unaffected.
4. Master `disable` restores the unfiltered scene and `status.active` becomes false. `enable` rebuilds the preset.
5. A failed replacement keeps the running preset. With two rapid `load`s, the newer one wins.
6. The pointer is shaded together with the scene (software cursor) while processing, and stops being shaded after `disable`.
7. Small damaged regions (a blinking text cursor) show no unfiltered patches.
8. A `bypass` reason appears for any unsupported output, where one can be reproduced; otherwise record "not reproduced".
9. `gnome-extensions disable` removes the effect cleanly.
10. The Shell stderr contains no `CRITICAL` or `WARNING` lines from WaylandShader during the run.

**T-GUI checklist** (controller window on the live desktop, D-Bus on the private bus):

1. Title, size, texts, tooltips and mnemonics match GUI:67–165.
2. Browse: cancel, reopen, choose a path containing spaces. The field is filled but nothing loads (docs/GNOME.md:290).
3. Recent fills and focuses the field but does not load. Load and Return-to-load both work. A non-`.slangp` path shows the error text.
4. The enable checkbox is pending-guarded. Reconnect activates the extension.
5. The monitor combo shows names and the id tooltip. State-label texts appear for each state.
6. Gamma and saturation commit on Enter and focus-out with 2-decimal rounding.
7. Parameter editors: the 100 ms debounce works, a dirty editor is not overwritten, and typing `1.0000001e-7` into a tiny-range parameter commits exactly.
8. Stopping the disposable Shell shows `Disconnected — displayed controls may be stale.`
9. GTK Inspector accessible names exist for the entry, Recent, combo and spin buttons.
10. The dash icon or app_id is `org.waylandshader.GnomeController`.
11. Closing the window leaves `status.active` unchanged.

## 9. Work breakdown and order

The file sets are disjoint, and no agent edits another agent's files. Missing foreign declarations go in the agent's own file (§5.1). Requests for build-file changes go to the builder by message. The builder runs the combined checks once, after every set has landed.

| Owner | Files (create, edit or delete) | Done when |
|---|---|---|
| **builder** (Astra 6) | `gnome/CMakeLists.txt`, `gnome/default.nix`, `gnome/shell.nix`, `docs/waterfall/03-implementation/build-log.md`; the S0 baseline worktree | Steps 0, 3, 4 and 5. Every catalog test is run once and its result recorded (pass, fail, skip or manual). |
| **ws-code** (sol 6.1) | `gnome/native/{effect,engine,paint,config,mutter,native_test}.odin`, `gnome/native/exports.map`; `gnome/runtime/{runtime,egl,libra}.odin`, `gnome/runtime/gltest/main.odin`; `gnome/common/*`; `gnome/glib/{glib,gobject}.odin`; delete `gnome/native/waylandshader-effect.cpp` | S1, S2; T-ABI (Odin side), T-LIFE, T-RECENT, T-UNIT-COMMON, T-UNIT-NATIVE, T-GL, T-GL33 |
| **ws-security** (sol 6.1) | `gnome/native/boundary.odin`, `gnome/native/abi-check.c`; `gnome/glib/gio.odin`; `gnome/controller/client/*`; `gnome/tests/{native-contract.js,elf-check.sh,ban-check.sh,isolated-session.sh}`; `gnome/tests/golden/{exports.txt,snippet-decl.glsl,snippet-body.glsl}` (the GLSL transcribed from E:320–330, decoding the C string escapes) | T-CONTRACT (baseline first, then Odin), T-UNIT-CLIENT, T-ELF, T-BAN, T-ABI (C side). Reviews C-boundary ownership (`transfer full` strings, callback lifetimes) in the code and ui files and reports findings by message. |
| **ws-ux** (sonnet 5.5) | `gnome/controller/ctl/*`; `gnome/controller/gui/{view.odin,view_test.odin}`; `gnome/tests/{cli-golden.sh,hang-shell.js,iso-cli.sh}`, `gnome/tests/golden/cli/**`; `README.md` and `docs/GNOME.md` GNOME sections (§7) | T-UNIT-CTL, T-CLI-GOLDEN (goldens captured from `$BASE`), T-UNIT-GUI; `iso-cli.sh` ready for T-ISO-CLI; T-DOCS hits reviewed |
| **ws-ui** (sonnet 5.5) | `gnome/controller/gui/{main,window,gtk}.odin`, `gnome/controller/gui/controller.ui` | The GUI builds and links; S3 passes; T-GUI checklist items are implementable as written |

**Order of work (feasibility spikes first; a failed spike stops Step 2 and triggers its fallback in §10):**

- **Step 0 (builder).** `git worktree add /tmp/ws-baseline b223c1a && nix-build /tmp/ws-baseline/gnome/default.nix -o /tmp/ws-baseline-result`. Write the initial CMake and Nix changes so that `gnome_native`, `gnome_abi_check`, GIR/typelib and `shader-runtime-gltest` build from the spike sources.
- **Step 1 (spikes, in parallel):**
  - **S1** (ws-code, with ws-security's `boundary.odin` API and `abi-check.c`):
    - Build the real `effect.odin` registration (gates 1–3) with `new`, `get_status`, `shutdown` and `exports.map`.
    - Pass criteria: `gnome_abi_check` compiles; g-ir-scanner succeeds and the GIR has `glib:signal name="status-changed"`; `gjs -m` imports the typelib, and `Effect.new()` is non-null and `get_status()` returns a string; `nm -D` shows only `wayland_shader_effect_*`.
    - This is the first slice of the real implementation, completed in Step 2, not a throwaway stub.
  - **S2** (ws-code): gltest creates a surfaceless llvmpipe context in `nix-build` and in `nix-shell`, and runs one `libra_gl_filter_chain_frame` with the fixture preset. Pass: the pixel readback matches the C++ expectation (this proves the by-value `libra_image_gl_t` lowering).
  - **S3** (ws-ui): a GtkSpinButton with the §4.6 `input` handler commits `1.0000001e-7` exactly (adjustment value equals `f64(f32(1.0000001e-7))`), and the gamma field commits `1.234` as `1.23`.
  - **S4** (builder): `isolated-session.sh` (from ws-security) starts and stops a disposable headless Shell with the *baseline* package, and T-BYPASS passes on `$BASE`. This proves the harness before any Odin module runs in it.
- **Step 2 (parallel):** all four agents implement their file sets. Interfaces are frozen before parallel coding: `boundary.odin` (§5.6), the client API (§4.4), the `view.odin` signatures (§4.6) and the `common` API (§4.3).
- **Step 3 (builder integration):** S1 configure and build; all CTest entries; T-NIX, T-KWIN, T-GIR, T-LAYOUT, T-WRAP, T-UNCHANGED and T-ELF on the installed files. Record the results in the build log.
- **Step 4 (builder, isolated-session):** T-BYPASS and T-ISO-CLI with `$R`.
- **Step 5 (manual):** T-ISO-RENDER, T-GUI, T-SAFETY and T-DOCS, with results recorded. T-HW is left to the user after phase 4 acceptance.

## 10. Risks and fallbacks

| # | Risk | Mitigation | Fallback |
|---|---|---|---|
| R1 | Class or instance layout or vfunc offset mismatch crashes the Shell | Three gates (§5.2–5.3); layouts already measured; Shell-hosted runs only in disposable sessions | Correct the mirrors against the measured headers. If a registration bug cannot be solved in Odin, stop and report it to Main; a C subclass would leave a C component and needs a scope decision. |
| R2 | g-ir-scanner dumper or GJS cannot load the Odin dll | The probe already showed INIT, general-dynamic TLS and a working `dlopen`; S1 repeats this with GObject | If init is the cause, call `runtime._startup_runtime` in `get_type`'s once-block. If TLS is the cause, use `-no-thread-local` and keep temp-allocator use off the worker. |
| R3 | An Odin panic aborts the compositor | §5.6 ban list, Error values, allocation checks, critical log before the trap; all native logic exercised headless and in isolated sessions before any real install | Fix the bug; the same class of fault crashed the C++ build too |
| R4 | librashader ABI (by-value struct, bool layout) | `abi-check.c` sizes, S2 pixel check, T-GL | Correct the declaration. A C pointer shim needs a scope decision from Main. |
| R5 | JSON bytes differ from Qt (key order, numbers) | Baseline literals in T-CONTRACT, writer units, T-ISO-CLI diff | Adjust the writer until T-CONTRACT passes; the functional contract is unaffected |
| R6 | GTK 3 hand-binding mistakes (varargs, gboolean, signal signatures) | Builder XML keeps the FFI to about 45 calls; S3; T-GUI | None needed: the controller is a separate process (docs/GNOME.md:33) |
| R7 | Mesa llvmpipe is unavailable in the Nix sandbox | Vendor JSON in `preCheck` | Run T-GL/T-GL33 in `nix-shell` on the host (its own process, no compositor contact) and record that in the build log |
| R8 | The `--devkit` viewer behaves differently than assumed | S4 checks it | Run T-ISO-RENDER in a nested headless session with a screenshot over D-Bus `org.gnome.Shell.Screenshot` on the private bus [INFERENCE], recorded as such |
| R9 | The GTK 3 app_id is not the desktop id | `g_set_prgname` before `gtk_init`; T-GUI | `GtkApplication` with `G_APPLICATION_NON_UNIQUE` and the same id |
| R10 | Live-session safety | Never install into `~/.local/share` or the system during phases 3–4. Every Shell-hosted check goes through `isolated-session.sh`, which refuses the live bus. The GUI uses the private bus with `GSETTINGS_BACKEND=memory`. | n/a |

## 11. Accepted deviations (from decision.md; need Main or user confirmation)

- **D1:** The per-item popup tooltips in the monitor combo are not reproduced (GTK 3 has none). The selected-id tooltip is kept, and ids equal names (XJS:100–101).
- **D2:** GtkSpinButton ignores stepping increments of 1e-10 or less. Typed values remain exact. This is marked with a `shortcut:` comment in `window.odin`.

Not done in this phase: no Odin code was compiled beyond the throwaway probes in `/tmp/wsprobe`. The JSON key and number rules for Qt, the libglvnd stub validity across contexts, and the devkit viewer behavior stay [INFERENCE] until S1–S4 and T-CONTRACT.
