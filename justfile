# Build/test pipeline. Tools (zig, dotnet, just) are pinned in mise.toml: `mise install`.

set shell := ["bash", "-euo", "pipefail", "-c"]

export DOTNET_NOLOGO := "1"
export DOTNET_CLI_TELEMETRY_OPTOUT := "1"

root := justfile_directory()
cache := root / ".cache"
backends := "godot stride unity unreal o3de native"
backend_file := cache / "backend"
# Precedence: SBD_BACKEND env, then .cache/backend (written by `just configure`), then godot.
backend := env("SBD_BACKEND", if path_exists(backend_file) == "true" { trim(read(backend_file)) } else { "godot" })
godot_version := env("GODOT_VERSION", "4.7.2-stable")
godot_dir := cache / "godot-mono" / godot_version
godot_bin := godot_dir / ("Godot_v" + godot_version + "_mono_linux_x86_64") / ("Godot_v" + godot_version + "_mono_linux.x86_64")
o3de_gem := root / "engines/o3de/Gems/SbdCore"
native_dir := root / "engines/native"

# list recipes
@default:
    just --justfile "{{ justfile() }}" --list

# choose the build backend (godot|stride|unity|unreal|o3de|native); no argument shows the current one
[group('build')]
configure name='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ name }}" ]; then echo "backend: {{ backend }}"; exit 0; fi
    case " {{ backends }} " in *" {{ name }} "*) ;; *) echo "unknown backend: {{ name }} (choose: {{ backends }})" >&2; exit 2 ;; esac
    mkdir -p "{{ cache }}"
    echo "{{ name }}" > "{{ backend_file }}"
    echo "backend set to {{ name }}"

# build the core plus one backend (default: the configured backend)
[group('build')]
build name=backend:
    #!/usr/bin/env bash
    set -euo pipefail
    case " {{ backends }} " in *" {{ name }} "*) ;; *) echo "unknown backend: {{ name }} (choose: {{ backends }})" >&2; exit 2 ;; esac
    exec just --justfile "{{ justfile() }}" "build-{{ name }}"

# build the Zig core for all targets and run its unit and C ABI tests
[group('build')]
build-core:
    "{{ root }}/core/build.sh"

# build the Godot backend (core, sync, C# project)
[group('build')]
build-godot: build-core
    "{{ root }}/tools/sync-godot-core.sh"
    dotnet build "{{ root }}/engines/godot/StarcraftBaseDefense.csproj"

# build the Stride backend
[group('build')]
build-stride: build-core
    dotnet build "{{ root }}/engines/stride/StarcraftBaseDefense.Stride"

# prepare the Unity backend (sync core into engines/unity; the player is built in the Unity editor)
[group('build')]
build-unity: build-core
    "{{ root }}/tools/sync-unity-core.sh"
    @echo "Open engines/unity in Unity to build the player."

# Unreal backend: not automated, needs Unreal Engine 5
[group('build')]
build-unreal:
    @echo "Unreal builds require UE5 and are not automated here (open engines/unreal in Rider/UE)." >&2; exit 1

# build the O3DE backend (core, sbd.h C++20 check; registers the gem when O3DE_ENGINE_PATH is set)
[group('build')]
build-o3de: build-core
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    ZIG_LOCAL_CACHE_DIR="$tmp/cache" ZIG_GLOBAL_CACHE_DIR="$tmp/gcache" \
      zig c++ -std=c++20 -c -I"{{ root }}/core/include" "{{ o3de_gem }}/Code/Tests/HeaderCheck.cpp" -o "$tmp/h.o"
    echo "sbd.h C++20 check OK"
    if [ -n "${O3DE_ENGINE_PATH:-}" ] && [ -x "$O3DE_ENGINE_PATH/scripts/o3de.sh" ]; then
      "$O3DE_ENGINE_PATH/scripts/o3de.sh" register --gem-path "{{ o3de_gem }}"
      echo "Gem registered. Enable SbdCore in your O3DE project and build it with CMake."
    else
      echo "O3DE_ENGINE_PATH not set: skipped gem registration (gem: {{ o3de_gem }})."
    fi

# build the native backend (Zig + SDL3 + wgpu-native + optional OpenXR; imports the core as a Zig module)
[group('build')]
build-native optimize='ReleaseFast':
    zig build --build-file "{{ native_dir }}/build.zig" install -Doptimize={{ optimize }}
    @echo "Run: just run-native  (binary: engines/native/zig-out/bin/sbd_native)"

# run the native game; pass options after the recipe, e.g. `just run-native --no-xr`
[group('run')]
run-native *args: (build-native 'ReleaseFast')
    "{{ native_dir }}/zig-out/bin/sbd_native" {{ args }}

# build the whole solution (binding, tests, Godot, Stride)
[group('build')]
build-solution: build-core
    dotnet build "{{ root }}/StarcraftBaseDefense.sln"

# download Godot .NET (mono) into .cache/ for the headless smoke run
[group('setup')]
setup-godot:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -x "{{ godot_bin }}" ]; then exit 0; fi
    mkdir -p "{{ godot_dir }}"
    curl -fsSL "https://github.com/godotengine/godot/releases/download/{{ godot_version }}/Godot_v{{ godot_version }}_mono_linux_x86_64.zip" -o "{{ godot_dir }}/g.zip"
    unzip -q -o "{{ godot_dir }}/g.zip" -d "{{ godot_dir }}"
    rm "{{ godot_dir }}/g.zip"

# run every automated validation (core, C# binding, solution build, headless Godot, native)
[group('test')]
test: test-binding build-solution test-godot test-native
    @echo "Unity/Unreal/O3DE need their editors: see engines/unity/PARITY_CHECKLIST.md"

# Zig core: unit tests, C ABI test, cross builds
[group('test')]
test-core: build-core

# C# binding xUnit tests against the Zig library
[group('test')]
test-binding: build-core
    dotnet test "{{ root }}/bindings/csharp/Sbd.Native.Tests"

# headless Godot smoke run (expects SMOKE OK)
[group('test')]
test-godot: build-godot setup-godot
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(timeout 180 "{{ godot_bin }}" --headless --path "{{ root }}/engines/godot" res://smoke/Smoke.tscn 2>&1)" || true
    grep -E "SMOKE|ERROR" <<<"$out" || true
    grep -q "SMOKE OK" <<<"$out"

# native backend: host unit tests and the headless scripted game (expects NATIVE SMOKE OK)
[group('test')]
test-native: build-core
    zig build --build-file "{{ native_dir }}/build.zig" test smoke --summary failures
