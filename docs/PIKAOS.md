# PikaOS / Debian-based branch

`pikaOS-DebianBased` preserves the GNOME work and named-profile feature from the NixOS-oriented upstream while retaining this branch's native GNOME51 opt-in, relative-library RUNPATH fix and guarded private-librashader optimization. Profiles themselves use standard GNOME GSettings and the session D-Bus; they require neither Nix nor a Nix store path.

## Packaging versus runtime

The Nix derivations and NixOS installation examples remain upstream packaging/reference material. Do not run `nixos-rebuild`, `glf-update` or a Nix system installation on a Debian/PikaOS host. There is no generic `.deb` installer or binary release in this source branch. A previously assembled personal user-local package is not a portable Debian package or a profile-enabled rebuild of this merged source.

A non-Nix build uses Odin, CMake/pkg-config, GTK3/GIO, GObject introspection and the matching Mutter/Clutter/Cogl/MTK development SDK, plus the private librashader headers/library with both retained patches. Resolve those dependencies from the target host/toolchain rather than copying absolute Nix store paths. `gnome/CMakeLists.txt` is the build definition; the CMake option `WAYLANDSHADER_EXPERIMENTAL_GNOME51=ON` selects the experimental51 API. It does not make the default GNOME50 extension metadata a supported GNOME51 installation. Schema compilation, generated GI metadata, library search paths and destination ownership must match the actual installation.

This integration does not widen the native support declaration: default GNOME50 packaging remains distinct from the experimental51 path. The native code and shader patches were not changed or rebuilt while integrating profiles. Isolated earlier native checks do not establish general GNOME51 painting, HDR or performance acceptance for this combined source.

## Distribution-independent profile checks

From the repository root, with Node installed:

```sh
node gnome/tests/profiles.mjs
```

The fixture executes actual extension methods with in-memory GI/Shell boundaries. It covers settings preservation, exact profile names, save/load/delete/default behavior, malformed defaults and accepted-target replies. It does not connect to a running compositor or load the native module. The Odin controller unit tests include profile parsing, closed-client replies and load-target identity; run those with the target's existing Odin/GLib toolchain in an isolated environment.

Profile names are exact keys, including surrounding whitespace; empty/whitespace-only names are rejected. The CLI uses the additive `loadProfileStatus` method to capture the accepted canonical preset in the same dispatch, then checks subsequent load status against that target. The original boolean `loadProfile` remains available for older clients/GUI. A newer CLI talking to an older extension fails unavailable rather than silently using the unsafe completion check.

After installing changed native libraries, the running Shell can retain the old mapped inodes until the next normal login. Publishing this source does not update an installed application, restart GNOME, enable an extension or change saved settings. Preserve the current installation and use a separately verified update for deployment.
