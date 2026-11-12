# Check an actual Slang preset before desktop use

This small executable accepts an **absolute `.slangp` path** and calls the production shader runtime. It does not import
Mutter, start GNOME Shell, use the desktop bus, install an extension or change the GNOME compatibility guards.
Keep presets and their shader/include/LUT files in their original relative layout.

Build this Odin package directly with the same patched private librashader dependency used by the application:

```sh
odin build gnome/runtime/presetcheck -out:/absolute/private-build/presetcheck -o:speed -vet -strict-style '-extra-linker-flags:-L/absolute/private-library-directory -pthread'
```

The private library must be loader-resolvable at execution. The command's paths describe build inputs; this is not an
installer. In this workspace, the trial owner supplies actual resolved paths, a read-only namespace, software llvmpipe,
private temporary directories, resource/output limits and supervised cleanup. The executable **alone is not a sandbox**.
Do not execute unknown GPU programs inside your working compositor just because this check exists.

The executable takes `ABSOLUTE.slangp identity|capture OUTPUT.ppm`. It creates a 128×72 spatial RGB test pattern,
loads the actual preset on a worker, reports active passes/parameters, renders eight frames and checks finite readback,
GL errors and host-context/viewport restoration. `identity` additionally compares every RGBA component against the
source at tolerance0.003 and tests missing-preset rejection followed by continued rendering. Use that mode only for a
preset actually specified to preserve the input; use `capture` for artistic filters.

The last-frame PPM preview is vertically arranged for ordinary image viewers and **clipped to SDR [0,1]**. It is not
an HDR-output or visual-fidelity oracle. Black frames, temporal behavior and HDR-range values can be intentional;
`capture` does not invent a universal must-change/must-not-be-black rule. A passing run establishes this preset's
load/render/control behavior on the recorded GL implementation, not compositor integration or physical display quality.

`verify.py` and its scoped law task are workspace acceptance support: they use the trial's bounded owner and frozen
input manifest, reparse successful receipts and never replay a completed preset process. This does not configure or
complete the full application's acceptance loop. Local native installation still requires a validated target-Mutter
port, the private library at a durable path, GI/schema/GUI dependencies and isolated full-application checks.
