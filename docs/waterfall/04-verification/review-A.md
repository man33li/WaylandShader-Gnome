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
