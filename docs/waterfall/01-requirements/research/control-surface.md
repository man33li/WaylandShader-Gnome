# Phase 1 Inventory: GNOME Backend Control Surface (read-only)

Scope: `WAYLANDSHADER_GNOME` paths only. Citations are `file:line`. `[INFERENCE]` marks anything I did not verify by reading code or running it. I did not execute any test or binary.

## 1. D-Bus interface `org.waylandshader.Effect` (`/WaylandShader` on `org.gnome.Shell`)

Name, path and interface are fixed by the GNOME branch of `controller_backend.h`: `service`, `effectPath`, `effectInterface` at `src/controller_backend.h:7-8` and `:12`. The XML is declared in `gnome/extension/extension.js:10-22`, and the object is exported at `:63-64`.

| Member | Args in → out | JS handler (`extension.js`) | Native implementation (`gnome/native/waylandshader-effect.cpp`) | Validation / error reply | Test expectation |
|---|---|---|---|---|---|
| `status` | `—` → `s` (JSON) | `:146-148` returns `get_status()` | `:1342-1349`; on exception returns fallback JSON with `enabled:false`, `error:"Unable to construct native status"` (`:1348`) | Read-only; never activates the extension (`src/ctl_main.cpp:190` uses `ensureAvailable(!readOnly)`) | `recent-presets.js:19` reads `recentPresets` |
| `loadPreset` | `s` path → `b` | `:165-167` → `_mutate` | `:1501-1510`: `QFileInfo` must be absolute, readable file (`:1505`); canonicalised (`:1506`); `engine.request` (`:1508`) | Non-absolute/unreadable → `Rejected`. **No `.slangp` suffix check** in native; suffix enforced by CLI (`ctl_main.cpp:97-98`) and GUI (`controller_main.cpp:401`) only | `parameter-bypass.js:69-70` |
| `setEnabled` | `b` → `b` | `:169-171` | `:1512-1520`; no-op when unchanged (`:1515-1516`) still returns success | Master switch; no-op returns `true` | `effect-lifecycle.js:25` |
| `setParameter` | `s` name, `d` value → `b` | `:173-175` | `:1523-1544`: requires `!loading && preset` (`:1526`); live runtime path (`:1530`) or bypassed path checks `lastParameters` (`:1536-1538`); stores override (`:1541`) | Unknown name → `Unknown shader parameter '%1'` (`:1537`); NaN/out-of-range rejected (`parameter-bypass.js:78-89`). Runtime-path validator message not read [INFERENCE] | `parameter-bypass.js:72-89` |
| `setOutputShaderEnabled` | `s` id, `b` → `b` | `:177-179` | `:1547-1559`; unknown id → `Unknown active output: %1` (`:477`) | Independent of color flag | not directly tested |
| `setOutputColorEnabled` | `s` id, `b` → `b` | `:181-183` | `:1561-1570` | Same as above | not directly tested |
| `setOutputGamma` | `s` id, `d` → `b` | `:185-187` | `:1572-1583`; `require(finite && 0.1≤v≤5)` (`:1575-1576`) | `Gamma must be finite and between 0.1 and 5` | not directly tested |
| `setOutputSaturation` | `s` id, `d` → `b` | `:189-191` | `:1585-1596`; `require(finite && 0≤v≤2)` (`:1588-1589`) | `Saturation must be finite and between 0 and 2` | not directly tested |
| `statusChanged` (signal) | `s` JSON | XML `:20`; emitted in `_onStatus` with `GLib.Variant('(s)')` (`:124-144`) | — | Emitted after every `_onStatus` call, i.e. after every mutation and monitor change | `parameter-bypass.js` polls `status` instead |

**Error replies** (`extension.js:150-163`):
- Extension shutting down or effect null → `org.waylandshader.Error.Unavailable`, text `The GNOME effect is shutting down.` (`:151-152`).
- Any exception thrown by the native call → `org.waylandshader.Error.Rejected` with `error.message` (`:157-161`). Native errors come from `mutate()` at `gnome/native/waylandshader-effect.cpp:1219-1230`, which sets a GError and returns `false`.
- Successful mutation → `(b)` true, after `_onStatus` (`:156-158`).
- Malformed argument types are rejected by GIO before JS runs [INFERENCE].

**Status JSON contract** (produced at `waylandshader-effect.cpp:522-544`, validated by `src/controller_client.cpp:229-354`):

| Key | Type | Source | Client check |
|---|---|---|---|
| `enabled`, `active`, `loading` | bool | `:541` | required bool (`controller_client.cpp:240-248`) |
| `preset`, `requestedPreset`, `error` | string | `:542-543` | required string (`:250-258`) |
| `recentPresets` | optional array of nonempty strings | `:542` | `:261-269` |
| `parameters[]` | `name, description, minimum, maximum, step, default, value` | `:524-528` | finite numbers; `min≤max`, `step≥0`, value and default in range, unique names (`controller_client.cpp:270-300` [INFERENCE on exact span]) |
| `outputs[]` | `id, name, shaderEnabled, colorEnabled, gamma, saturation, shaderActive, colorActive, bypass?` | `:531-538`, `settingsJson` `:107-111` | id nonempty and unique; gamma `[0.1,5]`, saturation `[0,2]` (`controller_client.cpp:314-349`) |

**Activation rules.**
- `status` never activates. If the effect is absent it returns `Unavailable` with the install hint (`controller_client.cpp:124-134`).
- Mutations and GUI launch do activate. The client calls `org.gnome.Shell.Extensions.EnableExtension` for `waylandshader@man33li.github.com` (`controller_backend.h:16-19`) when `allowActivation` is true (`controller_client.cpp:136-146`).
- Activation is confirmed by `GetExtensionInfo` and `ExtensionStateChanged` (`controller_client.cpp:160-215`), with a 10 s timeout (`:201`).

## 2. GSettings

| Key | Schema / path | Type | Default | Meaning | Citation |
|---|---|---|---|---|---|
| `configuration` | `org.gnome.shell.extensions.waylandshader` at `/org/gnome/shell/extensions/waylandshader/` | `s` | `''` | Versioned native JSON (`version:1`) with `enabled`, `preset`, `recent_presets`, `parameters`, `outputs` | `gnome/extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml:3-7`; export at `waylandshader-effect.cpp:1352-1375` |

Read on enable (`extension.js:59-61`). Written by `_saveSettings`, which runs on every `_onStatus` and at cleanup (`:114-122`, `:198`). Written only if the string changed (`:118-120`). `metadata.json` names this schema at line 7.

## 3. Extension lifecycle

| Phase | Behavior | Citation |
|---|---|---|
| Enable | Sets `_closing=false`, prepends the `native/` dir to the GI search path, dynamically imports `WaylandShader-1.0` | `extension.js:25-37` |
| Abort during import | If `_closing` was set during the import, returns early | `:38-39` |
| Construction | Creates `Effect`, connects `status-changed`, `monitors-changing` (reset history, set outputs `[]`), `monitors-changed` (rebuild outputs), session `updated` (reset history), `shutdown` | `:41-52` |
| Duplicate guard | Throws if an effect with the same name already exists on the stage | `:54-55` |
| Attach + load | `add_effect_with_name`, `_updateOutputs()`, then `import_settings(saved)` before D-Bus export | `:56-61` |
| Export | Sets `_settingsLoaded`, exports `/WaylandShader`, emits initial status | `:62-65` |
| Failure | Any throw in enable calls `_cleanup()` and rethrows | `:67-70` |
| Signal guard | Handlers are no-ops after `_closing`; exceptions are logged, not propagated | `:77-88` |
| Output inventory | Active monitors only, each as `{id, name, x, y, width, height, scale}` (connector name used as id) | `:90-112` |
| Inhibit unredirect | Held while `enabled && (active || loading || requested)`; `requested` excludes errored state | `:124-141` |
| Disable / cleanup | Sets `_closing`, saves, unexports D-Bus, disconnects signals, `shutdown()`, removes stage effect, re-enables unredirect | `:73-75`, `:193-228` |
| Pending load (native) | `request()` sets `requested`, `pending`, `loading=true`, clears error (`waylandshader-effect.cpp:777-789`). Completion applies only if `generation` matches (`:849-850`). Success prepends to `recent` (`:865-868`). Failure keeps the old preset, restoring `pending=preset` if no runtime exists (`:879-886`) | as cited |
| Disable during pending load | Asserted by `effect-lifecycle.js:23-29`: a queued disable is delivered after GC | `gnome/tests/effect-lifecycle.js:23-30` |
| Recent presets | Cap 10 (`waylandshader-effect.cpp:56`), applied on success (`:866-868`) and on import, where only absolute `.slangp` entries that are not duplicates are kept (`:1417-1424`) | as cited |
| Per-output bypass reason | `failure` string on each output is exported as `bypass` (`:537-538`). Set at `:683`, `:687`, `:692`, `:700`, `:723`, cleared on repaint (`:673`, `:861`) | as cited |

Enable-race note: `enable()` awaits the import and then checks `_closing` (`extension.js:37-39`). A `disable()` during the await is therefore honoured.

## 4. CLI `waylandshader-gnomectl` (`src/ctl_main.cpp`)

**Help text** (`:23-49`):

| Command | Argument count | Mutates | Activates extension | Output |
|---|---|---|---|---|
| `status` | 0 | no | no (`:74-75`, `:190`) | full status JSON, indented (`:160-162`, `:202`) |
| `parameters` | 0 | no | no | JSON array of `parameters` (`:198-200`) |
| `outputs` | 0 | no | no | JSON array of `outputs` (`:198-200`) |
| `load FILE` | 1 | yes | yes (`:190`) | status JSON after success (`:177-178`) |
| `param NAME VALUE` | 2 | yes | yes | status JSON after mutation (`:242-243`) |
| `output ID_OR_NAME shader on|off` | 3 | yes | yes | status JSON |
| `output ID_OR_NAME color on|off` | 3 | yes | yes | status JSON |
| `output ID_OR_NAME gamma NUMBER` | 3 | yes | yes | status JSON; range 0.1–5 |
| `output ID_OR_NAME saturation NUMBER` | 3 | yes | yes | status JSON; range 0–2 |
| `enable` / `disable` | 0 | yes | yes | status JSON |
| `toggle` | 0 | yes | yes | inverts `status.enabled` (`:283`) |

Note that `disable` and `toggle` also activate the extension, since `ensureAvailable(!readOnly)` is true for every non-read-only command (`ctl_main.cpp:190`).

**Argument validation** (all exit 2):
- Unknown command, or wrong arg count (`:82-89`).
- `--timeout` must be an integer 1–3600 (`:90-94`).
- `load` requires an existing `.slangp` file (`:96-104`).
- `param` requires a nonempty name and a finite number (`:105-112`).
- `output` requires `on|off` for shader/color (`:121-124`), or a number in range for gamma/saturation (`:125-136`).
- Monitor selector: exact id first, then unique exact name. An ambiguous name exits 2 (`:248-270`).

**Options and timing:**
- `--timeout SECONDS`, default `120` (`:51-53`). Overall deadline covers asynchronous compile (`:189`).
- Bus call timeout is 10 000 ms (`controller_client.cpp:94`).

**Exit codes** (from help text `:46`, mapped in `:157-158`):
- `0` success.
- `1` rejected by the extension, or shader load failure (`:168`, `:173`, `:175`).
- `2` usage error.
- `3` unavailable, transport or protocol error.
- `4` timeout (`:186`). Operation may still finish.

**Load semantics** (`:163-180`): The CLI waits for `loading` to clear and checks `preset == requested`. If another load replaces the request, it exits 1 (`:166-169`).

**Help output:** `--help` prints to stdout and exits 0 (`:62-64`). Parse errors print to stderr and exit 2 (`:58-60`).

## 5. GUI `waylandshader-gnome-controller` (`src/controller_main.cpp`)

| Widget / control | Behavior | Range / constraints | Citation |
|---|---|---|---|
| Window | Title `WaylandShader — GNOME Shell Desktop Effects`, 740×620 | — | `:69-70` |
| Preset line edit | Placeholder `Select a RetroArch .slangp preset`; typing sets `m_pathEdited` | — | `:77-78`, `:175` |
| Browse… | Native `QFileDialog::getOpenFileName`, filter `RetroArch slang presets (*.slangp)`; picked path fills the line edit | — | `:80`, `:167-174` |
| Recent ▾ | Menu from `status.recentPresets` (cap 10 by native). Disabled when empty. Clicking fills the line edit, does **not** load | ≤10 | `:81-85`, `:503-520`, `:511-517` |
| Load preset | `load()`: rejects non-`.slangp` or non-file, else `loadPreset(canonicalPath)` | — | `:86`, `:176`, `:398-413`, error text `:402` |
| Return in preset field | Loads if the button is enabled | — | `:177` |
| Enable desktop effects | `setEnabled` (master); checkbox state follows status unless a mutation is pending | — | `:93`, `:179-186`, `:525-528` |
| Reconnect / refresh | `ensureAvailable(true)`, i.e. may activate the extension | — | `:94`, `:178`, `:359-372` |
| Monitor combo | Lists `outputs[]` by name, tooltip is id; placeholder `No connected monitors` | — | `:100-105`, `:188-191`, `:305-327` |
| Monitor state label | `Saving…`, `Bypassed`, `Unfiltered: <reason>`, `Preset + color active`, `Preset active`, `Color active`, `No processing active` | — | `:106`, `:294-301` |
| Apply preset on this monitor | `setOutputShaderEnabled` | — | `:113`, `:192-194` |
| Enable color adjustments | `setOutputColorEnabled` | — | `:114`, `:195-197` |
| Gamma | QDoubleSpinBox, decimals 2, step 0.05, keyboard tracking off; `valueChanged` → `setOutputGamma` | **0.1–5.0** (`output_settings.h:6-7`) | `:120-127`, `:198-200` |
| Saturation | Same pattern; `valueChanged` → `setOutputSaturation` | **0.0–2.0** (`output_settings.h:8-9`) | `:129-136`, `:201-203` |
| Summary | Plain text: active / disabled / enabled-but-not-active, plus `Compiling:`, `Loaded preset:`, `Outputs:` | — | `:144-147`, `:535-547` |
| Error label | Operation error plus `Effect error: <status.error>` | — | `:149-153`, `showErrors` `:347-357` |
| Parameter editors | Built from `parameters[]`: spin range = `[min,max]`, step = `step` or `span/100`, tooltip shows default and range; label = description. Changes debounced 100 ms (`:455`), then `setParameter` | exact server bounds | `:434-500`, `:441-452`, `:464-486` |
| Float edit precision | `ParameterSpinBox` prints shortest float via `to_chars`; decimals 323 | — | `:32-63` |
| Master status refresh | Every status event rebuilds controls; dirty parameter editors are not overwritten | — | `:522-558` |
| Monitor-selection guard | Output mutations ignored while another is pending or unavailable | — | `:330-345` |
| Disconnect | `transportError` disables controls and shows `Disconnected — displayed controls may be stale.` | — | `:212-217` |
| Desktop file | `Exec=waylandshader-gnome-controller`, `OnlyShowIn=GNOME` | — | `gnome/org.waylandshader.GnomeController.desktop:5,9` |

**Async behavior:**
- Every mutation is a D-Bus async call with a 10 s timeout (`controller_client.cpp:94`).
- After each mutation the GUI calls `requestStatus` (`controller_main.cpp:375-396`).
- Only transport or unavailable errors disable controls. `Rejected` shows the message and keeps controls live (`:377-380`).
- The GUI calls `ensureAvailable(true)` at startup (`:218`) and on reconnect (`:363`). **Opening the GUI can enable the extension.**

## 6. Tests (`gnome/tests/*.js`)

| Test | Run how | Asserts | Citation |
|---|---|---|---|
| `effect-lifecycle.js` (ctest `gnome_effect_lifecycle`) | `gjs -m … effect-lifecycle.js <ext-dir> tests/fixtures/temporal.slangp`, timeout 10 s, `GI_TYPELIB_PATH` set | Pending `load_preset` then `set_enabled(false)` plus `System.gc()`: the `status-changed` signal still delivers `enabled:false`, `loading` false, no error; 5 s internal deadline | `gnome/CMakeLists.txt:100-105,111`; `effect-lifecycle.js:12-30` |
| `recent-presets.js` (ctest `gnome_recent_presets`) | `gjs -m … recent-presets.js <ext-dir>`, timeout 10 s | Import of 12 valid + mixed entries yields exactly `[p0, UPPER.SLANGP, p1..p8]`: relative paths, non-`.slangp` and non-string entries dropped, duplicates collapsed, cap 10; same list via export and status; malformed `recent_presets` imports as empty | `recent-presets.js:11-27`; `CMakeLists.txt:106-111` |
| `parameter-bypass.js` (**not** in ctest; manual) | `gjs -m gnome/tests/parameter-bypass.js <private-bus-address>` against a fresh disposable Shell | Refuses if a preset or active effect already exists (`:43-44`), needs a virtual monitor (`:45`). Real probe preset loads and is active with `GAIN=1` (`:69-70`) and is first in `recentPresets` (`:71`). Edit while bypassed persists (`:72-75`). Edit while bypassed does not activate (`:76-77`). Invalid edits (`GAIN=3`, `NaN`, `UNKNOWN`) are rejected with `org.waylandshader.Error.*` and do not change the value (`:78-89`). Re-enable applies the bypassed edit (`:91-94`). Cleanup disables and unlinks (`:95-101`) | `parameter-bypass.js:1-101`; `docs/GNOME.md:246,281`; `README.md:240-246` |

**Run path:** `gnome/CMakeLists.txt:96-112` gates the tests on `WAYLANDSHADER_BUILD_TESTS` (default OFF). `gnome/default.nix:49-53` sets it and runs `ctest` in the package check. `docs/GNOME.md:237-239` and `README.md:235-237` document the same commands.

**Fixture:** `tests/fixtures/temporal.slangp` exists (glob result).

## Observations and risks (factual, for the requirements record)

| # | Observation | Evidence |
|---|---|---|
| O1 | Extension returns `org.waylandshader.Error.Unavailable` during shutdown, but the client classifies every `org.waylandshader.Error.*` name as `Rejected`. CLI therefore exits **1**, not 3 | `extension.js:151-152` vs `controller_client.cpp:30-33`; `ctl_main.cpp:158` |
| O2 | Native `load_preset` does not enforce `.slangp`. Only the CLI and GUI do | `waylandshader-effect.cpp:1505` vs `ctl_main.cpp:97-98`, `controller_main.cpp:401` |
| O3 | Opening the GUI activates the extension (`ensureAvailable(true)`) | `controller_main.cpp:218,363`; `controller_client.cpp:136-146` |
| O4 | `disable` and `toggle` may activate the extension | `ctl_main.cpp:190` |
| O5 | `setEnabled` with no change returns `true` | `waylandshader-effect.cpp:1515-1516` |
| O6 | `parameter-bypass.js` is not run by ctest; it needs a disposable session | `gnome/CMakeLists.txt:100-111`; `docs/GNOME.md:246` |
| O7 | `_mutate` does not re-emit status when the mutation throws | `extension.js:155-161` |

## Not verified

- Runtime-path validation messages from `setParameter` (`waylandshader-effect.cpp:1530`) and the internal behaviour of `validateValue` (`:1538`). Not read.
- GNOME `ExtensionState` numeric values. Names `ENABLED→ACTIVE`, `DISABLED→INACTIVE`, `ENABLING→ACTIVATING`, `DISABLING→DEACTIVATING` are confirmed at https://gjs.guide/extensions/upgrading/gnome-shell-46.html. The numeric values 1, 2, 6, 7, 8 are from memory of the Shell source and are `[INFERENCE]`. The client relies on `1=ACTIVE` and waits on `2, 6, 8` (`src/controller_client.cpp:180-195`).
- Exact line spans for `controller_client.cpp` parameter and output bounds checks (`:270-300`, `:320-349`) are inferred from truncated reads, so treat those ranges as approximate.
- Did not inspect `docs/waterfall/README.md`, `gnome/shell.nix`, or the KWin paths, which are out of scope.

**Checks the main agent should run later (not run by me):** `ctest --test-dir build/gnome --output-on-failure` with `-DWAYLANDSHADER_BUILD_TESTS=ON`. Manually run `gjs -m gnome/tests/parameter-bypass.js <private-bus>` in a disposable session. Verify O1 by calling `org.waylandshader.Effect.setEnabled` while the extension is closing.

Skipped or not checked: all runtime behavior, the GJS test outcomes, and the native runtime validators. Risk: O1 and O2 are behavior the user may not expect. O3 means a GUI launch can enable the desktop effect.