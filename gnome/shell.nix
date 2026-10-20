{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  inputsFrom = [ (import ./default.nix { inherit pkgs; }) ];
  packages = with pkgs; [
    gnome-shell
    gjs
    pipewire
  ];
}
