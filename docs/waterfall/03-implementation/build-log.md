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

## Rework round 1

Round-1 acceptance rejected A-01, A-02, A-03, A-05 and imported B2/B3/B6 (`../04-verification/acceptance.md:178–188`). These independently observed failures are treated as ground truth; existing passing fixtures are not sufficient acceptance. Manual render/GUI/hardware and safety/docs signoff remain deferred as ruled in acceptance.

### Disjoint ownership

| Agent | Rework / owned files |
|---|---|
| Builder.ReworkCore | B2 and A-05: `common/json.odin`, `common/json_test.odin`, `native/paint.odin`, `native/native_test.odin` |
| Builder.ReworkSecurity | A-01/A-02/B6: `common/json_parse.odin`, `common/text.odin`, parser/text tests, `native/boundary.odin`, `native/config.odin`, native-contract and its baseline/path fixtures |
| Builder.ReworkABI | A-03: C ABI gate and concrete mirrors in native/Mutter, runtime EGL/librashader, shared GLib/GObject and GUI GTK |
| Builder.ReworkBus | B3: client/GIO local error mapping, client units and appended private timeout golden |
| Builder | CMake integration, baseline captures, positive/negative verification, final package/KWin builds and this log |

No subagent runs builds/tests. String representation changes are coordinated across the parser, writer and C-string boundaries; raw canonical filename replacement remains distinct from escaped lone-surrogate preservation.

### Baseline-first regression evidence

1. Executed the existing native-contract command with `--capture` against `/tmp/ws-baseline-result` after adding the rework fixtures (standalone GJS, no Shell/session calls):

   ```sh
   nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native --capture'
   ```

   **PASS, exit 0.** Exact observations were saved to `local://rework1-native-baseline.json` and pinned without alteration in `gnome/tests/native-rework-baseline.json`. Covers all accepted parser counterexamples, high/low lone surrogates and ordering, all eight numeric counterexamples plus existing small/f32 numbers, three non-clean missing paths, and byte-verified raw-FF canonical filename direct-load and restored/export state. Qt preserves excess `..` above root (`/../../tmp//missing.slangp` → `/../../tmp/missing.slangp`); the fallback must not use a root-clamping normalizer.

2. Executed `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh capture-new /tmp/ws-baseline-result/bin/waylandshader-gnomectl'`. **PASS, exit 0**, 107 total cases after appending the per-call timeout. The new mode writes only absent cases and does not replace any existing baseline golden.

CMake's compile-only ABI target now includes `${GTK3_INCLUDE_DIRS}`, so assertions against GTK headers compile with the existing real-header gate.

### Integration execution

| Command / check | Result |
|---|---|
| Baseline native-contract without `--capture`, first attempt | FAIL before assertions: GJS has no web `URL` constructor. Fixture loading corrected to `Gio.File.new_for_uri(import.meta.url)`; oracle unchanged. |
| Same baseline native-contract command after loader correction | PASS, `Native byte/error contract passed.` |
| `nix-build gnome/default.nix -o /tmp/ws-rework1-result`, first rework attempt | Build/ABI PASS; 12/13 tests PASS, including all new native differential cases, number/parser units, real GL and 107 CLI goldens. Existing client `"not json"` expectation exposed malformed literal dispatch (`illegal number` instead of `illegal value`). No golden was weakened. |
| Standalone baseline GI `import_settings` for `"not json"`, `"tru"`, `"fals"`, and `{"version":1,"x":nul}` | All four baseline errors are exactly `illegal value`; exit 0 with caught GErrors. Parser keyword dispatch corrected and common regression added. |
| `mktemp -d /tmp/ws-rework1-negative.XXXXXX`; `cp -a gnome <private-root>/gnome` through the tool subprocess API | Created `/tmp/ws-rework1-negative.AYoCtd` for deliberate source mutations only. Production sources remain untouched by negative controls. |

The new parser uses checked byte scanning rather than the incompatible standard tokenizer. Internal WTF-8 preserves escaped UTF-16 surrogate code units, which the JSON writer emits as `\ud800`/`\udfff`; raw external filename bytes and actual C-string arguments are independently replacement-decoded to valid UTF-8. This distinction is covered by the baseline-pinned native cases and common text tests.

### Positive and negative verification

| Command / regression | Observed result |
|---|---|
| `nix-build gnome/default.nix -o /tmp/ws-rework1-result` after malformed-literal correction | **PASS**, real configure/build/checkPhase/install; **13/13 passed, no skips**, 16.66 seconds. Includes every new common/native/client regression and all 107 CLI goldens. |
| `nix-build default.nix -o /tmp/ws-rework1-kwin` | **PASS**, actual KWin C++ compile/link/install. This is a build check, not a KWin runtime test. |
| Acceptance's six assertion-presence checks, run with `nix-shell gnome/shell.nix --run 'gjs -c <coverage body from acceptance.md:97–110>'` | **PASS 6/6**: shared GList/GObject, GUI GError/GList and C GList/GObject assertions present. |
| Copied C gate: change only `SIZE(GList, 24)` to `SIZE(GList, 25)`; `cmake -S <copy>/gnome -B <copy>/build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build <copy>/build --target gnome_abi_check` | **EXPECTED FAIL**, exit 1, real-header `_Static_assert` reports `"GList size"`. |
| Initial copied Odin invocation `odin check ... -build-mode:obj` | Invalid invocation: `check` does not accept `-build-mode`; not counted as a negative-control pass. Replaced with the supported build command below. |
| Copied Odin gate: change only shared `#assert(size_of(GList) == 24 …)` to 25; `odin build <copy>/gnome/<package> -build-mode:obj -out:<copy>/<package>.o -vet -strict-style -define:GL_DEBUG=false`, for native, controller/gui, controller/ctl and runtime | **EXPECTED FAIL in all four**, exit 1 at the exact `size_of(GList) == 25` compile-time assertion. |
| Restore both copied ABI assertions. Insert `probe,_:=make([]u8,1,context.allocator); delete(probe);` inside the actual `before_paint_output` loop; `ctest --test-dir <copy>/build -R '^gnome_native_units$' --output-on-failure` | **EXPECTED FAIL**, exit 8: measured `heap_delta` is **1400**, expected 0. No callback context reset hides the allocation. |
| Replace that copied injection with `probe,_:=make([]u8,1,context.temp_allocator); delete(probe,context.temp_allocator);`; same native CTest | **EXPECTED FAIL**, exit 8: measured `temp_delta` is **1400**, expected 0. |
| Remove copied allocation injection; `cmake --build <copy>/build --target gnome_abi_check && ctest --test-dir <copy>/build -R '^gnome_native_units$' --output-on-failure` | **PASS**, exit 0, real C gate and restored native regression pass. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-rework1-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''` | **PASS**, unchanged real GPU-runtime bypass/rebuild regression in disposable Shell. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-rework1-result -- gnome/tests/iso-cli.sh /tmp/ws-rework1-result/bin/waylandshader-gnomectl'`, stdout captured to `/tmp/ws-rework1-iso.log`, then `diff /tmp/ws-iso-base.log /tmp/ws-rework1-iso.log` | **PASS**, both exit 0 and empty diff against the retained original-baseline transcript. |
| T-UNCHANGED's exact protected-path `git diff --exit-code b223c1a -- …` command | **PASS**, no output. |
| `rm -rf /tmp/ws-rework1-negative.AYoCtd` | Removed only the owned temporary negative-control copy after restoring and testing it. No deliberate mutations remain in production source. |

`<copy>` above was `/tmp/ws-rework1-negative.AYoCtd`; all compiler/test commands ran inside the project's Nix shell. Negative and restored command outputs are retained as `local://rework1-negative-c.log`, `local://rework1-negative-odin-*.log`, `local://rework1-negative-heap.log`, `local://rework1-negative-temp.log` and `local://rework1-restored-controls.log`.

### Per-item results

| Item | Root fix and source | Baseline-pinned / required regression | Result |
|---|---|---|---|
| A-01 | Qt-compatible scanning/errors at `gnome/common/json_parse.odin:21,67,115,200`; lossless surrogate decoding at `gnome/common/text.odin:6`; escaped output at `gnome/common/json.odin:15` | `gnome/common/json_parse_test.odin:9–57`, `gnome/tests/native-contract.js:61–100` and exact `native-rework-baseline.json`: all six counterexamples plus malformed literal/separator controls, lone-high/low bytes and UTF-16 ordering | **PASS** baseline first, then Odin |
| A-02 | Missing-path lexical cleanup at `gnome/native/config.odin:102–120,178–187`, preserving realpath for existing files and excess root-level `..` | Native contract's three missing/non-clean paths assert exact export, status preset and requestedPreset before async completion (`gnome/tests/native-contract.js:101–104`) | **PASS** baseline first, then Odin |
| A-03 | Shared dual checks at `gnome/glib/glib.odin:11–12`, `gnome/glib/gobject.odin:19–22`, GUI shared aliases/assertions at `gnome/controller/gui/gtk.odin:21–26`, C at `gnome/native/abi-check.c:16–32`; expanded Mutter/librashader/EGL/GTK/GIO assertions in their mirror files | All six omitted-layout coverage checks; real-header and all consuming Odin builds; wrong GList size rejected by C and all four Odin consumers | **PASS**, including deliberate compile failures |
| A-05 | Actual production loop extracted at `gnome/native/paint.odin:174–184`; warmed heap/temp measurements at `gnome/native/native_test.odin:29–75` | Active shader/color, nil/missing/inactive cases; positive zero deltas; separate injected heap/temp allocations each detected as 1400; restored source passes | **PASS**, including both negative controls |
| B2 | Qt's precision-preserving integer and shortest-notation policy at `gnome/common/json.odin:39–81`, rather than guessed fixed/scientific thresholds | All eight required numeric exports plus retained small/f32 values, pinned from baseline in `native-rework-baseline.json` and common units | **PASS** byte equality |
| B3 | Local GIO transport errors mapped to async libdbus/QDBus error name/text at `gnome/controller/client/client.odin:58–63,174–178`; GIO constants dual-asserted | Baseline-added `gnome/tests/golden/cli/107.{out,err,code}` from `cases.txt:109`: `--timeout 30 status` exits 3 with exact NoReply stderr and empty stdout. Existing overall-timeout exit-4 cases retained; client mapping units pass | **PASS**, 107/107 goldens |
| B6 | Separate external UTF-8 replacement at `gnome/common/text.odin:20`, canonical paths at `gnome/native/config.odin:179–185,244–246`, worker filesystem boundary at `gnome/native/engine.odin:286–289`, GError and GTK boundaries | Byte-verified actual FF target behind valid UTF-8 symlink; direct load status and restored/committed preset export match baseline replacement text (`gnome/tests/native-contract.js:105–126`), without losing escaped-surrogate semantics | **PASS** baseline first, then Odin |

B2's policy is grounded in Qt 6.10 [`resolveFormat`](https://raw.githubusercontent.com/qt/qtbase/6.10/src/corelib/text/qlocale_tools.cpp), [`doubleValueHelper`](https://raw.githubusercontent.com/qt/qtbase/6.10/src/corelib/serialization/qjsonvalue.cpp) and [`convertDoubleTo`](https://raw.githubusercontent.com/qt/qtbase/6.10/src/corelib/global/qnumeric_p.h), with captured baseline bytes as the test authority. B3's full timeout text is independently pinned by `107.err`; local-close unit handling follows the async libdbus queued-NoReply path, not its different blocking-call error path.

### Rework handoff

- GNOME: `/tmp/ws-rework1-result` → `/nix/store/ww4q6ac99g61ix13z9z21zkxm622nrxw-waylandshader-gnome-0.1.0`.
- KWin: `/tmp/ws-rework1-kwin` → `/nix/store/xg5jjapnkvzd1192nk8d0hibmgiqb27w-waylandshader-0.1.0`.
- All seven upheld items have passing required regressions. No existing baseline golden was changed to match the port; only observed new baseline cases were added.
- Manual T-ISO-RENDER/T-GUI/T-HW and safety/docs signoff remain pending under the acceptance ruling. D1/D2 are unchanged.
- No commit, live native-module load, live extension installation/enabling, compositor restart, or mutating live-session-bus call was performed in this rework round.

## Rework round 2

This final rework addresses the ten items in `../04-verification/acceptance.md:306–319`. Manual observations/signoffs remain deferred under that decision, and D1/D2 are unchanged. Baseline observations remain authoritative; previous goldens are retained.

### Ownership and baseline authority

| Owner | Disjoint work |
|---|---|
| Builder.FinalParser (security) | R2-1/R2-2/R2-A-02 shared parser, common corpus test, new parser differential script/oracle; reviews other slices' C boundaries |
| Builder.FinalPaths (UX) | R2-3/B8 native path/suffix logic, new path/recents differential script/oracle |
| Builder.FinalABI (UI/FFI) | B7 Cogl signature, B9 real-header API version assertion, B10 direct C-entry regression |
| Builder.FinalTiming (code) | B12 frame-anchor transition and native failure/retry units |
| Builder | CMake/test registration, binary-safe T-WRAP catalog repair, all baseline captures/builds/negative controls and this log |

The parser follows the pinned baseline's [Qt 6.11.2 structural-token/cursor parser](https://raw.githubusercontent.com/qt/qtbase/v6.11.2/src/corelib/serialization/qjsonparser.cpp), not eager full-token lexing. Native `QString::fromUtf8` removes one initial BOM and the JSON parser can consume another; captured double-BOM behavior is represented as these two ordered stages, not arbitrary BOM trimming. UTF-8 conversion authority: [qstringconverter.cpp](https://raw.githubusercontent.com/qt/qtbase/v6.11.2/src/corelib/text/qstringconverter.cpp), and baseline native `text()` at `/tmp/ws-baseline/gnome/native/waylandshader-effect.cpp:76–83`.

### Baseline-first executions

| Command / check | Result |
|---|---|
| Repaired catalog T-WRAP inside `nix-shell gnome/shell.nix` with `R=/tmp/ws-baseline-result`, `grep -ao`, first extracted schema path, and the existing file-existence assertion | **PASS**, exit 0. This fixes binary extraction, not package schemas. |
| Initial asynchronous tool-process capture launcher | Tool cell timed out and reset before saving output. Not counted as a baseline result; a bounded native capture below succeeded. |
| `nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" timeout 30s gjs -m gnome/tests/parser-corpus.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native --capture'` | **PASS**, exit 0 in 4.46 seconds. Full output retained; no baseline parser hang. |
| Same parser capture through a synchronous subprocess, and analogous `path-contract.js … --capture` | **PASS**. Exact **269 parser records** and **60 path/recents records** saved as `local://final-parser-baseline.json` and `local://final-path-baseline.json`, then pinned unchanged in the corresponding test baseline JSON files. No unexpected-error records in parser capture. |
| Baseline `parser-corpus.js`, `path-contract.js` and original `native-contract.js`, separately invoked without capture in one Nix-shell command | **PASS**: 269 cases match; 60 path/recents cases match; original byte/error contract passes. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-final-build -G Ninja -DWAYLANDSHADER_BUILD_TESTS=ON && cmake --build /tmp/ws-final-build --target gnome_native_arguments && /tmp/ws-final-build/gnome_native_arguments /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native/libwaylandshader-gnome.so'` | **PASS**, six direct baseline NULL/byte-FF calls return FALSE and exact non-NULL GError domain/code/message. Effect and errors cleaned up. |

Corpus coverage includes initial/misplaced/repeated BOMs; leading-dot, exponent, overflow/underflow and truncated numbers; root/inner trailing-content precedence; object keys before/after commas; raw/truncated/Unicode escapes; container/depth limits; old duplicate/empty-key/surrogate controls; and valid whitespace controls. Common units consume the same captured parser table. Raw invalid UTF-8 bytes are rejected by the native argument guard, but a valid UTF-8 argument containing an unknown escape before a multibyte character can produce the parser's `invalid UTF8 string` error; additional native value/key cases below cover this distinction. Obsolete/non-emitted Qt error enumerators are not falsely claimed exercised.

B12's baseline oracle is the original source ordering: destination allocation at E:1141, source copy at E:1142, anchor at E:1144–1145, previous-time/history after rendering at E:1159–1160. The new regression exercises the shared production state transition and real gamma failure-clear route; it is not represented as an injected driver/GL allocation failure.

CMake registers three additional checks: `gnome_parser_corpus`, `gnome_path_contract`, `gnome_native_arguments`; the complete checkPhase now contains 16 entries. Existing lifecycle/contract timeouts are retained.

### Integration diagnostics and negative ABI controls

| Command / check | Result |
|---|---|
| `nix-build gnome/default.nix -o /tmp/ws-final-result`, first final-round attempt | FAIL at compile: BOM slicing reassigned an immutable Odin parameter. Changed to a local descriptor; baseline fixtures unchanged. Real C ABI/signature/version and C argument-test targets compiled. |
| `nix-shell gnome/shell.nix --run 'cmake --build /tmp/ws-final-build --parallel && LIBGL_ALWAYS_SOFTWARE=1 ctest --test-dir /tmp/ws-final-build --output-on-failure'`, first attempt | FAIL at compile: inline compound-literal loop in the new frame regression needed a local binding. Corrected without changing assertions. |
| Same build/tree-suite command after syntax corrections | Build PASS; **15/16 tests passed**. All 269 parser cases, shared parser corpus, native arguments, native timing/failure/retry tests, old contracts, 107 CLI goldens and real GL/GL33 passed. Broader path corpus exposed three additional baseline differences below; oracle was not weakened. |
| Owned copied `abi-check.c`, expected API version deliberately changed from 2 to 3; C compile with the real pkg-config headers and private librashader include | EXPECTED FAIL, exit 1: `_Static_assert` reports `LIBRASHADER_CURRENT_VERSION value`. |
| Same copy with version restored and expected Cogl mask changed from `unsigned long` to `unsigned int` | EXPECTED FAIL, exit 1: `_Static_assert` reports `cogl_framebuffer_clear4f signature`. |
| Both copied assertions restored; same C compile | PASS, exit 0. Production sources were never mutated by these negative controls. |

The negative copy is `/tmp/ws-final-abi-negative.DeFSju`; compiler invocation:

```sh
cc -DLIBRA_RUNTIME_OPENGL $(pkg-config --cflags libmutter-18 mutter-clutter-18 mutter-cogl-18 mutter-mtk-18 graphene-gobject-1.0 egl gio-2.0 gtk+-3.0) -I/nix/store/gl6nf7xzs0ifldc0h2bxplaw4g22pvs4-waylandshader-librashader-0.10.1/include/librashader -c /tmp/ws-final-abi-negative.DeFSju/abi-check.c -o /tmp/ws-final-abi-negative.DeFSju/abi.o
```

Each invocation ran inside `nix-shell gnome/shell.nix`; outputs retained in `local://final-api-version-negative.log`, `local://final-cogl-signature-negative.log` and `local://final-restored-abi.log`.

The 60-case path matrix caught Qt-specific missing-path behavior beyond the original five cases: `/a/../` and `/a/..//` export `//` in the baseline, and `/a/../..//` exports `/..//`. The first correction emitted `/`, `/`, `/../`. Paths ownership was returned for a source-derived `QFileInfo::absoluteFilePath` correction and additional neighboring baseline controls, not special-case oracle changes.

The path correction now follows Qt 6.11.2 [`QFileSystemEngine::absoluteName`](https://raw.githubusercontent.com/qt/qtbase/v6.11.2/src/corelib/io/qfilesystemengine_unix.cpp) and [`QDir::cleanPath`](https://raw.githubusercontent.com/qt/qtbase/v6.11.2/src/corelib/io/qdir.cpp), including normalization's moving root and the final slash re-append. It does not introduce input-string exceptions.

Additional neighboring root-collapse/trailing-separator cases were captured from the original baseline. Before extending `path-contract-baseline.json`, the capture procedure required **all 60 existing records to remain exactly equal**; that check passed. The extended table contains **77 unique cases**. Baseline non-capture check passes all 77.

`nix-shell gnome/shell.nix --run 'GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/path-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native && cmake --build /tmp/ws-final-build --parallel && ctest --test-dir /tmp/ws-final-build -R "^gnome_(path_contract|parser_corpus|native_units)$" --output-on-failure'`: **PASS**, baseline 77/77 and all three port tests, including parser 269/269 and the new frame transition. Existing baseline expectations were not changed.

The copied C ABI file was restored and recompiled successfully, then `/tmp/ws-final-abi-negative.DeFSju` was removed. No negative-control mutation or throwaway source remains in the repository.

### Final coverage closure and successful executions

- The source-derived path correction passed all **77** baseline-pinned cases; all prior 60 observations were verified unchanged before extending the oracle.
- Native and common parser suites initially passed 269 records. A final error-category check corrected an earlier reachability assumption: valid UTF-8 JSON containing an unknown escape before `é`, `€` or `😀` can still produce `invalid UTF8 string` inside Qt's parser. Baseline probes confirmed this, and six value/key cases were appended. All prior **269 records remained exactly equal**; the final **275-case** native corpus passes both baseline and port without a production-parser change.
- `nix-build gnome/default.nix -o /tmp/ws-final-result` passed the complete **16/16** suite before and after caching the immutable frame count once for the B12 transition. No tests skipped. The subsequent fixture-only corpus extension is included in the final build rerun below.
- `nix-build default.nix -o /tmp/ws-final-kwin` passed a fresh actual C++ compile/link/install: `/nix/store/pipxarlznnafsi31az8b4wg95y1dai28-waylandshader-0.1.0`.
- The repaired documented `grep -ao`/schema-existence T-WRAP gate passed inside the Nix shell on both baseline and port.
- Installed baseline and port were tested in separate processes with the original native contract, parser corpus, path contract and `gnome_native_arguments`: all passed, including six exact NULL/byte-FF assertions per library.
- `gnome/tests/cli-golden.sh check` passed **107/107** on both original and final CLIs. The per-call timeout and overall deadline cases remain pinned.
- T-BYPASS passed in the disposable Shell; fresh baseline and port T-ISO-CLI runs exited 0 and their captured transcript diff was empty. The final frame-count integration artifact was replayed with the same passing bypass and empty CLI diff.
- Installed ELF checks passed; T-UNCHANGED's protected-path diff exited 0 with no output.

The final parser oracle has all twelve reachable native parser-error categories. Raw invalid argument bytes are additionally checked through the C ABI. Obsolete/non-emitted error enumerators and real driver allocation/copy fault injection are not claimed exercised.

### Final artifact verification and per-item results

Final command `nix-build gnome/default.nix -o /tmp/ws-final-result`: **PASS**, fresh configure/build/checkPhase/install, **16/16 passed, no skips**, 16.67 seconds. This build includes the complete 275-case parser oracle, 77-case path/recents oracle, C-entry regression and frame-preparation transition tests.

```text
GNOME /tmp/ws-final-result -> /nix/store/zsiwskpgiapg0f6b9y54hq3vl52fhg66-waylandshader-gnome-0.1.0
KWin  /tmp/ws-final-kwin   -> /nix/store/pipxarlznnafsi31az8b4wg95y1dai28-waylandshader-0.1.0
```

The final installed artifact was replayed with:

```sh
nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-final-result -- sh -c '\''gjs -m gnome/tests/parameter-bypass.js "$WS_PRIVATE_BUS"'\'''
nix-shell gnome/shell.nix --run 'gnome/tests/isolated-session.sh /tmp/ws-final-result -- gnome/tests/iso-cli.sh /tmp/ws-final-result/bin/waylandshader-gnomectl'
diff /tmp/ws-final-iso-baseline.log /tmp/ws-final-iso-port.log
```

**PASS:** bypass exit 0; final CLI exit 0; empty diff against the fresh original-baseline run. The tool subprocess API captured only the commanded stdout into `/tmp/ws-final-iso-port.log`; private service diagnostics were retained separately. Repaired T-WRAP, installed ELF, GIR byte diff and installed-path-set diff also passed on this final artifact.

| Item | Root fix / source | Required regression | Final result |
|---|---|---|---|
| R2-1 | Baseline's ordered initial BOM stages at `gnome/common/json_parse.odin:184–191`; no arbitrary interior trimming | Actual BOM settings/output arrays, misplaced/repeated BOM and whitespace controls in shared **275-case** baseline corpus, through common parsing and real native methods | **PASS** baseline first, then port |
| R2-2 | Qt structural cursor/value parsing, number grammar and contextual errors at `gnome/common/json_parse.odin:27–35,84–183` | All specified leading-dot, key, escape and closing-token cases; broad numeric/separator/escape/depth matrix; all twelve reachable parser-error categories; earlier overflow/underflow/`1.`/surrogate cases retained | **PASS**, 275/275 native records and common units |
| R2-A-02 | Root completion checks remaining non-whitespace without lexing trailing content at `gnome/common/json_parse.odin:192–199` | `{}"`/`{}tru`, array equivalents, nested malformed tails, valid whitespace and primitive-root controls | **PASS**, exact baseline errors |
| R2-3 | Qt `absoluteName`/`cleanPath` normalization and slash re-append at `gnome/native/config.odin:103–143`; realpath unchanged | Five failing paths, three required controls, old cases and expanded root-collapse/repeated-slash neighbors; exact export/preset/requestedPreset/loading comparisons | **PASS**, all 77 path/recents records |
| R2-4 | Binary-safe catalog extraction at `docs/waterfall/01-requirements/requirements.md:190` | Exact `grep -ao` plus schema file-existence gate inside Nix shell on original and final binary wrappers | **PASS** both; repaired test command, not package schema behavior |
| B7 | `buffers: c.ulong` at `gnome/native/mutter.odin:102`; exact real-header function type at `gnome/native/abi-check.c:161–163` | Native consumers and real GL/GL33 pass; copied expected `unsigned int` prototype fails the signature `_Static_assert` | **PASS**, including negative control |
| B8 | Unicode suffix folding over final runes, retaining path bytes, at `gnome/native/config.odin:144–149` | `/a.ſlangp`, ASCII mixed case, Kelvin/dotless-i/nonmatching controls and combined recents ordering/dedup/cap in baseline path corpus | **PASS**, exact baseline retained text |
| B9 | `VALUE(LIBRASHADER_CURRENT_VERSION, 2)` at `gnome/native/abi-check.c:160` | Real header compiles; owned copy expecting version 3 fails; restored copy compiles | **PASS**, including negative control |
| B10 | Persistent raw C-entry test at `gnome/tests/native-arguments.c:20–53`, registered in CTest | Three real exported mutators × NULL/byte-FF: FALSE, non-NULL GError, exact domain/code/message and cleanup; baseline/port separate processes | **PASS**, six checks per implementation |
| B12 | Tentative timing and post-preparation anchor transition at `gnome/native/paint.odin:160–175,239–254`; immutable frame count cached once | Four allocation/copy-failure scenarios with nominal/zero-refresh warm-up, real gamma failure clearing, first successful frame 0 and subsequent numbering; normal timing/history/zero-allocation retained (`gnome/native/native_test.odin:38–82`) | **PASS**; pure production-transition regression, not a claimed driver fault injection |

### Final-round handoff

- All ten requested items have passing required regressions; Security reviewed boundary and lifetime changes.
- Fresh GNOME checkPhase: **16/16**; fresh KWin build: **PASS**; CLI goldens: **107/107** on both original and port; isolated bypass and fresh baseline/port transcript comparison: **PASS**.
- Parser oracle: **275** cases; path/recents oracle: **77** cases. Existing expectations were checked unchanged before extensions. No expectations were captured from the port.
- The API-version/prototype negative copies were removed after restoration and positive recompilation. No diagnostic mutation or throwaway source remains in production.
- No commit or live GNOME installation/enabling/module load/restart/mutating live-session-bus call was performed. Manual render/GUI/hardware observations and safety/docs signoffs remain deferred to the user, not counted as passed. D1/D2 remain unchanged.
- These are finite, executed compatibility and regression results; final phase-4 acceptance remains the reviewer's decision.

## Rework round 3

The user authorized up to five rework rounds and retained GTK 3. This round fixes the two R3-1 surfaces in `../04-verification/acceptance.md:431–440`: JSON string/key conversion and shared native C-string conversion. It also implements the explicitly requested devkit-only access to the caller's `pipewire-0` socket; every other isolation boundary is retained. Historical Round-3 acceptance text describing the earlier two-round limit is superseded by this authorization.

### Ownership and conversion design

| Owner | Disjoint files/work |
|---|---|
| Builder.BomCore | Shared JSON document/provenance and tests; native config extraction; client status extraction/tests; CLI document serialization |
| Builder.BomSecurity | Shared native text boundary/tests; isolated-session single-socket sharing; boundary/lifetime review |
| Builder.BomCorpus | New BOM contract and appended parser/path corpus cases |
| Builder | Build/test integration, baseline captures, negative isolation tests, devkit proof and this log |

The parsed document retains core JSON values and document-scoped UTF8/UTF16 string provenance, plus its allocator. Raw object lookup is unchanged. Text extraction and writing use the source encoding, so a raw UTF8 leading BOM loses one character while an escaped/UTF16 BOM remains. Duplicate keys retain the last encoding/value; discarded metadata is removed before freeing strings, and decoded-key collisions release replaced nested maps. There are no marker bytes, global provenance tables or blanket key trimming. The native text boundary removes one BOM only after validating the original complete C string; the parser's separate document-BOM stage is coordinated with that conversion.

### Baseline-first and isolation checks

| Command / check | Result |
|---|---|
| Original-only `bom-contract.js --capture`, then parser/path capture extensions, using standalone GJS with baseline native directory, `GIO_USE_VFS=local` and the inherited typelib path prepended with Mutter's directory | PASS. **1285 BOM records**, **369 parser records** and **203 path records** pinned. The prior **275 parser records** and **77 path records** were required to remain exactly equal before extensions; both checks passed. Session provenance copies: `local://r3-*-baseline.json`. |
| Baseline `bom-contract.js`, `parser-corpus.js`, `path-contract.js`, `native-contract.js` without capture | PASS: 1285, 369 and 203 cases match, and the original native byte/error contract passes. No port result was used as an oracle. |
| `computer.capabilities()` | Wayland backend: AX read capability granted; screenshot capture unavailable. Final viewer observation will use available read-only window evidence and/or the viewer's Wayland protocol evidence, not claim an unavailable screenshot. |
| `WS_DEVKIT=1` harness with an owned synthetic absolute caller runtime lacking `pipewire-0` | EXPECTED FAIL, exit 1: `devkit requires caller runtime pipewire-0 socket`, before any Shell launch. Synthetic runtime removed. |
| Direct private-child harness with synthetic equal caller/child bus addresses, `WS_DEVKIT=1` | EXPECTED FAIL, exit 1: `refusing caller bus or runtime directory`. Existing guard remains effective before socket sharing. |
| `nix-build gnome/default.nix -o /tmp/ws-r3-result`, first attempt | FAIL at Odin compile: immutable parameter reassignment and runtime string concatenation in new tests. Owner received diagnostics; real C ABI and direct argument-test targets compiled. |

The BOM matrix covers raw/escaped, single/double/middle/only BOMs; raw static-key lookup; iterated-key conversion; duplicate/colliding keys in both orders; a later escape changing storage provenance; saved values/recents/output id/name; and actual exported string-argument calls. Readable preset files are in an exclusive temporary directory; unattached effects lack stage/EGL, so these calls verify request acceptance without starting a shader compile worker.

`WS_DEVKIT=1` now validates an absolute caller runtime and an actual `pipewire-0` socket, then symlinks only that runtime entry into the disposable directory. No lockfile, session-bus socket, other runtime entry or whole directory is linked; the existing host-Wayland viewer connection is unchanged. Headless behavior remains unchanged. User-facing documentation records this exception and the 20-second command; the CTest manifest includes `gnome_bom_contract`.

### Integration corrections and final checks

| Command / check | Result |
|---|---|
| Full external CMake build in `/tmp/ws-r3-build`, first attempt | FAIL at `-vet` shadowing in decoded-key collision cleanup; renamed the local presence flag. CLI/GUI/runtime already compiled. |
| `cmake --build /tmp/ws-r3-build --parallel` followed by full CTest, next attempt | Build PASS, but standalone native contracts crashed and common tracking tests reported retained string allocations. No Shell-hosted test loaded this intermediate module. Root: assigning `context.allocator` inside an `if` block did not survive that block; destruction used the wrong allocator. |
| Corrected document destruction | `destroy_document` now passes its original allocator explicitly into recursive `json.destroy_value` (`gnome/common/json_parse.odin:15–20`). Security retracted its initial allocator-safety assessment and reviewed the correction. Tracking and native temporary-document tests cover the actual lifetime paths. |
| Remaining common fixture parse failure | Odin's formatter interpreted literal JSON braces. Replaced that test's formatter-generated input with constant JSON; expected success and baseline expectations unchanged. |
| Final full external build/CTest | **PASS 17/17**, no skips, 47.15 seconds. |
| `nix-build gnome/default.nix -o /tmp/ws-r3-result` | **PASS**, fresh configure/build/checkPhase/install, **17/17 passed**, no skips, 16.74 seconds. |
| `nix-build default.nix -o /tmp/ws-r3-kwin` | **PASS**, fresh KWin C++ compile/link/install. |
| Installed BOM/parser/path checks plus baseline/port `gnome_native_arguments` in separate processes | **PASS:** 1285 BOM cases, 369 parser cases, 203 path cases, and six exact NULL/byte-FF checks per implementation. |
| Headless `WS_DEVKIT=0` T-BYPASS, additionally asserting no host `pipewire-0` symlink | **PASS**, unchanged GPU-runtime bypass/rebuild test. |
| Fresh baseline and port `WS_DEVKIT=0` T-ISO-CLI, then transcript diff | **PASS**, both runs exit 0 and diff is empty. Files: `/tmp/ws-r3-iso-baseline.log`, `/tmp/ws-r3-iso-port.log`. |
| Installed ELF/GIR/layout checks | **PASS**, exit 0; public ABI and installed paths unchanged. |
| T-UNCHANGED protected-path diff against `b223c1a` | **PASS**, no output. |

### Twenty-second devkit proof

The tested package was `/tmp/ws-r3-result` → `/nix/store/9hfbxb7zajp8fbnhmb5xaglgsn40fcmj-waylandshader-gnome-0.1.0`. The private Shell log explicitly selected that package and said the system extension would not be loaded.

Inside `nix-shell gnome/shell.nix`, the **exact executed command** was:

```sh
WS_DEVKIT=1 WAYLAND_DEBUG=client gnome/tests/isolated-session.sh /tmp/ws-r3-result -- sh -c 'set -eu; test -L "$XDG_RUNTIME_DIR/pipewire-0"; test "$(readlink "$XDG_RUNTIME_DIR/pipewire-0")" = "$WS_CALLER_RUNTIME/pipewire-0"; test ! -e "$XDG_RUNTIME_DIR/pipewire-0.lock"; printf "DEVKIT_READY shell=%s root=%s start=%s\n" "$WS_SHELL_PID" "$WS_PRIVATE_ROOT" "$(date +%s)"; ps -o pid=,ppid=,args= --ppid "$WS_SHELL_PID" || :; sleep 20; kill -0 "$WS_SHELL_PID"; printf "DEVKIT_20S_ALIVE end=%s\n" "$(date +%s)"'
```

**PASS, exit 0.** The assertions confirmed the exact socket symlink and absence of a linked/copied lockfile. Ready/end timestamps were `1792505617` and `1792505637`; the owned Shell remained alive after the 20-second hold, then the harness stopped it.

Read-only desktop inspection did not yield a viewer window through the attempted `devkit` name filter; that lookup was inconclusive (the actual title is “Mutter Development Kit”). Screenshot capture was unavailable on this Wayland provider. No visual screenshot or full manual GUI/render pass is claimed. Instead, the owned client's protocol provides direct window-mapping/presentation evidence:

- Owned Shell **402516** launched viewer **402567** (`mutter-devkit`).
- `xdg_surface#77.get_toplevel` created `xdg_toplevel#78`, with title **Mutter Development Kit** and app id **org.gnome.Mutter.Mdk**.
- The host configured the toplevel to **1280×846**, and `wl_surface#47` entered `wl_output#6`.
- That surface attached buffers and committed them; **159 presentation events** were recorded, including host presentation feedback. This proves a mapped, presented viewer, not merely a spawned process.
- After the command, `ps -p 402516,402567 -o pid=,stat=,args=` returned no processes (exit 1, expected absence). The private root was removed.
- Host `/run/user/1000/pipewire-0` identity stayed **`78:45:socket`** before and after. The host socket was not removed or replaced.

Evidence: `local://r3-devkit-wayland.log` (exact command, process identity, mapping/presentation and shutdown), and bounded `local://r3-devkit-proof.json`. Relevant trace positions: package selection at line 40; toplevel identity at 1766–1773; configure at 2032–2036 and 2511–2515; first buffer/commit at 2466–2468; presentation at 2550; shutdown at 4742. The read-only computer session was closed afterward; no desktop input/control grant was used.

This proves the newly requested devkit startup and teardown path. It does not replace the deferred visual T-ISO-RENDER/T-GUI checklists.

### Per-item results and handoff

| Item | Root fix / source | Executed regression | Result |
|---|---|---|---|
| R3-1: JSON values and iterated keys | Document-owned storage provenance and original allocator at `gnome/common/json_parse.odin:9–50`; explicit conversion at `json_text`/`json_string_value`; raw lookup remains unchanged. Native conversion/collision cleanup at `gnome/native/config.odin:150–249`, client extraction at `gnome/controller/client/status.odin:31–130`, and provenance-aware writer/CLI migration | Original baseline first, then port: **1285** BOM cases, **369** parser cases and **203** path cases; common conversion/lookup/duplicate/allocator tests and all client status-string fields. Raw/escaped/later-escape, repeated/middle/only BOM and lone-surrogate controls retained | **PASS** |
| R3-1: native C-string arguments | Complete UTF-8 validation followed by exactly one leading BOM removal in shared `gnome/native/boundary.odin:31–38`; every existing caller uses that conversion | Actual exported load/output mutator calls and controls in BOM matrix; `gnome/native/boundary_test.odin:6–31`; original six NULL/byte-FF assertions on both libraries in separate processes | **PASS** |
| Devkit-only PipeWire access | `gnome/tests/isolated-session.sh:55–60`: absolute caller-runtime/socket checks, one symlink only, before private Shell startup; existing isolation guards retained | Missing-socket and equal-bus refusal tests; headless no-symlink assertion; exact devkit symlink/no-lockfile assertions; unchanged host socket identity and private-root cleanup | **PASS** |
| Final-package devkit startup/closure | Existing `--devkit` path with the requested one-socket access | Owned viewer toplevel configured, mapped to host output and presented buffers; 20-second hold; owned Shell/viewer PIDs absent afterward. Protocol proof, not a screenshot/manual rendering checklist | **PASS** |
| Existing compatibility/build gates | No public ABI, installed-layout or protected KWin-source change | Fresh GNOME **17/17** checkPhase, fresh KWin build, installed ELF/GIR/layout, protected diff, headless T-BYPASS, fresh baseline/port T-ISO-CLI empty diff, and **107/107** CLI goldens on both implementations | **PASS** |

Final tested artifacts:

```text
/tmp/ws-r3-result -> /nix/store/9hfbxb7zajp8fbnhmb5xaglgsn40fcmj-waylandshader-gnome-0.1.0
/tmp/ws-r3-kwin   -> /nix/store/d6kvi9b689fwndx0bd35lzjz09nh604p-waylandshader-0.1.0
```

GTK 3 and D1/D2 are unchanged. No baseline expectation was changed to fit the port, no commit was made, and no live extension installation/enabling/native-module load or live compositor restart occurred. The only newly authorized host resource was the devkit client's PipeWire socket connection, alongside the existing host-Wayland viewer connection. Full visual GUI/render/hardware acceptance and manual safety/docs signoffs remain deferred; the protocol startup proof does not claim those checks.

## Rework round 4

Scope: **G-1 only**, as requested by `docs/waterfall/04-verification/acceptance.md` Round 4 and `visual-checks.md:44`. The observed failure was an empty accessible name on dynamic parameter spins, despite their buddy relationship and tooltip. The baseline uses the description-or-name label and `setBuddy(spin)` (`/tmp/ws-baseline/src/controller_main.cpp:446–462`).

### Ownership and implementation

- **ws-ui / AccessibleParameters:** `gnome/controller/gui/window.odin` and `gtk.odin`. `build_parameters` now converts `parameter_label(&p)` once and uses the same text for the explicit ATK name and the visible GTK label (`window.odin:619–629`). Existing tooltip, mnemonic-widget association, input handlers and debounce remain in place. The narrow ATK/GTK bindings use opaque object pointers; no new mirrored C structure is introduced.
- **Builder:** `gnome/CMakeLists.txt`, `gnome/default.nix`, new `gnome/tests/gtk-headless.sh`, this log and the CTest coverage-manifest addition in `requirements.md`. The new `gnome_gui_accessibility` CTest explicitly enables `WS_GTK_PARAM_A11Y_TEST` and selects `main.parameter_spin_accessible_name` (`CMakeLists.txt:118–126`). Nix adds `xvfb-run` to check inputs and supplies its store-local D-Bus configuration to the launcher (`default.nix:22–25,61`).
- Core/runtime, UX and security implementation slices were not reopened. The UI owner ran no checks; Builder ran the integration checks below after the UI changes landed.

The real-GTK regression (`window.odin:118–154`) calls the actual `build_parameters` function, not a recreation of the controls. Two consecutive production rebuilds test `{name: GAIN, description: Gain}` → ATK name **Gain**, then `{name: GAIN, description: empty}` → **GAIN**. It reads `atk_object_get_name`, checks the visible label and its mnemonic-widget association, and checks the tooltip. The owned tooltip string is freed, and editors, strings and the GTK grid are cleaned up. Missing display initialization fails the enabled test. The existing pure GUI unit test entry still does not initialize GTK.

The launcher creates private temporary XDG directories, removes inherited Wayland/AT-SPI/session-bus addresses, forces X11 and local GIO, disables the AT-SPI bridge, and runs an owned Xvfb server and private D-Bus session (`gtk-headless.sh:1–12`). This checks the real local GTK/ATK objects without accessing the live compositor or its accessibility bus.

### Commands and observed results

All commands below ran from the repository root. No failed command or retry was needed in this rework.

| Command | Result |
|---|---|
| `nix-build gnome/default.nix -o /tmp/ws-r4-result` | **PASS**, exit 0. Fresh build and full checkPhase: **18/18 passed**, no skips. New accessibility CTest passed in 8.74 s; both GL tests executed and passed. |
| `nix-build default.nix -o /tmp/ws-r4-kwin` | **PASS**, exit 0. Fresh KWin plugin, Qt controller and CLI build/install completed. |
| `nix-shell gnome/shell.nix --run 'cmake -S gnome -B /tmp/ws-r4-build -DWAYLANDSHADER_BUILD_TESTS=ON && ctest --test-dir /tmp/ws-r4-build -R "^gnome_gui_accessibility$" -V'` | **PASS**, exit 0. Verbose command confirms the enable define and exact test-name selection. Odin reported **“Finished 1 test … The test was successful.”** with memory tracking enabled; CTest reported **1/1 passed** in 8.76 s. |

The standalone result confirms this is an executed production-path GTK regression, not merely an inert test compiled into the package.

### Test-ID results

| Test ID / rework coverage | Result this round |
|---|---|
| T-NIX | **PASS** — fresh package, 18/18 CTests passed |
| T-ABI | **PASS** — real-header C ABI target and native Odin package compiled during the fresh GNOME build |
| T-LIFE, T-RECENT, T-CONTRACT (port CTest) | **PASS** — corresponding lifecycle, recent-presets and native-contract tests |
| Parser/path/BOM differential regressions; native argument regression | **PASS** — `gnome_parser_corpus`, `gnome_path_contract`, `gnome_bom_contract`, `gnome_native_arguments` |
| T-UNIT-COMMON, T-UNIT-NATIVE, T-UNIT-CLIENT, T-UNIT-CTL, T-UNIT-GUI | **PASS** — all five Odin unit-test entries |
| T-GL, T-GL33 | **PASS**, neither skipped |
| T-CLI-GOLDEN, T-BAN, T-ELF (build-tree CTest) | **PASS** |
| T-GUI item 9 / G-1 dynamic parameter-name regression | **PASS** — actual ATK names **Gain** and **GAIN**, visible label, buddy association and tooltip checked through production construction; passed in checkPhase and independently |
| T-KWIN | **PASS** — fresh root Nix build |
| Full manual T-GUI / T-ISO-RENDER and physical T-HW | **Not rerun** — this narrowly scoped correction uses headless GTK. Prior visual observations remain in `visual-checks.md`; no new full visual, screen-reader or hardware pass is claimed. Physical testing remains user-owned. |
| Other baseline/install/isolated-session comparisons from earlier rounds | **Not rerun** — not requested for G-1; prior results remain recorded above rather than being claimed as fresh executions |

Tested artifacts:

```text
/tmp/ws-r4-result -> /nix/store/b9hlianbibv0p0vdxijyvrz4ix0zq59l-waylandshader-gnome-0.1.0
/tmp/ws-r4-kwin   -> /nix/store/92abcna6b116qbx90hr1c2pgpqp1s2lq-waylandshader-0.1.0
```

Both builds consumed `/nix/store/3jh4hmks3bryyygnl9md3vrqxxxsxiyj-source`. Only documentation was updated after these successful builds. Build evidence is in Nix derivations `iim9zqvgg5wc34idam5ngc88xilc45kx-waylandshader-gnome-0.1.0.drv` and `3qhx5k6z2i7gip95cj66q6c1d594zg8f-waylandshader-0.1.0.drv`; command transcripts are `artifact://726`, `artifact://727` and `artifact://728`, respectively.

**Deviations:** none. GTK 3, D1/D2, visible wording, parameter editing and debounce are unchanged. No live Shell/native-module load, extension installation/enabling, live-bus mutation or compositor restart was performed. No commit was made.
