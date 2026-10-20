# Phase 1 research: Odin GNOME backend feasibility

**Observed versions:** `odin version` returned `dev-2026-09`; Nix reported `nixpkgs#odin.version = "dev-2026-05"` and `nixpkgs#mutter.version = "50.5"`. The compiler result and package attribute therefore do not identify the same Odin revision. The Nix expression’s channel/revision was not recorded, so these observations are not enough to establish that the installed compiler exactly matches the selected nixpkgs package.

## 1. Odin shared library, C ABI, linking, and runtime context

| Question | Finding |
|---|---|
| Build as shared library | Odin’s official example builds a dynamic library with `odin build … -build-mode:dll`; on Unix-like systems this produces a `.so`. `-build-mode:shared` is also used in Odin examples, but use the mode accepted by the pinned compiler and check its actual output name. [Odin: Calling Odin from Python](https://odin-lang.org/news/calling-odin-from-python/) · [Odin forum: Erl_Interface/NIFs](https://forum.odin-lang.org/t/odin-and-erlang-interface-nifs/1463) |
| Export C symbols | Exported functions use `@(export)` and a C-compatible procedure such as `proc "c" (...)`; `@(link_name="...")` sets the exported symbol name. Keep the boundary to C ABI-compatible types and signatures. [Odin: Calling Odin from Python](https://odin-lang.org/news/calling-odin-from-python/) · [Odin: Binding to C](https://odin-lang.org/news/binding-to-c/) |
| Import system libraries | Odin `foreign import` associates a foreign block with a library; declarations in a foreign block use the C calling convention by default. Odin can also use system libraries and explicit shared-library paths. For a pkg-config-discovered `.so`, use the discovered linker flags/library path in the build and bind the actual C declarations in foreign blocks; pkg-config itself does not generate Odin declarations. [Odin: Binding to C](https://odin-lang.org/news/binding-to-c/) |
| `context` in exported callbacks | A C callback has no Odin implicit context parameter. Before calling context-dependent Odin code, set `context = runtime.default_context()` in that callback. This supplies Odin’s default context, not a caller’s custom allocator/logger context. [Odin overview](https://odin-lang.org/docs/overview/) · [Odin runtime package](https://pkg.odin-lang.org/base/runtime/) |
| Host process, threads, runtime | **[INFERENCE]** A GNOME Shell-loaded library must not assume callbacks enter through an Odin `main` path or that host threads already have an appropriate Odin context. Initialize/set context at each C-to-Odin callback boundary, and avoid assuming Odin context is implicitly thread-local. The official overview documents explicit context handling across C boundaries; it does not establish a complete GNOME-hosted thread/runtime lifecycle contract. [Odin overview](https://odin-lang.org/docs/overview/) · [Odin forum: context across foreign calling conventions](https://forum.odin-lang.org/t/passing-context-through-foreign-calling-conventions-is-this-not-working-as-intended/762) |

## 2. Odin OpenGL and EGL packages

- The Odin `vendor:OpenGL` package supports core OpenGL through 4.6 and provides a loader mechanism (`gl.load_up_to` with a caller-supplied procedure resolver). This covers GL 3.3+ entry points when loaded at the needed version; the actual runtime context must also expose the required functions. [Odin OpenGL README](https://github.com/odin-lang/Odin/blob/master/vendor/OpenGL/README.md)
- **[INFERENCE]** For an EGL-backed context, the resolver can be adapted to `eglGetProcAddress`; confirm the exact type/signature against the pinned Odin package and platform headers before binding it.
- The cited vendor EGL release notes confirm ongoing procedure/constant additions, but do **not** prove that `vendor:egl` includes `EGL_KHR_fence_sync` declarations. **Unverified:** whether the exact selected Odin revision binds `eglCreateSyncKHR`, `eglClientWaitSyncKHR`, and `eglDestroySyncKHR`; if absent, they can be declared as C function pointers loaded through EGL, provided the runtime advertises the extension. [Odin release dev-2025-11](https://github.com/odin-lang/Odin/releases/tag/dev-2025-11) · [Khronos EGL_KHR_fence_sync registry](https://registry.khronos.org/EGL/extensions/KHR/EGL_KHR_fence_sync.txt)
- The GL vendor package’s core-profile claim is a binding-coverage statement, not a promise that Mutter’s compositor context exposes every GL 3.3+ function.

## 3. GObject subclassing and introspection

- `g_type_register_static` and a `GTypeInfo`-style class initializer are the conventional C mechanisms for registering a GObject subtype and assigning class vfuncs. A Clutter effect is a GObject class; Odin can call these C APIs through bindings/foreign declarations, but class-init and vfunc callbacks must obey exact C ABI signatures. [GLib `g_type_register_static`](https://docs.gtk.org/gobject/func.type_register_static.html) · [Clutter Effect API](https://mutter.gnome.org/clutter/class.Effect.html)
- Existing Odin binding projects include [PucklaJ/odin-gtk](https://github.com/PucklaJ/odin-gtk) (generated GTK4/libadwaita-related bindings) and [Hyperquader-Coders/odin-gtk4](https://github.com/Hyperquader-Coders/odin-gtk4) (GTK/GDK/GSK bindings with GLib/GObject provided separately). They are community projects, not an official GNOME/Odin binding set; suitability for Mutter’s private Clutter ABI is unverified.
- `g-ir-scanner` parses public C headers and also builds/runs an introspection dumper linked to the target library; runtime GType information is needed for registered classes. A hand-written header therefore needs valid C declarations for the exported library API and its types, correct included headers, and annotations/metadata where needed; the built library must export the declared symbols and be loadable by the dumper. It is not sufficient to provide an Odin declaration alone. [g-ir-scanner documentation](https://gi.readthedocs.io/en/latest/tools/g-ir-scanner.html)
- **[INFERENCE]** GIR generation for an Odin implementation is feasible if its exported C ABI and runtime GType registration agree with the hand-written header and scanner-visible symbols. Scanner execution against the real Mutter runtime is a key integration risk.

## 4. Mutter 50, Clutter 18, and Cogl

- Nix reported Mutter `50.5`; this confirms the queried nixpkgs attribute, not the installed GNOME Shell runtime. Mutter 50 corresponds to versioned Clutter/Cogl ABI 18 in the cited Mutter API/build references. [Mutter 50.5 Nix package version](https://search.nixos.org/packages?query=mutter) · [Mutter Clutter API](https://mutter.gnome.org/clutter/)
- Clutter effects use paint-node-era vfuncs. The documented effect class includes paint hooks receiving an effect, paint node, paint context, and flags; `ClutterPaintContext` exposes the framebuffer through `clutter_paint_context_get_framebuffer`. [Clutter Effect API](https://mutter.gnome.org/clutter/class.Effect.html)
- Relevant integration surface includes `ClutterEffect` paint vfuncs, `ClutterPaintContext`, `CoglFramebuffer`, stage/view handling, and frame-clock timing. **[INFERENCE]** Exact entry points needed depend on the current C++ backend’s behavior; confirm against the repository implementation and Mutter 18 headers rather than deriving a broader API set from these references.
- **ABI-layout hazard:** GObject subclasses must embed the exact parent instance layout and use a compatible class-struct layout/size for registration; vfunc offsets and signatures must match the Mutter headers. Hand-mirroring C struct layouts in Odin is inherently sensitive to ABI/version, packing, pointer width, and parent-class layout. [GLib `GTypeInfo`](https://docs.gtk.org/gobject/struct.TypeInfo.html) · [Clutter Effect API](https://mutter.gnome.org/clutter/class.Effect.html)
- Clutter/Cogl APIs are versioned/private compositor interfaces. The observed `mutter = 50.5` makes ABI 18 relevant to this environment; a different GNOME/Mutter release may require different headers and ABI.

## 5. librashader 0.10.1 C API

- The 0.10.1 release uses C API ABI version 2. Its C API documentation recommends `librashader_ld.h`, a function-pointer loader for dynamically loading the library; direct foreign linking is an alternative only when the library’s exported ABI and link setup are available. [librashader 0.10.1 release](https://github.com/SnowflakePowered/librashader/releases) · [librashader C API crate](https://docs.rs/librashader-capi/0.10.1/librashader_capi/)
- ABI 2 changed the GL chain creation API to accept a GL loader, removed `libra_gl_init_context`, changed the frame function’s viewport parameter, and made librashader manage its own framebuffer for the output texture. Bindings must match the exact 0.10.1 headers, not an older declaration set. [ABI 2 migration guide](https://github.com/SnowflakePowered/librashader/blob/v0.10.1/MIGRATION-ABI2.md)
- **[INFERENCE]** In Odin, model the public header’s structs, enums, opaque pointers, callback/function-pointer types, and calling conventions in foreign declarations, or bind the loader header’s function-pointer table explicitly. Do not assume Rust internals or infer C layout from function names; verify sizes, alignment, nullability, and parameter order against the tagged header.

## Ranked blocking risks

| Rank | Risk | Likelihood / impact |
|---:|---|---|
| 1 | Exact Clutter 18 class/vfunc and `GTypeInfo` ABI/layout mismatch when registering the effect from Odin | High / port-blocking: a mismatch can crash during type registration or paint dispatch. |
| 2 | GIR dumper cannot load the Odin library or obtain valid GType/introspection data | High / port-blocking for GJS exposure; scanner requires a runnable linked dumper. |
| 3 | Odin callback context/runtime assumptions fail on GNOME-created threads or callbacks | Medium-high / potentially process-crashing or allocator-invalidating. |
| 4 | librashader declarations mismatch 0.10.1 ABI 2, especially function-pointer loader and frame parameters | Medium / rendering failure or ABI corruption. |
| 5 | EGL fence/sync bindings are absent or the compositor context lacks the needed extension | Medium / synchronization path may require manual declarations or another supported path. |
| 6 | Nix compiler/package version discrepancy (`odin version dev-2026-09` vs nixpkgs attribute `dev-2026-05`) | Medium / build-mode, runtime, or binding details may differ from pinned source. |

**Skipped:** no repository edits; exact local Odin vendor-package declarations and Mutter 18 headers were not inspected.  
**Risk to know:** the external sources establish feasibility patterns, not a verified build against the repository’s complete GNOME/Nix environment.