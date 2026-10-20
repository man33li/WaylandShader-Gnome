# Phase 4 acceptance

## Round 1

### Decision and review selected

**I side with review A (sol 6.1), and only review A.** Its independently reproducible JSON compatibility/data-preservation failures, missing-file path mismatch, and missing ABI assertions justify returning the build to phase 3. I uphold A-01, A-02 and A-03 as blockers, and A-05 as a regression-coverage defect. I additionally carry over **B2, B3 and B6**, by name, after independently reproducing each below. This is not adoption of review B as a second selected review.

Reviewed HEAD: `94656d9`, confirmed by `git rev-parse --short HEAD` (exit 0). The feature boundary remains the original C++ project, not new functionality (`docs/waterfall/README.md:5`). The phase-4 gate requires passing tests (`docs/waterfall/README.md:12`); passing the existing suite does not override failures of its byte-compatibility requirements (`docs/waterfall/01-requirements/requirements.md:34-35,132`).

**A-04 is not upheld as an acceptance blocker.** Under the main agent's process ruling, manual T-ISO-RENDER/T-GUI observation, T-HW, and T-SAFETY/T-DOCS sign-off are deferred to the user; their pending status alone does not reject this round. They remain pending, not passed (`docs/waterfall/03-implementation/build-log.md:275-279`; checklist definitions at `docs/waterfall/02-design/design.md:530-555`). D1/D2 remain accepted deviations, not defects (`docs/waterfall/02-design/decision.md:60-63`). No other B finding is imported into this decision.

### Commands run and results

Commands ran from the repository root. `BASE=/tmp/ws-baseline-result`, `R=/tmp/ws-acceptance-gnome`, and `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com` are shorthand below; executed native commands used the literal package paths. Only this acceptance document was written in the repository. External filename fixtures were removed after the probes.

| Command / check | Result independently observed |
|---|---|
| `git rev-parse --short HEAD` | Exit 0: `94656d9`. |
| `nix-build gnome/default.nix --check -o /tmp/ws-acceptance-gnome` | Exit 1 before building/testing: this source derivation had no valid existing output, so Nix could not perform a reproducibility check. Not a test pass or a compilation failure; followed by the fresh build below. |
| `nix-build default.nix --check -o /tmp/ws-acceptance-kwin` | Exit 1 for the same missing-output prerequisite; followed by the fresh build below. |
| **T-NIX:** `nix-build gnome/default.nix -o /tmp/ws-acceptance-gnome` | Exit 0; actual configure/build/checkPhase/install, not a cached-output lookup. **13/13 CTest entries passed, 0 failed, no skips**, 7.22 seconds. Both GL and GL33 executed. Real-header C ABI object and Odin native library compiled. Output: `/nix/store/8gqb25b6aan0rhdd277gypnl38jb30pm-waylandshader-gnome-0.1.0`. |
| **T-KWIN:** `nix-build default.nix -o /tmp/ws-acceptance-kwin` | Exit 0; actual C++ compile/link/install. Output: `/nix/store/391v9p1xdqh2pp6ikgi2y7qvd6bnsfm6-waylandshader-0.1.0`. This catalog check is a build, not a KWin runtime test (`docs/waterfall/01-requirements/requirements.md:175`). |
| First native-probe launcher using `GIRepository.Repository.prepend_search_path` | Exit 1: that static API is unavailable in this environment. Replaced with explicit GI/loader environment paths below; no compatibility conclusions drawn from this attempt. |
| Baseline and Odin standalone GI parser/path/number probe, using the environment command and body below | Both exit 0 because the probe catches GErrors. **Compatibility FAIL**: A-01, A-02 and B2 reproduced. Exact observations follow. |
| `nix-shell gnome/shell.nix --run 'gjs -c <ABI-coverage-body>'`, body below | Exit 1: all six named assertion-presence checks fail, reproducing A-03. This is a source-coverage test, not a claim that today's layouts have the wrong size. |
| Targeted search for `before_paint`, `Tracking_Allocator`, and `total_allocation_count` in native/runtime/GUI/GLib sources, followed by reading the matching test and callback bodies | A-05 confirmed: measured native loop calls only `frame_timing`/`select_output`; measured GL loop calls `runtime.render`. Neither measures `before_paint` (`gnome/native/native_test.odin:29-47`; `gnome/runtime/gltest/main.odin:105-115`; `gnome/native/paint.odin:174-180`). No actual steady-state allocation is alleged. |
| Private-bus timeout probe below, baseline then Odin, each `waylandshader-gnomectl --timeout 30 status` | Probe exit 0; **both CLIs exit 3**, stdout empty. Baseline stderr starts `org.freedesktop.DBus.Error.NoReply: Did not receive a reply. Possible causes include:`; Odin stderr is `: Timeout was reached\n`. **Compatibility FAIL**, B3. |
| Initial shell ANSI-C-quoted invalid-filename fixture, then `readlink /tmp/ws-acceptance-b6/link.slangp \| od -An -tx1` | Fixture was unsuitable: target contained UTF-8 `ef bf bd`, not byte `ff`; both builds returned valid text. Discarded as a B6 test and reported the tool byte-preservation issue. |
| Python byte-exact fixture command below, then `readlink /tmp/ws-acceptance-b6/rawlink.slangp \| od -An -tx1` | Exit 0; target contains actual byte `ff` after `rawbad`. |
| Standalone GI `load_preset`/`get_status` probe below, baseline and Odin separately | Both probe processes exit 0 (exception caught). Baseline returns `/tmp/ws-acceptance-b6/rawbad�.slangp`; Odin raises `String from C value is invalid UTF-8 and cannot be safely stored`. **Compatibility FAIL**, B6. |
| Python `os.unlink` of the four external fixture names, then `os.rmdir` of their directory | Exit 0; external B6 fixtures removed. |

The fresh GNOME checkPhase ran: `gnome_effect_lifecycle`, `gnome_recent_presets`, `gnome_native_contract`, `gnome_common_units`, `gnome_native_units`, `gnome_client_units`, `gnome_ctl_units`, `gnome_gui_units`, `gnome_shader_runtime_gl`, `gnome_shader_runtime_gl33`, `gnome_cli_golden`, `gnome_elf`, and `gnome_ban`. These results establish the current suite passes, not that its missing cases pass.

#### Native differential reproduction

For each of the two packages separately, the executed environment pattern was:

```sh
nix-shell gnome/shell.nix --run 'env GI_TYPELIB_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" LD_LIBRARY_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$LD_LIBRARY_PATH" gjs -c '\''<BODY>'\'''
```

`<PACKAGE>` was the literal baseline or acceptance-package path above. `<BODY>` was the following JavaScript (shell escaping omitted):

```js
const W = imports.gi.WaylandShader;
for (const s of [
    '{"version":1.}',
    '{"version":1,"ignored":1e-4000}',
    '{"version":1,"ignored":"\\u+123"}',
    '{"version":1,"ignored":"a\nb"}',
    '{"version":}',
    '{"version":1,"recent_presets":["/x\\ud800.slangp"]}',
    '{"version":1,"preset":"/tmp/ws-acceptance-absent/../missing.slangp"}',
    ...[0.0005, 0.0001, 1234567.5, 12345678.25, 1e16, 9.2e18,
        9223372036854776000, 123456789012345680000].map(n =>
        JSON.stringify({version: 1, parameters: {"/p.slangp": {GAIN: n}}})),
]) {
    const e = W.Effect.new();
    try {
        e.import_settings(s);
        print(JSON.stringify(s) + ' => ' + e.export_settings());
        if (s.includes('ws-acceptance-absent')) print(e.get_status());
    } catch (x) {
        print(JSON.stringify(s) + ' => ERROR ' + x.message);
    } finally {
        e.shutdown();
    }
}
```

| Input / observed value | Baseline | Odin |
|---|---|---|
| `{"version":1.}` | Accepted | `illegal number` |
| `{"version":1,"ignored":1e-4000}` | `illegal number` | Accepted |
| `\u+123` inside ignored string | `invalid escape sequence` | Accepted |
| Raw LF inside ignored string | Accepted | `unterminated string` |
| `{"version":}` | `object is missing after a comma` | `illegal value` |
| Recent path `/x\ud800.slangp` | Export retains escaped `\ud800` | Export replaces it with U+FFFD |
| Missing preset `/tmp/ws-acceptance-absent/../missing.slangp` | `/tmp/missing.slangp` | Unnormalized input |
| Parameter `0.0005` | `5e-04` | `0.0005` |
| Parameter `0.0001` | `1e-04` | `0.0001` |
| Parameter `1234567.5` | `1234567.5` | `1.2345675e+06` |
| Parameter `12345678.25` | `12345678.25` | `1.234567825e+07` |
| Parameter `1e16` | `1e+16` | `10000000000000000` |
| Parameter `9.2e18` | `9.2e+18` | `9200000000000000000` |
| Parameter `9223372036854776000` | `9223372036854776000` | `9.223372036854776e+18` |
| Parameter `123456789012345680000` | `123456789012345680000` | `1.2345678901234568e+20` |

The missing-preset difference appeared in exported `preset` and status `preset`/`requestedPreset`; both statuses had `loading:true`. It therefore does not depend on subsequent shader compilation.

#### ABI assertion-coverage reproduction

The executed `gjs -c` body was:

```js
const GLib = imports.gi.GLib, BA = imports.byteArray;
function read(p) { return BA.toString(GLib.file_get_contents(p)[1]); }
const c = read('gnome/native/abi-check.c');
const checks = [
    ['shared GList Odin assertion', /#assert\([^\n]*size_of\(GList\)/.test(read('gnome/glib/glib.odin'))],
    ['shared GObject Odin assertion', /#assert\([^\n]*size_of\(GObject\)/.test(read('gnome/glib/gobject.odin'))],
    ['GUI GError Odin assertion', /#assert\([^\n]*size_of\(GError\)/.test(read('gnome/controller/gui/gtk.odin'))],
    ['GUI GList Odin assertion', /#assert\([^\n]*size_of\(GList\)/.test(read('gnome/controller/gui/gtk.odin'))],
    ['C GList size assertion', /SIZE\(GList,/.test(c)],
    ['C GObject size assertion', /SIZE\(GObject,/.test(c)],
];
for (const [name, ok] of checks) print((ok ? 'PASS ' : 'FAIL ') + name);
imports.system.exit(checks.every(x => x[1]) ? 0 : 1);
```

All six printed `FAIL`. Direct inspection confirmed these are concrete mirrors, not opaque handles, and their checks are absent (`gnome/glib/glib.odin:9-11`; `gnome/glib/gobject.odin:6-20`; `gnome/controller/gui/gtk.odin:18-28`; `gnome/native/abi-check.c:14-48`). The probe is a targeted reproduction of these omissions, not a general-purpose assertion parser.

#### Private-bus timeout reproduction

Executed launcher:

```sh
nix-shell gnome/shell.nix --run 'env WS_CALLER_BUS="$DBUS_SESSION_BUS_ADDRESS" XDG_DATA_DIRS=/nonexistent GIO_USE_VFS=local dbus-run-session -- gjs -c '\''<BODY>'\'''
```

Body:

```js
const {Gio, GLib} = imports.gi;
const fixture = Gio.Subprocess.new(['gjs', '-m', 'gnome/tests/hang-shell.js'], Gio.SubprocessFlags.NONE);
try {
    const ready = Gio.Subprocess.new(['gdbus', 'wait', '--session', '--timeout', '5', 'org.gnome.Shell'], Gio.SubprocessFlags.NONE);
    if (!ready.wait_check(null)) throw Error('not ready');
    for (const root of ['/tmp/ws-baseline-result', '/tmp/ws-acceptance-gnome']) {
        const p = Gio.Subprocess.new([root + '/bin/waylandshader-gnomectl', '--timeout', '30', 'status'],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        const [ok, out, err] = p.communicate_utf8(null, null);
        print(root + ' exit=' + p.get_exit_status() + ' stdout=' + JSON.stringify(out) + ' stderr=' + JSON.stringify(err));
    }
} finally {
    fixture.force_exit();
    fixture.wait(null);
}
```

The private owner refuses the caller bus (`gnome/tests/hang-shell.js:9-14`). The test exercises the per-call timeout rather than the already-covered one-second overall deadline (`gnome/controller/client/client.odin:162-166`; `docs/waterfall/02-design/design.md:504-505`).

#### Invalid canonical filename reproduction

The fixture directory was created by `mkdir /tmp/ws-acceptance-b6`. After rejecting the initial incorrectly encoded fixture, the byte-exact creation command was:

```sh
nix-shell -p python3 --run 'python3 -c '\''import os; p=b"/tmp/ws-acceptance-b6/rawbad\xff.slangp"; os.close(os.open(p,os.O_CREAT|os.O_WRONLY|os.O_EXCL,0o600)); os.symlink(p,b"/tmp/ws-acceptance-b6/rawlink.slangp")'\''' && readlink /tmp/ws-acceptance-b6/rawlink.slangp | od -An -tx1
```

Using the native environment launcher above, each build executed:

```js
const e = imports.gi.WaylandShader.Effect.new();
try {
    e.load_preset('/tmp/ws-acceptance-b6/rawlink.slangp');
    try { print(JSON.stringify(JSON.parse(e.get_status()).requestedPreset)); }
    catch (x) { print('STATUS ERROR ' + x.message); }
} finally { e.shutdown(); }
```

The symlink argument is valid UTF-8; only the canonical target contains byte `ff`. Baseline returned a valid replacement-character string; Odin's GI return conversion failed. A previous sentinel run also confirmed the Odin module rejects `{"version":1.}`, distinguishing it from the baseline. The final byte-exact probe, not the unsuitable initial fixture, is the evidence for B6.

### Upheld findings

| Finding | Disposition / requirement | Independently verified evidence and impact |
|---|---|---|
| **A-01** | **Blocking** — REQ-068, REQ-006 | Differential parser/error/surrogate cases above fail. Shared tokenizer handling and UTF-8 encoding lose baseline semantics and lone-surrogate data (`gnome/common/json_parse.odin:15-22,46-56,72-76,138-139`). Ordinary passing fixtures do not cover these cases. |
| **A-02** | **Blocking** — REQ-005/006/007 | Missing-preset fallback preserves raw input instead of baseline lexical normalization (`gnome/native/config.odin:159-167`). Export and both status path fields differ in the headless reproduction. |
| **A-03** | **Blocking** — REQ-061 | Six assertion-coverage checks fail as detailed above. Every mirror must have both Odin and real-header C checks (`docs/waterfall/01-requirements/requirements.md:125`); successful compilation of the present assertions is insufficient. No current layout mismatch is claimed. |
| **A-05** | **Major, required regression coverage** — REQ-063 | Search/read evidence identifies the actual measured loops, excluding the `before_paint` loop. Its entry resets the context (`gnome/native/paint.odin:174-180`), so merely wrapping that callback in a caller tracking allocator would not prove the requirement. No production allocation defect is claimed. |
| **B2**, imported from review B | **Blocking** — REQ-006; shared writer also serves REQ-005 | Eight independently reproduced parameter exports differ from baseline bytes. The formatter's notation thresholds and integer fast path are not Qt's (`gnome/common/json.odin:34-54`). This is a byte-contract failure, not a claim that all numeric values changed. |
| **B3**, imported from review B | **Blocking** — REQ-041/043 error output | Private-bus per-call timeout reproduces malformed stderr despite matching exit 3. A local GIO error supplies no remote name, but `classify` always prints a name plus colon (`gnome/controller/client/client.odin:43-53,162-166`). |
| **B6**, imported from review B | **Blocking** — REQ-005/009 | A valid UTF-8 symlink to a raw-byte canonical filename makes Odin `get_status()` fail GI conversion, whereas baseline returns valid text. Canonical bytes pass directly into `request` and the JSON writer copies high bytes unchanged (`gnome/native/config.odin:221-224`; `gnome/native/engine.odin:240-243`; `gnome/common/json.odin:16-32`). [INFERENCE] The same invalid status would break extension consumers; the direct GI failure itself was exercised. |

### Numbered rework list for the builder

1. **A-01 — Restore baseline JSON parsing and string preservation.** Fix the shared parser's accepted/rejected documents, exact errors, and lone-surrogate export preservation; do not simply tighten parsing to standard JSON, because the contract is Qt compatibility. **Required regression:** baseline-pinned T-UNIT-COMMON/T-CONTRACT cases for all six parser/string counterexamples above, including exact exported surrogate bytes, passing the original baseline first and then Odin.
2. **A-02 — Normalize missing restored preset paths lexically.** Retain canonicalization of existing files; on its failure reproduce the baseline's absolute-path cleanup rather than preserving raw `.`/`..`/repeated separators. **Required regression:** missing non-clean path imports asserting exact export, status `preset`, and `requestedPreset` against the baseline before asynchronous completion.
3. **A-03 — Complete the required dual ABI checks.** Add missing Odin/C checks for the concrete GList/GObject mirrors and GUI duplicates, or reuse shared checked mirrors. Account for every concrete struct/enum mirror under REQ-061 without introducing a generator or runtime shim. **Required regression:** build the real-header ABI target and every consuming Odin target, explicitly covering these omitted layouts; a deliberately wrong asserted layout must fail compilation.
4. **A-05 — Measure the actual warmed before-paint output loop.** Extend the existing heap/temp tracking test to execute the production output-loop logic without the C-entry context reset bypassing the counters. Keep the existing timing, selection, rendering and size checks. **Required regression:** zero heap and temp allocation deltas over repeated warmed processing; demonstrate an allocation inserted into the measured production loop makes the regression fail. This is test coverage, not a request for a new hot-path layout or optimization.
5. **B2 — Match the baseline JSON number bytes.** Fix the shared writer's fixed/scientific and integral representation rules using baseline observations, not a new guessed notation threshold. **Required regression:** all eight numeric exports above, plus existing small/f32 round-trip cases, pinned against baseline bytes in common/native contract tests. Do not change goldens merely to match the port.
6. **B3 — Preserve local bus-error output compatibility.** Handle local timeout/error mapping so the CLI produces the baseline error name and message, not an empty-name prefix. Do not mask it as success or change exit classification. **Required regression:** private `hang-shell.js` owner with `--timeout 30 status`, byte-equal stderr/stdout and exit 3 against baseline, alongside the existing overall-deadline exit-4 case.
7. **B6 — Decode canonical filename bytes as the baseline does.** Ensure paths entering status/settings JSON are valid UTF-8 with the baseline's replacement behavior, covering both direct load and settings canonicalization. Do not reject otherwise readable symlinks or replace the whole status with a fallback. Preserve A-01's distinct escaped-surrogate semantics. **Required regression:** byte-verified `ff` target behind a valid UTF-8 symlink; standalone GI status must succeed and match baseline replacement text. Include the corresponding saved-path/export case once the preset state is committed.

After rework, rerun `nix-build gnome/default.nix` with its full headless checkPhase, T-KWIN, and the added targeted regressions. No feature additions, compatibility shims, or changes to D1/D2 are required.

Not checked in this acceptance run: manual visual/accessibility/app_id observations, physical AMD/HDR/hotplug/suspend behavior, and manual safety/docs sign-off; these remain user sign-off items, not automated passes. No live Shell module load, extension installation/enabling, compositor restart, or mutating live-session-bus call was performed. Remaining risk: the existing green suite misses the independently reproduced compatibility failures above.

REJECTED

## Round 2

### Decision and review selected

**I side with review B (opus 5.5), and only review B, for Round 2.** Its broader baseline comparison identifies the remaining leading-dot number and missing-path trailing-slash differences as well as the BOM regression. I independently reproduced all three blockers, rather than accepting the report on authority. I additionally import **R2-A-02** from review A: the independently reproduced trailing-garbage error-precedence defect. R2-A-01 duplicates B's R2-1 and is not a separate rework item.

Reviewed HEAD: **`88c69ec`**, independently confirmed by `git rev-parse --short HEAD` (exit 0). This decision concerns rework round 1, with the next builder rework being the last available round under the process limit (`docs/waterfall/README.md:12`). The numbered list below includes every defect upheld in this decision, including the inexpensive, verified minor fixes; it is not a request to add features.

The manual-test ruling from Round 1 remains in force. T-ISO-RENDER/T-GUI visual observations, T-HW and T-SAFETY/T-DOCS sign-offs remain **deferred to the user, not passed and not acceptance blockers by themselves**. D1/D2 are unchanged accepted deviations (`docs/waterfall/02-design/decision.md:60-63`). The rejection is based on reproduced automated compatibility failures, not those deferred observations.

### Commands run and results

All commands ran from the repository root. In this section, `R=/tmp/ws-acceptance-r2-gnome`, `BASE=/tmp/ws-baseline-result`, and `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com`; actual invocations used the literal paths. No production source, fixture or golden was edited.

| Command / check | Independently observed result |
|---|---|
| `git rev-parse --short HEAD` | Exit 0: `88c69ec`. |
| **T-NIX:** `nix-build gnome/default.nix -o /tmp/ws-acceptance-r2-gnome` | Exit 0; actual fresh configure/build/checkPhase/install. **13/13 CTest entries passed, 0 failed, no skips**, 16.75 seconds. Both real GL and GL33 tests executed. C ABI assertions and the Odin native/controller/runtime targets compiled. Output: `/nix/store/hc7v1929hqnyiczimx0dhhgp214cjrwv-waylandshader-gnome-0.1.0`. |
| **T-KWIN:** `nix-build default.nix -o /tmp/ws-acceptance-r2-kwin` | Exit 0; actual compile/link/install. Output: `/nix/store/zbr3i21nbl8bmrvs5cmmbfzd4nb6m9g3-waylandshader-0.1.0`. This is the required KWin build check, not a runtime observation. |
| `nix-shell gnome/shell.nix --run 'env GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-baseline-result/share/gnome-shell/extensions/waylandshader@man33li.github.com/native && env GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" gjs -m gnome/tests/native-contract.js /tmp/ws-acceptance-r2-gnome/share/gnome-shell/extensions/waylandshader@man33li.github.com/native'` | Exit 0; **both** print `Native byte/error contract passed.` No capture mode used. Includes original parser/surrogate cases, missing-path reproductions, number exports and the byte-verified raw-FF canonical-path regressions (`gnome/tests/native-contract.js:61-132`). |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit 0: **107 cases match** on the original C++ CLI. The rework CLI passed the same golden test in my fresh Nix checkPhase, including per-call NoReply and overall-deadline cases. |
| Native parser/path/recent matrix below, separately on baseline and rework with the explicit native GI/loader environment used in Round 1 | Both observational probes exit 0 because GErrors are caught. **Comparison fails** for R2-1, R2-2, R2-3, R2-A-02 and B8, with exact results below. |
| Native BOM assertion below on the rework package | **Exit 1**, uncaught `wayland-shader-error: illegal number`. This is an actual failing acceptance assertion, not merely a diagnostic difference. |
| Same BOM assertion on retained Round-1 `/tmp/ws-acceptance-gnome` | Exit 0: `Round-1 BOM control PASS`. Baseline acceptance was also observed in the matrix. The rework introduced this regression. |
| `nix-shell gnome/shell.nix --run 'pkg-config --variable=includedir mutter-cogl-18; pkg-config --variable=prefix libmutter-18; printenv NIX_CFLAGS_COMPILE'`, followed by tool glob/read/grep of the resolved real headers | Exit 0; resolved actual Mutter 50.5 and private librashader 0.10.1 headers. Confirmed Cogl's `unsigned long buffers` and `#define LIBRASHADER_CURRENT_VERSION 2`, versus the Odin `u32` declaration and absent C version assertion. |
| `nix-shell gnome/shell.nix --run 'gjs -c <wrapper-probe>'`, described below | Exit 0 observationally; for **both** baseline and rework, GNU `grep -o` returns exit 0 but no extracted path, reports `binary file matches`, and the schema-existence criterion is false. With `-ao`, stderr is empty and the schema criterion is true for both. R2-4 confirmed as a catalog-command defect, not a missing packaged schema. |
| Native C-entry NULL/invalid-UTF8 probe using Python `ctypes`, described below | First launcher: six baseline assertions passed, then exit 1 because loading the second implementation into the same process attempted to register the already-existing GType. This is a probe-isolation mistake, not an Odin API failure. Corrected separate-process rework probe: **exit 0, six assertions passed**. |
| Targeted source searches/reads for invalid-text tests, frame-anchor ordering, retry/failure clearing, ABI assertions and package documentation | B7, remaining B9, B10 and B12 verified as bounded source/coverage findings below. No GL allocation/copy failure was injected in this acceptance run. |

The fresh checkPhase exercised the same 13 test names recorded in Round 1, now with the expanded contract and 107-case CLI goldens. It did **not** contain the new counterexamples below. A passing suite and a failing BOM acceptance assertion are therefore consistent results.

#### Targeted differential reproductions

For each package separately, I used the Round-1 native launcher with these literal package roots: `/tmp/ws-baseline-result` and `/tmp/ws-acceptance-r2-gnome`. It sets `GI_TYPELIB_PATH` to the selected package's native directory plus the `pkg-config` Mutter typelib directory, and `LD_LIBRARY_PATH` to that same native directory before invoking `gjs -c`.

The matrix created a **fresh unattached `WaylandShader.Effect` per input**, called `import_settings(source)`, printed `export_settings()` or the caught GError message, and always called `shutdown()` in `finally`. For missing paths it also printed status `preset`, `requestedPreset` and `loading`. Separately, a fresh object called `set_outputs("\ufeff[]")`. No object was attached to a compositor and no session-bus calls were made.

| Input / case | Baseline b223c1a | Rework 88c69ec |
|---|---|---|
| Actual BOM + `{"version":1,"enabled":false}` | Accepted; exported `enabled:false` | `illegal number` |
| Actual BOM + `[]` through import | `Configuration must be a JSON object` | `illegal number` |
| Actual BOM + `[]` through `set_outputs` | Accepted | `illegal number` |
| `{}"` | `garbage at the end of the document` | `unterminated string` |
| `{}tru` | `garbage at the end of the document` | `illegal value` |
| `{"version":1,"x":.5}` | Accepted | `illegal number` |
| `{"version":1,"x":-.5}` | Accepted | `illegal number` |
| `{"version":.5e1}` | `Unsupported settings version` (parsing succeeds) | `illegal number` |
| `{1:2}` | `unterminated object` | `object is missing after a comma` |
| `{'version':1}` | `unterminated object` | `object is missing after a comma` |
| `{"x":"` followed by one backslash and EOF | `invalid escape sequence` | `unterminated string` |
| `{"x":"` followed by backslash, `u`, and EOF | `invalid escape sequence` | `unterminated string` |
| Top-level `]` | `object is missing after a comma` | `illegal value` |
| Top-level `}` | `object is missing after a comma` | `illegal value` |
| `recent_presets:["/a.ſlangp"]` in version-1 settings | Export keeps `/a.ſlangp` | Export drops it |
| Missing preset `/a/./` | `/a/` | `/a` |
| Missing preset `/a//b//` | `/a/b/` | `/a/b` |
| Missing preset `/a/b/` | `/a/b/` | `/a/b` |
| Missing preset `/a/b/../` | `/a/` | `/a` |
| Missing preset `/nx/x.slangp/` | `/nx/x.slangp/` | `/nx/x.slangp` |
| Control: missing preset `/a/b/.` | `/a/b` | Same |
| Control: missing preset `/a/b/..` | `/a` | Same |
| Control: missing preset `/../` | `/` | Same |

For each of the five failing missing paths, the difference appears in **all three** path observations: exported `preset`, status `preset`, and status `requestedPreset`; both statuses have `loading:true`. The assertions concern fixed-input bytes before asynchronous completion, not whether a directory can compile as a preset.

The executed failing BOM assertion body was:

```js
const e = imports.gi.WaylandShader.Effect.new();
try {
    e.import_settings("\ufeff{\"version\":1}");
    if (JSON.parse(e.export_settings()).version !== 1) throw Error("wrong version");
} finally {
    e.shutdown();
}
```

The Round-1 control used the same body with a success print after the assertion. For the matrix, the truncated-escape strings were constructed as `'{"x":"' + String.fromCharCode(92)` and the same expression plus `'u'`, so the tested backslash is an actual final byte, not a display escape.

For R2-4, the `gjs -c` probe spawned GNU grep via `Gio.Subprocess` with arguments `["grep", flag, '/nix/store/[^:"]*/share/gsettings-schemas/gtk+3-[^:"/]*', root + "/bin/waylandshader-gnome-controller"]`, captured stdout/stderr/exit, selected the first stdout line as `d`, and called `Gio.File.new_for_path(d + "/glib-2.0/schemas/org.gtk.Settings.FileChooser.gschema.xml").query_exists(null)`. It tested flags `-o` and `-ao` on each package. This reproduces the catalog's extraction/existence logic without changing its file or running the GUI.

For B10, the corrected `ctypes` probe loaded only the rework `.so` in its process, constructed one real effect, and called each of `wayland_shader_effect_set_outputs`, `wayland_shader_effect_import_settings`, and `wayland_shader_effect_load_preset` with both NULL and `b"\xff"`. For each call it asserted FALSE, a non-NULL `GError`, code 1 and exact message `Invalid UTF-8 argument`, then freed the error. Finally it shut down and unrefed the effect. All six passed, matching the six baseline observations before the first launcher's GType collision. The defect is the **absence of this persistent regression coverage**, not a demonstrated validation failure.

### Disposition of Round-1 rework

| Original item | Round-2 disposition and evidence |
|---|---|
| A-01 | **Original named parser/surrogate cases fixed**, independently exercised by the same expanded native contract on baseline and rework. REQ-068 is still open for the new matrix above; this is not global parser equivalence. |
| A-02 | **Original three missing-path reproductions fixed**, same dual native-contract run (`gnome/tests/native-contract.js:101-104`). R2-3 exposes a remaining trailing-slash case, not failure of those three regressions. |
| A-03 | **Original omitted checks fixed.** Inspected shared GList/GObject assertions and GUI aliases/assertions (`gnome/glib/glib.odin:9-12`; `gnome/glib/gobject.odin:18-22`; `gnome/controller/gui/gtk.odin:20-26`) and matching real-header C checks (`gnome/native/abi-check.c:16-32`); my fresh build compiles them. I did not repeat reviewers' destructive negative controls on copied sources. |
| A-05 / B11 | **Requested loop coverage fixed.** The actual callback and tracking test share `before_paint_output` (`gnome/native/paint.odin:174-184`; `gnome/native/native_test.odin:29-75`); the heap/temp counters span shader/color/nil/missing/disabled cases and pass in my checkPhase. Builder/reviewer negative-control results are recorded at `docs/waterfall/03-implementation/build-log.md:341-344` and `review-A.md:246-247`, not claimed as my executions. |
| B2 | **All requested numeric export cases fixed**, dual native-contract run with unchanged baseline-pinned expectations (`gnome/tests/native-contract.js:79-82,127-132`). |
| B3 | **Requested per-call timeout regression fixed**, original CLI matches all 107 goldens and rework matches them in my checkPhase. This is finite coverage, not verification of every local GIO error. |
| B6 | **Requested direct-load/restored raw-filename cases fixed**, dual native-contract run checks actual byte 255 in its fixture before testing status/settings (`gnome/tests/native-contract.js:105-125`). |

### Upheld findings

| Finding | Disposition / requirement | Independently verified evidence |
|---|---|---|
| **R2-1** | **Blocking regression**, REQ-068 | BOM acceptance fails in both settings import and output inventory; an explicit rework assertion exits 1 while baseline and retained Round-1 behavior accepts it. Initial scanner dispatch has no BOM handling (`gnome/common/json_parse.odin:21-29,200-206`). |
| **R2-2** | **Blocking**, REQ-068 | All nine leading-dot/error-text cases in the matrix differ. Scanner numeric dispatch requires a digit before `.`, string scanning loses truncated-escape precedence, and object/root dispatch uses the wrong errors (`gnome/common/json_parse.odin:36-61,87-96,146-148,200-206`). |
| **R2-A-02**, imported from A | **Blocking**, REQ-068 | Both `{}"` and `{}tru` have the wrong trailing-content error. Root completion eagerly scans the next token and returns its lexical error before the final garbage check (`gnome/common/json_parse.odin:145,166,189,207-209`). |
| **R2-3** | **Blocking**, REQ-006/007 | Five missing trailing-slash paths differ in export and both status fields. `clean_absolute` discards the final separator (`gnome/native/config.odin:102-120,178-187`). No new path policy is authorized. |
| **R2-4** | **Minor catalog-test defect**, T-WRAP | Binary extraction without `-a` makes the schema gate false on both packages inside the required development shell (`docs/waterfall/01-requirements/requirements.md:189-190`). The schema exists; the extractor is faulty. |
| **B7** | **Minor FFI declaration defect**, REQ-061/062 | Odin declares `buffers: u32` (`gnome/native/mutter.odin:101`); the actual pinned header declares `unsigned long` (`/nix/store/ai91zd3ad7m9vs5x39yynf2kyn91ml5p-mutter-50.5-dev/include/mutter-18/cogl/cogl/cogl-framebuffer.h:654-659`). Current calls pass only mask 1, so this is not a claim of an observed x86-64 rendering failure. |
| **B8** | **Minor compatibility defect**, REQ-017 | Baseline retains `/a.ſlangp`, rework drops it. The current suffix slices seven bytes before folding, which cannot recognize this Unicode-fold-equivalent suffix (`gnome/native/config.odin:168-171`). No third accepted deviation exists. |
| **B9**, remaining version-assertion portion only | **Minor ABI-gate coverage**, REQ-020/059/061 | Field offsets are now checked (`gnome/native/abi-check.c:70-109`). The actual private header defines current API version 2 (`/nix/store/gl6nf7xzs0ifldc0h2bxplaw4g22pvs4-waylandshader-librashader-0.10.1/include/librashader/librashader.h:1189`), but the C gate does not assert it while runtime options hard-code 2 (`gnome/runtime/runtime.odin:136-137,239`). No current header/version mismatch is alleged. |
| **B10** | **Minor persistent-test gap**, REQ-016 | Source search and contract inspection show no native C-entry NULL/invalid-UTF8 regression. My six corrected direct C-entry probes pass; the branch is real at `gnome/native/boundary.odin:31-35` and exported callers at `gnome/native/config.odin:287-302`. This needs a committed test, not a validation rewrite. |
| **B12** | **Minor frame-state ordering defect**, REQ-032 | The port mutates `first_frame` before destination allocation/source copy (`gnome/native/paint.odin:166,240-244`); baseline commits it only after both (`/tmp/ws-baseline/gnome/native/waylandshader-effect.cpp:1141-1145`). A gamma/color mutation can clear output failure without resetting that clock (`gnome/native/config.odin:271-276`; `gnome/native/engine.odin:424-428`). [INFERENCE] Following an initial allocation/copy failure and that retry, the first successful shader frame can therefore have a nonzero number instead of baseline zero. The source ordering/retry route was verified; a real GL failure was not injected here. |

**Not upheld:** B13's claimed Qt handling of a malformed signal remains an unverified inference, so I do not require a behavioral change on that basis. B14 overstates the documentation problem: `docs/GNOME.md:148` says the package “also runs” lifecycle, not that it runs **only** lifecycle; that statement is true. A fuller suite description is optional, not a defect blocking this feature-preserving cutover. B11 is closed as above. No other B finding or unverified A claim is silently imported.

### Numbered rework list for the builder

1. **R2-1 — Restore initial BOM handling in the shared parser.** Match baseline acceptance without stripping arbitrary BOMs inside the document. **Required regression:** actual UTF-8 BOM before a settings object and output array, through common parsing and the real native API; assert accepted bytes/behavior on baseline first, then rework, retaining depth and trailing-content checks.
2. **R2-2 — Complete the reproduced numeric grammar and error precedence.** Accept `.5` and `-.5` where Qt does; match baseline errors for non-string object keys, terminal backslash/Unicode escapes and top-level closing tokens. Fix the scanner/parser root cause, not individual input strings. **Required regression:** every R2-2 matrix case above, including version `.5e1`, pinned from baseline in native/common tests; preserve existing overflow/underflow, `1.`, leading-zero and surrogate cases.
3. **R2-A-02 — Detect trailing content before exposing its token error after a complete root.** Preserve internal-document errors while matching Qt's root trailing-garbage precedence. **Required regression:** `{}"` and `{}tru` must produce exact `garbage at the end of the document` on baseline and rework; include array-root equivalents and valid-whitespace controls.
4. **R2-3 — Preserve the baseline trailing slash in missing-path cleanup.** Keep one final `/` when the input ends in `/` and the cleaned non-root result requires it; retain existing-file realpath behavior and the already-correct `/.`, `/..` and root cases. **Required regression:** all five failing paths plus the three controls above, comparing export, status `preset` and `requestedPreset` to baseline before asynchronous completion.
5. **R2-4 — Make T-WRAP extraction binary-safe.** Change the catalog extractor to `grep -ao` or an equally small binary-safe equivalent, retaining the schema file-existence check. **Required regression:** execute that documented extraction/existence gate inside `nix-shell gnome/shell.nix` on baseline and rework; both must pass. Record it as a repaired test command, not a package schema fix.
6. **B7 — Correct the Cogl mask declaration to `c.ulong`.** Do not add a wrapper or alter current rendering behavior. **Required regression:** compile native consumers and add a real-header function-signature check for `cogl_framebuffer_clear4f`, so the mask parameter width cannot drift unnoticed; existing real GL tests must still pass.
7. **B8 — Match baseline Unicode suffix folding for imported recents.** Recognize the case-fold-equivalent `.ſlangp` suffix without changing the stored path text. D1/D2 do not authorize dropping this entry. **Required regression:** `/a.ſlangp` retained byte-for-byte against baseline, with ordinary ASCII mixed-case and non-matching suffix controls.
8. **B9 — Finish the API-version gate.** Add the missing real-header assertion for `LIBRASHADER_CURRENT_VERSION == 2`, consistent with the pinned private ABI and runtime option literals. Keep existing size/offset checks. **Required regression:** the ABI target passes with the actual header and rejects a deliberately mismatched expected version in an owned temporary negative control.
9. **B10 — Persist the native argument-validation regression.** Add a small native-unit or C-level test of NULL and byte-FF arguments through actual exported mutators with valid effect instances; no production validation rewrite is needed. **Required regression:** FALSE plus non-NULL GError, domain `wayland-shader-error`, code 1 and exact `Invalid UTF-8 argument`, with correct cleanup. Include at least `set_outputs`, `import_settings` and `load_preset`; run baseline and port in separate processes.
10. **B12 — Commit the first-frame anchor after source preparation succeeds.** Keep the baseline warm-up/timing behavior, but do not permanently advance `first_frame` before destination allocation and source copy. **Required regression:** a targeted failure-path test proves failed preparation leaves an unstarted anchor, then a permitted failure-clearing retry produces frame number 0; retain normal timing, history-reset and zero-allocation regressions. Prefer testing a small production state transition or existing failure seam over a new rendering abstraction.

After the final rework, rerun the fresh GNOME build/checkPhase, T-KWIN, dual baseline/native contract, 107-case CLI comparison, the corrected T-WRAP gate and every new targeted regression above. Keep original baseline observations as the oracle; do not recapture expectations from the port. No new feature, compatibility shim, broad architecture rewrite or change to D1/D2 is requested.

Not checked in this acceptance run: manual visual/accessibility/app_id/hardware observations and sign-offs; malformed-signal baseline behavior; real GL allocation/copy fault injection. No live compositor module load, extension installation/enabling, compositor restart or mutating live-session-bus call was performed. The remaining acceptance risk is concrete parser/path compatibility failure despite the current green headless suite.

REJECTED

## Round 3

### Final decision and review selected

**I side with review B (opus 5.5), and only review B, for Round 3.** I uphold **R3-1**, after independently reproducing both its JSON-conversion and native C-string-argument cases against the actual baseline. R3-A-01 describes the overlapping JSON-string defect, not a second independent blocker; no separate A finding is imported. B's broader account includes the independently verified native argument boundary.

Reviewed HEAD: **`d50af2d`**, confirmed by `git rev-parse --short HEAD` (exit 0), with the main agent's subsequent `GATES.md` documentation correction present. **R3-2 is closed**, not upheld: `docs/waterfall/GATES.md:9-12` now records both verification rejections, both implementation reworks, and the authorized requirements-catalog amendment.

**Final verdict: REJECTED under the current exact-compatibility requirements.** All ten numbered Round-2 rework items now have passing finite evidence. One additional string-conversion compatibility gap remains outside those tests. It has **low practical impact for ordinary inputs**, but causes actual acceptance and stored/status-byte differences and therefore fails REQ-005/006/007/008/017/068 as applicable (`docs/waterfall/01-requirements/requirements.md:34-38,132`). It is not an observed compositor crash, memory-safety issue, security vulnerability or ordinary rendering failure.

The two permitted rework rounds are exhausted (`docs/waterfall/README.md:12`; `docs/waterfall/GATES.md:10-12`). **This decision ends the authorized automatic rework cycle.** The numbered remaining items below are a precise handoff for the user to either authorize an additional round or explicitly accept a new deviation; they do not themselves authorize further implementation. D1/D2 remain unchanged and do not cover this behavior (`docs/waterfall/02-design/decision.md:60-63`).

Manual visual render/GUI observations, physical hardware tests and manual safety/docs sign-offs remain deferred to the user under the established ruling. They are not represented as passes and do not cause this rejection.

### Commands run and results

All commands ran from the repository root. Here `R=/tmp/ws-acceptance-r3-gnome`, `BASE=/tmp/ws-baseline-result` and `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com` are display shorthands; native commands used literal paths. Only this acceptance document was edited by this reviewer.

| Command / check | Independently observed result |
|---|---|
| `git rev-parse --short HEAD` | Exit 0: `d50af2d`. |
| **T-NIX:** `nix-build gnome/default.nix -o /tmp/ws-acceptance-r3-gnome` | Exit 0; actual fresh configure/build/checkPhase/install, not a cache-only lookup. **16/16 CTest entries passed, 0 failed, no skips**, 16.76 seconds. Both real GL variants executed. Output: `/nix/store/n3qrajfcvni1snm6bcjqsxkja3zxwp7r-waylandshader-gnome-0.1.0`. |
| **T-KWIN:** `nix-build default.nix -o /tmp/ws-acceptance-r3-kwin` | Exit 0; actual compile/link/install. Output: `/nix/store/gb6xa2xk6lc411jqb9i9wyalgkwb5wz2-waylandshader-0.1.0`. No KWin runtime result is claimed. |
| `nix-shell gnome/shell.nix --run 'export GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH"; gjs -m gnome/tests/native-contract.js <native> && gjs -m gnome/tests/parser-corpus.js <native> && gjs -m gnome/tests/path-contract.js <native>'`, executed sequentially for the baseline and final package in one invocation | Exit 0. **Each library** prints `Native byte/error contract passed.`, `Parser corpus: 275 cases match.`, and `Path/recents contract passed (77 cases).` No capture mode or oracle edits used. |
| `nix-shell gnome/shell.nix --run 'gnome/tests/cli-golden.sh check /tmp/ws-baseline-result/bin/waylandshader-gnomectl'` | Exit 0: **107 cases match** on the original C++ CLI. The final CLI independently passes the golden test in my fresh checkPhase. |
| Standalone native GI JSON/output/C-argument matrix below, separately on baseline and final package using the explicit native GI/loader environment | Both observational probes exit 0 because errors are caught. **Compatibility comparison fails**, R3-1, as detailed below. |
| Raw-BOM parameter-name assertion below, separately on baseline and final | Baseline **exit 0**, `Raw-BOM assertion PASS`; final **exit 1**, `raw BOM name not decoded like baseline`. This is an actual failing acceptance assertion despite the green suite. |
| Standalone native `load_preset` probe below with a real temporary readable file and a U+FEFF-prefixed C-string argument, separately on baseline and final | Both observational probes exit 0. Baseline accepts and reports the unprefixed absolute `requestedPreset` with `loading:true`; final raises `Preset must be an absolute readable file`. Cleanup runs in `finally`. This checks request acceptance, not shader compilation or rendering. |
| `nix-shell gnome/shell.nix --run 'gjs -c <binary-safe-wrapper-gate>'`, using the Round-2 `Gio.Subprocess` extraction/existence body with `grep -ao` and a throwing assertion | Exit 0: **both** baseline and final wrappers pass the schema-existence gate. Neither GUI wrapper was launched. |
| Tool reads of corrected gates, real-header ABI assertions, C argument regression, frame-anchor transition and test registration | Confirmed the closure evidence summarized below. No additional production edits, copied-source negative controls, or real driver fault injection were performed by me. |

The 16 checkPhase tests are the previous 13 plus `gnome_parser_corpus`, `gnome_path_contract`, and `gnome_native_arguments`, registered at `gnome/CMakeLists.txt:97-110`. Passing them establishes the current corpus passes, not complete equivalence for all strings.

#### Reproduction environment and failing assertion

Each standalone probe used a separate process, selecting exactly one installed implementation:

```sh
nix-shell gnome/shell.nix --run 'env GI_TYPELIB_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH" LD_LIBRARY_PATH="<PACKAGE>/share/gnome-shell/extensions/waylandshader@man33li.github.com/native:$LD_LIBRARY_PATH" gjs -c '\''<BODY>'\'''
```

`<PACKAGE>` was `/tmp/ws-baseline-result` or `/tmp/ws-acceptance-r3-gnome`. The executed assertion body, shown without shell escaping, was:

```js
const e = imports.gi.WaylandShader.Effect.new();
try {
    e.import_settings(JSON.stringify({
        version: 1,
        parameters: {p: {["\ufeffGAIN"]: 0.5}},
    }));
    const saved = JSON.parse(e.export_settings());
    if (saved.parameters.p.GAIN !== 0.5 ||
        Object.keys(saved.parameters.p).length !== 1)
        throw Error("raw BOM name not decoded like baseline");
    print("Raw-BOM assertion PASS");
} finally {
    e.shutdown();
}
```

Here the JavaScript string contains U+FEFF; `JSON.stringify` emits its **actual UTF-8 bytes EF BB BF inside the JSON string**, not the ASCII JSON escape. This distinction is essential.

#### Independently reproduced R3-1 behavior

Let **B** denote one actual U+FEFF character, and **escaped B** denote six ASCII JSON characters `\ufeff`. The matrix generated raw cases with `JSON.stringify`; escaped controls replaced each actual B in that serialized text with the ASCII escape. Every settings/output case used a fresh unattached native object and called `shutdown()` in `finally`.

| Input / operation | Baseline b223c1a | Final d50af2d |
|---|---|---|
| Settings parameter preset key B+`p`, parameter name B+`GAIN`, value 0.5 | Exported keys `p` and `GAIN` | Export retains B on both keys |
| Same parameter keys expressed with escaped B | Export retains B on both keys | Same, control |
| Saved `preset` value B+`/tmp/ws-r3-acceptance-missing.slangp` | Accepted, export `/tmp/ws-r3-acceptance-missing.slangp` | `Saved preset must be an absolute filename` |
| Same saved preset with escaped B | `Saved preset must be an absolute filename` | Same, control |
| Recents `[B+"/a.slangp", B+B+"/b.slangp", "/m"+B+".slangp"]` | Keeps `/a.slangp` and `/m`+B+`.slangp`; drops the double-B path | Keeps only `/m`+B+`.slangp` |
| Static object key B+`version`, value 1 | `Unsupported settings version` | Same, control: raw lookup keys are not globally normalized |
| Saved output key consisting only of B, otherwise valid settings | `Invalid saved output settings` | Accepted and exported with key B |
| `set_outputs` with id B, name B+`N`, valid unit geometry/scale | `Output IDs must be nonempty and unique` | Accepted, status retains id B and name B+`N` |
| `set_outputs` with id B+`A`, name B+`N` | Status id `A`, name `N` | Status retains B on id and name |
| First install ordinary output id `A`; call `set_output_gamma(B+"A", 2)` | Succeeds, status gamma 2 | `Unknown active output: `+B+`A` |
| Same ordinary output; call `set_output_shader_enabled(B+"A", false)` | Succeeds, status shader disabled | `Unknown active output: `+B+`A` |
| `load_preset(B + <existing absolute file>)` | Request accepted; `requestedPreset` is the unprefixed absolute path | `Preset must be an absolute readable file` |

The output rows used `{x:0,y:0,width:1,height:1,scale:1}`. Saved-output settings used `{shaderEnabled:true,colorEnabled:false,gamma:1,saturation:1}`. For the C-argument load case, each process created a fresh `GLib.dir_make_tmp("ws-acceptance-r3-load-XXXXXX")` directory, wrote a readable `probe.slangp` containing `x`, called `load_preset("\ufeff" + path)`, and then shut down and executed `GLib.unlink(path)`/`GLib.rmdir(root)` in `finally`. No main-loop wait or compile-success claim was made.

The observed raw/escaped, double-B, mid-string and raw-lookup controls mean **a blanket trim of U+FEFF from all decoded strings or all object keys would be wrong**. Matching baseline requires the relevant conversion semantics, not treating every U+FEFF as whitespace.

### Closure of the ten Round-2 items

| Items | Final finite evidence and disposition |
|---|---|
| R2-1, R2-2, imported R2-A-02 | **Requested cases fixed.** My baseline/final runs both pass the 275-case parser corpus and original native contract; my fresh common/native tests pass. The new defect concerns conversion inside strings and native arguments, not the repaired initial-document BOM or trailing-token checks. |
| R2-3 and B8 | **Requested cases fixed.** Both real modules pass the 77-case path/recents contract, including final slashes and Unicode suffix folding. R3-1 is a distinct leading-character conversion case outside that finite coverage. |
| R2-4 | **Fixed.** Catalog uses `grep -ao` (`docs/waterfall/01-requirements/requirements.md:190`), and my extraction/existence gate passes on both installed wrappers. |
| B7 and B9 | **Fixed.** `buffers: c.ulong` is present (`gnome/native/mutter.odin:102`); the C gate asserts API version 2 and the real-header function prototype (`gnome/native/abi-check.c:160-163`); my fresh build compiles it. Reviewer A's copied-source negative controls are recorded at `review-A.md:484-486`, not claimed as my executions. |
| B10 | **Fixed.** The persistent direct C-entry test asserts NULL/byte-FF rejection, exact domain/code/message and cleanup (`gnome/tests/native-arguments.c:20-53`), is registered at `gnome/CMakeLists.txt:107-110`, and passes in my fresh checkPhase. |
| B12 | **Fixed for the required transition regression.** `frame_timing` leaves an unstarted anchor unchanged; `frame_source_prepared` commits it only on successful source preparation (`gnome/native/paint.odin:160-175,249-250`). My native units and both GL tests pass. No real driver failure was injected in this review. |

B13/B14 are not reopened. R3-2's gate-recording concern is addressed as noted above. I do not adopt either reviewer's fuzz totals as my own verification, and do not infer global compatibility from their or my finite passing corpus.

### Upheld finding: conformance and real-world impact

| Finding | REQ conformance | Real-world impact | Evidence / scope |
|---|---|---|---|
| **R3-1 — leading-U+FEFF conversion differs at JSON extraction and C-string boundaries** | **Blocking under the unchanged exact baseline contract.** Reproduced accept/reject differences for saved presets/output ids and byte differences for parameter keys, recents and output status. It is outside D1/D2. | **Low practical severity / unusual-input compatibility edge case.** The mismatch requires an actual leading invisible U+FEFF at a converted string boundary. [INFERENCE] Normally generated connector ids, shader parameter names and absolute saved paths do not contain that prefix, so routine operation is unlikely to reach it. If reached, an otherwise accepted preset request or output mutation can be rejected, an invalid/empty-after-baseline-conversion id can be accepted, or saved/status names/history differ. No crash, ordinary rendering failure or security exploit was demonstrated. | JSON raw-byte copying and escaped decoding collapse the distinction (`gnome/common/json_parse.odin:35-82`); consumers directly use the strings/iterated keys (`gnome/native/config.odin:157-200`). Native `text()` validates UTF-8 but returns all bytes unchanged (`gnome/native/boundary.odin:31-35`), whereas the observed baseline calls `QString::fromUtf8` (`/tmp/ws-baseline/gnome/native/waylandshader-effect.cpp:74-84`) and converts extracted/iterated strings (`:1388-1409,1417-1421`). The direct matrix and failing assertion establish the bounded behavior without relying on a theory of Qt internals. |

**Why reject despite low practical severity?** The accepted requirement explicitly demands matching documents/errors and fixed-input status/settings bytes; earlier rounds enforced that same rule on rare numeric/path inputs. There is no authorized severity-based waiver or new deviation for R3-1. Accepting it silently would change that contract. Conversely, the evidence does not justify presenting this edge case as a general stability or safety failure.

### Numbered remaining items for user disposition

These are the two verified surfaces of **one remaining finding**, not two unrelated defects:

1. **R3-1 / JSON string extraction and iterated keys.** **Required fix if another round is authorized:** reproduce baseline conversion for literal leading U+FEFF in extracted JSON values and iterated output/preset/parameter keys, while retaining the observed distinction from ASCII `\ufeff`, raw static-key lookup, a second leading B and a mid-string B. Do not globally strip keys or all decoded U+FEFF characters. **Required regression:** capture baseline results for every JSON/settings/output row above; add the cases to common parser/conversion tests and the native parser/path contract corpus, asserting exact export/status bytes and exact errors. Include both raw and escaped parameter names/preset paths and a BOM-only id/key so a partial byte-format-only fix cannot pass.
2. **R3-1 / native C-string arguments.** **Required fix if another round is authorized:** make the shared valid-UTF8 argument conversion match baseline handling of one leading B; preserve existing NULL/invalid-UTF8 errors and document-level BOM behavior. Cover all callers of that conversion rather than special-casing the three reproduced methods. **Required regression:** real exported calls on fresh standalone objects for U+FEFF-prefixed `load_preset`, `set_output_gamma` and `set_output_shader_enabled`, with ordinary/unprefixed and repeated/mid-string controls, matching the baseline's acceptance, error text and status. Keep the six existing C NULL/byte-FF assertions green.

If the user instead accepts the edge case, the new deviation must **explicitly cover both numbered surfaces**: raw-versus-escaped JSON conversion and iterated-key/lookup behavior, plus native argument conversion and its acceptance/status/settings effects. Record the authorization in the design decision and applicable requirement/gate artifacts; merely adding another passing port-only expectation does not waive REQ conformance. No such authorization has been given in this cycle, so this review remains rejected.

If an extra round is authorized, require fresh GNOME checkPhase and T-KWIN, the unchanged dual-baseline native/parser/path contracts and CLI goldens, and the added R3-1 regression corpus. Do not reopen the resolved items or add features. Otherwise hand the final rejected state and the narrowly scoped deviation choice to the user; do not start a third implementation rework automatically.

Not checked: deferred manual visual/accessibility/app_id/hardware observations and sign-offs; real GL fault injection; the inferred extension/CLI/GUI propagation of malformed-prefix status outside the exercised native APIs. No live Shell module load, extension installation/enabling, compositor restart or mutating live-session-bus call was performed. The outstanding risk is this low-reach but demonstrated string-compatibility gap, not a failing package build or the absence of manual sign-off.

REJECTED

## Round 4

### Decision and review selected

**Selected adversarial review: review B (opus 5.5), and only review B.** I side with its assessment that R3-1 is fixed and its reviewed code/test changes introduce no demonstrated remaining blocker in that scope. Its Round-4 **ACCEPT** predates the new executed visual/accessibility results and explicitly leaves them to the main agent (`review-B.md:182,210,230`). I do **not** adopt that limited verdict as unconditional acceptance after receiving contrary test evidence.

**Round-4 verdict: REJECTED for G-1 only.** The additional primary input, `visual-checks.md`, records a failed T-GUI item 9 on the actual application against the Qt baseline (`visual-checks.md:44,50-52`). I independently verified the production setup, compared the baseline buddy-label code, and reproduced the GTK accessible-name behavior under a private headless display. The existing manual-class ruling defers missing observations; it does not waive an executed, reproducible failed test. This rejection is not for unavailable physical hardware or unobservable devkit behavior.

Build source: **`6f6709d`**, with documentation HEAD **`799e676`** (`git rev-parse --short HEAD`, exit 0). The raised limit is **five rework rounds** (`docs/waterfall/README.md:12`); three have been used, so two remain. Round 3's historical exhaustion language no longer controls after the user's recorded authorization (`docs/waterfall/GATES.md:14-16`).

### Commands run and results

Commands ran from the repository root. `R=/tmp/ws-acceptance-r4-gnome`, `BASE=/tmp/ws-baseline-result` and `EXT=share/gnome-shell/extensions/waylandshader@man33li.github.com` are display shorthands. Only this acceptance document was edited by this reviewer.

| Command / check | Independently observed result |
|---|---|
| `git rev-parse --short HEAD` | Exit 0: `799e676`. |
| **T-NIX:** `nix-build gnome/default.nix -o /tmp/ws-acceptance-r4-gnome` | Exit 0; actual configure/build/checkPhase/install. **17/17 CTest entries passed, 0 failed, no skips**, 16.78 seconds. Both GL variants and the new BOM contract executed. Output: `/nix/store/6m5j3b5349wkjjmzd4nbjcxv8d5mlama-waylandshader-gnome-0.1.0`. |
| **T-KWIN:** `nix-build default.nix -o /tmp/ws-acceptance-r4-kwin` | Exit 0; actual compile/link/install. Output: `/nix/store/5fg7hbvamhl3jrh56il73kcxy4njfin8-waylandshader-0.1.0`. No KWin runtime claim. |
| `nix-shell gnome/shell.nix --run 'export GI_TYPELIB_PATH="$(pkg-config --variable=prefix libmutter-18)/lib/mutter-18:$GI_TYPELIB_PATH"; gjs -m gnome/tests/bom-contract.js <native> && gjs -m gnome/tests/parser-corpus.js <native> && gjs -m gnome/tests/path-contract.js <native> && gjs -m gnome/tests/native-contract.js <native>'`, executed sequentially for baseline and final package in one invocation | Exit 0. **Both libraries:** 1,285 BOM cases, 369 parser cases, 203 path/recents cases and original native byte/error contract pass. No capture mode or expectation edits. |
| Initial doubly nested Nix/Xvfb/GJS launcher | Exit 2: shell quoting error before GTK execution. No accessibility conclusion drawn from that attempt. |
| `nix-shell -p xvfb-run --run 'command -v xvfb-run'` | Exit 0; resolved `/nix/store/940y9pcrxibjg54684874n70nd4mvany-xvfb-run-1+g87f6705/bin/xvfb-run`. Used the resolved binary directly to avoid nested quoting. |
| First single-shell headless GTK probe with `accessible.get_name()` | Exit 1 due to GJS's `Atk.Action.get_name` interface-method ambiguity, not an application assertion. Corrected by explicitly invoking `Atk.Object.prototype.get_name`. |
| Corrected headless GTK/ATK probe below | **Exit 1 at the expected-name assertion.** Observed `name:null`, `labelledBy:["Gain"]`, and the tooltip only as accessible description. This reproduces the missing-name mechanism independently of the main agent's actual-app AT-SPI observation. An unrelated missing `colorreload-gtk-module` message also appeared; it is not the cause of the assertion. |
| Source reads of production parameter creation, label helper, baseline buddy setup, requirement/checklist and current gates | Confirmed the application uses the reproduced setup without assigning a parameter spin's accessible name; baseline uses a buddy label. Existing gate rows cover rework 3 and its authorized documentation amendments. |

The GTK probe recreated the **actual production widget setup**, not the whole Odin application: the independently read production code is `gnome/controller/gui/window.odin:19-27,574-585`. The main agent's separate `visual-checks.md:44` is the evidence from the actual running controller. My baseline comparison used source at `/tmp/ws-baseline/src/controller_main.cpp:446-462`; I did not independently drive the Qt application or repeat the main agent's desktop screenshots.

#### Headless G-1 reproduction

Executed launcher, with `<BODY>` replaced by the JavaScript below and shell-escaped as a single argument:

```sh
nix-shell gnome/shell.nix --run '/nix/store/940y9pcrxibjg54684874n70nd4mvany-xvfb-run-1+g87f6705/bin/xvfb-run -a dbus-run-session -- env -u WAYLAND_DISPLAY -u AT_SPI_BUS_ADDRESS GDK_BACKEND=x11 NO_AT_BRIDGE=1 GIO_USE_VFS=local gjs -c '\''<BODY>'\'''
```

```js
imports.gi.versions.Gtk = "3.0";
const {Gtk, Atk} = imports.gi;
Gtk.init(null);
const w = new Gtk.Window(), grid = new Gtk.Grid();
const label = new Gtk.Label({label: "Gain"});
const spin = new Gtk.SpinButton({
    adjustment: new Gtk.Adjustment({
        lower: 0.1, upper: 2, step_increment: 0.1,
        page_increment: 1, value: 1,
    }),
    climb_rate: 0, digits: 0,
});
spin.set_hexpand(true);
spin.set_tooltip_text("GAIN\nDefault: 1; range: 0.1 to 2");
label.set_xalign(0);
label.set_line_wrap(true);
label.set_max_width_chars(40);
label.set_mnemonic_widget(spin);
grid.attach(label, 0, 0, 1, 1);
grid.attach(spin, 1, 0, 1, 1);
w.add(grid);
w.show_all();
while (Gtk.events_pending()) Gtk.main_iteration();
const a = spin.get_accessible();
const relation = a.ref_relation_set().get_relation_by_type(Atk.RelationType.LABELLED_BY);
const observed = {
    name: Atk.Object.prototype.get_name.call(a),
    description: Atk.Object.prototype.get_description.call(a),
    labelledBy: relation ? relation.get_target().map(t => Atk.Object.prototype.get_name.call(t)) : [],
};
print(JSON.stringify(observed));
w.destroy();
if (observed.name !== "Gain")
    throw Error("G-1: parameter spin accessible name must be Gain");
```

Observed:

```json
{"name":null,"description":"GAIN\nDefault: 1; range: 0.1 to 2","labelledBy":["Gain"]}
```

The labelled-by relation and tooltip therefore exist, but do **not** supply the required accessible **name**. This is not a missing visible label, a missing tooltip or a demand for a new GUI feature.

### Disposition of previous findings and new visual evidence

- **R3-1 closed for the required reproductions.** My unchanged dual-baseline contracts pass, including raw/escaped/single/double/interior BOM and native-argument cases (`gnome/tests/bom-contract.js:120-148,185-200`). The native boundary still validates UTF-8 before removing one leading BOM (`gnome/native/boundary.odin:31-38`). No previous resolved parser/path/ABI issue is reopened.
- **Review B's R4-1 gate note is addressed, not upheld.** Rework 3 and authorized manifest/devkit documentation amendments are recorded at `docs/waterfall/GATES.md:15`; visual evidence is recorded at `:16`.
- **T-ISO-RENDER:** adopt the main agent's recorded seven passes and three observation/reproduction limits as supplied test evidence (`visual-checks.md:20-30`), not as my own executed desktop tests. The baseline-identical tool limits are not additional defects or blockers; do not label every checklist item passed.
- **T-GUI:** the supplied run records ten passes and **G-1 failing item 9** (`visual-checks.md:36-46`). My source comparison and headless probe independently support G-1. The prior deferral ruling does not allow ignoring a known failed item.
- **D1/D2 remain accepted.** Neither concerns parameter accessible names. Physical T-HW and remaining user-only sign-offs remain deferred, not passed.

### Optional Nix byte-reproducibility observation

Review A reports that an extra `nix-build --check` rebuilt the package and passed all 17 tests, but then exited 1 because installed output bytes differed (`review-A.md:650,686,703`). **I do not uphold this as a second blocker.** The required build command is ordinary `nix-build` with every headless checkPhase test passing, not a bit-for-bit reproducibility check (`docs/waterfall/01-requirements/requirements.md:119,172`); my actual required builds pass. Neither the report nor my evidence isolates a functional, ABI or other required-contract failure from that comparison.

I did not repeat that optional check, do not know the byte-level cause, and make **no claim of bit-reproducibility or that the differing bytes are harmless**. It remains a disclosed, unisolated, noncontract observation, not an exercised pass or an assumed compiler/debug-metadata explanation. No new reproducibility requirement or extra implementation rework is introduced here.

### Upheld-findings table

| Finding | Requirement / severity | Independently verified evidence | Real-world impact / required fix |
|---|---|---|---|
| **G-1 — parameter spin buttons lack an accessible name** | **Acceptance blocker: failed T-GUI item 9**, associated with REQ-045's baseline GUI parity and REQ-052's parameter labels. Accessible-name acceptance is explicit in `docs/waterfall/02-design/design.md:553` and `requirements.md:179`. **Moderate accessibility impact**, not a rendering/security failure. | Production builds the parameter spin, tooltip and mnemonic-label relation but never assigns its name (`gnome/controller/gui/window.odin:574-585`); the headless probe returns `name:null` despite `labelledBy:["Gain"]`. Baseline sets its label to description-or-name and makes it the spin's buddy (`/tmp/ws-baseline/src/controller_main.cpp:457-462`); the main agent observed baseline AT-SPI name `Gain` on the actual Qt control (`visual-checks.md:44`). | [INFERENCE] Assistive clients relying on accessible names cannot identify these parameter controls by name, although some may consult labelled-by relations. This affects ordinary parameter editors, not contrived input. Set each spin's accessible name to the same description-or-name text already returned by `parameter_label`; retain its existing relation and tooltip. |

### Numbered rework list for the builder

1. **G-1 — Name every dynamically created parameter spin using its visible label.** **Required fix:** set the spin's ATK accessible name to `parameter_label(&p)` in the production construction path (`view.odin:119-121` already provides description-or-name selection). Preserve the mnemonic buddy relation, tooltip, editing/debounce behavior and D2; do not replace the GTK widget or change visible text. **Required regression:** add an executed real-GTK headless test, using Xvfb/private D-Bus or equivalent, that exercises the production parameter-editor construction path and checks `gtk_widget_get_accessible`/ATK object name. Cover `description:"Gain", name:"GAIN"` → `Gain`, and empty description → `GAIN`. Assert the name itself, not merely a nonempty labelled-by relation or tooltip. The test must fail on this revision and run in the registered acceptance suite, not remain behind a disabled-by-default self-check or test only a duplicated mock widget. Re-run T-GUI item 9 on the actual controller after the fix, plus the normal GNOME checkPhase and T-KWIN.

No other builder rework is required by this decision. The green 17-test suite currently omits this dynamic-widget name assertion; its success does not override the failed accessible-name check. Rejection returns to phase 3 within the user's expanded five-round allowance.

Not independently exercised here: the main agent's screenshot/AT-SPI desktop scenarios, physical display/HDR/hotplug/suspend tests, optional output-byte reproducibility comparison or driver fault injection. Those limits do not weaken the directly reproduced G-1 finding. This review started no Shell/devkit session, installed/enabled no extension, loaded no module into the live compositor, restarted no compositor and made no mutating live-session-bus call; the GTK probe used only Xvfb, a private bus and local ATK access with the accessibility bridge disabled.

REJECTED
