# Native constructor contract (not native rendering acceptance)

`run.py` copies whole selected declarations VERBATIM from current `gnome/native/paint.odin`, compiles them with explicit deterministic Cogl/GObject doubles, and type-checks the actual complete native Odin package. It does not substitute a Python algorithm for application behavior. Source-fragment hashes and binary/input identities are retained under ignored `.law/color-contract/`; compiler/runtime stages use read-only inputs, private namespaces/no desktop/GPU/network, finite resources and owned process-group cleanup. Uncertain cleanup quarantines later runs.

The doubles test publication, re-entry, cache dependencies and reference arithmetic only. They do NOT validate real GObject/Cogl ABI, transform pixels, ICC behavior, GL resource upload/failure, GI, Shell, native linking, deployment or speed. Existing GNOME50/ABI18 stops are unchanged. A missing required native check remains open, not passed by these mocks.

From the application root:

```
/usr/bin/python3 -I -B tests/color_contract/run.py build
/usr/bin/python3 -I -B tests/color_contract/run.py test all
/usr/bin/python3 -I -B tests/color_contract/run.py test snippet_failure_preserves_configuration
```

Unknown names exit2 and never print PASS. Each real successful named case prints PASS only AFTER assertions run. Baseline5536abd builds but fails snippet_failure_preserves_configuration. Build failures/negative witnesses stay in exclusive numbered artifacts; cached binaries require current complete native-source/fixture/tool hash match. Unit budgets are owned by the trial plan, not a permanent expiry on reusable application tests.

Scoped law commands (explicit root/config; never the trial's unrelated existing law loop):

```
/usr/bin/python3 -I -B ../architecture-law/scripts/law.py task start color-construction --root . --config tests/color_contract/law.json
/usr/bin/python3 -I -B ../architecture-law/scripts/law.py loop --root . --config tests/color_contract/law.json
```

This config covers the APPLICATION tree but builds/tests only the constructor contract plus actual native type-check. LOOP COMPLETE here means only the task's stated contract, NOT a configured/passing full-native application loop. A fresh independent reviewer supplies `.law/color-contract-review.json` with current tree/criteria/code/assertion quotes. The parent trial's law config/state is neither invoked nor changed.
