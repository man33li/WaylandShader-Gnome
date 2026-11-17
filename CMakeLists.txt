cmake_minimum_required(VERSION 3.25)
project(WaylandShaderPikaOS VERSION 0.1.0 LANGUAGES C)

# This branch targets PikaOS GNOME 51, not the upstream KWin/NixOS packages.
set(WAYLANDSHADER_EXPERIMENTAL_GNOME51 ON)
if(WAYLANDSHADER_BUILD_TESTS)
    enable_testing()
endif()
add_subdirectory(gnome)
