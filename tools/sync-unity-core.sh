#!/usr/bin/env bash
# Copies build outputs and shared sources into the Unity project. Run after core/build.sh.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/core/zig-out"
u="$root/engines/unity/Assets"
mkdir -p "$u/Plugins/SbdCore/x86_64" "$u/Plugins/SbdCore/Android/arm64-v8a" "$u/Scripts/Core/Sbd.Native" "$u/Resources"
cp "$out/x86_64-linux/libsbd_core.so" "$u/Plugins/SbdCore/x86_64/libsbd_core.so"
cp "$out/x86_64-windows/sbd_core.dll" "$u/Plugins/SbdCore/x86_64/sbd_core.dll"
cp "$out/aarch64-android/libsbd_core.so" "$u/Plugins/SbdCore/Android/arm64-v8a/libsbd_core.so"
for f in Structs Native World BalanceLoader; do
  cp "$root/bindings/csharp/Sbd.Native/$f.cs" "$u/Scripts/Core/Sbd.Native/$f.cs"
done
cp "$root/data/balance.json" "$u/Resources/balance.json"
echo "unity core synced"
