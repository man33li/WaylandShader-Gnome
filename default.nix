{ pkgs ? import <nixpkgs> { } }:

let
  shaderLibrary = import ./shader-library.nix { inherit pkgs; };
in
pkgs.stdenv.mkDerivation {
  pname = "waylandshader";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let name = baseNameOf path;
      in !(builtins.elem name [ "build" "result" ".git" ".cache" ])
        && pkgs.lib.cleanSourceFilter path type;
  };

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
  ];
  buildInputs = with pkgs; [
    kdePackages.kwin
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.kconfig
    kdePackages.kcoreaddons
    libepoxy
    libdrm
    wayland
    libglvnd
    shaderLibrary
  ];

  meta = {
    description = "Native RetroArch slang preset effects for KWin";
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "waylandshader-controller";
  };
}
