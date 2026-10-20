{ pkgs ? import <nixpkgs> { } }:

let
  shaderLibrary = import ../shader-library.nix { inherit pkgs; };
in
assert pkgs.lib.assertMsg (pkgs.lib.versions.major pkgs.mutter.version == "50")
  "WaylandShader GNOME currently targets GNOME 50 / Mutter ABI 18.";
pkgs.stdenv.mkDerivation {
  pname = "waylandshader-gnome";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ../.;
    filter = path: type:
      let name = baseNameOf path;
      in !(builtins.elem name [ "build" "result" ".git" ".cache" ])
        && !(pkgs.lib.hasPrefix "result-" name)
        && pkgs.lib.cleanSourceFilter path type;
  };
  postUnpack = ''
    sourceRoot="$sourceRoot/gnome"
  '';
  postPatch = ''
    substituteInPlace tests/cli-golden.sh \
      --replace-fail 'dbus-run-session --' 'dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf --'
  '';

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    gobject-introspection
    glib
    gjs
    wrapGAppsHook3
    odin
  ];
  buildInputs = with pkgs; [
    mutter
    gtk3
    # Private pkg-config requirements not propagated by Mutter's dependencies.
    expat
    isocodes
    lerc
    libdeflate
    libevdev
    libwebp
    xz
    libXdmcp
    libXtst
    pcre2
    util-linux
    libselinux
    libsepol
    libthai
    libdatrie
    libxml2
    zstd
    libGL
    shaderLibrary
  ] ++ pkgs.mutter.buildInputs;
  nativeCheckInputs = with pkgs; [ dbus mesa ];
  preCheck = ''
    export HOME=$TMPDIR
    export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
    export LIBGL_ALWAYS_SOFTWARE=1
  '';
  cmakeFlags = [ "-DWAYLANDSHADER_BUILD_TESTS=ON" ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure
    runHook postCheck
  '';
  passthru = {
    extensionUuid = "waylandshader@man33li.github.com";
  };
  meta = {
    description = "Native RetroArch Slang desktop effects for GNOME Shell";
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "waylandshader-gnome-controller";
  };
}
