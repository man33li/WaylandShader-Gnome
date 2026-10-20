#!/bin/sh
# Golden transcripts of waylandshader-gnomectl (REQ-041..044, T-CLI-GOLDEN).
#   cli-golden.sh capture <ctl>   record golden/cli/NNN.{out,err,code} from <ctl> (the baseline binary)
#   cli-golden.sh check   <ctl>   compare <ctl> with the recorded transcripts
# Every case runs under its own `dbus-run-session` with an empty XDG_DATA_DIRS, so it never
# reaches the caller's session bus. The invoked ctl path is replaced by @CTL@.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
golden=$here/golden/cli
fix=/tmp/ws-cli-golden

if [ "${1:-}" = _case ]; then
    # Runs inside dbus-run-session ($2 = ctl, $3 = case line). Only the ctl's own stdout, stderr
    # and exit code go to $WS_CASE_OUT/$WS_CASE_ERR/$WS_CASE_CODE; everything this wrapper, the
    # bus and gjs print stays on the diagnostic stream. Infrastructure failures exit non-zero
    # without writing $WS_CASE_CODE.
    ctl=$2
    line=$3
    if [ -z "${WS_CALLER_BUS+x}" ] || [ "${DBUS_SESSION_BUS_ADDRESS:-}" = "$WS_CALLER_BUS" ]; then
        echo "cli-golden.sh: refusing to run on the caller's session bus" >&2
        exit 99
    fi
    hang=
    case $line in
    "hang "*)
        hang=1
        line=${line#hang }
        ;;
    esac
    line=$(printf '%s' "$line" | sed "s|@FIX@|$fix|g")
    [ "$line" = "@NONE@" ] && line=
    pid=
    if [ -n "$hang" ]; then
        gjs -m "$here/hang-shell.js" >/dev/null 2>&1 &
        pid=$!
        gdbus wait --session --timeout 5 org.gnome.Shell || {
            echo "cli-golden.sh: hang-shell.js did not appear on the private bus" >&2
            exit 98
        }
    fi
    rc=0
    set -f
    eval "set -- $line"
    "$ctl" "$@" >"$WS_CASE_OUT" 2>"$WS_CASE_ERR" || rc=$?
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    echo "$rc" >"$WS_CASE_CODE"
    exit 0
fi

mode=${1:-}
ctl=${2:-}
case $mode in capture | check) ;; *)
    echo "usage: $0 capture|check <ctl>" >&2
    exit 64
    ;;
esac
[ -x "$ctl" ] || {
    echo "cli-golden.sh: $ctl is not executable" >&2
    exit 64
}

# Fixtures live at a fixed path (cases reference it) but are created exclusively and removed
# on exit; a pre-existing path is never touched.
umask 077
mkdir -p "$golden"
mkdir -m 700 "$fix" || {
    echo "cli-golden.sh: $fix already exists; remove it yourself if it is stale" >&2
    exit 1
}
work=
empty=
trap 'rm -rf ${work:+"$work"} ${empty:+"$empty"} "$fix"' EXIT
printf 'x' >"$fix/a.slangp"
printf 'x' >"$fix/A.SLANGP"
printf 'x' >"$fix/b.txt"

work=$(mktemp -d)
empty=$(mktemp -d)
pattern=$(printf '%s' "$ctl" | sed 's/[][\\/.*^$|&]/\\&/g')
caller=${DBUS_SESSION_BUS_ADDRESS:-}

n=0
failed=0
while IFS= read -r line; do
    case $line in '' | '#'*) continue ;; esac
    n=$((n + 1))
    id=$(printf '%03d' "$n")
    # Private per-case XDG directories and no gvfs daemon/FUSE: nothing leaks from the caller.
    cdir=$work/$id.home
    mkdir -m 700 "$cdir" "$cdir/runtime" "$cdir/config" "$cdir/cache" "$cdir/data" "$cdir/state"
    infra=0
    env -u DBUS_SESSION_BUS_ADDRESS -u DBUS_STARTER_ADDRESS -u DBUS_STARTER_BUS_TYPE \
        XDG_DATA_DIRS="$empty" XDG_RUNTIME_DIR="$cdir/runtime" XDG_CONFIG_HOME="$cdir/config" \
        XDG_CACHE_HOME="$cdir/cache" XDG_DATA_HOME="$cdir/data" XDG_STATE_HOME="$cdir/state" \
        GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 WS_CALLER_BUS="$caller" \
        WS_CASE_OUT="$work/$id.raw.out" WS_CASE_ERR="$work/$id.raw.err" WS_CASE_CODE="$work/$id.raw.code" \
        dbus-run-session -- "$here/cli-golden.sh" _case "$ctl" "$line" \
        >"$work/$id.diag" 2>&1 || infra=1
    if [ "$infra" = 1 ] || [ ! -f "$work/$id.raw.code" ]; then
        echo "cli-golden.sh: infrastructure failure in case $id ($line); nothing recorded" >&2
        cat "$work/$id.diag" >&2
        exit 1
    fi
    sed "s|$pattern|@CTL@|g" "$work/$id.raw.out" >"$work/$id.out"
    sed "s|$pattern|@CTL@|g" "$work/$id.raw.err" >"$work/$id.err"
    cp "$work/$id.raw.code" "$work/$id.code"
    for ext in out err code; do
        if [ "$mode" = capture ]; then
            cp "$work/$id.$ext" "$golden/$id.$ext"
        elif ! cmp -s "$work/$id.$ext" "$golden/$id.$ext"; then
            echo "FAIL case $id ($ext): $line" >&2
            diff "$golden/$id.$ext" "$work/$id.$ext" >&2 || true
            failed=1
        fi
    done
done <"$golden/cases.txt"

if [ "$mode" = capture ]; then
    echo "captured $n cases from $ctl into $golden"
    exit 0
fi
[ "$failed" = 0 ] || exit 1
echo "cli-golden: $n cases match"
