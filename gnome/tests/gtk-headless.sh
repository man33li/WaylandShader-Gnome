#!/bin/sh
# Real GTK tests use only an owned X server, private bus and temporary XDG paths.
set -eu
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -m 700 "$root/runtime" "$root/config" "$root/cache" "$root/data" "$root/state"
env -u WAYLAND_DISPLAY -u AT_SPI_BUS_ADDRESS -u DBUS_SESSION_BUS_ADDRESS \
    -u DBUS_STARTER_ADDRESS -u DBUS_STARTER_BUS_TYPE -u GTK_MODULES \
    XDG_RUNTIME_DIR="$root/runtime" XDG_CONFIG_HOME="$root/config" \
    XDG_CACHE_HOME="$root/cache" XDG_DATA_HOME="$root/data" XDG_STATE_HOME="$root/state" \
    GDK_BACKEND=x11 NO_AT_BRIDGE=1 GIO_USE_VFS=local \
    xvfb-run -a dbus-run-session -- "$@"
