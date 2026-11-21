# Unreal adapter (UE 5.8, C++20)

`StarcraftBaseDefense/` is a code-only Unreal project that plays the gameplay-parity slice on the Zig core.

- `Source/ThirdParty/SbdCore/SbdCore.Build.cs`: external module that links `core/zig-out/*` and includes `core/include/sbd.h`.
- `Source/SbdGame/SbdAbiCheck.h`: `static_assert`s on the `sbd.h` struct sizes (also checked in Zig and C#).
- `ASbdGameMode`: creates the world from `data/balance.json`, ticks it every frame (`ParallelFor` over enemy ranges), dispatches events, loads/saves the high score through `USbdSaveGame`, maps effect IDs to Niagara systems via `EffectSystems` (debug markers when unset).
- `ASbdEnemyActor`: `ACharacter` with an AI controller (`MoveToActor` on a nav mesh; straight-line steering if the level has none).
- `ASbdPlayerPawn`: first-person pawn; shooting uses a line trace, the core gates fire rate and damage.
- `ASbdHud`: canvas HUD (score, health, enemies, pause/game-over banner).

## Build and open in Rider
1. `core/build.sh` (produces the libraries under `core/zig-out`).
2. Install Unreal Engine 5.8 and Rider with the Unreal Engine plugin. Rider: *File > Open* and choose `StarcraftBaseDefense.uproject`
   (Rider treats it as an Unreal project and generates the solution); or right-click the `.uproject` in Explorer/Files,
   *Generate project files*, then open the generated `.sln`.
3. Build target `StarcraftBaseDefenseEditor` (Development Editor) and run; the default map is the engine's `Template_Default`
   and the arena floor is spawned in code.

## Status
Not compiled in this environment (Unreal Engine is not installed there). Only the plain-C++ struct checks in
`SbdAbiCheck.h` were verified, with a regular C++ compiler. The retarget from 5.4 to 5.8 (engine association,
`BuildSettingsVersion.Latest`, the engine-default C++20) is therefore untested. Known gaps: HUD is canvas-based instead of UMG,
and Niagara systems have to be assigned in a Blueprint subclass or `DefaultGame.ini`.
