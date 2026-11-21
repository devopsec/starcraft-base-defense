# SbdCore Gem (O3DE skeleton)

Integration skeleton only: it proves O3DE can link the Zig core through the same `sbd.h` as the Unreal module
and tick a world from a system component. It targets O3DE 26.05 and has not been built against an O3DE engine here.

1. Build the core: `core/build.sh` (creates `core/zig-out/...`).
2. Register the gem: `o3de register --gem-path engines/o3de/Gems/SbdCore`, then enable it in your project.
3. `SbdCoreSystemComponent` creates the world, ticks it from `AZ::TickBus` (enemy ranges run on the AzCore
   job system through `AZ::parallel_for` once there are 32 or more enemies), and logs events.
   Follow-ups: load `data/balance.json`, map events to entities/animation, add input and physics raycasts.

## just
`just build o3de` (or `just configure o3de && just build`) builds the core, compiles `Code/Tests/HeaderCheck.cpp`
(C++20 check of `sbd.h`) and, when `O3DE_ENGINE_PATH` is set, registers this gem. The gem itself is still unbuilt without an O3DE engine.
