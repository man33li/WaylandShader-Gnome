#!/bin/sh
set -eu
[ "$#" = 3 ] || { echo 'usage: elf-check.sh LIB CTL GUI' >&2; exit 2; }
export LC_ALL=C
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
nm -D --defined-only --format=just-symbols "$1" | sort > "$tmp/exports"
diff -u "$here/golden/exports.txt" "$tmp/exports"
readelf -d "$1" > "$tmp/dynamic"
grep -Eq '\(SONAME\).*\[libwaylandshader-gnome\.so\]' "$tmp/dynamic"
grep -Eq '\(NEEDED\).*\[libwaylandshader-rashader\.so\.2\]' "$tmp/dynamic"
for file do
    readelf -d "$file" > "$tmp/dynamic"
    if grep -E '\(NEEDED\).*\[(libQt6|libstdc\+\+)' "$tmp/dynamic"; then
        echo "forbidden dependency: $file" >&2
        exit 1
    fi
    if grep -E '\((RUNPATH|RPATH)\).*\[([^]:]*:)*/(:[^]]*)?\]' "$tmp/dynamic"; then
        echo "forbidden root runtime search path: $file" >&2
        exit 1
    fi
done
