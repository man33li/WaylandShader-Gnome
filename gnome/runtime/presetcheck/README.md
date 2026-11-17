# Optional offscreen preset checker

`main.odin` is an application developer utility for loading a supplied preset in a private EGL/OpenGL context. It is not installed by the normal PikaOS application build.

It accepts an absolute preset path, the mode `identity` or `capture`, and an output PPM path. Build it only with the same patched private shader library and Odin toolchain as the application. Use a private working/output directory, no desktop bus/display variables and software rendering for isolated checks. A successful offscreen result does not establish GNOME rendering, HDR, physical VRAM or performance behavior.

See the repository-root README for the supported PikaOS source build and application usage. The utility requires the complete preset and its referenced assets; it does not install shader collections.
