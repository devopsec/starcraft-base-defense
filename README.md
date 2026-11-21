# starcraft-base-defense

First person VR shooter game

## Layout

- `core/` – engine-agnostic Zig gameplay core (C ABI, `include/sbd.h`)
- `bindings/csharp/` – shared C# P/Invoke binding (Unity, Godot, Stride)
- `engines/unity|godot|stride|unreal|o3de/` – thin engine adapters
- `engines/native/` – engine-free Zig backend (SDL3 + wgpu-native + optional OpenXR) that imports the core as a Zig module
- `data/balance.json` – single source of gameplay tunables
- Open `StarcraftBaseDefense.sln` in JetBrains Rider; open the Unreal `.uproject` separately.

## Prerequisites

- Zig 0.17.1
- .NET SDK 10 (C# binding, Godot, Stride)
- Only for the matching backend:

| Backend | Target version | Parallel enemy stepping | Verified here |
|---|---|---|---|
| Godot | 4.7.2 .NET (`Godot.NET.Sdk/4.7.2`, net10.0) | `WorkerThreadPool` group task, cached `Callable` | headless smoke |
| Stride | 4.4.3 (net10.0) | `Dispatcher.For`, cached delegate | build |
| Unity | 6000.6.10f1 (Unity 6.6), OpenXR | `IJobParallelFor` | no (needs the editor; see `engines/unity/PARITY_CHECKLIST.md`) |
| Unreal | 5.8, C++20 | `ParallelFor` | no (UE not installed) |
| O3DE | 26.05 | `AZ::parallel_for` | `sbd.h` C++20 check only |
| native | Zig 0.17.1, SDL 3.4.20, wgpu-native 29.0.1.1, OpenXR 1.1.65 headers | `std.Io.Group` | tests, headless smoke, windowed run |

The shared C# binding targets `netstandard2.1;net10.0` with C# 9 (the Unity 6 limit). On .NET 5+ its constant-time getters use
`SuppressGCTransition`, and `Push`/`Poll` have `Span` overloads so hosts can pass pooled or stack memory without copying.

## Build & test

- Core: `core/build.sh` (unit tests, C ABI test, Windows/Linux/Android libraries into `core/zig-out`). `zig build test abi-test` is the equivalent
  build.zig flow.
- C# binding: `dotnet test bindings/csharp/Sbd.Native.Tests` (needs `core/zig-out/x86_64-linux/libsbd_core.so`).
- Unity: `tools/sync-unity-core.sh` copies libraries, binding sources and balance.json into `engines/unity`; see `engines/unity/PARITY_CHECKLIST.md`.

## Toolchain (mise)

mise only manages dependencies: `mise.toml` pins Zig, .NET 10 and `just`.

```
mise trust && mise install
```

## Build & test pipeline (just)

All build, setup and test recipes live in the `justfile`; `just` lists them.

```
# choose backend (default: godot); no arg shows current
just configure [godot|stride|unity|unreal|o3de|native]

# core + configured backend
just build
# one-off backend (or SBD_BACKEND=stride just build)
just build stride

# core, C# binding, solution build, headless Godot smoke, native tests + smoke
just test

# play the native backend (see engines/native/README.md)
just run-native
```

Single recipes:
- `build-core`
- `build-godot`
- `build-stride`
- `build-unity`
- `build-o3de`
- `build-native`
- `build-solution`
- `run-native`
- `test-core`
- `test-binding`
- `test-godot`
- `test-native`
- `setup-godot`

Backend precedence: `SBD_BACKEND` env, then `.cache/backend`, then `godot`. `setup-godot` downloads Godot .NET into the git-ignored `.cache/` (the
aqua registry `godot` package is the non-.NET editor, which cannot run this C# adapter). Unity is built in its editor (see
`engines/unity/PARITY_CHECKLIST.md`), Unreal needs UE 5.8 and is not automated. `build-o3de` builds the core, checks `sbd.h` from C++20 and, if
`O3DE_ENGINE_PATH` is set, registers the gem.

## More Info

About the [licensing](LICENSE.md)
The [design document](technical_report.docx)
