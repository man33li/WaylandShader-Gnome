# WaylandShader TODO

Current implementations: native KWin 6.6 and GNOME 50, with one shared Slang preset, independent monitor selection, and per-monitor gamma/saturation controls.

## Install and verify the KWin update

- [ ] Let the current `glf-switch` finish successfully.
- [ ] Log out of Plasma and back in to load the updated KWin plugin.
- [ ] Check the monitor selector, per-monitor shader and color toggles, and gamma/saturation controls on physical monitors.

## Native backends

- [ ] **niri:** continue native-backend development and validation on CachyOS in the separate `niri-backend` branch.
- [x] **GNOME:** implement native GNOME Shell/Mutter integration, separate packaging, GUI/CLI controls, and isolated native rendering verification.
- [ ] **COSMIC:** implement native COSMIC compositor integration.

## Further validation

- [ ] Validate physical HDR and wide-gamut behavior. KWin uses SDR sRGB; GNOME preserves HDR headroom and passes a synthetic PQ identity check, but hardware/preset compatibility remains unvalidated.
- [ ] Validate physical monitor rotation.
- [ ] Measure latency on physical displays with representative shader presets.
- [ ] Measure idle and active power consumption with representative shader presets.
- [ ] Validate GNOME installation, physical monitor hotplug/scaling, lock/unlock, and native-module upgrades across fresh logins on GLF-OS.
