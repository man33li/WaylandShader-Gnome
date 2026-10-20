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
