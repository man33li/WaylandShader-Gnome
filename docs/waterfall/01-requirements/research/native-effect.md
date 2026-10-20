# GNOME native effect: feature and behavior inventory

Read-only research for Phase 1 of the Odin port. Scope: the five target files. Build files, GIR packaging, tests and the librashader and Mutter headers were not read. Line numbers marked `~` are approximate, because the read tool elided some blocks. Everything else is cited from grep or raw reads.

Abbreviations: **E** = `gnome/native/waylandshader-effect.cpp`, **EH** = `gnome/native/waylandshader-effect.h`, **R** = `src/shader_runtime.cpp`, **RH** = `src/shader_runtime.h`, **OS** = `src/output_settings.h`.

---

## 1. Public GObject API (GIR source: EH)

Type: `WaylandShaderEffect`, a final `ClutterEffect` (EH:14, `G_DECLARE_FINAL_TYPE`). The type is defined at E:504. Clutter/Mutter ABI 18 is implied by the includes (EH:9–11) [INFERENCE from task context].

| Symbol (EH line) | Signature | Behavior | Testable statement |
|---|---|---|---|
| `wayland_shader_effect_new` (23) | `WaylandShaderEffect* (void)` | Creates the effect with a fresh `Engine`; returns NULL if engine allocation fails (E:1330–1340). | `new()` returns a non-NULL owned object, or NULL when `Engine` construction throws. |
| `wayland_shader_effect_get_status` (30) | `gchar* (self)` | Returns compact JSON status (E:1342–1350); a fixed fallback JSON on exception. | Always returns non-NULL JSON; on exception it returns the fixed `"Unable to construct native status"` object. |
| `wayland_shader_effect_export_settings` (37) | `gchar* (self)` | Returns `{version:1, enabled, preset, recent_presets, parameters, outputs}` (E:1352–1375). Returns **NULL** on exception. | Output contains `"version":1`; NULL is returned on failure (undocumented in EH:32–36). |
| `wayland_shader_effect_import_settings` (46) | `gboolean (self, json, GError**)` | Validates and applies saved settings; schedules a preset reload (E:1377–1452). | Rejects non-object JSON, `version≠1` (unless the object is empty), relative preset paths, and any call while compiling. |
| `wayland_shader_effect_set_outputs` (55) | `gboolean (self, json, GError**)` | Replaces the output inventory; remaps only when the inventory changed or mapping is dirty (E:1454–1499). | Duplicate or empty IDs, non-integer geometry, and out-of-range scale are rejected; an unchanged inventory is a no-op. |
| `wayland_shader_effect_load_preset` (67) | `gboolean (self, path, GError**)` | Requires an absolute readable file, canonicalises it, and calls `request` (E:1501–1510). | Relative or unreadable path → `GError`; success means async compile started. |
| `wayland_shader_effect_set_enabled` (76) | `gboolean (self, gboolean)` | Master switch. Off: `reset(false)`, which drops the runtime. On: `reset(true)`, which rebuilds the selected preset (E:1512–1521). | Toggling to false drops the runtime and history; toggling back to true reloads the last preset. |
| `wayland_shader_effect_set_parameter` (89) | `gboolean (self, name, double, GError**)` | Sets a preset parameter. With a runtime it calls `setParameter`; without one it validates against stored metadata (E:1523–1544). | Edits with no runtime are stored and validated against the stored metadata. Edits during compile are rejected. |
| `wayland_shader_effect_set_output_shader_enabled` (99) | per output | Toggles the shader for one output (E:1547–1559). | Toggling resets that output's history flags; the color flag is untouched. |
| `wayland_shader_effect_set_output_color_enabled` (109) | per output | Toggles color (E:1561–1570). | Setting the same value is a no-op (no status emission). |
| `wayland_shader_effect_set_output_gamma` (119) | `double`, range 0.1–5 | Validates and stores gamma (E:1572–1583). | Values outside [0.1, 5] or non-finite are rejected. |
| `wayland_shader_effect_set_output_saturation` (129) | `double`, range 0–2 | Validates and stores saturation (E:1585–1596). | Values outside [0, 2] or non-finite are rejected. |
| `wayland_shader_effect_reset_history` (138) | `void (self)` | `reset(true)`; drops GPU chains and resources and rebuilds asynchronously (E:1598–1609). Errors go to `fail()`. | After the call, every output's `clearHistory` is true and the preset is recompiled. |
| `wayland_shader_effect_shutdown` (147) | `void (self)` | Idempotent teardown; called from `dispose` (E:1611–1620, E:1290–1294). | A second call is a no-op. |

Signal: `status-changed` (E:1317–1318), `G_SIGNAL_RUN_LAST`, one `G_TYPE_STRING` argument (controller JSON). Emitted from an idle source on the main context, never during paint (E:546–571, doc at E:1310–1316). Emitted only when the JSON differs from the last one (E:552–556).

Properties: none. The class defines no GObject properties.

Threading contract (EH:8–9 doc, E:453–455): every method calls `Engine::check()` and throws if not on the owner thread or after shutdown.

### 1a. JSON contracts

| Document | Keys | Citation | Testable statement |
|---|---|---|---|
| Status | `enabled, active, loading, preset, requestedPreset, recentPresets, error, parameters[], outputs[]`; param rows carry `name, description, minimum, maximum, step, default, value`; output rows carry `shaderEnabled, colorEnabled, gamma, saturation, id, name, shaderActive, colorActive`, plus `bypass` when a failure is set | E:~519–544 (status body, between `fail`@509 and `notify`@546) | Output row contains `bypass` only when `failure` is non-empty. |
| Settings | `version`(1), `enabled`, `preset`, `recent_presets`, `parameters{preset:{name:value}}`, `outputs{id:{...}}` | E:1366–1368 | Round-trip of export→import preserves the `overrides` map. |
| Outputs inventory (input) | `id`(string), `name`(string), `x`,`y`(int, min INT_MIN), `width`,`height`(int ≥1), `scale`(0.01–64) | E:1454–1499 (checks at ~1465–1490) | Missing `scale` is rejected even though EH:49–54 does not list it. |

---

## 2. Rendering pipeline

| Feature | Citation | Testable statement |
|---|---|---|
| Per-output state (`Output`: id, name, failure, layout, scale, key, settings, view, timeline, resources, retired, clearHistory, previousTime, firstFrame, expandedFrame) | E:383–408 | Each connector ID maps to exactly one `Output`; `key` is a fresh `nextKey` integer (E:1459) used as the librashader chain key. |
| Output selection by stage view | E:664–730 (`mapOutputs`), E:1079–1083 (`paint` selection) | Paint is processed only for the view whose `expandedFrame == frame count`. |
| Output binding to Mutter view: monitor found by connector; must be active (682–683), not tiled (685–687), CRTC not shared (689–692), layout must match stage view (697–700) | E:664–730 | Each rejection string appears as `status.outputs[i].bypass`, and processing is skipped for that output. |
| Stage-view destroy: detach, `mappingDirty=true`, `reset(true)` | E:~1000 region (destroy handler inside `mapOutputs`, E:~705–715) | Destroying a view clears that output's resources and triggers a recompile. |
| Scene capture: raw framebuffer blit to FP16 `raw` surface | E:1111 | `raw` is `RGBA_FP_16161616_PRE`, allocated at E:214. |
| Working color state: if the target is HDR (`mastering_max > ref`), the working state is sRGB with max luminance scaled to `ref*mastering_max/ref_target`; otherwise plain sRGB | E:296–308 | Shader runs in extended sRGB with headroom; the SDR default is never used when the target has HDR luminance. |
| `targetIsSrgb` = `clutter_color_state_equals(target, working)` | E:311 | When true, the sRGB→target conversion (E:1119 and final pass) is skipped unless color adjust is active. |
| Target→sRGB conversion into `srgb` FP16 surface when target is not sRGB | E:1116–1121 | Shader input is always linear-sRGB-working FP16. |
| Shader source copy into effect-owned `GL_RGBA16F` mip texture (blit to level 0, `GL_TEXTURE_MAX_LEVEL=0`) | E:340–380 (`copyShaderSource`), E:351 (`glTexImage2D GL_RGBA16F`) | The source has a full mip chain allocated but only level 0 is valid after copy. |
| Shader destination: `destination` surface, FP16 | E:1141, E:1147–1153 (`ShaderFrame`) | Destination name and `GL_RGBA16F` format are passed to librashader. |
| Shader run per output; `frame.number` = frames since first frame; `frame.elapsedMilliseconds` = time since this output's last frame | E:1143–1151 | First frame of a chain has `number==0`; `clearHistory` is set on first frame and after resets. |
| FPS: from `clutter_frame_clock_get_refresh_rate`; if 0, measured from `1e6/(now−prev)`; first frame after 0 skips the shader (warm-up) | E:1122–1137 | Externally driven views render their second frame onward. |
| Final pass (gamma/saturation + working→target) when `!targetIsSrgb || adjustsColor` | E:1166–1181 | With defaults (1.0/1.0) on an sRGB target, the final pass is skipped. |
| Present: blit processed FP surface to target framebuffer | E:1187–1192 | Any GL error after present throws and triggers failure handling. |
| Failure during paint: restore raw scene to target, set `output.failure`, call `fail`, continue scene | E:1194–1207 | After a paint failure the output shows the unfiltered scene and `bypass` in status. |
| Master bypass: `enabled==false` → `shader()`/`color()` false; paint with `BYPASS_EFFECT` or not-selected view calls `continueScene` | E:456–462, E:1060–1070 | With master off, `paint` never allocates resources. |
| Color-only path: `color()` true when `colorEnabled && (gamma≠1 || saturation≠1)` and EGL context captured; runtime may be null | E:460–462, E:1163–1164 (retired reset when no runtime) | Color adjust works with no preset loaded. |
| Shader-only path: `shader()` requires `runtime` non-null, `enabled`, output shader on | E:456–458 | Disabling color does not disable the shader. |
| Software cursor inhibit: `meta_backend_inhibit_hw_cursor` whenever `active()` changes; uninhibit on deactivate/shutdown/attach | E:632–638, E:771–774 | Any active output forces software cursor. |
| Direct-scanout handling: no direct-scanout API is called; the code forces a full-view redraw clip (`add_redraw_clip(view,nullptr)`) and records `expandedFrame` in before-paint | E:997–1001 (before-paint), E:579/650 (clip), E:766–768 (comment) | [INFERENCE] Filtered outputs bypass direct scanout because a full redraw clip is forced every frame; the code never names direct scanout. |
| Frame-clock animation: `clutter_timeline_new_for_frame_clock(clock, 1000)`, repeat −1, `new-frame` queues redraw with output layout | E:642–653 | Timeline exists only while `shader(output)` is true; color-only outputs get no timeline. |
| Redraw request: `redraw()` adds full-view clip to every view then `clutter_actor_queue_redraw(stage)` | E:573–586 | Topology changes and master toggles repaint every view. |

---

## 3. Shader math

Gamma and saturation run in the **texture-lookup snippet** (E:319–330), after the texture read and before the color transform, in unpremultiplied sRGB:

```glsl
if (wls_gamma != 1.0 || wls_saturation != 1.0) {
  if (cogl_texel.a > 0.0) {
    vec3 rgb = pow(max(cogl_texel.rgb / cogl_texel.a, vec3(0.0)), vec3(1.0 / wls_gamma));
    vec3 linear_rgb = mix(pow((rgb + 0.055) / 1.055, vec3(2.4)), rgb / 12.92, lessThanEqual(rgb, vec3(0.04045)));
    float luma = dot(linear_rgb, vec3(0.2126, 0.7152, 0.0722));
    linear_rgb = max(mix(vec3(luma), linear_rgb, wls_saturation), vec3(0.0));
    rgb = mix(1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear_rgb, lessThanEqual(linear_rgb, vec3(0.0031308)));
    cogl_texel.rgb = rgb * cogl_texel.a;
  } else { cogl_texel.rgb = vec3(0.0); }
}
```

| Item | Citation | Testable statement |
|---|---|---|
| Gamma formula: `rgb' = rgb_srgb^(1/γ)` applied to encoded sRGB, then sRGB decode | E:322–324 | With γ=2 and sat=1, a mid-gray 0.5 encodes to ~0.707 before decode. |
| Saturation: Rec.709 luma `(0.2126, 0.7152, 0.0722)` on linear RGB, `mix(luma, c, s)`, clamped ≥0 | E:325–326 | s=0 yields exact luma gray; s=2 doubles chroma around luma. |
| Re-encode: sRGB OETF with knee 0.0031308 | E:327 | Round-trip with γ=1, s=1 is identity within FP16 error. |
| Premultiplication handling: unpremultiply before math, re-multiply after; alpha ≤0 → rgb=0 | E:323, E:328–329 | Fully transparent texels stay black. |
| Gamma/saturation are uniforms `wls_gamma`, `wls_saturation` set per frame when changed | E:335–336, E:1170–1177 | Uniform write is skipped when value unchanged since last frame (`resources.gamma`/`saturation` cache). |
| Gamma/saturation UI range | OS:6–9, E:1575 (gamma), E:1588 (sat) | Gamma ∈ [0.1, 5], saturation ∈ [0, 2]. |
| Working→target color conversion by Mutter pipeline transforms | E:313–316 (`add_pipeline_transform` to `toSrgb`), E:333–334 and E:~1178 (`update_uniforms`) | No hand-written HDR tone mapping; Mutter's transform does the conversion. |
| Snippet hook | E:319 | Lookup is `COGL_SNIPPET_HOOK_TEXTURE_LOOKUP` on layer 0 of `toTarget`. |

---

## 4. librashader usage (R)

Compiled only with `LIBRA_RUNTIME_OPENGL` (R:6–9). Header is `librashader.h`.

| Call | Citation | Use |
|---|---|---|
| `libra_error_write`, `libra_error_errno`, `libra_error_free_string`, `libra_error_free` | R:35–41 (`checkLibra`) | Error message extraction; fallback text `librashader failed (error N)`. |
| `libra_preset_create_with_options` | R:362 | Loads `.slangp` with `original_aspect_uniforms=true` and `frametime_uniforms=true` (R:348–352). |
| `libra_preset_get_runtime_params` | R:368 | Parameter metadata. Freed via `libra_preset_free_runtime_params` (R:141). |
| `libra_gl_filter_chain_create` | R:411 | Chain with `loadGl` = `eglGetProcAddress`; `glsl_version = version*10`, `use_dsa = version>=45`, mipmaps not forced off, cache enabled (R:353–357; `loadGl` R:146–149). |
| `libra_gl_filter_chain_get_active_pass_count` | R:416 | Rejects a preset with 0 active passes (R:419–422). |
| `libra_gl_filter_chain_get_param` | R:429, R:488 | Reads pragma and `.slangp` defaults for every param. |
| `libra_gl_filter_chain_set_param` | R:436, R:493, R:496 | Applies overrides at load; setter with rollback in `setParameter`. |
| `libra_gl_filter_chain_free` | R:190, R:449 | Destructor; load-time validation chain freed before return (R:448–452). |
| `libra_gl_filter_chain_frame` | R:571–573 | Per-frame run with `frame_gl_opt_t` (R:552–561), `frame_direction=1`, `total_subframes=1`, `current_subframe=1`, `aspect_ratio=w/h`, `frames_per_second`, `frametime_delta`, `clear_history`. The MVP is a fixed 4×4 `{2,0,0,0 / 0,2,0,0 / 0,0,0,0 / -1,-1,0,1}` (R:565–570). |
| `libra_preset_free` | R:130 | Frees the preset handle. |

Context and sharing:
- EGL OpenGL API only; GLES rejected (R:213–227). Requires EGL 1.5 or surfaceless (R:230–231).
- Context versions tried in order 4.6, 4.5, 3.3 (R:249). Robust variant with `LOSE_CONTEXT_ON_RESET` and `ROBUST_ACCESS` tried second (R:252–265).
- Shared with the host via `hostContext` argument to `eglCreateContext` (R:266).
- Pbuffer fallback when surfaceless is unavailable (R:278–284).
- Requires GL 3.3, or GL 4.2 / `GL_ARB_texture_storage` (R:341–345).

Fences and bindings:
- Incoming fence: `glFenceSync` → `glFlush` → private context `glWaitSync` (R:531–547).
- Outgoing fence after `libra_gl_filter_chain_frame`, `glFlush`, then host restore, then `glWaitSync` (R:576–590). GPU-side waits only, no CPU wait (comment R:575).

Feedback and history: `clear_history` is passed to librashader (R:554). Engine sets `clearHistory` true on resize, output-shader toggle, reset, and load; it is cleared after a successful frame (E:1160). History is per output (one chain per output key).

### 4a. Parameters

| Behavior | Citation | Testable statement |
|---|---|---|
| Metadata is the union of all passes, last-pass-wins by name, sorted by name | R:~380–400 (`existing` search), R:~407 (sort) | Duplicate parameter names across passes appear once. |
| Metadata validated: finite min/max/step, `min≤max`, `step≥0`, default in range | R:378–381 | Invalid metadata fails the whole load with `Invalid shader metadata for parameter '…'`. |
| Overrides validated against metadata, unknown names rejected | R:~412–426 | Unknown override name → `Unknown shader parameter 'X'`. |
| Value read from chain (`get_param`), validated, override applied (`set_param`) | R:428–444 | Loaded value is the chain's value after overrides. |
| All chains must agree on each parameter value | R:440–442 | A mismatch between output chains fails the load. |
| Runtime `setParameter`: name lookup, validate, return early if unchanged (float compare), preflight `get_param` on all chains before any `set_param`, rollback on partial failure | R:466–505 | A failed set leaves every chain at its prior value (rollback loop R:494–498). |
| Range check on float cast | `ShaderParameter::validateValue` R:153–164 | Candidate outside `[minimum, maximum]` after float cast is rejected. |

---

## 5. Preset lifecycle

| Behavior | Citation | Testable statement |
|---|---|---|
| Request: monotonic `generation++`, `requested`, `pending`, `loading=true`, clear error, queue work, redraw, notify | E:777–788 | Each request invalidates earlier in-flight results. |
| Job start: only if display/context captured and stage present; overrides copied per path; output keys snapshot | E:790–819 | Load never starts before the first before-paint captures the EGL context. |
| Worker thread compiles with `ShaderRuntime::load(display, context, …)`; completion source attached from the worker | E:821–832 | Results are delivered by `g_source_attach` on the main context, not by polling. |
| Completion: join worker, stale-generation results discarded silently, HostContext switched to compositor context | E:843–850 | A superseded compile does not change `error` or `preset`. |
| Success: old runtime retired first; per-output retired/resources cleared (retained-by-runtime resources kept only for failed-output case); new runtime installed; `preset` set; `recent` MRU list max 10 updated; `lastParameters` copied; `error` cleared if `requested` matches; history flags reset | E:852–878, recent cap `maxRecentPresets=10` at E:56 | After success, `recentPresets[0]` equals the loaded path and length ≤ 10. |
| Failure: `error` set, runtime **kept**, `pending = preset` only if no runtime and the failing path differs | E:880–885 | A failed replacement keeps the previous working preset running. |
| Retry of previous preset when runtime was torn down by a reset during compile | E:884–885 | A failed compile after a reset rebuilds the last good preset. |
| Output failures cleared on successful completion for outputs with a view; a surviving output failure is re-applied to `error` | E:858–862, E:872–878 | Per-output bypass reasons persist across successful loads only if still failing. |

Settings restore (`import`): if the saved `preset` file is missing, the request fails asynchronously; monitor controls remain live (E:1443–1449, comment). Canonical path used when available (E:1441–1443) [line approx].

---

## 6. Threading, lifetime and release

| Rule | Citation | Testable statement |
|---|---|---|
| Owner thread captured at `Engine` construction; every public method checks it | E:420, E:452–455 | Calls from another thread raise `Native effect methods require the compositor main thread`. |
| Compile worker is a raw `std::thread`; reads `display`/`context` by value | E:821–832 | Worker never touches `Engine` state except `task` and `completion`. |
| Host context captured on before-paint and paint; mismatch throws | E:732–755 (`captureContext`), E:745–746 (sRGB state creation) | A context change after first capture raises `The GNOME compositor EGL share context changed`. |
| `HostContext` RAII switches to the compositor context for destruction and resets, then restores caller state (surface, API) | E:131–166 | Restoration failure is a `g_warning`, not an exception. |
| `GLBindings` RAII saves/restores GL bindings and scissor/sRGB state | E:168–195 | The effect never leaves a changed texture or FBO binding in Cogl's state. |
| Resource destruction (`Resources::~Resources`) deletes GL objects with the host context active | E:~320–332 / E:~355–360 | GL names created in the host context are deleted there. |
| `Output::detach` stops timeline, disconnects view-destroy handler, clears view ref | E:615–626 | Output detach never leaves a live `new-frame` handler. |
| `Engine::shutdown`: set `stopped`, disconnect stage hooks, remove idle sources, detach outputs, uninhibit cursor, join worker, destroy completion source, drop job/runtime/outputs/srgb/backend | E:933–966 | A second call returns immediately (E:935). |
| `dispose` calls shutdown; `finalize` deletes engine | E:1290–1301 | Engine memory is released in finalize, not dispose. |
| `ShaderRuntime::Impl::~Impl` frees chains under the private context if it can enter, otherwise logs and leaks (`cannot release shader objects`) | R:182–209 | After EGL display/context loss, chains are not freed. |
| Runtime destruction happens on the owner thread (`reset`, `completeLoad`, `shutdown`) | E:853, E:900, E:959 | Runtime is never destroyed on the worker. |
| `Engine::notify` is idle-deferred and re-entrancy-safe (ref/unref of `self` around emit) | E:546–571 | A status handler may drop the last reference safely. |

Lifetime of the stage: `attach(actor)` requires `CLUTTER_IS_STAGE` (E:~994) and connects `before-paint` and optionally `gl-video-memory-purged` (E:~1012–1028). `attach(nullptr)` detaches (E:968–983).

---

## 7. Error reporting

| Path | Citation | Testable statement |
|---|---|---|
| Synchronous API error → `GError` domain `wayland-shader-error`, code 1 | E:1219–1229 (`mutate`) | Every failed mutator sets `GError` with that quark and code 1. |
| Native exception in async completion → `Engine::fail` → `error` string + `status-changed` | E:509–523, E:~869–880 | `status.error` mirrors the last failure text. |
| Paint-time failure → `output.failure` → `bypass` + `fail` | E:1194–1207 | Output keeps raw scene until a relevant change clears `failure`. |
| Before-paint failure → `rendererFailed=true`, generation bump, error | E:1003–1014 | After renderer failure, all shader/color paths are disabled until shutdown. |
| Paint wrapper catch-all → `rendererFailed` | E:1247–1267 | Any uncaught paint exception disables the renderer. |
| Status JSON emitted only on change | E:552–556 | Identical consecutive status payloads are not re-emitted. |
| Librashader error text | R:35–41 | Message from `libra_error_write`, else `librashader failed (error N)`. |
| EGL error text | R:22–27 | Format `"<op> failed (EGL error 0xNNNN)"`. |
| GL error after pass | E:1045–1047, E:1189–1192 | Format `Stage color conversion failed (GL 0x…)`, `Stage presentation failed (GL 0x…)`. |

---

## 8. Qt dependencies (to drop)

| Qt item | Used in | Citation | Notes for port |
|---|---|---|---|
| `QString`, `QStringLiteral`, `QString::fromUtf8/toUtf8/fromLatin1/arg/isEmpty/clear/endsWith` | E, R, RH | E:61–77; R:22–37; RH:8 | Replace with `char*`/`GString`/Odin strings; `.arg` formats need manual `snprintf`. |
| `QList` | E:431 (lastParameters), R:179, RH:5 | | Dynamic array. |
| `QMap` | E (`savedOutputs`, `overrides`), R:412 (overrides param), RH:6 | E:~440; R:~412 | Ordered map by string key; order affects JSON key order. |
| `QSize` | RH:36 (`ShaderFrame::size`), E:1147 | | Two ints. |
| `QByteArray` | R:180, R:~347 (`path.constData()`), E:~433 (lastStatus) | | Byte buffer. |
| `QJsonDocument`, `QJsonObject`, `QJsonArray`, `QJsonParseError` | E:12–16, E:80–86, E:88–105, E:1342–1452 | | Needs a JSON library with object key order semantics. **Note:** QJsonObject key order is sorted; the port must preserve sorted output if byte-identical settings files are expected. [INFERENCE] |
| `QJsonArray::fromStringList`, `QStringList` (`contains`, `removeAll`, `prepend`, `mid`, `size`, `push_back`) | E:17–18, E:866–868, E:1366–1367, E:1417–1421 | | Recent-presets list semantics: MRU, max 10, dedupe. |
| `QSet<QString>` | E:17, E:1457–1466 (`ids`) | | Duplicate-ID detection. |
| `QFileInfo` (`isAbsolute`, `isFile`, `isReadable`, `canonicalFilePath`, `absoluteFilePath`) | E:1378 region (`QFileInfo file(preset)`), E:1504–1510 (`load_preset`), E:1420 (`recent`), R:313–316 | | Replace with `realpath`/`stat`/`access`. |
| `QDebug` (`qWarning().noquote()`, `qCritical().noquote()`) | R:50, R:72 | | Logging. |
| `QChar::Null`, `QLatin1Char`, `Qt::CaseInsensitive` | R:314 (`presetPath.contains(QChar::Null)`), R:24–26 (`QLatin1Char('0')`), E:1421 (`Qt::CaseInsensitive`) | | Explicit NUL check; `.slangp` suffix compare case-insensitively. |
| `qsizetype` | E:56 | | Alias for `ptrdiff_t`. |
| `QString(...).toUtf8().constData()` for exception messages | E:62–63 (`Failure`) | | Exceptions carry strings. |

Qt-free: `waylandshader-effect.h` (EH) and `output_settings.h` (OS) have no Qt includes. `shader_runtime.h` uses Qt types in its public API (RH:5–8, RH:17–61).

---

## 9. Observations for the port (factual, from these files)

| # | Observation | Citation | Impact |
|---|---|---|---|
| 1 | `export_settings` returns NULL on error; EH doc says `transfer full` with no NULL case. | E:1371–1375 vs EH:32–36 | Doc gap. |
| 2 | `set_outputs` requires `scale`; EH doc lists only IDs, names and geometry. | E:~1484 vs EH:49–54 | Doc gap. |
| 3 | librashader is patched: copy-to-source relies on the patch exposing mip levels only during generation. | E:370–376 (~); comment "patched librashader exposes them only while generating mipmaps" | Port must keep the patched librashader or reproduce behavior. |
| 4 | Compile worker runs `ShaderRuntime::load` with `shareContext` on another thread, creating its own shared context there. | E:821–832; R:302–339 | Port must keep a shared-context worker model or synchronize. |
| 5 | `Impl::~Impl` leaks GL chains (logs only) if the EGL context cannot be entered. | R:182–209 | Known limitation on context loss. |
| 6 | Shader copy comment says `GL_TEXTURE_MAX_LEVEL=0` after copy; the write happens after the blit. | E:370–376 | Mip behavior is delicate. |
| 7 | `set_parameter` during compile is rejected, while EH says edits are "retained and applied when the runtime is rebuilt". | E:1526 vs EH:81–88 | Behavior and doc differ for the compile window. [INFERENCE on intent] |
| 8 | Direct scanout is never named in code; the only inhibit API is `meta_backend_inhibit_hw_cursor`. | E:635, E:772; E:766–768 (comment) | Port must reproduce the full-redraw clip (E:997–1001) to keep filtered frames out of direct scanout. |

---

## 10. Not verified

- librashader C API header (`librashader.h`): signatures inferred from call sites only. [INFERENCE]
- Mutter/Clutter/Cogl headers: types and functions taken from call sites and the extern block (E:34–50).
- Patched librashader 0.10.1 behavior; claims about mip exposure rely on the comment at E:370–376.
- Elided spans not fully read: `HostContext` constructor (E:131–166 partly), `reset()` timeline body (E:900–913 partly), paint lines E:1085–1105 (partly), and `status()` body (~519–544).
- GIR generation, CMake, tests and Nix packaging: not inspected.
- No build or test was run (read-only assignment).

Ponytail footer: skipped the build files, GIR packaging, KWin files, and the librashader and Mutter headers; line numbers marked `~` are approximate. Risk: the port must reproduce the patched librashader mip behavior and the full-view redraw clip, or filtered output will break silently.