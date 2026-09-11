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

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    gobject-introspection
    glib
    gjs
    wrapGAppsHook3
    kdePackages.wrapQtAppsHook
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
    kdePackages.qtbase
    kdePackages.qtwayland
    libepoxy
    shaderLibrary
  ] ++ pkgs.mutter.buildInputs;
  cmakeFlags = [ "-DWAYLANDSHADER_BUILD_TESTS=ON" ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure
    runHook postCheck
  '';
  # Qt's native GNOME file chooser needs GTK's schemas and GIO modules.
  # Merge them into the Qt wrapper instead of wrapping each executable twice.
  dontWrapGApps = true;
  preFixup = ''
    qtWrapperArgs+=("''${gappsWrapperArgs[@]}")
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
