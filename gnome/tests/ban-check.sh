#!/bin/sh
set -eu
[ "$#" = 1 ] || { echo 'usage: ban-check.sh GNOME_SOURCE_DIR' >&2; exit 2; }
root=$1
failed=0
for dir in native runtime common glib; do
    files=$(find "$root/$dir" -type f -name '*.odin' ! -name '*_test.odin' ! -path '*/gltest/*')
    [ -n "$files" ] || { echo "missing production package: $dir" >&2; exit 1; }
    # File names in this owned source tree contain no whitespace.
    for file in $files; do
        if grep -nE '(^|[^#[:alnum:]_])(panic|assert|unreachable)[[:space:]]*\(|#no_bounds_check|or_panic|gl\.(Finish|ClientWaitSync)' "$file"; then failed=1; fi
    done
done
cmake=$root/CMakeLists.txt
for required in 'GL_DEBUG=false' '--version-script'; do
    grep -Fq -- "$required" "$cmake" || { echo "missing $required" >&2; failed=1; }
done
if grep -nE -- '-no-bounds-check|CXX|Qt6' "$cmake"; then failed=1; fi
if find "$root/native" -type f -name '*.cpp' | grep .; then failed=1; fi
grep -RqF 'cannot release shader objects' "$root/runtime" || { echo 'missing context-release failure diagnostic' >&2; failed=1; }
exit "$failed"
