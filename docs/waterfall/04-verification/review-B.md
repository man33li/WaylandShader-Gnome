REJECT

# Phase 4 review B (round 1): Odin port of the GNOME backend

Reviewed build commit `94656d9` against the baseline `b223c1a` (worktree `/tmp/ws-baseline`, package `/tmp/ws-baseline-result`), `01-requirements/requirements.md`, `02-design/design.md` and `02-design/decision.md`. D1 and D2 are accepted deviations, so they are not counted as findings.

I reproduced every automated catalog test, and every one passes (commands table below). The build is still rejected for three reasons:

- I ran baseline-vs-Odin probes on the same inputs, through GI, in a standalone `gjs` process and on a private bus. They show real behavior differences in REQ-068, REQ-005/006 and REQ-041/038.
- The current tests cannot detect these differences. In one case the unit test asserts an oracle that is not the baseline's.
- The required tests T-ISO-RENDER and T-GUI have not been run.

No module was loaded into the live Shell, nothing was installed or enabled, and no call was made on the live bus. The native module ran only in standalone `gjs` processes and in sessions started by `gnome/tests/isolated-session.sh`.

## Findings

| ID | Severity | REQ | file:line | Evidence | Required fix |
|---|---|---|---|---|---|
| B1 | blocking | REQ-068 (and T-UNIT-COMMON validity) | `gnome/common/json_parse.odin:9-24,72-76,138-139`; `gnome/common/json_test.odin:81` | I ran `import_settings(S)` on the baseline and on the Odin build with the same input. **Accepted by the baseline, rejected by Odin:** `{"version":1.}` (Odin: `illegal number`) and a raw LF inside a string (Odin: `unterminated string`). **Rejected by the baseline, accepted by Odin:** `{"version":1,"x":1e-4000}` (baseline: `illegal number`) and `"\u+123"` (baseline: `invalid escape sequence`). **Different error text:** `{"a":` gives `unterminated object` vs `illegal value`; `[1,]` gives `object is missing after a comma` vs `illegal value`; `{"a":[}` gives `object is missing after a comma` vs `illegal value`; `{"a":-}` gives `illegal number` vs `illegal value`; `{"a":01}` gives `unterminated object` vs `illegal number`; `{1:2}` gives `unterminated object` vs `object is missing after a comma`; `{"a":é}` gives `illegal number` vs `illegal value`; `'…'` quotes give `unterminated object` vs `illegal value`. **Lone surrogate:** `recent_presets:["/\ud800.slangp"]` exports `"/\ud800.slangp"` on the baseline but `"/�.slangp"` (U+FFFD) on Odin. `json_test.odin:81` asserts `{"a":` → `illegal value` and `[1,]` → `illegal value`; neither is the baseline's text, so the test passes against a wrong oracle. | Make `common.parse_json` match `QJsonDocument::fromJson` acceptance and error strings on these inputs. Take the oracles from the baseline, as `native-contract.js --capture` does. Correct `json_test.odin:81`. Add the inputs above to `native-contract.js` so the same script runs against both builds. |
| B2 | blocking | REQ-005, REQ-006 (T-UNIT-COMMON "integral/shortest/exponent numbers") | `gnome/common/json.odin:46,53` | `export_settings()` after importing overrides, baseline vs Odin: `0.0005` gives `5e-04` vs `0.0005`; `0.0001` gives `1e-04` vs `0.0001`; `1234567.5` gives `1234567.5` vs `1.2345675e+06`; `12345678.25` gives `12345678.25` vs `1.234567825e+07`; `1e16` gives `1e+16` vs `10000000000000000`; `9.2e18` gives `9.2e+18` vs `9200000000000000000`; `9223372036854775807` gives `9223372036854776000` vs `9.223372036854776e+18`; `123456789012345680000` gives the same integer text vs `1.2345678901234568e+20`. The observed rule (my inference from these outputs): Qt writes integral values up to 2^53 as integers. Otherwise it picks the shorter of fixed and exponent shortest form, with fixed winning ties. Odin writes integers up to 2^63 and uses printf `%g` thresholds (`-4 ≤ exp < 6`). A realistic trigger is `waylandshader-gnomectl param NAME 0.0005`: the stored override exports as `0.0005` instead of the baseline's `5e-04`, so the GSettings bytes differ. The same writer feeds `get_status()` and the CLI's indented output. | Implement Qt's rule in `common.number`: integer form only for \|v\| ≤ 2^53, otherwise the shorter of fixed and exponent shortest form, ties to fixed. Add these values, with baseline-captured oracles, to `json_test.odin` and `native-contract.js`. |
| B3 | blocking | REQ-041 (error text), REQ-038, REQ-043 | `gnome/controller/client/client.odin:162-169` and `43-54` | A private `dbus-run-session` ran `gnome/tests/hang-shell.js` and then `waylandshader-gnomectl --timeout 30 status` (so the 10 s per-call timeout fires first). Both builds exit 3. Baseline stderr: `org.freedesktop.DBus.Error.NoReply: Did not receive a reply. Possible causes include: …`. Odin stderr: `: Timeout was reached`. For a local GIO error, `g_dbus_error_get_remote_error` returns NULL, so `classify("", …)` prefixes an empty name. Every local bus failure (timeout, closed connection) gets a malformed message that differs from Qt's (`CC:21-35`, where QDBusError names the error). No golden case covers a per-call timeout. | Map local GDBus/GIO errors to the names QtDBus reports (`G_IO_ERROR_TIMED_OUT` → `org.freedesktop.DBus.Error.NoReply` with Qt's text; closed/disconnected → `org.freedesktop.DBus.Error.Disconnected` …). Capture the baseline text and add a per-call-timeout case to `cli-golden.sh` (e.g. `--timeout 15 status` against `hang-shell.js`). |
| B4 | blocking (process) | REQ-027, 028, 029, 033, 034 (T-ISO-RENDER); REQ-045, 048, 049 (T-GUI only) | `docs/waterfall/03-implementation/build-log.md:275-276`; `docs/waterfall/README.md:12` | T-ISO-RENDER and T-GUI are "PENDING — manual". For the listed REQs these are the only catalog tests. I found no executed evidence for stage attachment, the per-connector bypass reasons, the full-view clip, master-off pass-through, the cursor inhibit, output-local failure, or the GUI title/menu/enable behavior. T-BYPASS and T-ISO-CLI run the paint path, but they observe no pixels or cursor state. The phase-4 gate accepts only on passing tests. T-HW is explicitly post-acceptance (REQ-067); these two tests are not. | Run T-ISO-RENDER and T-GUI with the catalog commands and record each checklist item in the build log. Alternatively, get explicit user approval to defer them, recorded in GATES.md. |
| B5 | major | REQ-007, REQ-006 | `gnome/native/config.odin:159-165` | `import_settings('{"version":1,"preset":"/nonexistent//a/./b/../c.slangp"}')`: the baseline stores and exports `"preset":"/nonexistent/a/c.slangp"` (`QFileInfo::absoluteFilePath`, `E:1435-1436`, cleans the path). Odin keeps the raw `/nonexistent//a/./b/../c.slangp` in `preset`, `requestedPreset` and the export. This only triggers on a missing preset with a non-clean saved path, for example after a manual dconf edit. | When `realpath` fails, clean the path as `QDir::cleanPath` does (collapse `//`, `/./`, `/../`). Add the case to `native-contract.js`. |
| B6 | major | REQ-005, REQ-009 | `gnome/native/config.odin:221-224`; `gnome/common/json.odin:16-33` | I loaded a symlink `link.slangp` whose target name contains byte `0xFF`. Baseline status: `requestedPreset` = `/…/bad\uFFFD.slangp`, valid UTF-8, because QString decodes it lossily. Odin: `get_status()` returns raw `0xFF`, and GJS throws `String from C value is invalid UTF-8 and cannot be safely stored`. In the extension this breaks `status()` and `status-changed` for that preset. A later export with that path has the same problem. | Decode the canonical path (or quote all JSON text) with U+FFFD replacement, as `QString::fromUtf8` does, so status/export strings are always valid UTF-8. Add a regression. |
| B7 | minor | REQ-061/062 (FFI correctness) | `gnome/native/mutter.odin:99` | The Odin mirror declares `cogl_framebuffer_clear4f(fb, buffers: u32, …)`, but the header (`cogl/cogl-framebuffer.h:654-655`) has `unsigned long buffers` (64-bit). It works only because the constant is materialized with `mov $0x1,%esi`, which zero-extends (objdump at `0x1edf0` and `0x31319`). `abi-check.c` checks no function signatures. | Declare `buffers: c.ulong`. |
| B8 | minor | REQ-017 | `gnome/native/config.odin:152` | `recent_presets:["/a.\u017Flangp",…]`: the baseline keeps `/a.ſlangp`, because Qt's case-insensitive `endsWith` folds `ſ` to `s`. Odin drops it, because it compares only the last 7 bytes as ASCII. | Use Unicode case folding over the trailing runes, or record the difference as an accepted deviation. |
| B9 | minor | REQ-061 | `gnome/native/abi-check.c:41-48`; `gnome/runtime/libra.odin:9-25`; `gnome/runtime/runtime.odin:136-137,239` | The librashader mirrors are checked by size only. Field offsets (`frame_gl_opt_t`, `libra_preset_param_t`, `filter_chain_gl_opt_t`) and `LIBRASHADER_CURRENT_VERSION == 2` are never asserted. I checked field order by hand against `librashader.h:183-318,1189` and it currently matches. | Add `OFFSET(...)` and `VALUE(LIBRASHADER_CURRENT_VERSION, 2)` asserts, plus matching Odin `offset_of` `#assert`s. |
| B10 | minor | REQ-016 | `gnome/tests/native-contract.js:73-139` | T-CONTRACT never checks `Invalid UTF-8 argument` (NULL or invalid UTF-8). The only evidence is reading `boundary.odin:30-35`. | Add a C-level or `GLib.Bytes`-based check, or a native unit test that calls the exported entry points with NULL. |
| B11 | minor | REQ-063 | `gnome/native/native_test.odin:29-48` | The zero-allocation check covers only `frame_timing`/`select_output` (pure arithmetic) and `runtime.render` (GL test). The `before-paint` output loop (`paint.odin:174-181`, with `discover`/`capture_context`) has no allocation check, only my reading of the code, which found no steady-state allocation. | Extend the tracking-allocator check to the `before_paint` body, or narrow the REQ text. |
| B12 | minor | REQ-032 | `gnome/native/paint.odin:166,236-240` | `frame_timing` sets `first_frame` before the destination allocation and the source copy. The baseline sets it after both (`E:1141-1145`). If the allocation or copy fails, the first-frame anchor differs from the baseline's when the output is retried without a history reset. | Set `first_frame` after `copy_shader_source` succeeds, or document the difference. |
| B13 | minor | REQ-037 | `gnome/controller/client/client.odin:259-267` | A `statusChanged` signal whose argument is not `s` is reported as a Protocol transport error and disconnects. QtDBus does not call a `receiveStatus(QString)` slot when the signature does not match (`CC:66-67`) [INFERENCE: Qt slot-signature filtering, not reproduced]. | Ignore signals whose argument is not `(s)`. |
| B14 | minor | REQ-066 | `docs/GNOME.md:148` | "The package also runs `gnome_effect_lifecycle`" is stale: `gnome/default.nix:69-73` runs all 13 CTest entries. The other T-DOCS hits I reviewed (README.md:27-40,239-259; docs/GNOME.md:36-314) are KWin or historical text. | Update the sentence. |

Checked without finding a defect:

- **GObject and GI surface:** the 15 exports and SONAME/NEEDED (T-ELF), the GIR (T-GIR), the installed layout (T-LAYOUT) and T-UNCHANGED.
- **Class/instance ABI:** layout asserts on the C and Odin sides (`mutter.odin:33-37`, `abi-check.c:14-30`).
- **C boundary:** every C-called entry sets its boundary context: native 29/29 `boundary_context`, client 5/5, ctl 2/2. The GUI's 23 GTK callbacks use `gui_context`. Production code has only two-value type assertions. GErrors go through `g_set_error_literal` (`boundary.odin:37-50`), and strings returned to GI come from `g_strndup`.
- **Runtime port:** context creation, fences, restoration, parameter rollback and the failure-retains-runtime path match `src/shader_runtime.cpp:211-592` and `E:777-966` line by line. `%.9g` validation text equals C/Qt output for f32-promoted bounds (probe compared against `printf`).
- **Snippet GLSL:** equals the baseline literal (`E:320-330`).
- **Isolation harness:** refuses the caller bus and runtime directory (`isolated-session.sh:39-43`).
- **Scope:** no new features found. The GUI strings in `controller.ui` match `src/controller_main.cpp:69-165`.

## Commands run

| Command | Result |
|---|---|
| `nix-build gnome/default.nix -o /tmp/wsB-gnome-result` | exit 0; `/nix/store/ffybgfharjdjpkzvarw0bvjd937dmqfs-waylandshader-gnome-0.1.0`. `nix log` of that path shows checkPhase `100% tests passed, 0 tests failed out of 13`, GL and GL 3.3 not skipped (T-NIX) |
| `nix-build default.nix -o /tmp/wsB-kwin-result` | exit 0; `/nix/store/3jf7jj0ri7bgws68nkxk4v4bsmb7f39d-waylandshader-0.1.0` (T-KWIN) |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/wsB-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/wsB-build --parallel && cmake --build /tmp/wsB-build --target gnome_abi_check gnome_native && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/wsB-build --output-on-failure'` | exit 0; ABI targets built (T-ABI); 13/13 passed: lifecycle, recent, native_contract, common/native/client/ctl/gui units, GL, GL33, cli_golden, elf, ban (T-LIFE, T-RECENT, T-UNIT-*, T-GL, T-GL33, T-CLI-GOLDEN, T-BAN, build-tree T-ELF and T-CONTRACT) |
| `git diff --exit-code b223c1a -- gnome/extension gnome/org.waylandshader.GnomeController.desktop gnome/native/waylandshader-effect.h gnome/tests/effect-lifecycle.js gnome/tests/recent-presets.js gnome/tests/parameter-bypass.js src tests CMakeLists.txt default.nix shell.nix shader-library.nix patches` | exit 0 (T-UNCHANGED); `waylandshader-effect.cpp` is deleted (1621 deletions) |
| `diff "$BASE/$EXT/native/WaylandShader-1.0.gir" "$R/$EXT/native/WaylandShader-1.0.gir"` (R=/tmp/wsB-gnome-result) | exit 0 (T-GIR) |
| T-LAYOUT block (`diff <(cd "$BASE" && find . \| sort) <(cd "$R" && find . \| sort)`) | exit 0 |
| T-WRAP block | exit 0 |
| `nix-shell gnome/shell.nix --run 'gnome/tests/elf-check.sh "$R/$EXT/native/libwaylandshader-gnome.so" "$R/bin/.waylandshader-gnomectl-wrapped" "$R/bin/.waylandshader-gnome-controller-wrapped"'` | exit 0 (installed T-ELF) |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js <native dir>'` on baseline and on the installed Odin build | both exit 0, `Native byte/error contract passed.` (T-CONTRACT) |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/wsB-gnome-result -- sh -c "gjs -m gnome/tests/parameter-bypass.js \"\$WS_PRIVATE_BUS\""'` | exit 0, `PASS: bypassed edits remain inactive…` (T-BYPASS) |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- gnome/tests/iso-cli.sh /tmp/ws-baseline-result/bin/waylandshader-gnomectl > /tmp/wsB-iso-base.log && gnome/tests/isolated-session.sh /tmp/wsB-gnome-result -- gnome/tests/iso-cli.sh /tmp/wsB-gnome-result/bin/waylandshader-gnomectl > /tmp/wsB-iso-new.log && diff /tmp/wsB-iso-base.log /tmp/wsB-iso-new.log'` | both exit 0, 515-line logs, diff empty (T-ISO-CLI) |
| Throwaway GI probe in `/tmp` (deleted afterwards): prepend the native dir via `GIRepository`, `W.Effect.new()`, then `import_settings(S)` / `export_settings()` / `get_status()` / `set_outputs()` for the inputs listed in B1, B2, B5, B8; run on both builds and diffed | exit 0. The baseline and Odin outputs differ exactly as stated in B1, B2, B5 and B8. `\v{}`/`\f{}`, BOM, NUL, tab, empty or whitespace document, `1e400`, outputs at the int32 bounds, scale > 64, `-0` geometry, unchanged-gamma no-op, and `load_preset` of a directory or missing file are identical |
| Same probe: `load_preset(<symlink to name with byte 0xFF>)`, then `get_status()` | baseline returns valid JSON (U+FFFD); Odin `get_status` raises `String from C value is invalid UTF-8…` (B6) |
| `env XDG_DATA_DIRS=<empty> GIO_USE_VFS=local dbus-run-session --config-file=<nix dbus>/share/dbus-1/session.conf -- sh probe.sh`; probe.sh refuses the caller bus, starts `gjs -m gnome/tests/hang-shell.js`, then runs each ctl with `--timeout 30 status` | both rc=3; stderr differs as stated in B3 |
| `nix-shell gnome/shell.nix --run 'objdump -d --no-show-raw-insn /tmp/wsB-build/libwaylandshader-gnome.so \| grep -B6 "call.*cogl_framebuffer_clear4f"'` | `mov $0x1,%esi` before both calls (B7) |
| `grep -n -A6 cogl_framebuffer_clear4f …/mutter-18/cogl/cogl/cogl-framebuffer.h`; `grep` of `clutter-color-state-params.h`, `clutter-frame.h`, `clutter-timeline.h`, `librashader.h` | signatures and struct order checked (B7, B9) |
| `odin run` and `cc` of a throwaway `%.9g` comparison (deleted) | Odin and C output are identical for all 11 values |
| `grep -nE 'Qt\|QFileDialog\|C\+\+\|libepoxy' README.md docs/GNOME.md` | hits reviewed (B14) |

Not run: T-ISO-RENDER and T-GUI (manual observation that agents cannot do here; see B4) and T-HW (user only). I did not perform the T-SAFETY manual sign-off beyond reading the harness and the build log.

## Round 2

REJECT

Reviewed rework commit `88c69ec` (`git rev-parse --short HEAD`, clean tree). The rework items are listed in `acceptance.md:178-188` and the builder's evidence in `build-log.md:290-372`. Per the main agent's ruling, manual-class tests are deferred to the user, so B4 no longer blocks on its own.

I re-ran the full headless suite, T-KWIN and both isolated-session tests, and all pass. I then probed both builds side by side through standalone GI with about 120 parser inputs, 66 numbers, 27 paths, surrogates, outputs and the raw-`0xFF` symlink.

**Fixed:** all seven rework items reproduce as fixed: A-01's six counterexamples, A-02's `.`/`..`/`//` cleanup, A-03, A-05, B2, B3 and B6. My round-1 B1 subset of `1.`, raw LF, `1e-4000`, `\u+123`, `{"a":`, `[1,]`, `{"a":[}`, `-`, `01`, `é` and the lone surrogates is also fixed. The new regressions can fail:
- `native-contract.js` fails against the round-1 Odin build.
- `cli-golden.sh check` fails case 107 on the round-1 ctl.
- A wrong `GList` size breaks the C gate and the Odin `native` and `controller/gui` builds.

**Why REJECT:** the rework introduced one REQ-068 regression (R2-1) and left REQ-068 and REQ-006 differences that the baseline reproduces (R2-2, R2-3).

No module was loaded into the live Shell and nothing was installed or enabled. The native module ran only in standalone `gjs` and in `isolated-session.sh` sessions. Temporary fixtures and probes were created with `mktemp` and deleted afterwards.

### Findings

| ID | Severity | REQ | file:line | Evidence | Required fix |
|---|---|---|---|---|---|
| R2-1 | blocking (regression) | REQ-068 | `gnome/common/json_parse.odin:21-28,200-206` | **UTF-8 BOM.** A leading U+FEFF (`EF BB BF`) is accepted by the baseline and was also accepted by the round-1 Odin build (`94656d9`). The new byte scanner rejects it. `import_settings('\ufeff{}')` and `import_settings('\ufeff{"version":1,"enabled":false}')` give: baseline `ok` (export `enabled:false`), round 1 `ok`, round 2 `illegal number`. `set_outputs('\ufeff[]')` gives baseline `ok`, round 2 `illegal number`. The same parser feeds the client's status validation. [INFERENCE: Qt's `QJsonPrivate::Parser` skips a UTF-8 BOM before the first token; the behavior itself is reproduced.] | Skip one leading `EF BB BF` in `parse_json` before the first token. Add both BOM documents to `native-rework-baseline.json`, captured from the baseline first. |
| R2-2 | blocking | REQ-068 (open part of round-1 B1) | `gnome/common/json_parse.odin:50-53,146-148,96,87`; top-level dispatch `:205-206` | **Accepted by the baseline, rejected by round 2:** `{"version":1,"x":.5}`, `-.5` and `{"version":.5e1}` (baseline: `Unsupported settings version`). Round 2 gives `illegal number` for all three, so Qt accepts numbers with a leading `.`. **Same verdict, different error text (baseline / round 2):** `{1:2}` and `{'version':1}` give `unterminated object` / `object is missing after a comma`; a string truncated after `\` or `\u` at end of input gives `invalid escape sequence` / `unterminated string`; a top-level `]` or `}` gives `object is missing after a comma` / `illegal value`. `{1:2}` and the single-quote case were already listed in round-1 B1. | Accept `.digits` and `-.digits` numbers as the baseline does. Make the non-string-key, truncated-escape and top-level close-token errors match the baseline. Pin all of these inputs from the baseline in `native-rework-baseline.json`/`json_parse_test.odin`. |
| R2-3 | blocking | REQ-006/007 (open part of A-02) | `gnome/native/config.odin:102-120` (`clean_absolute`) | **Trailing slash on a missing saved preset.** The baseline keeps one trailing `/`; Odin drops it. Exported `preset` (status `preset`/`requestedPreset` are the same), baseline vs round 2: `/a/./` gives `/a/` vs `/a`; `/a//b//` gives `/a/b/` vs `/a/b`; `/a/b/` gives `/a/b/` vs `/a/b`; `/a/b/../` gives `/a/` vs `/a`; `/nx/x.slangp/` gives `/nx/x.slangp/` vs `/nx/x.slangp`. These match: `/a/b/.`, `/a/b/..`, `/a/..`, `/..`, `/../`, `/.`, `/a/b//.`, `/x/../../y.slangp`, `/../../tmp//m.slangp` and the three fixtures in `native-contract.js`. Saved presets in practice never end in `/`, but REQ-006 requires byte equality for fixed inputs, and A-02 was upheld as blocking on this exact contract. | Keep a single trailing `/` when the input ends in `/` and the cleaned result is not `/`. Pin the five inputs above from the baseline. |
| R2-4 | minor | REQ-058 test validity (T-WRAP) | `docs/waterfall/01-requirements/requirements.md:190` | The catalog's T-WRAP `grep -o` command passes in the host shell for both the baseline and Odin (exit 0). Run inside `nix-shell gnome/shell.nix`, GNU grep 3.12 prints `binary file matches` for the ELF wrapper and the check fails, for the baseline too. This is a test-command fragility, not a build defect. | Use `grep -ao` in the catalog command. |
| B7 | minor (open) | REQ-061/062 | `gnome/native/mutter.odin:101` | `cogl_framebuffer_clear4f(..., buffers: u32, ...)` vs `unsigned long` in `cogl-framebuffer.h:654-655`. Unchanged. | `buffers: c.ulong`. |
| B8 | minor (open) | REQ-017 | `gnome/native/config.odin:152` | The baseline still keeps `/a.ſlangp` in `recent_presets`; round 2 drops it (probe `recentFold`). `/K.\u212Aslangp` and `/x.SLANGP\u0131` behave the same on both builds. | Unicode fold of the suffix, or an accepted deviation. |
| B9 | minor (mostly closed) | REQ-061 | `gnome/native/abi-check.c:75-104`; `gnome/runtime/libra.odin:25-33` | Field-offset asserts were added on both sides. `LIBRASHADER_CURRENT_VERSION == 2` is still not asserted, while `runtime.odin` passes a literal `2`. | `VALUE(LIBRASHADER_CURRENT_VERSION, 2)`. |
| B10 | minor (open) | REQ-016 | `gnome/tests/native-contract.js` | Still no test calls any entry point with NULL or invalid UTF-8 (`grep "Invalid UTF-8 argument" gnome/tests gnome/*/*_test.odin` finds nothing). | Add a native unit or C-level check. |
| B11 | closed | REQ-063 | `gnome/native/paint.odin:174-185`; `native_test.odin:29-75` | The production `before_paint_output` loop is now measured: 100 warmed iterations of shader, color, nil, missing and disabled cases, with heap and temp delta 0. The builder's injected-allocation controls failed as intended (`build-log.md:342-343`). `discover`/`capture_context` (EGL calls) are still unmeasured; reading the code, I found no allocation in their steady state. | — |
| B12 | minor (open) | REQ-032 | `gnome/native/paint.odin:166` | `first_frame` is still set before the source copy (baseline sets it after, `E:1141-1145`). | As in round 1. |
| B13 | minor (open) | REQ-037 | `gnome/controller/client/client.odin:271-279` | A non-`(s)` `statusChanged` still raises a transport error [INFERENCE: Qt ignores it]. | As in round 1. |
| B14 | minor (open) | REQ-066 | `docs/GNOME.md:148` | Still says the package runs only `gnome_effect_lifecycle`. | Update the sentence. |
| B2, B3, B5→A-02, B6 | closed | REQ-005/006/041/043/009 | `common/json.odin:39-81`; `client.odin:55-63,174-178`; `config.odin:179-185,244-246`; `engine.odin:286-289` | **B2:** all 66 probed numbers, including the eight from round 1, export the same bytes on both builds. **B3:** `cli-golden.sh check` passes 107/107 (case 107: exact NoReply stderr, exit 3), and fails on the round-1 ctl. **B6:** a byte-verified `…bad\xff.slangp` target behind a UTF-8 symlink gives the same `bad�` text on both builds for `load_preset` status, `import_settings` export and status; output is valid UTF-8. Lone `\ud800`/`\udfff` in recents, parameter keys and output ids export identically. Mapping `IO_ERROR_CLOSED` to NoReply rests on libdbus's synthesized pending-call reply [INFERENCE, not reproduced]. | — |

### Commands run (round 2)

| Command | Result |
|---|---|
| `git rev-parse --short HEAD`; `git status --short` | `88c69ec`; clean tree (the `review-A.md` modification belongs to reviewer A) |
| `nix-build gnome/default.nix -o /tmp/wsB2-gnome-result` | exit 0, `/nix/store/ywyrarmhrk5mpmq09fnj07ncwwb448lh-waylandshader-gnome-0.1.0`; `nix log` shows checkPhase 13/13 passed, 0 failed, GL and GL33 not skipped, cli_golden 16.75 s (T-NIX) |
| `nix-build default.nix -o /tmp/wsB2-kwin-result` | exit 0, `/nix/store/wsr8a4prijih9xrwgrq7sjki9jpr3mx3-waylandshader-0.1.0` (T-KWIN) |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/wsB2-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/wsB2-build --parallel && cmake --build /tmp/wsB2-build --target gnome_abi_check gnome_native && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/wsB2-build --output-on-failure'` | exit 0; 13/13 passed in 46.76 s (T-ABI, T-LIFE, T-RECENT, T-CONTRACT, T-UNIT-*, T-GL, T-GL33, T-CLI-GOLDEN, T-ELF, T-BAN) |
| `gnome/tests/elf-check.sh` on the installed `.so` and both wrapped binaries; T-GIR `diff`; T-LAYOUT `diff <(find…)`; T-UNCHANGED `git diff --exit-code b223c1a -- …` | all exit 0 |
| T-WRAP catalog block in the host shell, for the baseline and for Odin | both exit 0. The same block inside `nix-shell` exits 1 for both (R2-4) |
| `gjs -m gnome/tests/native-contract.js <native>` for the baseline, round 2 and round 1 (`/tmp/wsB-gnome-result`) | exit 0, 0, **1** (round 1 throws `String from C value is invalid UTF-8`), so the contract can fail |
| `gnome/tests/cli-golden.sh check` with the round-1 ctl, then the round-2 ctl | round 1 fails on case 107 (`: Timeout was reached`); round 2 prints `cli-golden: 107 cases match` |
| `gnome/tests/isolated-session.sh /tmp/wsB2-gnome-result -- sh -c "gjs -m gnome/tests/parameter-bypass.js \"\$WS_PRIVATE_BUS\""` | exit 0, `PASS: bypassed edits…` (T-BYPASS) |
| T-ISO-CLI: `isolated-session.sh` + `iso-cli.sh` for the baseline and round 2, then `diff` | both exit 0; 515-line logs; diff empty |
| Throwaway GI differential probe (about 120 `import_settings` documents, 12 + 15 missing-path imports, recents/parameter/output surrogates, 66 numbers, `set_outputs` edges) on the baseline and round 2, then `diff` | 122 lines each; the only differences are R2-1, R2-2, R2-3 and B8 |
| Throwaway BOM/leading-dot probe on the baseline, round 1 and round 2 | R2-1 confirmed as a regression (round 1 accepted the BOM); leading `.` was rejected by both Odin rounds |
| `mktemp -d` raw-`0xFF` target plus UTF-8 symlink (`readlink \| od -tx1` shows `…62 61 64 ff 2e…`); `load_preset`, `import_settings`, export and status on both builds | identical; output valid UTF-8 (`iconv` check) (B6 closed) |
| Negative control on a `mktemp` copy: `SIZE(GList, 25)` in `abi-check.c`, `size_of(GList) == 25` in `glib/glib.odin`; `cmake --build … --target gnome_abi_check`; `odin build <copy>/gnome/{native,controller/gui} -build-mode:obj -vet -strict-style -define:GL_DEBUG=false` | C: `static assertion failed: "GList size"`; both Odin packages: `Compile time assertion: size_of(GList) == 25`. Copy removed |

Not run: T-ISO-RENDER, T-GUI, T-HW and the T-SAFETY/T-DOCS sign-offs. These are manual-class tests deferred to the user by the main agent's ruling.

## Round 3

REJECT

Reviewed final rework commit `d50af2d` (`git rev-parse --short HEAD`, clean tree). The ten items are listed in `acceptance.md` "Round 2" (numbered rework list) and the builder's evidence in `build-log.md` "Rework round 2". Manual-class tests remain deferred to the user per the main agent's ruling.

All ten round-2 items reproduce as fixed. Every headless and isolated test passes. The new corpus tests can fail: `parser-corpus.js` reports 69 mismatches and `path-contract.js` 39 mismatches against the round-2 Odin build.

I ran a differential fuzz against the baseline, about 230 000 generated inputs in total:
- **JSON documents:** 80 000 malformed or mixed documents without raw BOMs gave 0 differences.
- **Valid settings documents:** 40 000 documents with random doubles (raw bit patterns, scientific, fixed, f32-promoted, large integers), escaped and raw Unicode keys, lone surrogates, `ſ`/`K`/`ı` suffixes and output profiles gave 0 differences across export and status. About 24 000 of them were accepted.
- **Preset paths:** 24 000 missing and existing paths, including symlinks, dangling links, `.`/`..`/`//`/trailing `/` and root escapes, through import, recents and `load_preset`, gave 0 differences.
- **Raw-BOM documents:** 45 000 documents that included raw U+FEFF characters gave 3 differences, all from the same cause: R3-1.

**Why REJECT:** R3-1 is a REQ-068/REQ-005/REQ-006 difference that every Odin round has had (`94656d9`, `88c69ec` and `d50af2d` behave identically). No previous review found it. It is a pre-existing gap, not a regression from this rework.

No module was loaded into the live Shell and nothing was installed or enabled. The native module ran only in standalone `gjs`, in the C `gnome_native_arguments` runner and in `isolated-session.sh` sessions. Fixtures came from `mktemp` and were deleted afterwards.

### Findings

| ID | Severity | REQ | file:line | Evidence | Required fix |
|---|---|---|---|---|---|
| R3-1 | blocking | REQ-068, REQ-005/006, REQ-007/008 (accept/reject) | `gnome/common/json_parse.odin:35-83` (`json_string`); `gnome/native/boundary.odin:31-35` (`text`) | **A leading raw U+FEFF inside a JSON string or a C string argument.** The baseline drops one leading U+FEFF from each string it converts to QString: JSON string values, keys reached by iteration, and every `text()` argument. Odin keeps it. All results below are baseline vs Odin. **Accept/reject differs:** `set_outputs('[{"id":"\uFEFF",…}]')` gives `Output IDs must be nonempty and unique` vs accepted; `import_settings({"version":1,"outputs":{"\uFEFF":{…}}})` gives `Invalid saved output settings` vs accepted; `import_settings({"version":1,"preset":"\uFEFF/x.slangp"})` is accepted with `preset:"/x.slangp"` vs `Saved preset must be an absolute filename`; `load_preset("\uFEFF" + <existing absolute file>)` is accepted vs `Preset must be an absolute readable file`; `set_output_gamma("\uFEFFA", 2)` succeeds vs `Unknown active output: \uFEFFA`. **Export/status bytes differ:** `recent_presets:["\uFEFF/a.slangp",…]` keeps `/a.slangp` vs drops it; parameter keys `"\uFEFF/p.slangp"`/`"\uFEFFg"` export as `/p.slangp`/`g` vs keeping the BOM (which also changes key sort order); output id/name `"\uFEFFA"`/`"\uFEFFN"` show in status as `A`/`N` vs keeping it. **What matches:** escaped `\ufeff`, a BOM in mid-string, a second BOM (`"\uFEFF\uFEFF/c.slangp"` is dropped by both), and lookup by raw key (`{"\uFEFFversion":1}` gives `Unsupported settings version` on both; `"enabled"` plus `"\uFEFFenabled"` are distinct keys on both). The document-level BOM (R2-1) is fixed. [INFERENCE: the same parser feeds the client's `accept_json`, so a BOM-prefixed status string would differ in the CLI/GUI too; not reproduced.] Practical reachability is very low: GNOME connector ids and saved paths do not start with U+FEFF. But REQ-068 requires the same accept/reject decisions, and earlier rounds upheld equally rare inputs (leading `.`, trailing `/`) as blocking. | Strip one leading `EF BB BF` when `json_string` produces a value, and in `text()`. Keep object lookup on raw key bytes so `"\uFEFFversion"` still does not match `version`, but strip the BOM from keys when they are iterated for export, status, outputs and parameters. Add the cases above to `parser-corpus-baseline.json`/`path-contract-baseline.json` from a baseline capture. If the user prefers to accept the difference instead, it must be recorded as a new deviation in `decision.md`; no such deviation exists now. |
| R3-2 | minor (process) | — | `docs/waterfall/GATES.md:5-8`; `docs/waterfall/README.md:3`; `requirements.md:190,197` | `requirements.md` (a phase-1 artifact) was edited in `d50af2d`: the T-WRAP command now uses `grep -ao`, and the CTest list adds three entries. Acceptance authorized the edit (R2-4), but `GATES.md` has no entry for it or for any rework round. README requires a new gate entry. | Add gate entries for rework rounds 1–2 and the catalog change. |
| R2-1, R2-2, R2-A-02 | closed | REQ-068 | `json_parse.odin:84-108,109-183,184-200` | Document BOM (import and `set_outputs`), `.5`/`-.5`/`.5e1`, `{1:2}`/`'…'` keys, truncated `\`/`\u`, top-level `]`/`}`, `{}"`/`{}tru`: all match. 0 differences in 80 000 malformed BOM-free fuzz documents. `parser-corpus.js` passes 275/275 on the baseline and the final build, and fails on round 2 (69 mismatches) | — |
| R2-3, B8 | closed | REQ-006/007, REQ-017 | `config.odin:103-149` | The trailing-slash cases, root escapes, `/a/../`-style cases and `ſ`/`K`/`ı` suffixes match. 0 differences in 24 000 path-fuzz cases (missing paths, existing files, symlinks, dangling links) and 40 000 recents/parameter documents. `path-contract.js` passes on the baseline and the final build, and fails on round 2 (39 mismatches) | — |
| R2-4 | closed | T-WRAP | `requirements.md:190` | `grep -ao` gate inside `nix-shell` exits 0 for both the baseline and Odin | — |
| B7, B9 | closed | REQ-061/062, REQ-020 | `mutter.odin:102`; `abi-check.c:160-163` | `buffers: c.ulong`; a real-header prototype `_Static_assert` and `VALUE(LIBRASHADER_CURRENT_VERSION, 2)` compile in my build. I did not repeat the builder's negative controls. | — |
| B10 | closed | REQ-016 | `gnome/tests/native-arguments.c:20-53`; `CMakeLists.txt:107-110` | `gnome_native_arguments` checks NULL and byte `0xFF` on three mutators, and exits 0 against the baseline, round 2 and final libraries. It is coverage for behavior that already worked, and it would fail if `text()` validation regressed. | — |
| B12 | closed | REQ-032 | `paint.odin:160-175,239-254` | The anchor is now set only after `copy_shader_source` succeeds. While the anchor is unset, `frame_timing` returns number 0, so the first successful frame is 0 as in the baseline (`E:1141-1148`). Checked by source reading plus the passing native unit; no GL fault was injected. | — |
| B13, B14 | not upheld by acceptance | — | — | Not reopened. | — |

### Commands run (round 3)

| Command | Result |
|---|---|
| `git rev-parse --short HEAD`; `git status --short` | `d50af2d`; clean |
| `nix-build gnome/default.nix -o /tmp/wsB3-gnome-result` | exit 0, `/nix/store/fz2myjcnbvp6qq9fm7j8z5dji5jf7dwb-waylandshader-gnome-0.1.0`; `nix log` shows checkPhase **16/16** passed (including `gnome_parser_corpus`, `gnome_path_contract`, `gnome_native_arguments`), GL and GL33 not skipped (T-NIX) |
| `nix-build default.nix -o /tmp/wsB3-kwin-result` | exit 0, `/nix/store/r5vq09z7v951xd3sq7d7f9xvzyx92mrc-waylandshader-0.1.0` (T-KWIN) |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/wsB3-build … && cmake --build … --parallel && cmake --build … --target gnome_abi_check gnome_native && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/wsB3-build --output-on-failure'` | exit 0, 16/16 passed in 47.36 s |
| `/tmp/wsB3-build/gnome_native_arguments <lib>` for the baseline, round 2 and final | all exit 0 |
| `gjs -m gnome/tests/{native-contract,parser-corpus,path-contract}.js <native>` for the baseline, final and round 2 | baseline and final: all exit 0 (`275 cases match`); round 2: native-contract 0, parser-corpus **1** (69 mismatches), path-contract **1** (39 mismatches) |
| Installed T-ELF (`elf-check.sh`), T-GIR, T-LAYOUT, T-UNCHANGED; T-WRAP (`grep -ao`) inside `nix-shell` for the baseline and final | all exit 0 |
| `isolated-session.sh` + `parameter-bypass.js` on the final build | exit 0, `PASS: bypassed edits…` (T-BYPASS) |
| `isolated-session.sh` + `iso-cli.sh` for the baseline and final, then `diff` | both exit 0; 515 lines; empty diff (T-ISO-CLI) |
| Throwaway GI fuzz `fuzz.js` (grammar plus byte mutation, raw BOM allowed), seeds 1–3 × 15 000, on the baseline and final, `diff` | 3 differences, all `set_outputs` with id `"\uFEFF"` (R3-1) |
| Throwaway `fuzz2.js` (same, BOM-free, more escapes and numbers), seeds 11–14 × 20 000 | 0 differences (each seed about 1 250 accepted; every error category present) |
| Throwaway `fuzz3.js` (valid settings: random doubles, Unicode/escaped keys, surrogates, suffix folds, outputs), seeds 21–24 × 10 000 | 0 differences (about 24 000 accepted) |
| Throwaway `fuzz4.js` (preset paths over a `mktemp` tree with a file, a directory, symlinks and a dangling link; import, recents and `load_preset`), seeds 31–33 × 8 000 | 0 differences |
| Targeted BOM probes: in-string and key BOMs through `import_settings`/`set_outputs`; BOM-prefixed `load_preset`/`set_output_gamma`/`set_output_shader_enabled` arguments, on the baseline and final, plus the same in-string probe on round 1 and round 2 | results as in R3-1; round 1, round 2 and final behave identically |

Not run: T-ISO-RENDER, T-GUI, T-HW and the T-SAFETY/T-DOCS sign-offs (manual-class, deferred to the user).

## Round 4

ACCEPT

Reviewed rework-round-3 commit `6f6709d` (`git rev-parse --short HEAD`, clean tree). The sole item is R3-1; the builder's evidence is `build-log.md` "Rework round 3". Manual-class tests remain deferred to the user, and the main agent is running T-GUI/T-ISO-RENDER itself, so I started no devkit session.

**R3-1 is fixed on every surface I found in round 3, and on the client surface I had only inferred.** Native JSON values, iterated keys and C-string arguments now drop exactly one leading raw U+FEFF, as the baseline does. Escaped `\ufeff` and second or mid-string BOMs are kept, and raw-key lookup is unchanged.

**Raw-BOM differential fuzz:**
- 180 000 cases (import, export/status, `set_outputs`, `set_output_gamma`/`set_output_shader_enabled`/`set_parameter`/`load_preset` with BOM-prefixed arguments, colliding keys) gave **0** differences against the baseline.
- The same generator gives 7 129 differences in 20 000 cases against the round-3 build, so it is sensitive to R3-1.

**BOM-free regression fuzz:** 80 000 documents (random doubles, escapes, surrogates, suffix folds, truncations) gave 0 differences.

**New client-side check:** a private-bus fake Shell returned BOM-bearing status strings, and the baseline and final `waylandshader-gnomectl status|outputs|parameters` produce identical stdout, stderr and exit codes for all 5 fixtures. The round-3 CLI differs on 3 of them. This confirms that my round-3 [INFERENCE] about the client path was real and is now fixed.

**Process changes are justified:**
- **CTest manifest:** the `requirements.md` amendment only adds the new `gnome_bom_contract` (`requirements.md:197`).
- **PipeWire link:** the `docs/GNOME.md:291-297` devkit exception matches the harness. The harness refuses the caller bus or runtime directory before it links anything (`isolated-session.sh:39-41` precede `:55-60`). It links only `$WS_CALLER_RUNTIME/pipewire-0`, and only when `WS_DEVKIT=1`. It has no other `ln`.
- **Why the link is needed:** it fixes the round-1 devkit `Failed to connect pipewire context` (`build-log.md:49`). It grants no new privilege, because the disposable Shell runs as the same user and could already reach that socket by absolute path [INFERENCE].
- **Cleanup:** the private root is removed with `rm -rf`, which deletes the symlink without following it.

No module was loaded into the live Shell and nothing was installed or enabled.

### Findings

| ID | Severity | REQ | file:line | Evidence | Required fix |
|---|---|---|---|---|---|
| R3-1 | closed | REQ-068, REQ-005/006/007/008, REQ-039 | `gnome/common/json_parse.odin:9-50,77-97,176-200,235-252`; `gnome/native/boundary.odin:31-38`; `gnome/native/config.odin:150-249`; `gnome/controller/client/status.odin:31-130`; `gnome/controller/ctl/main.odin:109,119,205` | Fuzz and fixtures as above. `bom-contract.js` (1 285 records), `parser-corpus.js` (369) and `path-contract.js` all pass on the baseline and final builds. Against round 3 they fail with 216, 16 and 8 mismatches, so the tests can fail. Provenance is document-scoped (`map[rawptr]` per parsed document). Entries are removed before strings are freed, and duplicate keys transfer the last encoding. I found no lifetime defect by reading the code, and fuzz across error paths showed no crash. | — |
| R4-1 | minor (process) | — | `docs/waterfall/GATES.md` (last row "User decision") | Gate rows now exist for rework rounds 1–2 (closing my R3-2), but there is no row for implementation rework 3 or for this round's amendments to `requirements.md`/`docs/GNOME.md`. `README.md:3` requires a gate entry for changes to an earlier artifact. | Add the rework-3 gate row when recording this round's acceptance. |
| PipeWire link | not a defect | REQ-065 | `gnome/tests/isolated-session.sh:55-60` | The refusal probe with equal caller/child bus and with the caller runtime as `XDG_RUNTIME_DIR`, both with `WS_DEVKIT=1`, exits 1 (`refusing caller bus or runtime directory`) and leaves the private runtime empty. Headless T-BYPASS/T-ISO-CLI are unchanged. | — |

Still open from earlier rounds: B13/B14 were not upheld by acceptance, and nothing else is open. The deferred manual tests (T-ISO-RENDER, T-GUI, T-HW, T-SAFETY/T-DOCS sign-off) are not counted as passed.

### Commands run (round 4)

| Command | Result |
|---|---|
| `git rev-parse --short HEAD`; `git status --short`; `git diff d50af2d HEAD -- <harness, docs, native, client, parser>` | `6f6709d`; clean; diff reviewed |
| `nix-build gnome/default.nix -o /tmp/wsB4-gnome-result` | exit 0, `/nix/store/61vxhhfjijiqknwl6q9sss8m58vz7l08-waylandshader-gnome-0.1.0`; `nix log` checkPhase **17/17** passed (incl. `gnome_bom_contract`), GL/GL33 not skipped (T-NIX) |
| `nix-build default.nix -o /tmp/wsB4-kwin-result` | exit 0, `/nix/store/9bcgx2b5p9himxwn3dpc07h4ckdwv27r-waylandshader-0.1.0` (T-KWIN) |
| Fresh `cmake` build tree `/tmp/wsB4-build`, ABI/native targets, `LIBGL_ALWAYS_SOFTWARE=1 ctest` | 17/17 passed in 48.36 s |
| `gnome_native_arguments` on the installed final library; installed T-ELF, T-GIR, T-LAYOUT, T-WRAP (`grep -ao`), T-UNCHANGED | all exit 0 |
| `gjs -m gnome/tests/{native-contract,parser-corpus,path-contract,bom-contract}.js` on the baseline, final and round 3 (`/tmp/wsB3-gnome-result`) | baseline and final: all exit 0 (`369 cases match`). Round 3: native-contract 0; parser **1** (16), path **1** (8), BOM **1** (216 mismatches) |
| `isolated-session.sh` + `parameter-bypass.js` (final) | exit 0, `PASS: bypassed edits…` (T-BYPASS) |
| `isolated-session.sh` + `iso-cli.sh` (baseline and final), `diff` | both exit 0; 515 lines; empty diff (T-ISO-CLI) |
| Throwaway raw-BOM GI fuzz (BOM at start, middle or doubled in values and keys, escaped `\ufeff`, mutations; plus `set_outputs`, BOM-prefixed mutator arguments, `load_preset` of an existing `mktemp` file), 8 seeds, 180 000 cases, baseline vs final | **0** differences (about 1 380 accepted documents per 20 000 contained a raw BOM) |
| Same fuzz, seed 1, baseline vs round 3 | 7 129 differences (the fuzz is sensitive) |
| Throwaway BOM-free fuzz (random doubles, escapes, surrogates, suffix folds, truncations), 4 × 20 000 | 0 differences |
| Private `dbus-run-session` with a fake `org.gnome.Shell` returning 5 BOM-bearing status fixtures (BOM before the document, in values/keys/ids, colliding after stripping, empty id after stripping, double document BOM); `waylandshader-gnomectl status/outputs/parameters` baseline vs final, then baseline vs round 3 | final: identical stdout/stderr/rc for all 15 runs. Round 3: differs for 3 fixtures (BOM kept in strings; duplicates and empty id not rejected) |
| Harness refusal probe: `sh gnome/tests/isolated-session.sh --private-child true` with `WS_DEVKIT=1` and (a) child bus equal to the caller bus, (b) `XDG_RUNTIME_DIR` equal to the caller runtime | both exit 1 `refusing caller bus or runtime directory`; nothing linked into the private runtime |

Not run: T-ISO-RENDER, T-GUI (the main agent is running them), T-HW and the sign-offs; no devkit session started by me. All throwaway probes and fixtures were deleted.
