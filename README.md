# WaylandShader for PikaOS GNOME

Apply Slang shader presets to your desktop, with per-monitor shader/color controls, a GTK controller, a CLI, and named profiles with an optional login default.

**This branch is the PikaOS GNOME 51 application.** It contains the Odin application, extension, required shader-library patches and application tests—not KDE/niri backends, NixOS packaging, agent instructions or development-session archives. No Nix installation is required. Other GNOME major versions need a matching port; do not bypass Shell version checks.

The native module runs inside GNOME Shell. The GNOME51 path remains experimental: prior isolated checks and controller tests are not general GPU/HDR/rendering acceptance. Only load trusted presets and test expensive shaders outside your working desktop first. This is source code, not a prebuilt `.deb` or a binary release.

## Install on PikaOS

### 1. Check your desktop

Run in a GNOME terminal:

```sh
gnome-shell --version
```

These instructions require **GNOME Shell 51** and the matching **Mutter 51 development SDK** from your PikaOS repositories. Stop if the major version differs. They target x86-64 PikaOS; other architectures/toolchains have not been validated here.

### 2. Install build prerequisites

Review the package list before installing:

```sh
sudo apt update
sudo apt install build-essential cmake ninja-build pkg-config git patch patchelf \
  clang libclang-dev libegl-dev libepoxy-dev libgtk-3-dev libgraphene-1.0-dev \
  libglib2.0-dev gobject-introspection libgirepository-1.0-dev libmutter-51-dev python3
```

You also need **Odin**, a current **stable Rust/Cargo toolchain**, and Python 3 on your `PATH`. Install Odin using its [official installation instructions](https://odin-lang.org/docs/install/) and Rust using its [official toolchain instructions](https://www.rust-lang.org/tools/install). The library build below explicitly enables its stable-Rust path. Build the versioned dependency, not a system-wide replacement.

```sh
odin version
rustc --version
cargo --version
pkg-config --modversion libmutter-51 mutter-clutter-51 mutter-cogl-51 mutter-mtk-51
g-ir-scanner --version
g-ir-compiler --version
```

If a package or SDK component is unavailable, resolve that with your PikaOS repositories before continuing. Do not substitute a different Mutter major.

### 3. Get this branch

```sh
set -eu
git clone --branch pikaOS-DebianBased --single-branch \
  https://github.com/man33li/WaylandShader-Gnome.git
cd WaylandShader-Gnome
APP="$PWD"
BUILD="$APP/build-pikaos"
mkdir -p "$BUILD/private/lib"
```

Keep this terminal open so the variables remain set. Use a clean build directory for a fresh source build; the dependency clone and patch steps below are intended to run once in that directory, not to be reapplied to an existing patched checkout.

### 4. Build the private shader library

Use **librashader 0.10.1** with **both patches in this order**. A stock library, a renamed file without its private SONAME, or another version is not equivalent.

```sh
git clone --branch v0.10.1 --depth 1 \
  https://github.com/SnowflakePowered/librashader.git "$BUILD/librashader"
patch --batch --forward --fuzz=0 -p1 -d "$BUILD/librashader" \
  -i "$APP/patches/librashader-gl-lifetime.patch"
patch --batch --forward --fuzz=0 -p1 -d "$BUILD/librashader" \
  -i "$APP/patches/librashader-gl-dead-final-pair.patch"

CARGO_TARGET_DIR="$BUILD/librashader-target" CARGO_BUILD_JOBS=2 \
  cargo rustc --locked --release \
    --manifest-path "$BUILD/librashader/Cargo.toml" \
    -p librashader-capi --lib --no-default-features \
    --features runtime-opengl,stable -- \
    -C link-arg=-Wl,-soname,libwaylandshader-rashader.so.2

install -m 755 "$BUILD/librashader-target/release/liblibrashader_capi.so" \
  "$BUILD/private/lib/libwaylandshader-rashader.so.2"
patchelf --set-soname libwaylandshader-rashader.so.2 \
  "$BUILD/private/lib/libwaylandshader-rashader.so.2"
ln -s libwaylandshader-rashader.so.2 \
  "$BUILD/private/lib/libwaylandshader-rashader.so"
readelf -d "$BUILD/private/lib/libwaylandshader-rashader.so.2" | grep SONAME
```

The final line must show `libwaylandshader-rashader.so.2`. No system library is overwritten. Cargo downloads the pinned release's locked dependencies; allow time, disk space and RAM for that build.

### 5. Build and stage the application

The repository-root CMake entry point selects the PikaOS GNOME51 backend. Do not use upstream KWin or Nix build commands.

```sh
cmake -S "$APP" -B "$BUILD/app" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DLIBRASHADER_INCLUDE_DIR="$BUILD/librashader/include" \
  -DLIBRASHADER_LIBRARY="$BUILD/private/lib/libwaylandshader-rashader.so.2"
cmake --build "$BUILD/app" --parallel 2
STAGE="$BUILD/stage"
DESTDIR="$STAGE" cmake --install "$BUILD/app"
```

Staging does **not** modify your installed extension or running desktop. Inspect the staged prefix at `$STAGE$HOME/.local`. It must include:

- `bin/waylandshader-gnome-controller` and `bin/waylandshader-gnomectl`;
- `share/applications/org.waylandshader.GnomeController.desktop`;
- `share/gnome-shell/extensions/waylandshader@man33li.github.com/extension.js` and GNOME51 `metadata.json`;
- that extension's `schemas/gschemas.compiled`;
- its `native/` directory containing the module, private `libwaylandshader-rashader.so.2`, GIR and typelib.

The private library is installed next to the module, whose relative `$ORIGIN` search path resolves it. No global `LD_LIBRARY_PATH` setting is required. Use this complete staged set rather than mixing files from different builds.

### 6. Publish the staged files while GNOME is logged out

**Do not run `cmake --install` directly over an active native extension.** It can overwrite library bytes mapped by Shell. This simple source-install route is not the rename-based updater used for some prior personal packages.

If this extension is already installed, disable it in the GNOME Extensions app first and leave it disabled if any installation step fails. Save your work, log out of GNOME, switch to a text console (for example **Ctrl+Alt+F3**), and log in as your normal user. Re-enter the checkout and restore these variables, adjusting the path if you cloned elsewhere:

```sh
set -eu
APP="$HOME/WaylandShader-Gnome"
STAGE="$APP/build-pikaos/stage"
PREFIX="$HOME/.local"
UUID=waylandshader@man33li.github.com
if pgrep -u "$(id -u)" -x gnome-shell >/dev/null; then
  echo 'GNOME Shell is still running for this user; do not install yet.'
  exit 1
fi
test -d "$STAGE$PREFIX/share/gnome-shell/extensions/$UUID/native" || exit 1
mkdir -p "$PREFIX"
BACKUP="$HOME/waylandshader-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$BACKUP"
for rel in bin/waylandshader-gnome-controller bin/waylandshader-gnomectl \
  share/applications/org.waylandshader.GnomeController.desktop \
  "share/gnome-shell/extensions/$UUID"; do
  if [ -e "$PREFIX/$rel" ]; then
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$PREFIX/$rel" "$BACKUP/$rel" || exit 1
  fi
done
cp -a "$STAGE$PREFIX/." "$PREFIX/"
```

The example backs up only the application's existing paths, not all of your user-local data. Use only a known, user-owned installation layout; stop and resolve unexpected symlinks, ownership or destination conflicts before copying. Do not use `sudo` for this user-local installation. Resolve any duplicate system-wide copy of the same extension with its package manager rather than layering unknown installations. Do not enable the extension if the build or copy failed. Restore the backup only while GNOME is likewise logged out.

The text-console example assumes `~/WaylandShader-Gnome`; if you chose another checkout or install prefix, use the same paths as in the build. For an automatic/transactional update or distribution-wide install, a separately tested package is needed; this guide does not claim one.

### 7. Log back into GNOME and use it

Start a normal GNOME login, then:

```sh
gnome-extensions enable waylandshader@man33li.github.com
"$HOME/.local/bin/waylandshader-gnome-controller"
```

The controller's master enable switch controls desktop processing. A CLI mutation may enable this extension; read-only status commands do not.

```sh
"$HOME/.local/bin/waylandshader-gnomectl" status
"$HOME/.local/bin/waylandshader-gnomectl" outputs
"$HOME/.local/bin/waylandshader-gnomectl" load /absolute/path/to/preset.slangp
"$HOME/.local/bin/waylandshader-gnomectl" profile save "My desktop"
"$HOME/.local/bin/waylandshader-gnomectl" profile default "My desktop"
"$HOME/.local/bin/waylandshader-gnomectl" profile clear-default
```

Presets and referenced shader/LUT assets are user supplied. Profile names are exact keys; the GUI and CLI preserve surrounding whitespace and reject blank names. Disabling the master switch bypasses both shader and color processing; per-monitor controls preserve other outputs' settings.

## Checks and troubleshooting

- If the extension is missing, check `gnome-extensions info waylandshader@man33li.github.com`, confirm metadata says `51`, and use a fresh login after native updates. Never globally disable version validation.
- For native errors inspect `journalctl --user -b` and verify that the module, private DSO and typelib came from the same staged build. Do not restart the working Wayland compositor as a test.
- Run `python3 gnome/tests/pikaos-packaging.py` to check README shell syntax, target metadata and the actual CMake install/schema rules against disposable dummy artifacts. This neither builds nor loads the native module.
- App tests and shader fixtures remain in `gnome/tests/` and `tests/fixtures/`. With Node installed, `node gnome/tests/profiles.mjs` exercises actual extension methods using mocked GI/Shell boundaries. It does not test live IPC or native rendering.
- `-DWAYLANDSHADER_BUILD_TESTS=ON` registers additional Odin, GI, GTK and GL checks. These need extra test/runtime prerequisites and isolated sessions; do not run a compositor test against your normal desktop bus. A skipped/missing test is not a pass.

The new PikaOS packaging path is source-reviewed and fixture-checked, not freshly end-to-end built or deployed on every PikaOS installation. A successful source push is not installation or rendering acceptance.

## License

[MIT](LICENSE).
