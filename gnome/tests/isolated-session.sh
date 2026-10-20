#!/bin/sh
set -eu
# Re-exec only after replacing every writable XDG directory and the session bus.
if [ "${1-}" != --private-child ]; then
    [ "$#" -ge 3 ] && [ "$2" = -- ] || { echo 'usage: isolated-session.sh PACKAGE -- COMMAND...' >&2; exit 2; }
    package=$(realpath "$1")
    [ -d "$package/share/gnome-shell/extensions/waylandshader@man33li.github.com" ] || { echo 'package extension missing' >&2; exit 2; }
    caller_bus=${DBUS_SESSION_BUS_ADDRESS-}
    caller_runtime=${XDG_RUNTIME_DIR-}
    host_socket=${WAYLAND_DISPLAY-}
    case "$host_socket" in /*|'') ;; *) host_socket=$caller_runtime/$host_socket ;; esac
    root=$(mktemp -d "${TMPDIR:-/tmp}/waylandshader-session.XXXXXXXX")
    cleanup_root() {
        status=$?
        trap - EXIT
        # Private bus-activated FUSE services need time to observe bus shutdown.
        for _ in $(seq 1 10); do
            if rm -rf -- "$root" 2>/dev/null; then exit "$status"; fi
            sleep 1
        done
        echo "private session cleanup failed: $root" >&2
        exit "$status"
    }
    trap cleanup_root EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir -m 700 "$root/runtime" "$root/config" "$root/data" "$root/cache" "$root/state"
    shift 2
    env -u DBUS_SESSION_BUS_ADDRESS -u DBUS_STARTER_ADDRESS -u DBUS_STARTER_BUS_TYPE -u DISPLAY -u WAYLAND_DISPLAY \
        WS_CALLER_BUS="$caller_bus" WS_CALLER_RUNTIME="$caller_runtime" WS_PRIVATE_ROOT="$root" \
        WS_HOST_WAYLAND_SOCKET="$host_socket" XDG_RUNTIME_DIR="$root/runtime" \
        XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache" XDG_STATE_HOME="$root/state" \
        XDG_DATA_DIRS="$package/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        GSETTINGS_BACKEND=keyfile GVFS_DISABLE_FUSE=1 LIBGL_ALWAYS_SOFTWARE=1 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
        dbus-run-session -- sh "$0" --private-child "$@" 3>&1 1>&2
    exit $?
fi
shift
[ -n "${WS_PRIVATE_ROOT-}" ] && [ "$XDG_RUNTIME_DIR" = "$WS_PRIVATE_ROOT/runtime" ] && \
    [ "$XDG_RUNTIME_DIR" != "${WS_CALLER_RUNTIME-}" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS-}" ] && \
    [ "$DBUS_SESSION_BUS_ADDRESS" != "${WS_CALLER_BUS-}" ] || { echo 'refusing caller bus or runtime directory' >&2; exit 1; }
[ "$XDG_CONFIG_HOME" = "$WS_PRIVATE_ROOT/config" ] && [ "$XDG_DATA_HOME" = "$WS_PRIVATE_ROOT/data" ] && \
    [ "$XDG_CACHE_HOME" = "$WS_PRIVATE_ROOT/cache" ] && [ "$XDG_STATE_HOME" = "$WS_PRIVATE_ROOT/state" ] || exit 1
export WS_PRIVATE_BUS=$DBUS_SESSION_BUS_ADDRESS
shell_pid=
cleanup() {
    if [ -n "$shell_pid" ]; then
        kill "$shell_pid" 2>/dev/null || :
        wait "$shell_pid" 2>/dev/null || :
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['waylandshader@man33li.github.com']"
if [ "${WS_DEVKIT:-0}" = 1 ]; then
    [ -S "$WS_HOST_WAYLAND_SOCKET" ] || { echo 'devkit requires host Wayland socket' >&2; exit 1; }
    WAYLAND_DISPLAY=$WS_HOST_WAYLAND_SOCKET gnome-shell --wayland --devkit --no-x11 --wayland-display waylandshader-check --virtual-monitor 640x480@60 --virtual-monitor 800x600@75 &
else
    env -u DISPLAY -u WAYLAND_DISPLAY gnome-shell --wayland --headless --no-x11 --wayland-display waylandshader-check --virtual-monitor 640x480@60 --virtual-monitor 800x600@75 &
fi
shell_pid=$!
export WS_SHELL_PID=$shell_pid
ready=0
deadline=$(($(date +%s) + 60))
while [ "$(date +%s)" -lt "$deadline" ]; do
    kill -0 "$shell_pid" 2>/dev/null || { echo 'private Shell exited' >&2; exit 1; }
    info=$(gdbus call --session --timeout 1 --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Extensions.GetExtensionInfo waylandshader@man33li.github.com 2>/dev/null) || info=
    case "$info" in *"'state': <1.0>"*|*"'state': <uint32 1>"*|*"'state': <1>"*) ready=1; break ;; esac
    sleep 1
done
[ "$ready" = 1 ] || { echo 'private extension did not activate within 60 seconds' >&2; exit 1; }
"$@" >&3 3>&-
