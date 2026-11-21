#!/usr/bin/env bash
# Direct-compiler equivalent of `zig build test abi-test` + cross builds (no build runner needed).
# Usage: core/build.sh [outdir]   (default: core/zig-out)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-$here/zig-out}"
cache="${ZIG_LOCAL_CACHE_DIR:-$here/.zig-cache}"
z=("${ZIG:-zig}")
c=(--cache-dir "$cache")

"${z[@]}" test "$here/src/root.zig" "${c[@]}"

mkdir -p "$out/x86_64-linux" "$out/x86_64-windows" "$out/aarch64-android" "$out/include"
cp "$here/include/sbd.h" "$out/include/sbd.h"
build() { # target dir file
  "${z[@]}" build-lib "$here/src/root.zig" -dynamic -OReleaseFast -target "$1" --name sbd_core \
    -femit-bin="$out/$2/$3" "${c[@]}"
}
build x86_64-linux-gnu x86_64-linux libsbd_core.so
build x86_64-windows-gnu x86_64-windows sbd_core.dll
build aarch64-linux-android aarch64-android libsbd_core.so
"${z[@]}" build-lib "$here/src/root.zig" -static -OReleaseFast -target x86_64-linux-gnu --name sbd_core_static \
  -femit-bin="$out/x86_64-linux/libsbd_core_static.a" "${c[@]}"

# ABI test: C program compiled against sbd.h, linked to the native library
"${z[@]}" cc -std=c11 -I"$here/include" "$here/tests/abi_test.c" -L"$out/x86_64-linux" -lsbd_core \
  -Wl,-rpath,"$out/x86_64-linux" -o "$out/x86_64-linux/abi_test"
"$out/x86_64-linux/abi_test"
echo "core build OK -> $out"
