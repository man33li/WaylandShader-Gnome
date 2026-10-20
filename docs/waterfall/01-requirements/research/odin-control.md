# Phase 1 research: Odin controller options

**Scope:** Replace the GNOME Qt6 Widgets controller and CLI while preserving the existing feature set. The GNOME build currently links a shared client into both executables; the GUI uses Qt Widgets and `QFileDialog`, while the CLI uses asynchronous client calls, deadlines, input validation, and JSON output (`gnome/CMakeLists.txt:1-9,97-104`; `src/controller_main.cpp`; `src/ctl_main.cpp`). No repository files were changed.

## 1. GUI toolkit options

| Option | Odin status / code size | GNOME file chooser | Wayland and accessibility | Nix packaging effort |
|---|---|---|---|---|
| **GTK4, optionally libadwaita** | Community Odin bindings exist; direct C ABI declarations are also possible. Binding quality/version compatibility varies, and C callbacks, ownership, and string conversion still need care. **Estimate: medium** for a controller GUI. [PucklaJ/odin-gtk](https://github.com/PucklaJ/odin-gtk), [Hyperquader-Coders/odin-gtk4](https://github.com/Hyperquader-Coders/odin-gtk4), [GTK4 C API](https://docs.gtk.org/gtk4/) | GTK 4.10+ provides asynchronous `GtkFileDialog`; it can use the FileChooser portal when available. [Gtk.FileDialog](https://docs.gtk.org/gtk4/class.FileDialog.html), [portal spec](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html) | Native GTK4 Wayland support; GTK accessibility exposes AT-SPI. Portal chooser behavior depends on the available portal backend. [GTK accessibility](https://docs.gtk.org/gtk4/section-accessibility.html), [GTK dialogs](https://docs.gtk.org/gtk4/section-dialogs.html) | **Medium.** Add GTK4/GIO development inputs, provide GTK schemas/modules and ensure runtime library paths are wrapped. GTK is already present as a GNOME package dependency in the current derivation (`gnome/default.nix`). |
| **raylib + microui** | Both are available in Odin’s vendor collection; microui is an Odin source port. Low-level UI means the controller’s widgets, layout, focus, and interactions need custom implementation. **Estimate: high** for equivalent settings UI. [vendor:raylib](https://pkg.odin-lang.org/vendor/raylib/), [vendor:microui](https://pkg.odin-lang.org/vendor/microui/) | Neither provides a GNOME-native chooser. Add a separate portal/file-dialog integration or build a custom file browser. [Portal spec](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html) | Wayland depends on the raylib/GLFW build configuration; upstream documents enabling GLFW’s Wayland backend. Microui does not provide GTK-style accessibility; adding accessibility would be separate work. [raylib Linux guide](https://github.com/raysan5/raylib/wiki/Working-on-GNU-Linux), [AccessKit](https://github.com/AccessKit/accesskit) | **Medium–high.** Odin vendor bindings do not remove the need to package/link suitable raylib/GLFW libraries and graphics dependencies. |
| **Other immediate-mode/rendered UI (e.g. SDL or custom)** | Odin bindings and microui examples exist for SDL, but this does not remove the need to build the application UI and platform integrations. **Estimate: high.** [microui package](https://pkg.odin-lang.org/vendor/microui/) | No GNOME chooser built in; integrate a portal or another native dialog library. | Wayland support depends on the selected window backend. Accessibility is not equivalent to a GTK widget tree unless separately implemented. | **Medium–high**, depending on backend, graphics libraries, and portal integration. |

**Assessment:** GTK4 is the closest fit to the existing GNOME desktop application and file-chooser behavior. The existing package already includes `gtk3` and comments that the Qt chooser needs GTK schemas and GIO modules; that does **not** establish that GTK4’s dependencies or wrapping are already complete (`gnome/default.nix`). For GTK4’s chooser, `GtkFileDialog` is the current API; older chooser classes are deprecated. [GTK dialogs](https://docs.gtk.org/gtk4/section-dialogs.html)

## 2. D-Bus client

**Recommendation: GIO GDBus through Odin’s C ABI.** The controller client needs asynchronous method calls, replies/signals, and timeouts; GDBus provides `g_dbus_connection_call()` with an explicit timeout and callback, designed to work with GLib’s main context. [GDBus call API](https://docs.gtk.org/gio/method.DBusConnection.call.html)

| Choice | Fit for this controller |
|---|---|
| **GDBus/GIO** | **Least code** if the GUI uses GTK: it shares GLib/GIO and the GLib main loop. For a CLI, run a `GMainLoop` until the callback completes; use the API timeout and print JSON with Odin’s JSON/formatting libraries. |
| **libdbus** | Usable asynchronously, but requires pending-call handling and integration of D-Bus watches/timeouts with the event loop. More glue than GDBus for this use. [libdbus async send](https://dbus.freedesktop.org/doc/api/html/group__DBusConnection.html) |
| **sd-bus** | Provides async calls and timeouts, but a GLib-loop application needs an adapter or a different loop integration. Its timeout parameter uses microseconds. [sd_bus_call_async](https://man7.org/linux/man-pages/man3/sd_bus_call_async.3.html) |

This recommendation is about integration effort, not a claim that the alternatives cannot implement the required behavior. The present C++ client uses asynchronous calls with a per-call 10-second timeout and tracks service/interface changes (`src/controller_client.cpp`).

## 3. Odin standard library and headless tests

The relevant library facilities are documented in Odin’s package reference: [`core:encoding/json`](https://pkg.odin-lang.org/core/encoding/json/), [`core:flags`](https://pkg.odin-lang.org/core/flags/), [`core:fmt`](https://pkg.odin-lang.org/core/fmt/), and [`core:testing`](https://pkg.odin-lang.org/core/testing/). `os.args` supplies program arguments; `flags` supports parsing arguments into a struct. Odin tests use `@(test)` procedures and run with `odin test`. [Testing guide](https://odin-lang.org/docs/testing/)

A Nix derivation can run headless tests in `checkPhase`, for example:

```nix
doCheck = true;
checkPhase = ''
  runHook preCheck
  odin test src -define:ODIN_TEST_THREADS=1
  runHook postCheck
'';
```

This is a **pattern**, not a verified project-specific test command: the final package/test directory layout and any required runtime environment must be confirmed during implementation. `odin test` runs the test package rather than launching the application; tests that require a display or live D-Bus session would need a separate suitable test environment.

## 4. Nix packaging

A plain `stdenv.mkDerivation` is the straightforward approach: place `odin` in `nativeBuildInputs`, compile with `odin build`, install the resulting executable(s), and list C libraries in `buildInputs`/`pkg-config` inputs as appropriate. Pass additional linker flags through Odin’s `-extra-linker-flags` when a library search path or linker option is needed. [Nixpkgs Odin package](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/od/odin), [Nixpkgs OLS package](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ol/ols), [Nixpkgs Odin packaging discussion](https://github.com/NixOS/nixpkgs/issues/338972)

A local read-only probe found `nixpkgs#odin.version` resolves to **`dev-2026-05`** in this environment. This is an environment observation, not a claim about current upstream nixpkgs.

## 5. GJS extension

**Keep `extension.js` as JavaScript.** GNOME’s extension documentation describes extensions as GJS/JavaScript modules; the project’s extension imports GJS modules and implements the Shell extension class in JavaScript (`gnome/extension/extension.js`). [GNOME extension guide](https://gjs.guide/extensions/), [extension anatomy](https://gjs.guide/extensions/overview/anatomy.html)

The extension currently loads the native WaylandShader library through GIRepository/typelib-related setup and exports the D-Bus interface from the extension (`gnome/extension/extension.js`; `gnome/CMakeLists.txt:45-85,106-126`). The Odin controller change does not imply replacing that extension module.

## Ranked recommendation

**Code size is a relative estimate** for preserving the existing GUI and CLI behavior, not a measured line count.

| Rank | Option | Relative code size | Main risks |
|---:|---|---|---|
| 1 | **GTK4/GIO via C ABI or maintained bindings** | Medium | Binding/API version mismatch; Odin–C callback and memory ownership; package GTK4/runtime integration. |
| 2 | **Other toolkit with an existing native/accessibility layer** | Medium–high | Binding maturity and GNOME integration vary; chooser and dependency packaging remain to verify. |
| 3 | **raylib + microui** | High | Custom UI work; no built-in GNOME chooser or GTK accessibility; Wayland depends on GLFW build configuration. |

Skipped: implementing or benchmarking alternatives, and validating current GTK4 Odin bindings against this repository’s pinned Nix environment. **Risk:** binding completeness and exact package/runtime integration remain to be checked when selecting the design.