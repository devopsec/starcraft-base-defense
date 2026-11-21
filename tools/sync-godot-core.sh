#!/usr/bin/env bash
# Copies native libraries and balance.json into the Godot project. Run after core/build.sh.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
g="$root/engines/godot"
mkdir -p "$g/native" "$g/data"
cp "$root/core/zig-out/x86_64-linux/libsbd_core.so" "$g/native/libsbd_core.so"
cp "$root/core/zig-out/x86_64-windows/sbd_core.dll" "$g/native/sbd_core.dll"
cp "$root/data/balance.json" "$g/data/balance.json"
echo "godot core synced"
