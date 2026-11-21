# Native backend

An engine-free host written in Zig 0.17. It imports the core as a Zig module (`core/build.zig` exports `sbd_core`), so
there is no FFI layer, and it presents with:

- **SDL 3.4** (castholm/SDL, built from source by `zig build`): window, keyboard/mouse, gamepads, save path.
- **wgpu-native 29** (prebuilt, Vulkan/DX12/Metal behind WebGPU): one instanced-cube pipeline for the arena, enemies,
  hit/death/spawn effects and the crosshair. HUD is the window title.
- **OpenXR 1.1** (optional, loader opened at runtime): see "VR" below.

Enemy ranges run on `std.Io.Group` (the `std.Io.Threaded` pool from `main`) once 32 or more enemies are alive, using
the same begin / `stepEnemies(range)` / resolve split as the engine adapters. The frame loop allocates nothing.

## Build, run, test

```
just build native        # ReleaseFast into engines/native/zig-out/bin
just run-native          # play; extra options go after the recipe, e.g. just run-native --no-xr
just test-native         # unit tests + headless scripted game (NATIVE SMOKE OK)
```

Directly with Zig, from `engines/native`: `zig build run`, `zig build test smoke`,
`zig build -Dtarget=x86_64-windows-gnu` (installs `sbd_native.exe` next to `wgpu_native.dll`).
Targets: x86_64 Linux (X11 or Wayland) and x86_64 Windows, which are the platforms the wgpu-native packages are wired for.

Options: `--smoke`, `--headless --frames N`, `--frames N` (windowed, then quit), `--balance PATH` (default: the
`data/balance.json` embedded at build time), `--no-xr`, `--serial` (no job system).

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | left stick |
| Look | mouse | right stick |
| Fire | left mouse / Space | right trigger |
| Pause | Esc / P | Start |
| Restart (game over) | Enter | South (A) |
| Quit | F10 / close window | |

The high score is saved to SDL's pref path (`~/.local/share/StarcraftBaseDefense/native/save_v1.bin`,
`%APPDATA%\StarcraftBaseDefense\native\` on Windows) in the core's versioned save format.

## VR

wgpu-native exposes no Vulkan interop in its C API, so frames cannot be submitted to an OpenXR swapchain from here.
What is implemented:

- With a loader and an HMD, the instance and system are created and reported in the log.
- If the runtime offers `XR_MND_headless` (Monado does), a session runs: head orientation drives aim and the right
  controller trigger fires (simple, Touch, Index and Vive profiles). The picture stays on the desktop window.
- Without a loader, runtime or HMD the game runs in desktop mode.

The XR path is untested here, because no OpenXR runtime is installed. Stereo rendering needs either wgpu-native Vulkan interop
or a dedicated Vulkan renderer and is a follow-up.
