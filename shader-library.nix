{ pkgs }:

# A private SONAME keeps the corrected GL ownership isolated from other users.
assert pkgs.lib.assertMsg (pkgs.librashader.version == "0.10.1")
  "WaylandShader's GL ownership patch currently targets librashader 0.10.1.";
pkgs.librashader.overrideAttrs (old: {
  pname = "waylandshader-librashader";
  patches = (old.patches or [ ]) ++ [ ./patches/librashader-gl-lifetime.patch ];
  postInstall = (old.postInstall or "") + ''
    mv "$out/lib/librashader.so.2" "$out/lib/libwaylandshader-rashader.so.2"
    rm "$out/lib/librashader.so"
    ln -s libwaylandshader-rashader.so.2 "$out/lib/libwaylandshader-rashader.so"
    patchelf --set-soname libwaylandshader-rashader.so.2 "$out/lib/libwaylandshader-rashader.so.2"
  '';
})
