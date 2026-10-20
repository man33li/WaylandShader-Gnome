REJECT

| ID | Severity | REQ | File:line | Evidence | Required fix |
|---|---|---|---|---|---|
| A-01 | blocking | REQ-068; REQ-006 | `gnome/common/json_parse.odin:15–22,46–56,72–76,138–139`; `gnome/common/json.odin:16–32` | Independent calls to the baseline and port reproduce different accepted documents, error messages, and saved bytes. Examples: `{"version":1.}` is accepted by the baseline but rejected by Odin; `{"version":1,"ignored":1e-4000}` is rejected by the baseline but accepted by Odin; `\\u+123` inside a JSON string is rejected by the baseline but accepted by Odin. A raw LF inside a string is accepted by the baseline but rejected by Odin. An isolated `\\ud800` in a recent-preset path survives baseline export as `\\ud800`, but becomes U+FFFD in Odin. See the differential results below. The current passing parser tests do not establish the required Qt compatibility. | Fix the shared parser/decoder and, where necessary, its string representation/writer to preserve the baseline's actual semantics, including surrogate preservation and numeric underflow. Add these baseline-pinned cases to the common and native-contract tests; pin the differing errors too. Do not make the baseline stricter to match Odin. |
| A-02 | blocking | REQ-005, REQ-006, REQ-007 | `gnome/native/config.odin:159–167`; baseline `b223c1a:gnome/native/waylandshader-effect.cpp:1435–1441` | Restoring `{"version":1,"preset":"/tmp/ws-review-a-absent/../missing.slangp"}` produces `/tmp/missing.slangp` in the baseline's exported `preset`, status `preset`, and `requestedPreset`. Odin preserves `/tmp/ws-review-a-absent/../missing.slangp` in all three. This was reproduced headlessly on fresh objects, before any compile or EGL context. `restored := preset` is not equivalent to `QFileInfo(preset).absoluteFilePath()` when `realpath` fails. | Apply the baseline's lexical absolute-path normalization on the missing-file fallback while retaining `realpath` for existing files. Add a missing-preset import/export/status oracle with dot segments. |
| A-03 | blocking | REQ-061 | `gnome/glib/glib.odin:9–11`; `gnome/glib/gobject.odin:6,19–20`; `gnome/controller/gui/gtk.odin:18–28`; `gnome/native/abi-check.c:14–48` | The required dual ABI checks are incomplete. The concrete `GList` and `GObject` mirrors have no Odin size assertions and no corresponding C `SIZE(GList, ...)` / `SIZE(GObject, ...)` assertions. The GUI also duplicates concrete `GError`/`GList` layouts without its own Odin assertions. Both build targets pass because these mirrors are omitted, not because every mirror has been checked. This is an assertion-coverage defect, not a claim that their current x86-64 layouts are wrong. | Add the missing Odin and real-header C layout checks for every concrete mirror, or reuse the already-checked shared mirror where appropriate. Include accessed offsets. Keep opaque handle declarations opaque; they do not need invented object layouts. |
| A-04 | blocking | REQ-027–034, REQ-045–054, REQ-060 | `docs/waterfall/01-requirements/requirements.md:176–179`; `docs/waterfall/02-design/design.md:530–555`; `docs/waterfall/03-implementation/build-log.md:275–276` | Required T-ISO-RENDER and full T-GUI acceptance remain unperformed. I reproduced the isolated CLI/bypass tests and the real GTK precision test, but those do not observe post-paint pixels, small-damage coverage, cursor balancing, color-only idle behavior, chooser/recent interactions, debounce, accessibility, or app_id. The build log explicitly marks both checklists pending. The waterfall gate permits acceptance only on passing tests (`docs/waterfall/README.md:12`). | Complete and record both specified checklists against a disposable Shell/private bus. Resolve the private viewer/capture limitation without using the live compositor as a substitute. Hardware T-HW is explicitly post-acceptance and is not part of this blocker. |
| A-05 | major | REQ-063 | `gnome/native/native_test.odin:29–47`; `gnome/native/paint.odin:174–180`; `gnome/runtime/gltest/main.odin:105–115` | The measured allocation checks cover `frame_timing`, `select_output`, and `runtime.render`. They do not execute the `before-paint` output loop. Therefore the tests cannot catch an allocation added to that fourth named hot path. Static inspection finds no allocation in the current loop itself; no actual per-frame allocation is alleged. | Add a mechanical zero-heap/zero-temp allocation check exercising the actual warmed output-loop logic, without resetting away the tracking allocators at the C-entry boundary. Retain the existing size and render checks. |

## Reviewed revision and scope

`git rev-parse --short HEAD` returned **94656d9**. Baseline: **b223c1a**. The requirements, selected design and decision, implementation log, changed production components, relevant original C++ paths, tests, build definitions and documentation were reviewed. Accepted deviations D1/D2 are not findings.

The review built a fresh external CMake tree at `/tmp/ws-review-a-build` and independently invoked both Nix package builds. The GNOME invocation actually built a derivation and executed checkPhase; this was not just a cached result lookup. Its result was:

```text
/tmp/ws-review-a-result -> /nix/store/ffybgfharjdjpkzvarw0bvjd937dmqfs-waylandshader-gnome-0.1.0
/tmp/ws-review-a-kwin   -> /nix/store/3jf7jj0ri7bgws68nkxk4v4bsmb7f39d-waylandshader-0.1.0
```

All **13/13** registered headless tests passed both in Nix and in the independent build tree. GL 4.6 and GL 3.3 executed, neither skipped. The installed GIR, file layout, ELF checks and GTK chooser-schema check passed. All 106 CLI goldens also passed against the actual baseline binary, not merely against the new binary. T-BYPASS and the baseline-versus-Odin isolated CLI transcript comparison passed. These successes do **not** erase the independently reproduced counterexamples in A-01/A-02.

No production source, fixture, baseline golden, requirements or design artifact was changed by this review. The only repository file written is this report. Builds and existing tests created their normal external temporary artifacts.

## Differential counterexamples

Both sides were called through their installed GI module using a fresh `WaylandShader.Effect.new()`, `import_settings(source)`, and `export_settings()`. These objects were not attached to a compositor and no D-Bus calls were made. The command deliberately caught and printed each GError, so process exit 0 means the **probe completed**, not that compatibility passed.

| Input / observation | Baseline b223c1a | Odin 94656d9 |
|---|---|---|
| `{"version":01}` | `unterminated object` | `illegal number` |
| `{"version":1.}` | Accepted, exports version 1 | `illegal number` |
| `{"version":1e0}` | Accepted | Accepted (control case) |
| `{"version":1,"ignored":1e-4000}` | `illegal number` | Accepted |
| `{"version":1,"ignored":1e4000}` | `illegal number` | `illegal number` (control case) |
| `{"version":1,"recent_presets":["/x\ud800.slangp"]}` | Exports recent path as `"/x\ud800.slangp"` | Exports `"/x�.slangp"` |
| `{"version":1,"ignored":"a<raw LF>b"}` | Accepted | `unterminated string` |
| `{"version":1,"ignored":"\u+123"}` | `invalid escape sequence` | Accepted |
| `{"version":1,"ignored":"\u 123"}` | `invalid escape sequence` | Same (control case) |
| `{"version":1,"ignored":"\ué123"}` | `invalid escape sequence` | Same (control case) |
| `{}x`, `{}:` | `garbage at the end of the document` | Same (control cases) |
| `{"version":}` | `object is missing after a comma` | `illegal value` |
| `[1e]` | `illegal number` | Same (control case) |
| `[01]` | `missing value separator` | `illegal number` |
| `{"version":1,"ignored":truefalse}` | `unterminated object` | `illegal value` |

A-02's independent path probe returned:

```text
baseline export:
{"enabled":true,"outputs":{},"parameters":{},"preset":"/tmp/missing.slangp","recent_presets":[],"version":1}
Odin export:
{"enabled":true,"outputs":{},"parameters":{},"preset":"/tmp/ws-review-a-absent/../missing.slangp","recent_presets":[],"version":1}
```

In each status, `loading` was true and both `preset` and `requestedPreset` contained the corresponding path above. Thus the discrepancy does not depend on eventual compilation timing.

## Requirement-by-requirement evidence

**Pass** below means the named bounded checks passed and the cited implementation was inspected; it is not a claim of exhaustive proof. **Partial** names material unexercised branches. **Pending** means a named acceptance observation is absent. **Fail** refers to a finding above. Every REQ ID is accounted for; post-acceptance hardware work is kept separate.

| REQ | Implementation / contract evidence | Independently exercised evidence and result |
|---|---|---|
| REQ-001 | `gnome/native/effect.odin:10–40`; `gnome/native/config.odin:257–309` | Pass: T-GIR byte diff, T-UNCHANGED, exact 15-symbol T-ELF. |
| REQ-002 | `gnome/CMakeLists.txt:27–46` | Pass: T-ELF, installed SONAME/NEEDED/export set and successful no-undefined link. |
| REQ-003 | `gnome/native/effect.odin:14–27,43–68` | Partial: T-LIFE/T-CONTRACT exercise successful owned construction; allocation failure and rejected-parent-layout branches were not fault-injected. |
| REQ-004 | `gnome/native/effect.odin:72–79` | Partial: normal compact status passes T-CONTRACT; native status-construction failure/fallback not fault-injected. |
| REQ-005 | `gnome/native/config.odin:18–35` | Fail A-02 for fixed-input path bytes. Fixed ordinary/non-ASCII status fixtures pass T-CONTRACT; isolated transcript also matches. |
| REQ-006 | `gnome/native/config.odin:43–63,102–170` | Fail A-01/A-02. Ordinary export fixtures, recents and isolated parameter/profile restoration pass. |
| REQ-007 | `gnome/native/config.odin:102–170,265–270` | Fail A-02 for missing-path restoration representation. T-CONTRACT covers object/version/relative-path/compiling validation; not all renderer-failure import paths were exercised. |
| REQ-008 | `gnome/native/config.odin:172–215` | Pass within T-CONTRACT/T-UNIT-NATIVE cases: missing scale, duplicate id, fractional geometry and zero width. Bounds/read-settings code inspected. |
| REQ-009 | `gnome/native/config.odin:217–224`; `gnome/native/engine.odin:240–287` | Pass: real asynchronous load in T-BYPASS/T-ISO-CLI; relative-file rejection in T-CONTRACT. No native suffix restriction added. |
| REQ-010 | `gnome/native/config.odin:226–242`; `gnome/native/engine.odin:346–363` | Pass: unchanged T-LIFE and real T-BYPASS edit/rebuild preservation. |
| REQ-011 | `gnome/native/config.odin:227–242`; `gnome/runtime/runtime.odin:196–217` | Pass for live/bypassed bounds, unknown parameter and retention: T-BYPASS/T-GL/T-CONTRACT. Partial setter rollback failure is not induced. |
| REQ-012 | `gnome/native/config.odin:244–254,294–307` | Pass for contract bounds/unknown-output and ordinary per-output mutations; T-ISO-CLI matches baseline. Visual independence remains T-ISO-RENDER pending. |
| REQ-013 | `gnome/native/engine.odin:346–398`; `gnome/native/effect.odin:83–104` | Partial: stopped mutators, idempotent shutdown and normal lifecycle pass; full stage detach/reset/visual cleanup checklist pending. |
| REQ-014 | `gnome/native/engine.odin:73–97` | Pass for idle deferral/coalescing/reentrant status/unchanged suppression in T-CONTRACT. Owner non-default-main-context behavior was inspected, not separately driven. |
| REQ-015 | `gnome/native/engine.odin:58–66`; `gnome/native/native_test.odin:49–62` | Pass: actual worker-thread `engine_check` error, stopped error and exported stopped-mutator contract. Getter/shutdown exceptions match original entry-point structure (`b223c1a:gnome/native/waylandshader-effect.cpp:1342–1375,1611–1620`). |
| REQ-016 | `gnome/native/boundary.odin:30–50` | Partial: T-CONTRACT confirms GError domain/code/messages on failed mutators; native NULL/invalid-UTF8 C-string arguments are not supplied by that GJS test. |
| REQ-017 | `gnome/native/config.odin:85–100,149–153`; `gnome/native/engine.odin:329–337` | Pass for ordinary recent ordering/filter/dedup/cap and successful/failed load behavior: T-RECENT/T-BYPASS/T-ISO-CLI. A-01 additionally exposes surrogate data loss in imported history. |
| REQ-018 | `gnome/native/engine.odin:240–295,313–344` | Partial: real worker load, failed replacement preservation and settings restoration pass T-GL/T-ISO-CLI. Rapid replacement/stale-generation/reset-during-compile behavior was inspected but not independently stress-driven. |
| REQ-019 | `gnome/runtime/runtime.odin:250–265` | Partial: ordinary owner-side destruction passes real-GL tests and literal safety check passes T-BAN. Failure to enter the destruction context was not induced. |
| REQ-020 | `gnome/runtime/runtime.odin:136–190,237–241`; `gnome/runtime/libra.odin:9–25` | Pass: T-GL/T-GL33 real temporal/LUT/mipmap/parameter pixels plus options/MVP inspection and ABI compilation. |
| REQ-021 | `gnome/runtime/runtime.odin:146–184,196–217` | Partial: real GAIN/unknown-name/bounds and multi-chain values pass T-GL; malformed metadata, mismatched chains and forced partial setter failures lack exercised cases. |
| REQ-022 | `gnome/runtime/runtime.odin:47–87,128–134`; `gnome/native/engine.odin:211–225` | Partial: normal/robust host contexts and GL 3.3 pass; GLES, GLX, changed-host and pbuffer-fallback rejection/restoration paths not individually induced. |
| REQ-023 | `gnome/runtime/runtime.odin:225–247` | Pass for real-GL frames and static two-direction fence/flush/wait inspection; T-BAN finds no forbidden CPU waits. A failing frame's fence path was not injected. |
| REQ-024 | `gnome/runtime/egl.odin:74–89`; `gnome/native/paint.odin:33–49,131–151` | Partial: T-GL checks host context/viewport. Complete display/API/draw/read/state restoration on every failure exit and stage-side state need additional observation/fault cases. |
| REQ-025 | `gnome/runtime/egl.odin:58–59`; `gnome/runtime/libra.odin:45–56`; `gnome/native/paint.odin:51,153–158,264` | Pass for formatters in T-UNIT-NATIVE and real failed replacement in T-GL/T-ISO-CLI. All possible EGL/GL error codes were not forced. |
| REQ-026 | `gnome/runtime/gltest/main.odin:52–123,124–166` | Pass: T-GL/T-GL33 use real readback pixels, two output keys, two cycles, robust/nonrobust hosts and generated LUT/base-level fixtures. This is not a mocked renderer. |
| REQ-027 | `gnome/native/effect.odin:107–112`; `gnome/native/engine.odin:400–421` | Pending A-04: stage attach works in isolated tests, but the full T-ISO-RENDER detach/purge checklist is not complete. |
| REQ-028 | `gnome/native/engine.odin:167–209` | Pending A-04: two virtual outputs work; inactive/tiled/shared-CRTC/mismatch/view-destroy branches were not all reproduced. |
| REQ-029 | `gnome/native/paint.odin:174–196` | Pending A-04: full-view and matching-view/frame/framebuffer guards inspected; no independent small-damage post-paint observation. |
| REQ-030 | `gnome/native/paint.odin:58–76,100–151,198–265` | Partial/pending A-04: runtime FP16/base-level test passes; actual Cogl color pipeline/HDR/identity/presentation not visually verified. |
| REQ-031 | `gnome/native/paint.odin:10–19,123–128,251–258` | Pass for snippet bytes in T-UNIT-NATIVE; visual gamma/saturation/alpha behavior remains A-04. Uniform change guards inspected. |
| REQ-032 | `gnome/native/paint.odin:160–169,234–249`; `gnome/native/engine.odin:141` | Pass for pure clock cases and zero-allocation checks in T-UNIT-NATIVE; stage resize/toggle/reset/load timing observations remain partial. |
| REQ-033 | `gnome/native/engine.odin:68–70,142–165`; `gnome/native/paint.odin:184–190` | Pending A-04: activity status matches baseline in T-ISO-CLI; idle animation, resource absence and balanced cursor inhibition not fully observed. |
| REQ-034 | `gnome/native/paint.odin:173–180,195,198–203`; `gnome/native/engine.odin:122–125` | Pending A-04: failure isolation/restore logic inspected; no injected output-local paint or before-paint failure. |
| REQ-035 | `gnome/extension/extension.js:10–230` (protected baseline content) | Pass: T-UNCHANGED plus isolated effect/D-Bus lifecycle. |
| REQ-036 | `gnome/extension/extension.js:59–61,114–122` | Pass: baseline and Odin T-ISO-CLI restoration transcripts match after extension disable/reactivation. |
| REQ-037 | `gnome/controller/client/client.odin:63–106,149–212,259–307` | Partial: real asynchronous private-bus calls and disconnection after extension disable pass T-ISO-CLI. Shell-name replacement and deliberately stale pending replies were not separately injected. |
| REQ-038 | `gnome/controller/client/client.odin:43–54,138–147,162–168` | Pass: classification/false/malformed boolean units and 106 real-baseline CLI goldens; ordinary shader rejection also passes isolated CLI. |
| REQ-039 | `gnome/controller/client/status.odin:31–128` | Pass for the status rejection/range/uniqueness fixture matrix in T-UNIT-CLIENT; shared parser still fails REQ-068 (A-01). |
| REQ-040 | `gnome/controller/client/client.odin:108–109,186–257`; `gnome/controller/ctl/main.odin:181–187` | Pass for read-only nonactivation and mutation activation/restoration in T-ISO-CLI; not every intermediate activation state was induced. |
| REQ-041 | `gnome/controller/ctl/args.odin:58–274` | Pass: T-UNIT-CTL and all 106 CLI goldens independently checked against both baseline and Odin. |
| REQ-042 | `gnome/controller/ctl/args.odin:177–227,277–367`; `gnome/controller/ctl/main.odin:241–263` | Pass: argument/numeric/file/selector units, goldens, and real unknown-selector usage exit in T-ISO-CLI. |
| REQ-043 | `gnome/controller/ctl/main.odin:82–105,122–178` | Pass for success/rejection/usage/unavailable/overall deadline: goldens and isolated CLI. Per-call 10 s timeout code inspected; not independently delayed past 10 s. |
| REQ-044 | `gnome/controller/ctl/main.odin:108–147,190–238,265–309` | Pass: full deterministic baseline-vs-Odin isolated transcript including arrays, successful mutation output and load completion. |
| REQ-045 | `gnome/controller/gui/controller.ui:15–220` | Pending A-04: XML title/size/text inspected, no complete T-GUI visual comparison. |
| REQ-046 | `gnome/controller/gui/window.odin:435–482` | Partial/pending A-04: installed GTK file-chooser schema is present; no chooser cancel/select/initial-location observation. |
| REQ-047 | `gnome/controller/gui/window.odin:412–432,810–835`; `gnome/controller/gui/view.odin:68–83` | Partial: pure load validation units pass; actual Return/button/edit behavior needs T-GUI. |
| REQ-048 | `gnome/controller/gui/window.odin:634–660,802–807` | Pending A-04: recent-menu text/fill/no-load/focus behavior inspected, not interacted with. |
| REQ-049 | `gnome/controller/gui/window.odin:333–351,663–670,731–737,844–853` | Pending A-04: startup/reconnect and pending-enable code inspected; GUI interactions not exercised end-to-end. |
| REQ-050 | `gnome/controller/gui/window.odin:183–312,386–401`; `gnome/controller/gui/view.odin:15–32` | Partial: state-label precedence units pass; real pending monitor-control/tooltip behavior awaits T-GUI. D1 excluded. |
| REQ-051 | `gnome/controller/gui/window.odin:62–70,100–110,873–878,944–965` | Partial: pure round2 tests and explicitly enabled real GTK selfcheck pass; full Enter/focus-out GUI commits not observed. |
| REQ-052 | `gnome/controller/gui/window.odin:19–59,519–627,679–687,766–799`; `gnome/controller/gui/view.odin:102–213` | Partial: f32 round trips, bounds/step presentation and real tiny/subnormal GTK input pass; debounce/focus/schema-change/stale-reply interactions await T-GUI. D2 excluded. |
| REQ-053 | `gnome/controller/gui/view.odin:36–63`; `gnome/controller/gui/window.odin:315–361,698–705` | Partial: summary/state pure units pass; rejection/disconnection control sensitivity not fully observed in GUI. |
| REQ-054 | `gnome/controller/gui/window.odin:880–890`; `gnome/org.waylandshader.GnomeController.desktop:5–9` | Partial: desktop file unchanged; closing-effect retention and actual Wayland app_id remain T-GUI pending. |
| REQ-055 | `gnome/default.nix:6–7,61–73`; `gnome/CMakeLists.txt:10–12,87–124` | Pass: fresh Nix build ran all 13 checks; guards retained. |
| REQ-056 | `gnome/CMakeLists.txt:126–144` | Pass: installed relative path sets identical to baseline. |
| REQ-057 | `gnome/CMakeLists.txt:2,42–58`; `gnome/tests/ban-check.sh` | Pass: T-BAN and installed T-ELF; no native C++ source or direct Qt/libstdc++ dependency in the three GNOME ELF payloads. |
| REQ-058 | Protected paths listed in T-UNCHANGED | Pass: protected diff empty and independent `nix-build default.nix` actually built KWin successfully. |
| REQ-059 | `gnome/default.nix:4–7`; `gnome/CMakeLists.txt:7–14`; unchanged `shader-library.nix`/`patches/` | Pass: Nix/build ABI versions, T-UNCHANGED and private librashader NEEDED in installed ELF. |
| REQ-060 | `gnome/native/exports.map`; unchanged extension/schema/desktop; CLI parser and GUI layout | Partial/pending A-04: no extra export/D-Bus/schema/CLI feature found; GUI controls reviewed statically, full GUI comparison pending. |
| REQ-061 | `gnome/native/abi-check.c:14–80`; `gnome/native/effect.odin:14–27`; mirror declarations cited in A-03 | Fail A-03: existing assertions compile, but not every concrete mirror is asserted. Runtime guard normal branch exercised by GI loading. |
| REQ-062 | `gnome/native/boundary.odin:18–50`; native exports/callbacks | Partial: T-BAN and ordinary error contracts pass; C-entry contexts/temp guards and GLib-return ownership inspected. Allocation failure across all native mutators was not fault-injected. |
| REQ-063 | `gnome/native/engine.odin:12–14`; `gnome/native/native_test.odin:29–47`; `gnome/runtime/runtime.odin:12–14`; `gnome/runtime/gltest/main.odin:105–115` | Partial A-05: sizes compile and measured timing/selection/render loops have zero allocation delta; before-paint loop has no mechanical allocation test. |
| REQ-064 | `gnome/CMakeLists.txt:27` | Pass: GL_DEBUG=false in real builds, T-BAN. |
| REQ-065 | `gnome/tests/isolated-session.sh:8–44,55–74` | Pass for this review: guard refusal exercised before any Shell-hosted check; all Shell-hosted commands used the harness. No live extension/module installation or live-bus mutation performed. |
| REQ-066 | `README.md:231–248`; `docs/GNOME.md:223–287,314` | Pass for source review: Odin/GTK build/dependencies/test descriptions and principal catalog build recipes match. Remaining terminology hits describe KWin, baseline or history, not a GNOME Qt build requirement. |
| REQ-067 | `docs/waterfall/01-requirements/requirements.md:131,182` | Deferred by contract: user-only fresh-login physical display/AMD/HDR/hotplug/suspend check, after acceptance. Not counted as passed or as a blocker. |
| REQ-068 | `gnome/common/json_parse.odin:9–152` | Fail A-01: baseline-pinned catalog subset passes, broader directly reproduced documents disagree. |

## Commands run

Paths below use these shorthands for readability: `B=/tmp/ws-review-a-build`, `R=/tmp/ws-review-a-result`, `BASE=/tmp/ws-baseline-result`, `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com`. Executed commands used the corresponding literal paths. All commands ran from the repository root. Read/grep navigation is excluded from this execution table.

| ID / tests | Command | Result |
|---|---|---|
| C01 / identity | `git rev-parse --short HEAD` | Exit 0, `94656d9`. |
| C02 / T-NIX | `nix-build gnome/default.nix -o /tmp/ws-review-a-result` | Exit 0, actual package build/checkPhase; **13/13** passed, no skips, 7.52 s CTest time. |
| C03 / T-KWIN | `nix-build default.nix -o /tmp/ws-review-a-kwin` | Exit 0, actual KWin compile/link/install. |
| C04 / T-UNCHANGED | `git diff --exit-code b223c1a -- gnome/extension gnome/org.waylandshader.GnomeController.desktop gnome/native/waylandshader-effect.h gnome/tests/effect-lifecycle.js gnome/tests/recent-presets.js gnome/tests/parameter-bypass.js src tests CMakeLists.txt default.nix shell.nix shader-library.nix patches` | Exit 0, empty diff. |
| C05 / independent build, T-ABI and all headless CTest entries | `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-review-a-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-review-a-build --parallel 2 && cmake --build /tmp/ws-review-a-build --target gnome_abi_check gnome_native && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/ws-review-a-build --output-on-failure'` | Exit 0, **13/13**, no skips, 36.94 s CTest time. This includes T-LIFE, T-RECENT, port T-CONTRACT, T-UNIT-COMMON/NATIVE/CLIENT/CTL/GUI, T-GL, T-GL33, T-CLI-GOLDEN, build-tree T-ELF and T-BAN. |
| C06 / installed T-ELF | `nix-shell gnome/shell.nix --run 'gnome/tests/elf-check.sh /tmp/ws-review-a-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so /tmp/ws-review-a-result/bin/.waylandshader-gnomectl-wrapped /tmp/ws-review-a-result/bin/.waylandshader-gnome-controller-wrapped'` | Exit 0. |
| C07 / T-GIR, T-LAYOUT | `diff "$BASE/$EXT/native/WaylandShader-1.0.gir" "$R/$EXT/native/WaylandShader-1.0.gir" && diff <(find -L "$BASE" -printf '%P\n' \| sort) <(find -L "$R" -printf '%P\n' \| sort)` | Exit 0, no differences. `find -L` compares relative installed paths through both result symlinks. |
| C08 / baseline T-CONTRACT | `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native'` | Exit 0, `Native byte/error contract passed.` |
| C09 / T-SAFETY refusal | `env WS_PRIVATE_ROOT=/tmp/ws-review-refusal XDG_RUNTIME_DIR=/tmp/ws-review-refusal/runtime WS_CALLER_RUNTIME=/tmp/ws-review-caller WS_CALLER_BUS=unix:path=/tmp/ws-review-a-refusal DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ws-review-a-refusal sh gnome/tests/isolated-session.sh --private-child true` | Expected exit **1**, `refusing caller bus or runtime directory`; execution stops before any gsettings/Shell command. Uses synthetic equal addresses, not a live-bus operation. |
| C10 / T-BYPASS | `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | Exit 0; `PASS: bypassed edits remain inactive, reject invalid values, and survive the real GPU-runtime rebuild.` Disposable Shell shut down. Ancillary private desktop services emitted environmental startup/shutdown warnings. |
| C11 / T-ISO-CLI | Sequential baseline and Odin harness runs, each piped to its own `tee` log under `set -o pipefail`, then `diff /tmp/ws-review-a-cli-baseline.log /tmp/ws-review-a-cli-odin.log` (full command below) | Both runs and final diff exit 0; deterministic transcripts identical, including failed replacement and restore/reactivation. |
| C12 / baseline CLI oracle | `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit 0, `cli-golden: 106 cases match`. No golden was recaptured or modified. |
| C13 / wrapper inspection | `strings /tmp/ws-review-a-result/bin/waylandshader-gnome-controller` | Exit 127 outside the Nix shell: command unavailable. Not counted as a pass. |
| C14 / T-WRAP | `nix-shell gnome/shell.nix --run 'strings /tmp/ws-review-a-result/bin/waylandshader-gnome-controller'`, then `test -f /nix/store/6ipigl0rqnc2vrqf7y3y9gz6b3nrdcrq-gtk+3-3.24.52/share/gsettings-schemas/gtk+3-3.24.52/glib-2.0/schemas/org.gtk.Settings.FileChooser.gschema.xml` | Both exit 0. Binary wrapper contains that GTK 3 schema directory in its XDG_DATA_DIRS prefix; schema file exists. Wrapper itself was not launched on the live bus. |
| C15 / real GTK S3 precision | Nested Nix/Xvfb/private-D-Bus command below, with `WS_GTK_SPIN_SELFCHECK=true` and only `main.spin_commit_selfcheck` selected | Exit 0, **1 actual test** successful. Tiny/subnormal values and two-decimal gamma input exercised. Environmental GTK module/accessibility-service warnings did not fail the test. |
| C16 / adversarial JSON differential | Native GI probe below, once with baseline native paths and once with Odin native paths | Both probes exit 0; compatibility comparison **FAILS** as detailed in A-01. |
| C17 / adversarial missing-path differential | Same native GI environment, fresh object, `import_settings(JSON.stringify({version:1,preset:"/tmp/ws-review-a-absent/../missing.slangp"}))`, then print `export_settings()` and `get_status()` and shutdown; baseline and Odin separately | Both probes exit 0; byte comparison **FAILS**, A-02. |
| C18 / T-DOCS | Tool-equivalent search for `Qt\|QFileDialog\|C\+\+\|libepoxy` in `README.md` and `docs/GNOME.md`, followed by review of hits and relevant recipes | Reviewed: hits concern KWin, original baseline or dated history/contrast. No GNOME Qt build recipe found. |

C11's executed pipeline (stdout only goes to the comparison logs; harness/service diagnostics remain stderr):

```sh
set -o pipefail && \
nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- gnome/tests/iso-cli.sh /tmp/ws-baseline-result/bin/waylandshader-gnomectl' | tee /tmp/ws-review-a-cli-baseline.log && \
nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-result -- gnome/tests/iso-cli.sh /tmp/ws-review-a-result/bin/waylandshader-gnomectl' | tee /tmp/ws-review-a-cli-odin.log && \
diff /tmp/ws-review-a-cli-baseline.log /tmp/ws-review-a-cli-odin.log
```

C15:

```sh
nix-shell -p xvfb-run --run 'nix-shell gnome/shell.nix --run '\''xvfb-run -a dbus-run-session -- env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 odin test gnome/controller/gui -define:WS_GTK_SPIN_SELFCHECK=true -define:ODIN_TEST_NAMES=main.spin_commit_selfcheck -define:ODIN_TEST_THREADS=1 -define:GL_DEBUG=false -out:/tmp/ws-review-a-spin "-extra-linker-flags:$(pkg-config --libs-only-L gtk+-3.0 gio-2.0)"'\'''
```

C16/C17 native GI invocation used this environment pattern for each package, inside `nix-shell gnome/shell.nix --run`:

```sh
export GI_TYPELIB_PATH="<PACKAGE>/$EXT/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH"
export LD_LIBRARY_PATH="<PACKAGE>/$EXT/native:$LD_LIBRARY_PATH"
gjs -c '<probe body>'
```

Here `<PACKAGE>` was `/tmp/ws-baseline-result` or `/tmp/ws-review-a-result`; `$EXT` was expanded to its literal path in the executed commands. C16's JavaScript body, shown unquoted for readability, was:

```js
const e = imports.gi.WaylandShader.Effect.new();
for (const s of [
    '{"version":01}',
    '{"version":1.}',
    '{"version":1e0}',
    '{"version":1,"ignored":1e-4000}',
    '{"version":1,"ignored":1e4000}',
    '{"version":1,"recent_presets":["/x\\ud800.slangp"]}',
    '{"version":1,"ignored":"a\nb"}',
    '{"version":1,"ignored":"\\u+123"}',
    '{"version":1,"ignored":"\\u 123"}',
    '{"version":1,"ignored":"\\ué123"}',
    '{}x', '{}:', '{"version":}', '[1e]', '[01]',
    '{"version":1,"ignored":truefalse}',
]) {
    try {
        e.import_settings(s);
        print(JSON.stringify(s) + ' => ' + e.export_settings());
    } catch (x) {
        print(JSON.stringify(s) + ' => ERROR ' + x.message);
    }
}
e.shutdown();
```

## Limits and disposition

No live extension installation/enabling, live module load, compositor restart, or mutating live-session-bus call was performed. The isolated harness's equality refusal was tested before using it. The direct GI probes are headless object tests, not Shell-hosted tests.

Not checked: full T-ISO-RENDER/T-GUI observation, physical hardware T-HW, and the explicitly identified fault-injection/race branches. T-HW belongs after acceptance; the missing GUI/render acceptance does not. The current automated suite is valuable but has real compatibility false negatives, and absent ABI/hot-path checks weaken its stated safety coverage.

REJECT — blocking findings A-01 (JSON compatibility/data preservation), A-02 (restored-path bytes), A-03 (required ABI checks omitted), and A-04 (required render/GUI acceptance missing).

## Round 2

REJECT

| ID | Severity | REQ | File:line | Evidence | Required fix |
|---|---|---|---|---|---|
| R2-A-01 | blocking | REQ-068 | `gnome/common/json_parse.odin:21–29,200–206`; missing case in `gnome/common/json_parse_test.odin:9–58` | The replacement scanner no longer accepts a leading UTF-8 byte-order mark (BOM). `import_settings("\ufeff{\"version\":1}")` succeeds on baseline b223c1a and on the independently retained round-1 Odin package, but 88c69ec raises `wayland-shader-error: illegal number`. The same assertion exits 0 on both controls and 1 on the new package. BOM-prefixed `[]` reaches `Configuration must be a JSON object` on the baseline, but fails parsing with `illegal number` on the new package. This is a newly introduced acceptance regression, not an authorized deviation. | Restore the baseline's handling of an initial UTF-8 BOM in the shared parser. Add baseline-pinned import and output-inventory cases, and a common parser regression. Preserve the required distinction between an initial BOM and an unexpected character elsewhere. |
| R2-A-02 | blocking | REQ-068 | `gnome/common/json_parse.odin:36–49,145,166,189,207–209` | End-of-document error precedence still differs from Qt. Baseline rejects `{}"` and `{}tru` with `garbage at the end of the document`. The new scanner instead returns `unterminated string` and `illegal value`, respectively. Completing the root container eagerly scans the trailing token and propagates its lexical error before the final trailing-content check. Both differences were reproduced independently against the installed baseline and installed rework package. | After a complete root value, reproduce Qt's trailing-content detection/error precedence rather than exposing the contents of a malformed trailing token. Add these exact baseline-pinned cases while retaining nested-string, malformed-literal, separator, and EOF errors. |

### Revision, ruling and independently observed results

Reviewed HEAD: **88c69ec**, from `git rev-parse --short HEAD`. The review follows the seven numbered rework items in `acceptance.md:178–188`. Per the main reviewer's explicit ruling at `acceptance.md:11`, **A-04 is not an acceptance blocker**: manual render/GUI/hardware and safety/docs sign-off remain deferred, not passed. That ruling supersedes Round 1's A-04 classification without rewriting the historical review. D1/D2 remain accepted.

Both Nix commands actually built their derivations. The GNOME build ran **13/13 CTest entries, no failures and no skips**, including real GL/GL33 and the expanded 107-case CLI comparison. An independent external CMake build ran the same 13 entries successfully. Build products:

```text
/tmp/ws-review-a-r2-result -> /nix/store/ywyrarmhrk5mpmq09fnj07ncwwb448lh-waylandshader-gnome-0.1.0
/tmp/ws-review-a-r2-kwin   -> /nix/store/wsr8a4prijih9xrwgrq7sjki9jpr3mx3-waylandshader-0.1.0
```

Those green suites are real results, but they miss R2-A-01/R2-A-02. Neither the baseline goldens nor the reviewed production sources were modified during this review. Deliberate negative controls were performed only in an owned `/tmp` copy and removed after restoring and testing that copy. The only repository file changed by this review is this appended report section.

### Rework disposition

| Rework item | Independent reproduction and inspection | Round-2 disposition |
|---|---|---|
| **A-01 — parser/string compatibility** | The expanded `native-contract.js` passes against both the actual baseline and installed rework library. Its `reworkCases`/`observeImport` path calls the real native API and compares exact captured exports/errors; capture mode was not used. The previous trailing-decimal, underflow/overflow, signed Unicode escape, raw-newline, separator, high/low surrogate and surrogate-ordering examples now match (`gnome/tests/native-contract.js:61–100,127–132`; `gnome/common/json_parse.odin:67–131`; `gnome/common/json.odin:15–37`). | **Original reproduced cases fixed; REQ-068 still fails** because the new scanner introduces BOM rejection and retains trailing-garbage error differences, R2-A-01/R2-A-02. |
| **A-02 — missing-path normalization** | Expanded native contract runs independently against baseline and port, checking export plus status `preset`/`requestedPreset`/`loading` for all three non-clean missing paths, including excess root-level `..` (`gnome/tests/native-contract.js:84–104`). `clean_absolute` is the production fallback and realpath remains the existing-file path (`gnome/native/config.odin:102–120,178–187`). | **Fixed for all requested reproductions.** |
| **A-03 — omitted ABI checks** | Inspected shared GList/GObject assertions, GUI shared aliases and assertions, and real-header C assertions (`gnome/glib/glib.odin:9–12`; `gnome/glib/gobject.odin:19–22`; `gnome/controller/gui/gtk.odin:20–26`; `gnome/native/abi-check.c:16–32`). Positive production builds compile the C gate and consuming native/controller/runtime code. Deliberately changing copied C GList size 24→25 fails its real-header assertion. Changing the copied shared Odin assertion 24→25 independently fails native, GUI, CLI and runtime object builds at that assertion. | **Fixed; both sides of the gate can fail.** No present-layout mismatch alleged. |
| **A-05 — before-paint allocation coverage** | The real callback calls production `before_paint_output`; tests call that same helper with shader/color, nil/missing and inactive cases under both counters (`gnome/native/paint.odin:174–184`; `gnome/native/native_test.odin:29–75`). In the copied production loop, an injected heap allocation makes the unchanged test fail with `heap_delta=1400`; replacing it with a temp allocation fails with `temp_delta=1400`. Removing the injection restores a pass. The opaque identity pointers are only compared and never passed to FFI. | **Fixed; independent negative controls prove the new regression is not a tautology and the C-entry context reset does not hide allocations.** |
| **B2 — JSON number bytes** | Both real modules pass the expanded native-contract oracle for all eight required values plus existing small/f32 cases (`gnome/tests/native-contract.js:79–82,127–132`). Inspected the shared formatter's integer-precision and notation rules (`gnome/common/json.odin:39–81`). Existing 001–106 golden files remain unchanged. | **Fixed for every requested numeric reproduction.** |
| **B3 — local per-call timeout** | All 107 CLI goldens pass against the actual baseline and against Odin. Additionally ran both installed CLIs sequentially under one private `hang-shell.js` owner with `--timeout 30 status`: both return exit 3, empty stdout and byte-identical `org.freedesktop.DBus.Error.NoReply: Did not receive a reply. Possible causes include: ...` stderr, including the final newline. Mapping is production code at `gnome/controller/client/client.odin:55–63,172–178`. The existing exit-4 overall-deadline cases still pass. | **Fixed; real delayed bus calls, not a unit-only mocked error.** |
| **B6 — raw canonical filename bytes** | The expanded native-contract test creates a real raw-FF filename behind a valid UTF-8 symlink and asserts that readlink returned actual byte 255 before testing native calls (`gnome/tests/native-contract.js:105–125`). The test independently passes on baseline and rework, including direct-load status and restored/exported state. Inspected the separate external-byte replacement and internal surrogate-preserving paths (`gnome/common/text.odin:5–32`; `gnome/native/config.odin:178–187,237–246`; `gnome/native/engine.odin:283–289`; `gnome/native/boundary.odin:38–54`). | **Fixed for both requested raw-filename paths, without undoing isolated-surrogate export preservation.** |

No evidence was found that the expanded native or CLI tests substitute the port's own model for the baseline oracle: the same native test passes on the original module, the same 107 golden cases pass on the original CLI, and independent delayed-call/negative-control checks exercise the risky paths. Coverage remains finite, as the new counterexamples demonstrate.

### Additional parser regression observations

All cases below used fresh unattached native objects; no Shell or session-bus access was involved.

| Input | Baseline b223c1a | Rework 88c69ec |
|---|---|---|
| `\ufeff{"version":1}` (actual leading U+FEFF, UTF-8 BOM) | Accepted; default settings export | `illegal number` |
| `\ufeff[]` | `Configuration must be a JSON object` | `illegal number` |
| `{}"` | `garbage at the end of the document` | `unterminated string` |
| `{}tru` | `garbage at the end of the document` | `illegal value` |
| `{}\` | `garbage at the end of the document` | Same, control |
| Backslash followed by literal `é` or `😀` inside an ignored string | `invalid UTF8 string` | Same, controls |
| `[1,]` | `object is missing after a comma` | Same, control |
| `[1e]` | `illegal number` | Same, control |
| `[1.]` | `Configuration must be a JSON object` | Same, control |
| `{"version":1.}` | Accepted | Accepted, original rework case fixed |

The executable BOM assertion was:

```js
const e = imports.gi.WaylandShader.Effect.new();
try {
    e.import_settings("\ufeff{\"version\":1}");
    if (JSON.parse(e.export_settings()).version !== 1) throw Error("wrong version");
} finally {
    e.shutdown();
}
```

It exits **0** for `/tmp/ws-baseline-result`, **0** for the retained Round-1 `/tmp/ws-review-a-result`, and **1** for `/tmp/ws-review-a-r2-result`. Thus R2-A-01 is demonstrably a rework regression, not merely an old untested baseline difference.

### Round-2 commands run

Repository root is the command working directory. Shorthands in this table are `B=/tmp/ws-review-a-r2-build`, `R=/tmp/ws-review-a-r2-result`, `BASE=/tmp/ws-baseline-result`, `COPY=/tmp/ws-review-a-r2-negative`, and `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com`; actual invocations used the corresponding literal paths. Source edits mentioned below were surgical tool edits to the owned copy, not shell edits or repository mutations.

| Check / command | Independently observed result |
|---|---|
| `git rev-parse --short HEAD`; `git diff --stat 94656d9 88c69ec` | Exit 0; reviewed revision `88c69ec` and inspected the rework's changed-file scope. |
| `nix-build gnome/default.nix -o /tmp/ws-review-a-r2-result` | Exit 0; actual configure/build/checkPhase/install; **13/13**, no skips, 16.76 seconds CTest time. |
| `nix-build default.nix -o /tmp/ws-review-a-r2-kwin` | Exit 0; actual C++ KWin compile/link/install. This is not a KWin runtime test. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-review-a-r2-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-review-a-r2-build --parallel 2 && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/ws-review-a-r2-build --output-on-failure'` | Exit 0; independent full build and **13/13** checks, no skips, 46.81 seconds CTest time. Includes ABI compilation, all five Odin unit suites, native lifecycle/recents/contract, real GL/GL33, 107 CLI goldens, ELF and ban checks. |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js <PACKAGE>/$EXT/native'`, separately for baseline and rework (literal expanded paths) | Both exit 0, `Native byte/error contract passed.` Independently covers the requested A-01/A-02/B2/B6 cases, including actual FF-byte verification. Neither run uses `--capture`. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit 0, **107 cases match** against the original CLI; no golden files written. |
| Independent private delayed-call command below, baseline then rework | Exit 0; explicit assertions confirm exit 3 and empty stdout; complete stdout/stderr/exit records compare equal. |
| Native scanner matrix using the GI environment below, separately for baseline and rework | Both observational probes exit 0 because GErrors are caught. **Comparison fails** for the four cases in R2-A-01/R2-A-02; controls match as recorded above. |
| BOM assertion body above using the same GI environment, for baseline, retained round-1 package and rework separately | Baseline **0**, Round-1 Odin **0**, rework **1** with uncaught `wayland-shader-error: illegal number`. This is an actual failing assertion, not just printed diagnostics. |
| `mkdir /tmp/ws-review-a-r2-negative && cp -a gnome /tmp/ws-review-a-r2-negative/gnome`; then copied C/Odin GList size assertions changed 24→25 | Exit 0 preparing the private copy; no production file changed. |
| `nix-shell gnome/shell.nix --run 'cmake -S /tmp/ws-review-a-r2-negative/gnome -B /tmp/ws-review-a-r2-negative/build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-review-a-r2-negative/build --target gnome_abi_check'` | Expected exit **1** at `_Static_assert`: `"GList size"`. |
| `nix-shell gnome/shell.nix --run 'odin build <COPY>/gnome/<PACKAGE> -build-mode:obj -out:<COPY>/<NAME>.o -vet -strict-style -define:GL_DEBUG=false'`, four separate commands for native, controller/gui, controller/ctl and runtime | Expected exit **1 in all four**, at the exact shared `size_of(GList) == 25` compile-time assertion. |
| Restored copied C/Odin assertions, injected `probe,_:=make([]u8,1,context.allocator); delete(probe)` inside copied production `before_paint_output`; then `cmake --build <COPY>/build --target gnome_abi_check && ctest --test-dir <COPY>/build -R "^gnome_native_units$" --output-on-failure` inside Nix shell | C ABI gate passes; expected CTest exit **8**, specifically `heap_delta` **1400**, expected 0. |
| Replaced copied heap injection with `probe,_:=make([]u8,1,context.temp_allocator); delete(probe,context.temp_allocator)`; same native CTest | Expected exit **8**, specifically `temp_delta` **1400**, expected 0. |
| Removed allocation injection; `cmake --build <COPY>/build --target gnome_abi_check && ctest --test-dir <COPY>/build -R "^gnome_native_units$" --output-on-failure` inside Nix shell | Exit 0; restored real C gate and **1/1** native CTest pass. |
| `rm -rf /tmp/ws-review-a-r2-negative` | Exit 0; removed only this review's owned temporary negative-control copy. |
| Exact T-UNCHANGED protected-path `git diff --exit-code b223c1a -- …` from Round 1 | Exit 0, empty diff. |
| `git diff --exit-code 94656d9 -- gnome/tests/golden/cli ':(exclude)gnome/tests/golden/cli/107.*' ':(exclude)gnome/tests/golden/cli/cases.txt'` | Exit 0; all previously existing 001–106 golden files are unchanged. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/elf-check.sh <R>/$EXT/native/libwaylandshader-gnome.so <R>/bin/.waylandshader-gnomectl-wrapped <R>/bin/.waylandshader-gnome-controller-wrapped'`; baseline/rework installed GIR `diff` | Both exit 0; exports/dependencies/SONAME and byte-identical GIR retained. |
| `diff <(find -L /tmp/ws-baseline-result -printf '%P\n' \| sort) <(find -L /tmp/ws-review-a-r2-result -printf '%P\n' \| sort)` | Exit 0; installed relative path sets identical. |
| `env WS_PRIVATE_ROOT=/tmp/ws-review-a-r2-refusal XDG_RUNTIME_DIR=/tmp/ws-review-a-r2-refusal/runtime WS_CALLER_RUNTIME=/tmp/ws-review-a-r2-caller WS_CALLER_BUS=unix:path=/tmp/ws-review-a-r2-refusal DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ws-review-a-r2-refusal sh gnome/tests/isolated-session.sh --private-child true` | Expected exit **1**, `refusing caller bus or runtime directory`, before any Shell-hosted test. Uses synthetic equal addresses; does not contact the live bus. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-r2-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | Exit 0; real bypass/edit/rebuild **PASS** in a disposable Shell. |
| `set -o pipefail && nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-r2-result -- gnome/tests/iso-cli.sh /tmp/ws-review-a-r2-result/bin/waylandshader-gnomectl' \| tee /tmp/ws-review-a-r2-cli.log && diff /tmp/ws-review-a-cli-baseline.log /tmp/ws-review-a-r2-cli.log` | Exit 0, transcript identical to the baseline independently run in Round 1. Private auxiliary desktop services emitted environmental startup/shutdown warnings; no live compositor was used. |

The native GI probes ran inside `nix-shell gnome/shell.nix --run` with explicit per-package paths:

```sh
env GI_TYPELIB_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" \
    LD_LIBRARY_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$LD_LIBRARY_PATH" \
    gjs -c '<BODY>'
```

The scanner-matrix body, shown without shell quoting, was:

```js
for (const s of [
    "\ufeff{\"version\":1}", "\ufeff[]",
    "{\"version\":1,\"ignored\":\"\\é\"}",
    "{\"version\":1,\"ignored\":\"\\😀\"}",
    "{}\\", "{}\"", "{}tru", "[1,]", "[1e]", "[1.]",
    "{\"version\":1.}",
]) {
    const e = imports.gi.WaylandShader.Effect.new();
    try {
        e.import_settings(s);
        print(JSON.stringify(s) + " => " + e.export_settings());
    } catch (x) {
        print(JSON.stringify(s) + " => ERROR " + x.message);
    } finally {
        e.shutdown();
    }
}
```

The independent timeout launcher was:

```sh
nix-shell gnome/shell.nix --run 'env WS_CALLER_BUS="$DBUS_SESSION_BUS_ADDRESS" XDG_DATA_DIRS=/nonexistent GIO_USE_VFS=local dbus-run-session -- gjs -c '\''<BODY>'\'''
```

Its body was:

```js
const {Gio, GLib} = imports.gi;
const f = Gio.Subprocess.new(["gjs", "-m", "gnome/tests/hang-shell.js"], Gio.SubprocessFlags.NONE);
try {
    if (!Gio.Subprocess.new(["gdbus", "wait", "--session", "--timeout", "5", "org.gnome.Shell"],
        Gio.SubprocessFlags.NONE).wait_check(null)) throw Error("not ready");
    let previous;
    for (const root of ["/tmp/ws-baseline-result", "/tmp/ws-review-a-r2-result"]) {
        const p = Gio.Subprocess.new([root + "/bin/waylandshader-gnomectl", "--timeout", "30", "status"],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        const [ok, out, err] = p.communicate_utf8(null, null);
        const record = JSON.stringify([p.get_exit_status(), out, err]);
        print(root + " " + record);
        if (p.get_exit_status() !== 3 || out !== "") throw Error("bad exit/stdout");
        if (previous && previous !== record) throw Error("timeout mismatch");
        previous = record;
    }
} finally {
    f.force_exit();
    f.wait(null);
}
```

Not checked in Round 2: deferred manual visual/accessibility/app_id/hardware observations and exhaustive unrelated fault/race cases. No installation, extension enablement, module load, compositor restart or mutating call targeted the live session. The remaining acceptance risk is specifically the shared parser's independently reproduced compatibility failures, not an unrun build or a presumed failure.

REJECT — R2-A-01 (leading-BOM acceptance regression) and R2-A-02 (wrong trailing-content error precedence) block REQ-068. All seven requested original rework reproductions otherwise pass; A-04 remains deferred under the main reviewer's ruling.

## Round 3

REJECT

| ID | Severity | REQ | File:line | Evidence | Required fix |
|---|---|---|---|---|---|
| R3-A-01 | blocking | REQ-006, REQ-007, REQ-017, REQ-068 | `gnome/common/json_parse.odin:35–82` (raw UTF-8 copy at 50–55, escape decoding at 66–76); consuming conversions in `gnome/native/config.odin:150–219`; baseline `b223c1a:gnome/native/waylandshader-effect.cpp:1388–1407,1417–1421` | Baseline behavior distinguishes a literal leading UTF-8 U+FEFF **inside a JSON string** from the ASCII JSON escape `\ufeff`. The port collapses them to the same string. With an actual U+FEFF before the parameter name `GAIN`, the baseline exports `GAIN` while the port exports U+FEFF+`GAIN`. With an actual U+FEFF before `/tmp/ws-r3-missing.slangp` in the preset value, the baseline imports the absolute path, while the port rejects it with `Saved preset must be an absolute filename`. A recent raw-U+FEFF-prefixed `/a.slangp` is retained as `/a.slangp` by baseline and dropped by the port. Escaped `\ufeff` controls match: it is preserved in names and rejected before an absolute preset path on both implementations. These are exercised byte/acceptance differences, not a suspected internal Qt representation issue. | Reproduce the baseline's representation-sensitive JSON/string conversion at the appropriate boundaries. Do not indiscriminately remove U+FEFF from every decoded string: the escaped controls must stay distinct, and document-level BOM handling must remain correct. Add baseline-pinned raw-versus-escaped U+FEFF cases for keys, parameter names, preset values and recents, with interior-character and known-key-lookup controls. |

### Reviewed revision and outcome

`git rev-parse --short HEAD` returned **d50af2d**. This final review covers the ten numbered items in `acceptance.md:306–319`, the final parser/path rewrites and their callers/tests. Earlier review sections are retained unchanged.

Both Nix invocations actually configured, compiled, tested where applicable, and installed their outputs:

```text
/tmp/ws-review-a-r3-result -> /nix/store/fz2myjcnbvp6qq9fm7j8z5dji5jf7dwb-waylandshader-gnome-0.1.0
/tmp/ws-review-a-r3-kwin   -> /nix/store/r5vq09z7v951xd3sq7d7f9xvzyx92mrc-waylandshader-0.1.0
```

GNOME checkPhase passed **16/16**, with no skips, including the added parser/path/C-argument regressions and both real GL variants. An independent external build tree also passed **16/16**. All explicitly requested Round-2 reproductions now pass their finite checks against the actual baseline. The final verdict is nevertheless **REJECT**, because independent differential fuzzing and direct follow-up assertions expose R3-A-01 outside that passing corpus.

The manual-observation ruling remains as recorded in `acceptance.md:202`: visual GUI/render/hardware observations and safety/docs sign-offs are deferred, not automated passes and not blockers by themselves. D1/D2 are unchanged. This rejection does not depend on a deferred manual observation.

### Every Round-2 rework item

| Item | Independent verification / source | Disposition |
|---|---|---|
| **R2-1 — document BOM handling** | Ran the 275-case native parser corpus on baseline and final package without capture mode. It covers actual initial BOMs in settings/output arrays, repeated/misplaced BOMs and whitespace controls (`gnome/tests/parser-corpus.js:12–19`). Reviewed the two ordered initial decoding stages and root handling at `gnome/common/json_parse.odin:184–199`. | **Requested document-level cases fixed.** R3-A-01 concerns raw versus escaped U+FEFF *inside strings*, not rejection of the initial document BOM. |
| **R2-2 — numeric grammar/contextual errors** | Same dual baseline/final corpus exercises `.5`, `-.5`, version `.5e1`, non-string keys, truncated backslash/Unicode escapes, closing tokens, overflow/underflow, leading zero and surrogate controls (`gnome/tests/parser-corpus.js:20–48`). Common units consume the baseline table and check cleanup under a tracking allocator (`gnome/common/parser_corpus_test.odin:10–35`); they passed independently. | **All requested matrix cases fixed.** Not a claim of complete parser equivalence. |
| **R2-A-02 — trailing-content precedence** | The native corpus includes `{}"`/`{}tru` equivalents for object and array roots plus nested malformed tails and valid whitespace (`gnome/tests/parser-corpus.js:12–15,37–43`). Both real modules pass. The parser now checks remaining root input without lexing it (`gnome/common/json_parse.odin:192–199`). | **Fixed for requested root/nested cases.** |
| **R2-3 — missing-path final slash** | Ran the 77-case path/recents contract separately on baseline and final package. It compares exact settings plus status `preset`, `requestedPreset` and `loading`, including the five required trailing-slash cases, `/.`, `/..`, root and neighboring root-collapse cases (`gnome/tests/path-contract.js:11–17,21–46`). Inspected the source-derived moving-root cleanup and final slash append (`gnome/native/config.odin:103–142`). The independent fuzz run also generated additional missing-path inputs and found no path mismatch. | **Requested cases fixed.** |
| **R2-4 — binary-safe T-WRAP** | The documented command uses `grep -ao` (`requirements.md:190`). Independently spawned that extractor on each actual binary wrapper, selected the first extracted schema path, checked its existence, and then ran `test -f` on the common extracted GTK chooser schema path. Both packages pass; neither GUI wrapper was launched. | **Catalog test repaired; packaged schema exists.** |
| **B7 — Cogl mask width** | Odin now declares `buffers: c.ulong` (`gnome/native/mutter.odin:102`). The real-header signature assertion is at `gnome/native/abi-check.c:161–163`. Production builds pass. In an owned copied C gate, changing only expected `unsigned long` to `unsigned int` makes the compiler reject the signature assertion. Restoring it passes. | **Fixed; signature gate demonstrably fails on a width mismatch.** |
| **B8 — Unicode recent suffix** | Both modules pass the path/recents contract, including literal `/a.ſlangp`, ASCII mixed case and nonmatching Unicode/suffix controls (`gnome/tests/path-contract.js:18–19,34–46`). The production helper folds the last seven runes without changing the saved path (`gnome/native/config.odin:144–148`). | **Requested suffix cases fixed.** R3-A-01 independently exposes another recent-string conversion difference. |
| **B9 — private API-version gate** | Real header gate now includes `VALUE(LIBRASHADER_CURRENT_VERSION, 2)` (`gnome/native/abi-check.c:160`). Actual package and independent builds pass. In the owned copy, changing expected 2→3 fails compilation with `LIBRASHADER_CURRENT_VERSION value`; restored expected 2 passes. | **Fixed; required negative control independently reproduced.** |
| **B10 — persistent native argument checks** | Independently built and ran `gnome_native_arguments` against each installed library in separate processes. All six NULL/byte-FF calls per library return FALSE with non-NULL GError, exact domain, code 1 and `Invalid UTF-8 argument`; errors/effect are cleaned up (`gnome/tests/native-arguments.c:20–53`). The same test is registered in checkPhase. | **Fixed; actual exported C procedures are exercised, not mocked validation helpers.** |
| **B12 — first-frame anchor ordering** | Independently ran native units and inspected production ordering. `frame_timing` leaves an unstarted anchor unchanged; `frame_source_prepared` commits only on success (`gnome/native/paint.odin:160–175`). Real paint performs destination allocation before the transition, passes the source-copy result into it, then renders (`:243–258`). The four nominal/zero-refresh preparation-failure/retry cases exercise that transition and the real gamma failure-clear route (`gnome/native/native_test.odin:38–82`). Existing timing/history/zero-allocation and real GL tests remain green. Baseline source orders preparation before anchor at `b223c1a:gnome/native/waylandshader-effect.cpp:1141–1145`. | **Required production-state-transition regression passes.** No actual driver allocation/copy fault is claimed injected. |

The original native contract and 107 CLI goldens also pass against baseline and final implementation. CLI goldens are unchanged from 88c69ec. Installed GIR bytes, installed relative file list, required ELF properties and protected KWin/shared paths remain unchanged. No new feature or stub was found in these rework slices.

### Additional differential fuzzing and concrete failure

An independent deterministic generator used seed **0x51a7c0de**. It attempted:

- 2,600 mutations of six JSON seeds using insertion/deletion/replacement with structural characters, numeric/literal characters, whitespace, U+FEFF and `é`;
- 1,200 generated absolute missing-path inputs with `a`, `b`, empty, `.`, `..` and `...` segments and optional final separators;
- 900 generated finite-double parameter settings across a wide exponent range.

After deduplication and nonfinite-number filtering, **3,366 inputs** were sent to separate baseline and final GJS processes. Every input used a fresh unattached native object. The comparison checked acceptance/error text, complete exported settings bytes, status `preset` and status `requestedPreset`. Both processes completed without a crash. There was **one mismatch**:

```text
input:    {"version":1,"parameters":{"<literal U+FEFF>p":{"GAIN":0.5}}}
baseline: {"enabled":true,"outputs":{},"parameters":{"p":{"GAIN":0.5}},"preset":"","recent_presets":[],"version":1}
Odin:     {"enabled":true,"outputs":{},"parameters":{"<literal U+FEFF>p":{"GAIN":0.5}},"preset":"","recent_presets":[],"version":1}
```

`<literal U+FEFF>` here denotes the actual UTF-8 bytes EF BB BF *within the JSON string*, not six ASCII escape characters. The fuzz comparison exits **1**, so it is an actual failed differential check. The other 3,365 generated comparisons match; this is finite evidence, not a global equivalence proof.

Fresh targeted probes then established:

| JSON string position / representation | Baseline b223c1a | Final d50af2d |
|---|---|---|
| Parameter-preset key: literal U+FEFF + `p` | Export key `p` | Export retains U+FEFF + `p` |
| Same key encoded as ASCII JSON `\ufeffp` | Export retains U+FEFF + `p` | Same, control |
| Parameter name: literal U+FEFF + `GAIN` | Export name `GAIN` | Export retains U+FEFF + `GAIN` |
| Same name encoded as ASCII JSON `\ufeffGAIN` | Export retains U+FEFF + `GAIN` | Same, control |
| Preset value: literal U+FEFF + `/tmp/ws-r3-missing.slangp` | Accepted; exported preset `/tmp/ws-r3-missing.slangp` | Rejected: `Saved preset must be an absolute filename` |
| Same preset encoded with ASCII JSON `\ufeff` | Rejected: `Saved preset must be an absolute filename` | Same, control |
| Recents containing literal U+FEFF + `/a.slangp` and escaped `\ufeff/b.slangp` | Export recent list `["/a.slangp"]` | Export recent list `[]` |

This smaller executable assertion separately exits **0 on baseline** and **1 on the final package**, with `raw BOM name not decoded like baseline`:

```js
const e = imports.gi.WaylandShader.Effect.new();
try {
    // JSON.stringify emits an actual U+FEFF in this string, not the ASCII \u escape.
    e.import_settings(JSON.stringify({version: 1, parameters: {p: {["\ufeffGAIN"]: 0.5}}}));
    const saved = JSON.parse(e.export_settings());
    if (saved.parameters.p.GAIN !== 0.5 || Object.keys(saved.parameters.p).length !== 1)
        throw Error("raw BOM name not decoded like baseline");
} finally {
    e.shutdown();
}
```

The observed raw-versus-escaped distinction means a blanket “strip BOM from strings” patch would be unsafe. The current string representation makes raw and escaped U+FEFF identical; the baseline conversion behavior demonstrated above is not identical.

### Round-3 commands run

All commands ran from the repository root. Table shorthands are `B=/tmp/ws-review-a-r3-build`, `R=/tmp/ws-review-a-r3-result`, `BASE=/tmp/ws-baseline-result`, `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com`; executed native/build commands used literal expanded paths.

| Command / check | Independently observed result |
|---|---|
| `git rev-parse --short HEAD`; `git diff --stat 88c69ec HEAD` | Exit 0; HEAD **d50af2d**, final rework source/test scope inspected. |
| `nix-build gnome/default.nix -o /tmp/ws-review-a-r3-result` | Exit 0; actual build/install and **16/16** checkPhase entries, **no skips**, 16.84 seconds CTest time. |
| `nix-build default.nix -o /tmp/ws-review-a-r3-kwin` | Exit 0; actual KWin C++ compile/link/install. No KWin runtime claim. |
| Independent build/test command below | Exit 0; full external build and **16/16**, no skips, 46.96 seconds CTest time. It then ran the C argument executable against baseline and final library in separate processes: all six exact assertions pass on each. |
| `nix-shell gnome/shell.nix --run 'export GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH"; gjs -m gnome/tests/native-contract.js <PACKAGE>/$EXT/native && gjs -m gnome/tests/parser-corpus.js <PACKAGE>/$EXT/native && gjs -m gnome/tests/path-contract.js <PACKAGE>/$EXT/native'`, once for baseline and once for final package (executed together sequentially with literal paths) | Exit 0; both libraries: original native byte/error contract passes, **275 parser cases match**, **77 path/recents cases match**. No capture mode or oracle modification. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit 0; **107 cases match** on original CLI. Final CLI independently passes the same golden suite in Nix and external CTest. |
| Initial deterministic fuzz launcher, passing the entire generated JSON input list as one child argument | Exit 1 before child execution: `GLib.SpawnError ... Argument list too long`. Infrastructure failure only, not a compatibility result. Replaced with 200-record argument chunks below. |
| Chunked deterministic fuzz launcher, seed 0x51a7c0de, body below | Exit **1** after both real native implementations completed: `cases=3366 mismatches=1`; raw-U+FEFF key counterexample above. |
| Targeted seven-input raw/escaped U+FEFF native GI probes, separately on baseline and final | Both diagnostic probes exit 0 because GErrors are caught; actual outputs differ as shown in the seven-row table. |
| Executable raw-BOM parameter-name assertion above, separately on baseline and final using the GI environment below | Baseline exit **0**; final exit **1**, `raw BOM name not decoded like baseline`. |
| Binary-safe wrapper gate: `Gio.Subprocess` runs `grep -ao '/nix/store/[^:"]*/share/gsettings-schemas/gtk+3-[^:"/]*' <PACKAGE>/bin/waylandshader-gnome-controller`, selects first stdout line and checks schema existence; then `test -f` on the extracted path | Exit 0 on both wrappers. Both extract `/nix/store/6ipigl0rqnc2vrqf7y3y9gz6b3nrdcrq-gtk+3-3.24.52/share/gsettings-schemas/gtk+3-3.24.52`; direct `test -f .../glib-2.0/schemas/org.gtk.Settings.FileChooser.gschema.xml` exits 0. This exercises the repaired catalog extractor, not a GUI launch. |
| `mkdir /tmp/ws-review-a-r3-abi && cp gnome/native/abi-check.c /tmp/ws-review-a-r3-abi/abi-check.c`; surgical copied version assertion 2→3; real-header compile below | Copy creation exit 0; expected compile exit **1**, exact static assertion `LIBRASHADER_CURRENT_VERSION value`. Production source unchanged. |
| Restore copied API version; surgical copied expected Cogl signature `unsigned long`→`unsigned int`; same compile | Expected exit **1**, exact static assertion `cogl_framebuffer_clear4f signature`. |
| Restore copied signature; same real-header compile; `rm -rf /tmp/ws-review-a-r3-abi` | Both exit 0; restored gate compiles and owned temporary negative-control source/object removed. |
| Exact T-UNCHANGED protected-path `git diff --exit-code b223c1a -- …` from earlier review sections | Exit 0, empty diff. |
| `git diff --exit-code 88c69ec -- gnome/tests/golden/cli` | Exit 0; all 107 CLI goldens/case definitions unchanged by final rework. |
| Installed `gnome/tests/elf-check.sh` on final native `.so` and both hidden wrapped ELF binaries, inside the Nix shell | Exit 0; required exports/SONAME/dependencies and no forbidden Qt/libstdc++ or root runtime path. |
| `diff "$BASE/$EXT/native/WaylandShader-1.0.gir" "$R/$EXT/native/WaylandShader-1.0.gir"`; sorted relative installed path-set comparison with `find -L … -printf '%P\n'` | Exit 0, no GIR or installed-layout differences. |
| Synthetic equal-bus/runtime refusal command below | Expected exit **1**, `refusing caller bus or runtime directory`, before any Shell-hosted test. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-r3-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | Exit 0; real bypass/edit/GPU-runtime reconstruction **PASS** in a disposable Shell. |
| `set -o pipefail && nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-review-a-r3-result -- gnome/tests/iso-cli.sh /tmp/ws-review-a-r3-result/bin/waylandshader-gnomectl' \| tee /tmp/ws-review-a-r3-cli.log && diff /tmp/ws-review-a-cli-baseline.log /tmp/ws-review-a-r3-cli.log` | Exit 0; final transcript identical to my retained independently executed Round-1 baseline transcript. Private auxiliary services emit environmental startup/shutdown diagnostics; these are not represented as WaylandShader failures. |

Independent build/test command:

```sh
nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-review-a-r3-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-review-a-r3-build --parallel 2 && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/ws-review-a-r3-build --output-on-failure && /tmp/ws-review-a-r3-build/gnome_native_arguments /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so && /tmp/ws-review-a-r3-build/gnome_native_arguments /tmp/ws-review-a-r3-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so'
```

Copied real-header ABI compile, executed inside `nix-shell gnome/shell.nix --run` for both failing mutations and the restored control:

```sh
cc -DLIBRA_RUNTIME_OPENGL \
  $(pkg-config --cflags libmutter-18 mutter-clutter-18 mutter-cogl-18 mutter-mtk-18 graphene-gobject-1.0 egl gio-2.0 gtk+-3.0) \
  -I/nix/store/gl6nf7xzs0ifldc0h2bxplaw4g22pvs4-waylandshader-librashader-0.10.1/include/librashader \
  -c /tmp/ws-review-a-r3-abi/abi-check.c -o /tmp/ws-review-a-r3-abi/abi.o
```

Native direct probe environment (each package in its own process):

```sh
nix-shell gnome/shell.nix --run 'env GI_TYPELIB_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" LD_LIBRARY_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$LD_LIBRARY_PATH" gjs -c '\''<BODY>'\'''
```

Synthetic refusal command:

```sh
env WS_PRIVATE_ROOT=/tmp/ws-review-a-r3-refusal \
    XDG_RUNTIME_DIR=/tmp/ws-review-a-r3-refusal/runtime \
    WS_CALLER_RUNTIME=/tmp/ws-review-a-r3-caller \
    WS_CALLER_BUS=unix:path=/tmp/ws-review-a-r3-refusal \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ws-review-a-r3-refusal \
    sh gnome/tests/isolated-session.sh --private-child true
```

For reproducibility, the successful fuzz launcher ran the following JavaScript body through `gjs -c` inside the project Nix shell, with `MUTTER_GIR="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18"`. Formatting below is expanded from the executed one-line body; generation and comparisons are unchanged:

```js
const {Gio, GLib} = imports.gi;
let seed = 0x51a7c0de;
function rnd(n) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed % n;
}
const sources = new Set();
const bases = [
    "{}", "[]", "{\"version\":1}",
    "{\"version\":1,\"ignored\":[0,true,null,{\"x\":\"é\"}]}",
    "[{},[],1,\"abc\"]",
    "{\"version\":1,\"parameters\":{\"/p\":{\"GAIN\":0.5}}}",
];
const alphabet = Array.from("{}[],:\"\\+-.01eEtnful \t\n\r\ufeffé");
for (let i = 0; i < 2600; i++) {
    let a = Array.from(bases[rnd(bases.length)]);
    for (let j = 0; j < 1 + rnd(3); j++) {
        const p = rnd(a.length + 1), c = alphabet[rnd(alphabet.length)];
        switch (rnd(3)) {
        case 0: a.splice(p, 0, c); break;
        case 1: a.splice(p, 1); break;
        case 2: a.splice(p, 1, c); break;
        }
    }
    sources.add(a.join(""));
}
for (let i = 0; i < 1200; i++) {
    const segments = [];
    for (let j = 0; j < 1 + rnd(12); j++)
        segments.push(["a", "..", ".", "b", "", "..."][rnd(6)]);
    const path = "/ws-review-a-r3-absent/" + segments.join("/") + (rnd(2) ? "/" : "");
    sources.add(JSON.stringify({version: 1, preset: path}));
}
for (let i = 0; i < 900; i++) {
    const n = ((rnd(0xffffffff) - 2147483648) / Math.max(1, rnd(0xffffffff)))
        * Math.pow(10, rnd(620) - 310);
    if (Number.isFinite(n))
        sources.add(JSON.stringify({version: 1, parameters: {"/p": {GAIN: n}}}));
}
const inputs = Array.from(sources), chunks = [];
for (let i = 0; i < inputs.length; i += 200)
    chunks.push(JSON.stringify(inputs.slice(i, i + 200)));
const body = String.raw`
const values = ARGV.flatMap(s => JSON.parse(s));
const W = imports.gi.WaylandShader;
const results = [];
for (const s of values) {
    const e = W.Effect.new();
    let result;
    try {
        e.import_settings(s);
        const status = JSON.parse(e.get_status());
        result = ["OK", e.export_settings(), status.preset, status.requestedPreset];
    } catch (x) {
        result = ["ERROR", x.message];
    } finally {
        e.shutdown();
    }
    results.push(result);
}
print(JSON.stringify(results));
`;
function run(root) {
    const ext = "/share/gnome-shell/extensions/waylandshader@man33li.github.com/native";
    const l = new Gio.SubprocessLauncher({
        flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
    });
    l.setenv("GI_TYPELIB_PATH", root + ext + ":" + GLib.getenv("MUTTER_GIR")
        + ":" + (GLib.getenv("GI_TYPELIB_PATH") || ""), true);
    l.setenv("LD_LIBRARY_PATH", root + ext + ":"
        + (GLib.getenv("LD_LIBRARY_PATH") || ""), true);
    const p = l.spawnv(["gjs", "-c", body, ...chunks]);
    const [ok, out, err] = p.communicate_utf8(null, null);
    if (!p.get_successful()) throw Error(root + " failed: " + err);
    return JSON.parse(out);
}
const a = run("/tmp/ws-baseline-result"), b = run("/tmp/ws-review-a-r3-result");
let failures = 0;
for (let i = 0; i < inputs.length; i++) {
    if (JSON.stringify(a[i]) !== JSON.stringify(b[i])) {
        if (failures < 30)
            print(JSON.stringify({input: inputs[i], baseline: a[i], odin: b[i]}));
        failures++;
    }
}
print("seed=0x51a7c0de cases=" + inputs.length + " mismatches=" + failures);
imports.system.exit(failures ? 1 : 0);
```

### Limits and final disposition

The only repository file written by this review is this appended report. The owned ABI mutation copy was restored, compiled and removed. No baseline fixture/golden, production source or requirements document was changed. Native probes used unattached objects; all compositor-hosted checks used the tested private-bus harness. No live module installation/load, extension enablement, compositor restart or mutating live-session-bus call occurred.

Not checked: deferred manual visual/accessibility/app_id/hardware sign-offs and actual driver allocation/copy fault injection. All ten requested Round-2 regressions have finite passing evidence, but that does not establish global Qt compatibility. R3-A-01 is independently reproduced using both observational comparisons and a failing assertion; it affects accepted input, stored parameter names and exported settings/history bytes.

REJECT — blocking finding R3-A-01: raw-versus-escaped leading U+FEFF inside JSON strings still differs from the baseline, violating the fixed input/byte-preservation contract despite 16/16 passing headless tests.

## Round 4

ACCEPT

| ID | Severity | REQ | File:line | Evidence | Required fix |
|---|---|---|---|---|---|
| None | — | — | — | No new requirement-violating defect found in the reviewed rework. Both R3-1 surfaces now match the exercised baseline cases, including the original failing assertion and repeated differential fuzz. Required test/safety evidence and the extra noncontract build-reproducibility observation are recorded below. | None for this review's acceptance scope. |

### Revision and verdict scope

Reviewed HEAD: **6f6709d** (`git rev-parse --short HEAD`, exit 0). This review covers R3-1's JSON extraction/provenance and native C-string boundaries, their ownership/callsite changes, the new `gnome_bom_contract` manifest entry, and the authorized devkit-only PipeWire exception. Earlier sections remain historical records, not current blockers.

**R3-1 is closed for the specified and independently exercised cases.** My original raw-BOM parameter-name assertion now passes on both baseline and port. Real prefixed `load_preset`, output gamma and shader-toggle calls also pass the same assertions on both implementations. The expanded original-module contracts match on both sides: **1,285 BOM cases, 369 parser cases, 203 path/recents cases**, plus the original native byte/error contract.

The exact deterministic Round-3 fuzzer, seed **0x51a7c0de**, was repeated with only the tested package changed to `/tmp/ws-review-a-r4-result`: **3,366 inputs, zero mismatches**. A second independent provenance-collision generator, seed **0x32bb7f91**, exercised **1,200 additional inputs, zero mismatches**. Its cases combine duplicate nested preset/parameter keys, literal/escaped/single/double/interior BOMs, later escapes, converted-key collisions, numeric survivors and recent-path extraction. Both compare actual original and port native outcomes/settings, not a port-derived expected model. Neither run crashed.

Normal Nix invocations returned:

```text
/tmp/ws-review-a-r4-result -> /nix/store/61vxhhfjijiqknwl6q9sss8m58vz7l08-waylandshader-gnome-0.1.0
/tmp/ws-review-a-r4-kwin   -> /nix/store/9bcgx2b5p9himxwn3dpc07h4ckdwv27r-waylandshader-0.1.0
```

The first GNOME invocation waited on another process building the same immutable derivation, so I did not claim that invocation independently executed its build. I additionally ran `nix-build ... --check`: that **actually rebuilt and ran all 17/17 checkPhase tests successfully, with no skips**, but its final output-byte comparison failed. This is disclosed separately below; it is not represented as a successful bit-reproducibility check. The required normal `nix-build` command exited 0. T-KWIN actually compiled/linked/installed successfully in my invocation.

My independent external CMake tree compiled all targets. Its first CTest run passed 16/17; the CLI golden alone refused the existing exclusive fixture directory because I had concurrently run the baseline golden command. After that baseline command completed, I ran the CLI test serially: **1/1 passed, all 107 cases**. Thus all 17 external entries were independently exercised successfully across those runs; I do not claim the initial full external run was 17/17. Both real GL variants executed, not skipped. Both installed libraries separately passed the six direct NULL/byte-FF C-entry assertions.

The main agent owns the concurrent visual T-GUI/T-ISO-RENDER work. I did **not** start a devkit session or claim its visual observations. Physical hardware acceptance and other deferred sign-offs remain outside my exercised evidence.

### Code, lifetime and oracle review

- **Document-owned provenance, not blanket trimming:** `JSON_Document` retains the core value, per-string encoding and originating allocator (`gnome/common/json_parse.odin:9–20`). Extraction removes exactly one leading BOM only for parsed UTF-8 storage (`:22–32`); raw lookup is unchanged. Any escape records UTF-16 storage for the whole string (`:77–96`). Duplicate keys update retained-key provenance, dispose the replaced value and remove discarded-string metadata (`:157–205`). This addresses raw/escaped distinctions and later-escape behavior rather than special-casing the original input.
- **Persistent and temporary owners migrated:** native import/output parsing destroys its complete document after cloning retained engine strings/maps (`gnome/native/config.odin:150–224,233–269`); client status owns its document and destroys the replaced document after the listener (`gnome/controller/client/status.odin:18–23,31–48,124–130`). CLI serialization passes that document to the writer (`gnome/controller/ctl/main.odin:108–109`). Source searches found no remaining production caller using the old parsed-value lifetime convention.
- **Allocator/lifetime checks:** the common provenance ownership test parses with a tracking allocator, disposes nested duplicate values, then destroys under the ordinary caller context and asserts no retained allocation (`gnome/common/json_bom_test.odin:91–105`). Parser-corpus tracking covers success/error cleanup (`gnome/common/parser_corpus_test.odin`). These passed in my independent units and Nix checkPhase. No ownership defect was found in the reviewed paths; this is bounded test evidence, not proof against every possible allocation failure.
- **C-string conversion:** complete UTF-8 validation still precedes removal of exactly one leading BOM (`gnome/native/boundary.odin:31–38`). Existing NULL/invalid-UTF8 errors remain intact. The native corpus invokes real exported load/output mutators with single/double/interior/escaped controls (`gnome/tests/bom-contract.js:120–148`), and my additional original reproductions call those exports independently.
- **Nonvacuous baseline oracle:** `bom-contract.js` uses fresh unattached real objects, real exported methods, exclusive readable-file fixtures and exact captured settings/status outcomes; it detects missing expected records as well as mismatches (`:150–200`). It passes unchanged on the original module and the port. Capture mode was not used in my checks. Common value/key tests and all client status-string fields also exercise the new representation. No new feature, public API, settings version or compatibility shim was found.

### Requirements manifest and devkit isolation amendment

Both amendments are justified, narrowly scoped test-infrastructure/documentation changes:

| Amendment | Checked implementation and independent evidence | Result |
|---|---|---|
| New CTest manifest entry | `requirements.md:197` adds `gnome_bom_contract`; `gnome/CMakeLists.txt:97–105` actually registers `bom-contract.js` with the existing parser/path checks and a bounded timeout. Existing checks remain. I observed the new test run in both CTest environments and ran the same corpus directly on baseline and port. | **Justified and accurate.** It adds coverage rather than weakening an acceptance criterion. |
| Devkit-only socket exception | `docs/GNOME.md:291–297` explicitly documents only the caller's `pipewire-0` socket. `isolated-session.sh:39–43` retains private bus/runtime/XDG checks before the sharing branch; `:55–60` requires devkit mode, an absolute caller runtime and a socket, then links one fixed entry. No lockfile, bus socket, arbitrary runtime entry or whole directory is linked. | **Justified by the authorization and accurately documented.** Not a production feature addition. |
| Equal-bus refusal | Ran direct private-child entry with `WS_DEVKIT=1` and synthetic equal caller/child bus addresses. It exits 1 with `refusing caller bus or runtime directory` before socket sharing, gsettings or Shell startup. | **Pass.** |
| Exactly-one-link positive branch without starting a devkit | Created an owned temporary caller directory with a synthetic Unix `pipewire-0` socket and sentinel `pipewire-0.lock`/`bus` files. Supplied fresh private XDG directories, keyfile settings and a guaranteed nonexistent host-Wayland socket. The harness passed the socket-sharing branch, then predictably exited at `devkit requires host Wayland socket`, **before launching any Shell/viewer**. Enumerating the private runtime with no symlink following found **only** `pipewire-0`, whose target was exactly the synthetic caller socket. No lockfile/bus entry was linked. Temporary files/socket were closed and removed. | **Pass.** No real host PipeWire/Wayland endpoint was used by this test. |
| Ordinary headless behavior | Ran `WS_DEVKIT=0` through the harness, asserting no `pipewire-0` symlink and no PipeWire lockfile before the unchanged real GPU-runtime bypass/rebuild test. | **Pass.** A disposable headless Shell only; no devkit session started. |

The synthetic positive-branch test verifies what is linked, not that the real viewer presents frames. The latter remains the main agent's separately exercised work. The source contains no additional sharing branch or `ln` operation, and cleanup removes the private tree rather than following the socket symlink into the caller's directory.

### Commands run

Repository root was the working directory. `R=/tmp/ws-review-a-r4-result`, `B=/tmp/ws-review-a-r4-build`, `BASE=/tmp/ws-baseline-result`, `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com` are table shorthand; actual build/native commands used the corresponding literal paths.

| Command / check | Result independently observed |
|---|---|
| `git rev-parse --short HEAD`; `git diff --stat d50af2d HEAD` | Exit 0; **6f6709d**, provenance/harness/test/documentation slice inspected. |
| `nix-build gnome/default.nix -o /tmp/ws-review-a-r4-result` | Exit **0**; waited for the same output's store lock and returned the package above. Not claimed as my own complete build execution. |
| `nix-build gnome/default.nix --check -o /tmp/ws-review-a-r4-result` | Actually rebuilt the same derivation; checkPhase **17/17**, no skips, 16.69 seconds. Final command exit **1** solely at Nix's subsequent output comparison: `may not be deterministic ... output ... differs`. No successful bit-reproducibility claim. See noncontract observation below. |
| `nix-build default.nix -o /tmp/ws-review-a-r4-kwin` | Exit **0**; actual KWin C++ compile/link/install. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-review-a-r4-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-review-a-r4-build --parallel 2 && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/ws-review-a-r4-build --output-on-failure && <baseline/native-argument commands>'` | Full build succeeds. Initial external CTest exits **8**: **16/17 pass**, CLI test alone refuses `/tmp/ws-cli-golden` because my simultaneous baseline-golden command owns it. Chained C-argument commands therefore did not run in this invocation. No directory was deleted/reused to bypass its safety guard. |
| `nix-shell gnome/shell.nix --run 'ctest --test-dir /tmp/ws-review-a-r4-build -R "^gnome_cli_golden$" --output-on-failure && /tmp/ws-review-a-r4-build/gnome_native_arguments /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so && /tmp/ws-review-a-r4-build/gnome_native_arguments /tmp/ws-review-a-r4-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so'` | After the baseline fixture owner finishes: exit **0**, CLI **1/1** passes (107 cases), followed by all six exact C-entry argument assertions on each library in separate processes. |
| Direct `gjs -m` executions of `bom-contract.js`, `parser-corpus.js`, `path-contract.js`, `native-contract.js` with prepended Mutter typelib path, separately for baseline and port | Exit **0**; on each: **1,285 BOM**, **369 parser**, **203 path/recents** records match, original native byte/error contract passes. No capture mode used. |
| Exact Round-3 deterministic fuzzer with `/tmp/ws-review-a-r4-result` as the port root | Exit **0**, `seed=0x51a7c0de cases=3366 mismatches=0`. The full generator/child comparison is recorded in Round 3; only the port root changed. |
| Additional provenance-collision fuzzer described below | Exit **0**, `provenance seed=0x32bb7f91 cases=1200 mismatches=0`. |
| Independent three-case assertion body below, separately on baseline and port with explicit native GI/loader paths | Both exit **0**: original raw-BOM parameter-name assertion, prefixed real-file load acceptance, prefixed output gamma and shader-toggle mutations all match. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit **0**, **107 cases match** on original CLI. Its exclusive fixture caused the concurrent external-suite collision disclosed above; serial port replay passed. |
| `git diff --exit-code b223c1a -- <exact T-UNCHANGED protected paths>` and `git diff --exit-code d50af2d -- gnome/tests/golden/cli` | Both exit **0**, empty diffs. Protected shared/KWin paths and the existing CLI goldens remain unchanged. |
| Installed `elf-check.sh` on final native library and both hidden wrapped binaries; baseline/port GIR diff; sorted relative installed path-set diff | All exit **0**; public ABI/GIR, installed layout and required ELF properties retained. |
| Binary-safe `grep -ao` wrapper extraction through `Gio.Subprocess`, first matching schema path, and `Gio.File.query_file_type(...) == REGULAR` on the chooser schema | Exit **0**, baseline and port both report T-WRAP PASS. No GUI wrapper launch. |
| Synthetic equal-bus refusal command below | Expected exit **1**, `refusing caller bus or runtime directory`, with `WS_DEVKIT=1`; no session starts. |
| Synthetic socket/one-link/prelaunch refusal test below | Exit **0**, `PASS: exactly one synthetic pipewire-0 link; no lockfile/bus link; refused before Shell launch`. It creates/removes only owned temporary test files and never starts a devkit. |
| `nix-shell gnome/shell.nix --run 'WS_DEVKIT=0 gnome/tests/isolated-session.sh /tmp/ws-review-a-r4-result -- sh -c '\''test ! -L "$XDG_RUNTIME_DIR/pipewire-0" && test ! -e "$XDG_RUNTIME_DIR/pipewire-0.lock" && gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | Exit **0**; no-link assertions and real bypass/edit/runtime-rebuild test PASS. Private auxiliary services emit environmental startup/shutdown warnings; no live module is loaded. |
| Additional real shader-metadata text boundary probe, baseline then port through `WS_DEVKIT=0` harness | Exit **0** on both. Created an exclusive temporary one-pass GAIN shader whose quoted pragma description begins with literal U+FEFF; loaded it through each installed CLI and compared the returned description. Both report `"Gain"`, first code point `0x47`. Temporary shader/preset files are removed, each owned headless Shell shuts down. This checks the observed metadata result, not its internal cause or rendered pixels. |

**Extra, noncontract build observation:** Nix `--check` detected different installed output bytes for the same derivation after all 17 required tests passed. I did not isolate the byte-level cause and do not infer a functional or ABI difference from that diagnostic. Bit-for-bit build reproducibility is not an acceptance requirement in this contract, so this optional comparison failure is not classified as a requirement blocker. It must not be quoted as a passed reproducibility check. The required normal Nix build returns 0, required tests were independently exercised, and installed semantic/ABI/layout checks pass.

### Reproducible assertion and isolation probes

The independent old-failure/native-argument assertion body, run separately under each installed native GI/loader environment, was:

```js
const W = imports.gi.WaylandShader;
for (const check of [
    e => {
        e.import_settings(JSON.stringify({version: 1, parameters: {p: {["\ufeffGAIN"]: 0.5}}}));
        if (JSON.parse(e.export_settings()).parameters.p.GAIN !== 0.5)
            throw Error("raw BOM parameter mismatch");
    },
    e => {
        const p = "/home/knd/AI/dodForPonytail/WaylandShader-gnome/tests/fixtures/temporal.slangp";
        e.load_preset("\ufeff" + p);
        if (JSON.parse(e.get_status()).requestedPreset !== p)
            throw Error("BOM load argument mismatch");
    },
    e => {
        e.set_outputs(JSON.stringify([{id: "A", name: "A", x: 0, y: 0, width: 1, height: 1, scale: 1}]));
        e.set_output_gamma("\ufeffA", 2);
        e.set_output_shader_enabled("\ufeffA", false);
        const s = JSON.parse(e.export_settings()).outputs.A;
        if (s.gamma !== 2 || s.shaderEnabled !== false)
            throw Error("BOM output argument mismatch");
    },
]) {
    const e = W.Effect.new();
    try { check(e); } finally { e.shutdown(); }
}
print("PASS: original raw-BOM parameter, load and output mutator assertions");
```

The equal-bus guard command used synthetic, not live, addresses:

```sh
env WS_DEVKIT=1 WS_PRIVATE_ROOT=/tmp/ws-review-a-r4-refusal \
    XDG_RUNTIME_DIR=/tmp/ws-review-a-r4-refusal/runtime \
    WS_CALLER_RUNTIME=/tmp/ws-review-a-r4-caller \
    WS_CALLER_BUS=unix:path=/tmp/ws-review-a-r4-refusal \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/ws-review-a-r4-refusal \
    sh gnome/tests/isolated-session.sh --private-child true
```

The synthetic positive-sharing test ran a `gjs -c` body inside the project Nix shell. It:

1. Used `GLib.dir_make_tmp("ws-review-a-r4-socket-XXXXXX")` and mode-0700 caller/private/XDG subdirectories.
2. Bound `Gio.Socket.new(UNIX, STREAM, DEFAULT)` to the owned caller's `pipewire-0`, and created caller sentinel files named `pipewire-0.lock` and `bus`.
3. Spawned the real unmodified `sh gnome/tests/isolated-session.sh --private-child true` with private XDG paths, `GSETTINGS_BACKEND=keyfile`, different synthetic caller/child bus addresses, `WS_DEVKIT=1`, and a guaranteed nonexistent `WS_HOST_WAYLAND_SOCKET`.
4. Asserted exit 1 and the exact later guard message `devkit requires host Wayland socket`, proving the sharing branch was reached but Shell startup was not.
5. Enumerated the private runtime with `NOFOLLOW_SYMLINKS`, asserted the complete name list was exactly `["pipewire-0"]`, and asserted its symlink target was exactly the synthetic caller socket.
6. Closed the socket and removed only that owned temporary root in `finally`.

This method deliberately exercises the authorized link without running or interfering with the main agent's devkit/manual sessions.

The additional provenance generator used the same separate-process GI launcher/comparison approach as Round 3, with seed **0x32bb7f91** and the same LCG constants. For each of 1,200 settings documents it generated three preset-key entries, each with four parameter-key/value entries. Key bodies were selected from:

```text
P
<literal BOM>P
\ufeffP                 (ASCII JSON escape)
<literal BOM><literal BOM>P
<literal BOM>\u0050
P<literal BOM>
<literal BOM>P\q
<literal BOM>
\ufeff                  (ASCII JSON escape)
```

Values were selected from `0.5, 1, 2`; recent entries were selected from ordinary, raw-BOM, escaped-BOM and raw-BOM-plus-later-escape paths. Child argument lists were chunked at 100 inputs. Each child used a fresh real effect per document and compared `[accepted, export_settings()]` or `[rejected, exact_error]`; mismatches make the parent exit 1. Both children completed and all 1,200 comparisons matched.

### Limits and disposition

Only this report was changed in the repository. Probe fixtures were external, owned and cleaned up. No production source, oracle, requirements or documentation file was edited by this review. No devkit session was started by me. All actual compositor-hosted work used disposable headless sessions with the live-bus refusal already exercised; the single-socket branch test used only synthetic sockets and stopped before compositor launch.

Not claimed: the main agent's concurrent manual GUI/render observations, physical hardware sign-off, exhaustive allocation-failure injection, or a successful bit-reproducibility check. Those limits do not reinstate the closed R3-1 compatibility failure. No new blocking requirement defect was found in the provenance/harness changes.

ACCEPT — R3-1's exercised JSON and native-argument surfaces match the original baseline; the repeated 3,366-case fuzz and 1,200 additional provenance cases have zero mismatches; the manifest and single-socket devkit exception are justified and retain bus/runtime isolation. No blocking findings.
