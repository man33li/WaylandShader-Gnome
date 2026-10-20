# Phase 3 implementation build log

## Scope and safety

Implementation follows `../02-design/design.md` and `../01-requirements/requirements.md`. Baseline revision: `b223c1a`. No package is installed in the live desktop, no extension is enabled there, and no mutating call is directed at its session bus. Shell-hosted checks must use the isolated-session harness; manual GUI/render/hardware checks remain user acceptance work.

## Ownership

| Agent | Files |
|---|---|
| Builder | `gnome/CMakeLists.txt`, `gnome/default.nix`, `gnome/shell.nix`, `gnome/native/exports.map`, this log; baseline worktree and integrated verification |
| Builder.Core (ws-code) | `gnome/native/{effect,engine,paint,config,mutter,native_test}.odin`, `gnome/runtime/**`, `gnome/common/**`, `gnome/glib/{glib,gobject}.odin`; native C++ deletion at cutover |
| Builder.Security (ws-security) | `gnome/native/{boundary.odin,abi-check.c}`, `gnome/glib/gio.odin`, `gnome/controller/client/**`, `gnome/tests/{native-contract.js,elf-check.sh,ban-check.sh,isolated-session.sh}`, `gnome/tests/golden/{exports.txt,snippet-decl.glsl,snippet-body.glsl}`; cross-owner safety findings sent to owners |
| Builder.Experience (ws-ux) | `gnome/controller/ctl/**`, `gnome/controller/gui/{view.odin,view_test.odin}`, `gnome/tests/{cli-golden.sh,hang-shell.js,iso-cli.sh}`, `gnome/tests/golden/cli/**`, GNOME sections of `README.md` and `docs/GNOME.md` |
| Builder.Interface (ws-ui) | `gnome/controller/gui/{main,window,gtk}.odin`, `gnome/controller/gui/controller.ui` |

The client is assigned to Security and CLI to Experience, following the design's disjoint ownership table. The builder owns the exports map. All agents were instructed not to run builds/tests/formatters; the builder executes the feasibility gates and combined verification.

## Commands and feasibility gates

Commands run from the repository root unless an absolute path is given. File-reading/navigation tools are not build commands.

| Gate | Command | Result |
|---|---|---|
| S0 | `git worktree add /tmp/ws-baseline b223c1a && nix-build /tmp/ws-baseline/gnome/default.nix -o /tmp/ws-baseline-result` | PASS, exit 0. Baseline result `/nix/store/1jgbzwzcn693s5i4m9p7693d5qnbdrwg-waylandshader-gnome-0.1.0`. |

S1–S4 results and the catalog test table are appended after execution. No unexecuted test is counted as passing.

## Deviations

D1 (monitor popup item tooltips) and D2 (GTK stepping increments ≤ 1e-10) are the design's accepted deviations; typed f32 parameter values must remain exact. No additional behavioral deviation is authorized.

### Initial integration diagnostics

| Command | Result |
|---|---|
| `nix-build default.nix -o /tmp/ws-kwin-result` | PASS (T-KWIN), exit 0; `/nix/store/9wbkn1ckhl09b7sf4gbadpsh6i151p76-waylandshader-0.1.0`. |
| `nix-shell gnome/shell.nix --run 'sh gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | S4 first attempt: test printed `PASS: bypassed edits remain inactive, reject invalid values, and survive the real GPU-runtime rebuild.`, but harness exit 1 because private FUSE mounts were still busy during cleanup. Security corrected private-session cleanup; not yet counted as a gate pass. The disposable Shell started and shut down. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B "$HOME/.cache/waylandshader/build-gnome" -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_abi_check'` | First attempt FAIL: librashader GL records hidden unless `LIBRA_RUNTIME_OPENGL` is defined. Added that compile definition. Configuration also exposed missing private pkg-config requirements `xdmcp` and `libpcre2-8`; added `libXdmcp` and `pcre2` build inputs. |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native --capture'` | FAIL: replacing the inherited typelib path made Pango unavailable. |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native --capture'` | PASS: captured exact initial/fixed settings and status bytes and every tested error message from the baseline. |

The catalog's direct baseline GJS command needs `:$GI_TYPELIB_PATH` appended, as the existing CMake scanner/tests already do. This is an environment correction, not a behavior change.

| Recheck | Command | Result |
|---|---|---|
| S1 C ABI | `nix-shell gnome/shell.nix --run 'cmake -S gnome -B "$HOME/.cache/waylandshader/build-gnome" -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_abi_check'` | PASS, exit 0 after the GL declaration compile definition. All C size/offset/enum assertions compile. The Odin half is a separate gate. |
| S4 headless baseline | `nix-shell gnome/shell.nix --run 'sh gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | PASS, exit 0 after the harness cleanup correction; bypassed edits test passed, disposable Shell stopped, no retained-root warning. Auxiliary private desktop services emit shutdown warnings; those are not WaylandShader failures. |
| S4 devkit baseline | `nix-shell gnome/shell.nix --run 'WS_DEVKIT=1 sh gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | Exit 0 and bypass test PASS. The devkit process launched, but reported `Failed to connect pipewire context`; viewer behavior is unverified. For manual T-ISO-RENDER use design R8's private-bus screenshot fallback, not the live session bus. |

Planner incorporated the observed typelib-path, private pkg-config dependency, and librashader compile-definition corrections into the phase-2 design and catalog. No additional production feature was added.

| S1 command | Result |
|---|---|
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_native gnome_abi_check gnome_introspection'` | First native compile FAIL: foreign variadic declarations put `#c_vararg` after the procedure. The compiler's own `core/c/libc/stdio.odin:261` uses `#c_vararg args: ..any`; diagnostics sent to the owning agents for correction. |
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_native gnome_abi_check gnome_introspection gnome_gltest'` | FAIL: native boolean comparison and inherited `using parent` name conflict; runtime/test compound array literals in `for` expressions need parentheses. Diagnostics returned to Core. |

| S3 command | Result |
|---|---|
| `nix-shell gnome/shell.nix -p xvfb-run --run 'xvfb-run -a odin test gnome/controller/gui -define:ODIN_TEST_NAMES=main.spin_commit_selfcheck -define:ODIN_TEST_THREADS=1 -define:GL_DEBUG=false -out:/tmp/ws-spin-selfcheck "-extra-linker-flags:$(pkg-config --libs-only-L gtk+-3.0 gio-2.0)"'` | FAIL before compilation: `nix-shell` cannot combine this shell-file invocation with `-p` that way; switched to an outer `nix-shell -p xvfb-run` wrapping the project shell. |
| `nix-shell -p xvfb-run --run 'nix-shell gnome/shell.nix --run '\''xvfb-run -a odin test gnome/controller/gui -define:ODIN_TEST_NAMES=main.spin_commit_selfcheck -define:ODIN_TEST_THREADS=1 -define:GL_DEBUG=false -out:/tmp/ws-spin-selfcheck "-extra-linker-flags:$(pkg-config --libs-only-L gtk+-3.0 gio-2.0)"'\'''` | FAIL compiling client compound-literal loops; corrected by Security. |
| Same nested shell command, adding `-define:WS_GTK_SPIN_SELFCHECK=true` | FAIL compiling client test concatenation/non-comparable union, cstring free cast, missing `math.is_finite`, unavailable `strconv.append_float`, and unavailable POSIX `IRWXU`. Diagnostics sent to respective owners; ordinary GUI units do not initialize GTK. |

### Feasibility gates reached

| Command | Result |
|---|---|
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_native gnome_abi_check gnome_introspection gnome_gltest'` | Native library compiled; GL test failed vet checks for unnecessary casts/unused variable and a required cstring→rawptr conversion. Core corrected these. |
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_introspection'` | PASS: scanner and typelib compiler succeed. Generated GIR contains `glib:signal name="status-changed" when="last"`. |
| Registration command below | PASS S1: non-null instance, string status, shutdown; only the four implemented initial API symbols are exported. Full 15-symbol gate remains the final T-ELF. No Odin startup or TLS fallback needed. |
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_gltest'` | PASS. |
| `nix-shell gnome/shell.nix --run 'LIBGL_ALWAYS_SOFTWARE=1 "$HOME/.cache/waylandshader/build-gnome/shader-runtime-gltest" "$PWD/tests/fixtures"'` | PASS S2 host: Mesa 26.1.8 GL 4.6, robust=false/true and two cycles each; temporal isolation, resets, reloads, parameters, base-level sampling, worker/main context sharing and allocation checks passed. Sandbox execution remains part of T-NIX. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh capture /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | PASS: 106 baseline cases captured. |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native'` | PASS baseline T-CONTRACT: exact byte/error oracle validated before use against Odin. |

Registration command (moved outside the table because the JavaScript contains a pipe):

```sh
nix-shell gnome/shell.nix --run 'export GI_TYPELIB_PATH="$HOME/.cache/waylandshader/build-gnome:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" LD_LIBRARY_PATH="$HOME/.cache/waylandshader/build-gnome:$LD_LIBRARY_PATH"; gjs -c '\''const W=imports.gi.WaylandShader; const e=W.Effect.new(); if (!e || typeof e.get_status() !== "string") throw Error("registration failed"); e.shutdown(); print("S1 registration PASS");'\'' && nm -D --defined-only "$HOME/.cache/waylandshader/build-gnome/libwaylandshader-gnome.so"'
```

| S3 corrected gate | Result |
|---|---|
| `nix-shell -p xvfb-run --run 'nix-shell gnome/shell.nix --run '\''xvfb-run -a odin test gnome/controller/gui -define:WS_GTK_SPIN_SELFCHECK=true -define:ODIN_TEST_NAMES=main.spin_commit_selfcheck -define:ODIN_TEST_THREADS=1 -define:GL_DEBUG=false -out:/tmp/ws-spin-selfcheck "-extra-linker-flags:$(pkg-config --libs-only-L gtk+-3.0 gio-2.0)"'\'''` | PASS, 1 test successful. Real GTK input handlers preserve tiny/subnormal f32 values and round gamma to two decimals. Xvfb was supplied, but this first invocation did not force GTK's backend or replace the inherited bus; it exercised only widgets, not the effect/client. Later GUI smoke explicitly forces X11 and a private bus. |

Security's cross-owner review identified missing callback context/temp guards and GUI/CLI ownership leaks. Owners corrected their respective files. The invented no-session-bus CLI/GUI early-exit behavior was removed: the original `src/controller_client.cpp:117–122` error is delivered through `ensure_available`, and the GUI remains open.

### Manual render environment

The design R8 fallback was exercised with:

```sh
nix-shell gnome/shell.nix --run 'sh gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- sh -c '\''gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.Screenshot false false "$XDG_CACHE_HOME/fallback.png"'\'''
```

Result: FAIL, exit 1: `org.freedesktop.DBus.Error.AccessDenied: Screenshot is not allowed`. The call targeted only the disposable Shell and its private cache. T-ISO-RENDER remains pending for a user-observed isolated session; neither the unverified viewer nor the denied screenshot counts as visual acceptance.

### Delegated baseline research

Experience additionally ran baseline CLI parsing probes before handing over its files; these were research, not port verification. Bare help/usage cases exited before any D-Bus access; valid commands ran under `XDG_DATA_DIRS=<empty mktemp directory> timeout 20 dbus-run-session -- /tmp/ws-baseline-result/bin/waylandshader-gnomectl …`. Output was summarized rather than retained verbatim. The authoritative reproducible record is now the 106 captured `gnome/tests/golden/cli/cases.txt` cases and their `.out/.err/.code` files.

Observed probe outcomes: help (`--help`, `-h`, `--h`, `-hh`) exited 0; malformed options and argument/range errors exited 2; valid commands without Shell exited 3. Numeric probes covered whitespace/leading plus, decimal/exponent forms, overflow/underflow, subnormal values, invalid numeric spellings and gamma/saturation bounds. No agent ran an Odin build or test independently.

T-DOCS terminology search was performed with the tool equivalent of `grep -nE 'Qt|QFileDialog|C\+\+|libepoxy' README.md docs/GNOME.md`. Remaining hits describe KWin, explicitly contrast backends, identify the original baseline oracle, or record the historical migration; none directs the GNOME build to Qt.

The baseline native-contract command was repeated after Security added idle-deferred/coalesced status-signal, unchanged-value suppression, and reentrant `get_status()` assertions. It again passed (exit 0); byte fixtures were unchanged.

### Baseline isolated CLI oracle

Executed `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-baseline-result -- gnome/tests/iso-cli.sh /tmp/ws-baseline-result/bin/waylandshader-gnomectl'`, capturing stdout to `/tmp/ws-iso-base.log` and stderr to `/tmp/ws-iso-base.stderr` through the tool's subprocess API. PASS, exit 0: all expected exit-code assertions and restore/load/error paths completed. Unknown monitor is usage exit 2, as the original CLI source specifies.

The first capture exposed an orchestration defect: a private calendar service wrote a PID-bearing shutdown message to stdout after the transcript. Security was asked to route ancillary bus/Shell/service stdout to stderr while preserving only the invoked command's stdout. The baseline transcript must be captured again after that fix; this run is not a clean comparison oracle.

### JSON parser compatibility correction

Pinned Odin `core/encoding/json/parser.odin` rejects duplicate object keys (261–264), drops empty keys (270–275), accepts a parsed value without requiring EOF (35–50), and recurses without a JSON depth limit (179–201). Core added `common/json_parse.odin`, reusing the standard tokenizer/unquote helpers while matching Qt container parsing, last-key-wins, empty keys, EOF, and depth 1024. Native and client share it; direct regression tests cover these compatibility cases. This is a necessary implementation correction, not a new accepted behavioral deviation.

Repeated the baseline isolated CLI command after descriptor routing was corrected: PASS, exit 0, all 23 step exit assertions passed and stdout ends with the final status JSON only. `/tmp/ws-iso-base.log` now holds the clean baseline comparison oracle; private session diagnostics are separate.

The native build command now depends on `gnome_abi_check`, so the header-based ABI gate completes before scanner-driven loading can proceed.

## Integrated build and test execution

| Command | Result |
|---|---|
| `rm /tmp/ws-cli-golden/a.slangp /tmp/ws-cli-golden/A.SLANGP /tmp/ws-cli-golden/b.txt && rmdir /tmp/ws-cli-golden` | PASS: removed only the three known fixtures left by the original baseline capture, before the corrected exclusive-directory test runner. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B "$HOME/.cache/waylandshader/build-gnome" -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel'` | Initial full build FAIL: common parser and CLI subset switches needed explicit partial-switch declarations under vet; common tests referenced unavailable `math.inf`/`math.nan`; GUI imported unused GDK. Owning agents received diagnostics. |

Inspection of the original timeout golden also exposed private bus/GVFS diagnostics mixed into CLI stderr, including a rejected GVFS mount attempt in the inherited runtime directory. No live bus was used. Experience was instructed to isolate the CLI cases' writable XDG directories and preserve only actual CLI stdout/stderr through separate descriptors. Baseline goldens will be recaptured; PID-bearing service logs are not acceptable golden data.

| Additional integrated command | Result |
|---|---|
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel'` | Second full build: CLI, GUI and GL test compiled; native failed because `matrix` is a reserved Odin parameter name. Core renamed it. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh capture /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Recapture PASS: all 106 cases, with private XDG directories and actual CLI-only stdout/stderr. |
| Nonnative CTest command below | T-GL, T-GL33 and T-CLI-GOLDEN PASS. T-UNIT-COMMON/client failed at the new parser's EOF handling; common number output had a leading plus. T-UNIT-CTL exposed a wrong test oracle for negative-option parsing. T-UNIT-GUI exposed the same leading-plus assumption in f32 formatting. Diagnostics returned to owners. |
| GUI startup command below | Expected timeout exit 124 after 3 seconds: controller stayed running, no GtkBuilder/XML failure. The private session emitted environmental GTK module/accessibility warnings. This is a startup smoke, not T-GUI acceptance. |

```sh
nix-shell gnome/shell.nix --run 'LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir "$HOME/.cache/waylandshader/build-gnome" -R "^gnome_(common_units|client_units|ctl_units|gui_units|cli_golden|shader_runtime_gl|shader_runtime_gl33)$" --output-on-failure'
nix-shell -p xvfb-run --run 'nix-shell gnome/shell.nix --run '\''xvfb-run -a dbus-run-session -- env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 timeout 3 "$HOME/.cache/waylandshader/build-gnome/waylandshader-gnome-controller"'\'''
```

The expanded baseline native-contract `--capture` command was run twice as the C6 parser matrix grew. Both exited 0. Baseline accepts depth 1024 and duplicate-last-wins/empty keys, rejects depth 1025 and trailing text, and accepts unknown string escapes (for example `\q` becomes `q`). Exact parser error messages are embedded in the contract test. Port parser behavior is corrected to this oracle, not to a stricter JSON interpretation.

| Correction checks | Result |
|---|---|
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel'` (third full build) | Native compile FAIL: test int/string conversions, map cast syntax and vet shadowing in config/paint/engine. CLI/GUI/GL compiled. Diagnostics sent to Core without weakening compiler flags. |
| `nix-shell gnome/shell.nix --run 'ctest --test-dir "$HOME/.cache/waylandshader/build-gnome" -R "^gnome_(common_units\|client_units\|ctl_units\|gui_units)$" --output-on-failure'` | Client, CLI and GUI units PASS. Common parser test failed a bounds check on an empty token while testing a malformed document; Core notified. The pipe characters in this table are Markdown-escaped, not shell escapes. |
| Explicitly isolated S3 command below | PASS, 1 real GTK precision test, forced X11/Xvfb and a private D-Bus. No native effect was loaded by this widget test. |

```sh
nix-shell -p xvfb-run --run 'nix-shell gnome/shell.nix --run '\''xvfb-run -a dbus-run-session -- env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 odin test gnome/controller/gui -define:WS_GTK_SPIN_SELFCHECK=true -define:ODIN_TEST_NAMES=main.spin_commit_selfcheck -define:ODIN_TEST_THREADS=1 -define:GL_DEBUG=false -out:/tmp/ws-spin-selfcheck "-extra-linker-flags:$(pkg-config --libs-only-L gtk+-3.0 gio-2.0)"'\'''
```

| Full integration command | Result |
|---|---|
| `nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir "$HOME/.cache/waylandshader/build-gnome" --output-on-failure'` | Build PASS. 12/13 CTest entries PASS: lifecycle, recents, native contract, common/native/CLI/GUI units, GL 4.6, GL 3.3, CLI goldens, ELF and ban checks. Client units alone exposed acceptance of leading vertical-tab/formfeed by the standard tokenizer. |

The earlier common OOM test trap was a test-allocator mistake: `mem.nil_allocator()` intentionally returns `(nil, nil)`, not an allocation error. Core replaced it with an allocator returning `.Out_Of_Memory`, preserving error-path coverage. The common units then passed.

The baseline's exact leading-whitespace error was probed, rather than assuming strict JSON error wording:

```sh
nix-shell gnome/shell.nix --run 'export GI_TYPELIB_PATH="/tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" LD_LIBRARY_PATH="/tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$LD_LIBRARY_PATH"; gjs -c '\''const W=imports.gi.WaylandShader; const e=W.Effect.new(); for (const s of ["\v{}", "\f{}"]) {try {e.import_settings(s); print("accepted");} catch(err) {print(err.message);}} e.shutdown();'\'''
```

Exit 0; both cases reported `illegal number`. Core and Security received this oracle to correct the parser and the earlier test expectation (`illegal value`). Rejection itself remains mandatory.

| Nix/package checks | Result |
|---|---|
| `git diff --exit-code b223c1a -- gnome/extension gnome/org.waylandshader.GnomeController.desktop gnome/native/waylandshader-effect.h gnome/tests/effect-lifecycle.js gnome/tests/recent-presets.js gnome/tests/parameter-bypass.js src tests CMakeLists.txt default.nix shell.nix shader-library.nix patches` | PASS T-UNCHANGED, exit 0, no output. |
| Final baseline native-contract command (same non-capture command above) | PASS, including final C6 depth/escape/whitespace assertions. |
| `nix-build gnome/default.nix -o /home/knd/.cache/waylandshader/gnome-result` | First sandbox attempt FAIL before checkPhase: Odin emits `-l:/absolute/store/path/stb_image_write.a`; its root library-search flag is removed by the compiler wrapper's purity filter. The archive exists in the compiler package. Sandbox also exposed missing private `mount.pc`; added `util-linux`. |

For the bundled archive, `preBuild` adds `-L/` through `NIX_LDFLAGS`, without disabling sandboxing or compiler purity. This lets the existing absolute archive reference resolve; no external library or tracked binary fixture is added. The private pkg-config dependency list now also includes `util-linux`.

The parser reuses the core tokenizer but requires a checked string decoder: core's unquote helper truncates unknown escapes that Qt accepts. This refines the earlier tokenizer/unquote description; baseline tests cover the decoder.

Second invocation of `nix-build gnome/default.nix -o /home/knd/.cache/waylandshader/gnome-result` still failed at the vendor archive link: adding `-L/` through `NIX_LDFLAGS` was ineffective and has been removed. The linker wrapper filters short `-L/` arguments; CMake now passes the equivalent GNU linker option `-Wl,--library-path=/`, retaining Odin's absolute-archive lookup without disabling the wrapper or sandbox. This does not add `/` to runtime RPATH.

Private pkg-config closure inspection (`gio-2.0.pc:24`, `libselinux.pc:10`) also required `libselinux` and `libsepol`, now explicit build inputs. The second attempt exposed the missing SELinux metadata after `mount.pc` was supplied.

Third `nix-build gnome/default.nix -o /home/knd/.cache/waylandshader/gnome-result`: archive-link correction PASS, all native/controller/GL targets and GIR built. checkPhase passed 12/13 tests, including both real-GL variants without skips. Only CLI goldens failed because the sandbox has no `/etc/dbus-1/session.conf`. `postPatch` now supplies the Nix D-Bus package's `share/dbus-1/session.conf` to that test runner; the bus remains private.

The remaining Pango private metadata requirement (`pango.pc:9` → `libthai.pc:9`) added `libthai` and `libdatrie` to the explicit build-input closure. No production frontend/runtime dependency was replaced or added for new functionality.

Fourth `nix-build gnome/default.nix -o /home/knd/.cache/waylandshader/gnome-result`: **PASS**, exit 0, all **13/13** checkPhase tests passed, including GL 4.6 and GL 3.3 (neither skipped). Produced `/nix/store/i9fw0s2n9qml24cs5z41vfj9xmacrjlm-waylandshader-gnome-0.1.0`; both controller binaries were wrapped and the native/GIR/schema layout installed.

The successful configure still reported missing private metadata for `libxml-2.0` (xkbregistry) and `libzstd` (libtiff); `libxml2` and `zstd` were added rather than suppressing those dependency warnings. The same Nix build command is being run against that final input closure.

Fifth Nix invocation passed all 13/13 tests and produced `/nix/store/74ya2h2xks1817sw0v0p02nhishs0n7w-waylandshader-gnome-0.1.0`. The last private metadata warning (`atspi-2` → `xtst`) added `libXtst`. T-ELF now additionally rejects a runtime RPATH/RUNPATH entry exactly `/`.

Installed-artifact checks on that result: **T-GIR PASS** (`diff` against baseline GIR), **T-LAYOUT PASS** (sorted relative package-path sets identical), **T-ELF PASS** (installed native library and both wrapped ELF binaries, including no root runtime path), **T-WRAP PASS** (wrapper contains GTK 3 schema directory and `org.gtk.Settings.FileChooser.gschema.xml` exists).

### Isolated native crash investigation

`nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /nix/store/74ya2h2xks1817sw0v0p02nhishs0n7w-waylandshader-gnome-0.1.0 -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` failed: the **disposable** Shell (PID 87919) segfaulted while starting a shader load. The live Shell was never loaded with this module.

`coredumpctl info 87919` identified `waylandshader::start_load` at module offset `0x31d65`, called by `work_idle`. REA's objdump provider was unavailable (configured command ENOENT), so the bounded fallback command was:

```sh
nix-shell gnome/shell.nix --run 'objdump -d --start-address=0x31d10 --stop-address=0x31da0 /nix/store/74ya2h2xks1817sw0v0p02nhishs0n7w-waylandshader-gnome-0.1.0/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so'
```

At `0x31d5d` the code calls the nested-map lookup; at `0x31d65` it immediately dereferences the returned pointer. The source directly iterates `e.overrides[e.pending]` when no overrides entry exists. Core was assigned an explicit comma-ok lookup correction and regression coverage. Headless success is not compositor acceptance; T-BYPASS remains failed until the corrected isolated run passes.

Core corrected the confirmed missing-map dereference by extracting the actual load-job snapshot path and checking map presence before iterating a local value. Native regression coverage now exercises nil outer maps, absent preset keys, present empty maps, populated overrides with deep-copy isolation, output keys and generation. The same Nix build/checkPhase command is being rerun before any isolated replay.

Sixth Nix invocation: **PASS 13/13**, produced `/nix/store/gv1h6cdysfxfkr694s17rw78af4a221y-waylandshader-gnome-0.1.0`; private pkg-config metadata warnings are resolved. Replayed T-BYPASS via the harness using `$R`: **PASS**, exit 0, including real GPU-runtime rebuild. The missing-map crash is resolved.

T-ISO-CLI then ran against `$R`, with stdout `/tmp/ws-iso-new.log`, stderr `/tmp/ws-iso-new.stderr`, followed by `diff /tmp/ws-iso-base.log /tmp/ws-iso-new.log`: **FAIL**. It exposed two additional real defects: f32-derived metadata printed an extra decimal digit, and loading the intentionally broken replacement preset aborted the disposable Shell (PID 96725) with `free(): invalid pointer`.

`coredumpctl info 96725` (saved `/tmp/ws-failed-load-core.txt`) locates the abort in `job_destroy`, via `mem_free_with_size`. Bounded `objdump -d --start-address=0x31750 --stop-address=0x317f0 <gv1h…native/libwaylandshader-gnome.so>` identified the freed field as `job.error` (offsets 0x10/0x18). Core is correcting error ownership at the explicit return boundary rather than modifying named return strings in `defer`, and adding a failed-load regression. The working-preset-on-failure contract cannot be marked passing until replay succeeds.

### Final isolated corrections and acceptance

Core replaced deferred return-value mutation with explicit load-error ownership. The GL regression now performs a real failed replacement on its guarded worker, reads/frees the returned error after join, and verifies the existing runtime still renders. A native unit also frees an early failure after the temp guard ends. Common and GUI formatting now find the shortest rounded significant-digit sequence that round-trips; exact f32-derived metadata and tiny-value text regressions were added.

Seventh `nix-build gnome/default.nix -o /home/knd/.cache/waylandshader/gnome-result`: **PASS**, all **13/13** checkPhase entries, no skipped tests. Final tested package:

```text
/nix/store/8j24rh5ab53zcz1lz9j89q0dd4pybshv-waylandshader-gnome-0.1.0
```

Replayed the isolated CLI command with `$R`, captured `/tmp/ws-iso-new.log` and `/tmp/ws-iso-new.stderr`, then ran `diff /tmp/ws-iso-base.log /tmp/ws-iso-new.log`: **both exit 0, empty diff**. Every expected step exit code passed, including failed replacement preserving the running preset and settings restoration after extension reactivation. **T-ISO-CLI PASS**.

Replayed `isolated-session.sh "$R" -- sh -c 'gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'`: **T-BYPASS PASS**, exit 0. Repeated installed T-GIR, T-LAYOUT, T-ELF and T-WRAP on this final package: all passed.

Final installed checks used:

```sh
diff "$BASE/$EXT/native/WaylandShader-1.0.gir" "$R/$EXT/native/WaylandShader-1.0.gir"
diff <(cd "$BASE" && find . | sort) <(cd "$R" && find . | sort)
nix-shell gnome/shell.nix --run 'gnome/tests/elf-check.sh /home/knd/.cache/waylandshader/gnome-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so /home/knd/.cache/waylandshader/gnome-result/bin/.waylandshader-gnomectl-wrapped /home/knd/.cache/waylandshader/gnome-result/bin/.waylandshader-gnome-controller-wrapped'
```

T-WRAP used the catalog's GTK-schema-path regex through the tool's JavaScript API and checked the named schema file exists; no wrapper was executed against the live bus.

The final build-tree catalog run uses:

```sh
nix-shell gnome/shell.nix --run 'cmake --build "$HOME/.cache/waylandshader/build-gnome" --parallel && cmake --build "$HOME/.cache/waylandshader/build-gnome" --target gnome_abi_check gnome_native && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir "$HOME/.cache/waylandshader/build-gnome" --output-on-failure'
```

Final build-tree run: **PASS**, ABI targets built and **13/13** CTest entries passed in 36.24 seconds. Both real-GL tests ran (no skips). `rm /tmp/ws-spin-selfcheck` reported it already absent (exit 1); Odin's test invocation had already removed that temporary executable. No throwaway source or binary was added to the repository.

## Final test-ID results

Automated acceptance: **22/22 test IDs passed**. All five manual catalog IDs remain pending user/reviewer signoff; automated checks do not stand in for visual or hardware observation.

| Test ID | Final result | Evidence / remaining work |
|---|---|---|
| T-UNCHANGED | PASS | Protected paths identical to `b223c1a`; exact catalog diff exited 0. |
| T-ABI | PASS | Real-header C assertions and Odin layout assertions compile; final explicit ABI/native targets succeed. |
| T-ELF | PASS | Build-tree and installed checks: 15 API exports, SONAME/private librashader dependency, no direct Qt/libstdc++, no `/` runtime path. |
| T-GIR | PASS | Final installed GIR is byte-identical to baseline. |
| T-LIFE | PASS | Unchanged GJS lifecycle regression, sandbox and build tree. |
| T-RECENT | PASS | Unchanged recent-presets regression, sandbox and build tree. |
| T-CONTRACT | PASS | Same final byte/error/signal/C6 assertions pass baseline and Odin. |
| T-UNIT-COMMON | PASS | JSON writer/parser, shortest numbers, UTF-16 ordering, depth/errors/OOM. |
| T-UNIT-NATIVE | PASS | Timing, selection, zero-allocation, ABI-adjacent formatters, GLSL and load-job/error lifetime regressions. |
| T-UNIT-CLIENT | PASS | Status validation, classification, cancellation/closed-client and parser compatibility. |
| T-UNIT-CTL | PASS | Parser, numeric grammar, selectors and fixture validation. |
| T-UNIT-GUI | PASS | Pure view functions, rounding and exact shortest f32 text/round trips. |
| T-GL | PASS | Real GL 4.6, worker loading, failed replacement, context restoration and zero-allocation render; no skip. |
| T-GL33 | PASS | Same real regression with GL 3.3 override; no skip. |
| T-CLI-GOLDEN | PASS | All 106 baseline stdout/stderr/exit-code cases match. |
| T-BAN | PASS | Native/runtime/common/GLib source bans and build cutover checks. |
| T-NIX | PASS | Final package builds; checkPhase 13/13 passed. |
| T-LAYOUT | PASS | Sorted relative installed-path sets match baseline. |
| T-WRAP | PASS | GTK file-chooser schema is present in the controller wrapper's schema path. |
| T-KWIN | PASS | Root `nix-build default.nix -o /tmp/ws-kwin-result` succeeded; shared source/build files unchanged. |
| T-BYPASS | PASS | Final Odin package passes unchanged regression in disposable Shell. |
| T-ISO-CLI | PASS | Both runs exit 0; all expected step exits pass; final transcript diff empty. |
| T-ISO-RENDER | PENDING — manual | Visual checklist not observed. Private devkit lacks PipeWire context; attempted private screenshot fallback was access-denied. |
| T-GUI | PENDING — manual | Startup smoke and real spin-handler spike pass; complete chooser/debounce/accessibility/app_id checklist needs user observation. |
| T-SAFETY | PENDING — manual signoff | Harness and log reviewed; native modules ran only in disposable Shells. Initial widget-only spike inherited its desktop environment, disclosed above; later GUI checks forced private bus/X11. |
| T-DOCS | PENDING — manual signoff | GNOME wording/recipes updated and terminology hits reviewed; final human review remains. |
| T-HW | PENDING — user only | Physical AMD/HDR/hotplug/suspend acceptance is not performed by agents. |

## Final handoff

- Tested GNOME result: `/home/knd/.cache/waylandshader/gnome-result` → `/nix/store/8j24rh5ab53zcz1lz9j89q0dd4pybshv-waylandshader-gnome-0.1.0`.
- Tested KWin result: `/tmp/ws-kwin-result` → `/nix/store/9wbkn1ckhl09b7sf4gbadpsh6i151p76-waylandshader-0.1.0`.
- Baseline retained at `/tmp/ws-baseline-result`; clean baseline/Odin CLI transcripts retained at `/tmp/ws-iso-base.log` and `/tmp/ws-iso-new.log`.
- Both isolated native crashes were fixed at their causes and covered by new regressions; neither is an accepted deviation.
- Accepted behavioral deviations remain only D1 (monitor-popup item tooltips) and D2 (GTK stepping ≤1e-10; typed values remain exact).
- No commit, live extension install/enable, live native-module load, or live compositor restart was performed. Do not install into the live session before phase-4 acceptance and the user's hardware check.
