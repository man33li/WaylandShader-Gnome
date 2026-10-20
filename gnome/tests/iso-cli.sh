#!/bin/sh
# T-ISO-CLI transcript driver: iso-cli.sh <ctl>. Run it through isolated-session.sh
# (which exports WS_PRIVATE_BUS); it only talks to that disposable bus. The transcript
# ("== <step> exit=<code>" plus stdout) on stdout is diffed between baseline and port.
set -u

ctl=${1:?usage: iso-cli.sh <ctl>}
# Provenance guards: only the disposable bus exported by isolated-session.sh is acceptable.
: "${WS_PRIVATE_BUS:?iso-cli.sh must run inside isolated-session.sh}"
if [ -z "${WS_PRIVATE_ROOT-}" ] || [ "${XDG_RUNTIME_DIR-}" != "$WS_PRIVATE_ROOT/runtime" ] ||
    [ "$WS_PRIVATE_BUS" = "${WS_CALLER_BUS-}" ] || [ "${DBUS_SESSION_BUS_ADDRESS-}" != "$WS_PRIVATE_BUS" ]; then
    echo "iso-cli.sh: refusing a bus that is not the isolated-session private bus" >&2
    exit 1
fi
uuid=waylandshader@man33li.github.com
# Fixed path (the preset path is part of the transcript); created exclusively, never reused.
umask 077
dir=/tmp/ws-iso-cli
mkdir -m 700 "$dir" || {
    echo "iso-cli.sh: $dir already exists; remove it yourself if it is stale" >&2
    exit 1
}
trap 'rm -rf "$dir"' EXIT

cat >"$dir/probe.slang" <<'EOF'
#version 450
layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
} global;
#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 uv;
void main() { gl_Position = global.MVP * Position; uv = TexCoord; }
#pragma stage fragment
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(push_constant) uniform Push { float GAIN; } params;
#pragma parameter GAIN "Gain" 1.0 0.1 2.0 0.1
void main() { FragColor = vec4(texture(Source, uv).rgb * params.GAIN, 1.0); }
EOF
printf 'shaders = 1\nshader0 = probe.slang\n' >"$dir/probe.slangp"
printf '#version 450\nthis does not compile\n' >"$dir/broken.slang"
printf 'shaders = 1\nshader0 = broken.slang\n' >"$dir/broken.slangp"

pattern=$(printf '%s' "$ctl" | sed 's/[][\\/.*^$|&]/\\&/g')

bad=0

# step <name> <expected-exit> <show-stdout 0|1> <ctl args...>: prints the transcript block and
# records a failure (reported on stderr, never in the transcript) when the exit differs.
step() {
    name=$1
    want=$2
    show=$3
    shift 3
    out=$("$ctl" "$@" 2>/dev/null)
    rc=$?
    echo "== $name exit=$rc"
    [ "$show" = 1 ] && [ -n "$out" ] && printf '%s\n' "$out" | sed "s|$pattern|@CTL@|g"
    if [ "$rc" != "$want" ]; then
        echo "iso-cli.sh: step $name exited $rc, expected $want" >&2
        bad=1
    fi
    return 0
}

# wait_idle <name>: poll status until it succeeds with loading=false (at most 30 s), then print
# it. Running out of time is a failure.
wait_idle() {
    deadline=$(($(date +%s) + 30))
    idle=0
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if out=$("$ctl" --timeout 1 status 2>/dev/null) && ! printf '%s' "$out" | grep -q '"loading": true'; then
            idle=1
            break
        fi
        sleep 1
    done
    if [ "$idle" != 1 ]; then
        echo "iso-cli.sh: $1: still loading or unavailable after 30 s" >&2
        bad=1
    fi
    step "$1" 0 1 --timeout 5 status
}

# 1
step 1-status 0 1 status
step 1-outputs 0 1 outputs
step 1-parameters 0 1 parameters
# 2
first=$("$ctl" outputs 2>/dev/null | sed -n 's/^ *"id": "\([^"]*\)".*/\1/p' | sed -n 1p)
if [ -z "$first" ]; then
    echo "iso-cli.sh: outputs reported no monitor id" >&2
    exit 1
fi
step 2-gamma 0 1 output "$first" gamma 1.2
step 2-saturation 0 1 output "$first" saturation 0
step 2-color 0 1 output "$first" color on
step 2-shader-off 0 1 output "$first" shader off
step 2-shader-on 0 1 output "$first" shader on
# 3: an unknown selector is a usage error (src/ctl_main.cpp:269-271)
step 3-unknown-output 2 0 output nonexistent gamma 1
# 4
step 4-load-probe 0 1 load "$dir/probe.slangp"
step 4-param-0.5 0 1 param GAIN 0.5
step 4-param-3 1 1 param GAIN 3
step 4-param-unknown 1 1 param UNKNOWN 1
# 5
step 5-load-broken 1 1 load "$dir/broken.slangp"
step 5-status 0 1 status
# 6
step 6-disable 0 1 disable
step 6-toggle 0 0 toggle
step 6-enable 0 0 enable
wait_idle 6-status
# 7
gnome-extensions disable "$uuid" >/dev/null 2>&1
rc=$?
echo "== 7-extension-disable exit=$rc"
if [ "$rc" != 0 ]; then
    echo "iso-cli.sh: gnome-extensions disable failed ($rc)" >&2
    bad=1
fi
step 7-status 3 1 status
# 8
step 8-enable 0 0 enable
wait_idle 8-status
exit "$bad"
