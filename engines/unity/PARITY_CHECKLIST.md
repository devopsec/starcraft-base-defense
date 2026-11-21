# Unity adapter: parity checklist vs. build v1.00.01

Setup: `core/build.sh && tools/sync-unity-core.sh`, then open `engines/unity` with Unity 6000.6.10f1
(re-add the project in Unity Hub; the folder moved). Do the "Unity 6 upgrade" section below first. Open `Assets/Scenes/TempScene.unity`.
Run the EditMode tests (Window > General > Test Runner): `LegacySaveImporterTests`.

## Unity 6 upgrade (from 2019.2.10f1; not run in an editor yet)
`ProjectVersion.txt` and `Packages/manifest.json` were retargeted by hand. The editor has to do the rest on first open.
Back up or commit first; the asset upgrade is one-way.
- [ ] Let the editor upgrade the project and reimport assets (API updater: accept).
- [ ] Package Manager resolves `manifest.json` without errors. Removed: package-manager-ui, multiplayer-hlapi, analytics,
      textmeshpro (now part of ugui 2.0), legacy input helpers, Oculus/OpenVR standalone packages, the built-in VR module.
      Added: XR Plug-in Management and OpenXR.
- [ ] Fix compile errors in the bundled SDKs under `Assets/` (VRTK 3, SteamVR, Oculus Integration, PostProcessing v1):
      they use the built-in VR API that Unity 6 no longer has. Either update each SDK to an OpenXR-capable release or
      replace the rig with XR Interaction Toolkit. Until then the VR rig in `TempScene.unity` does not work.
- [ ] Project Settings > XR Plug-in Management: enable OpenXR for Standalone and Android, add the controller profiles.
- [ ] Re-bake the NavMesh if enemies no longer path (AI Navigation package).
- [ ] `GameHost` now steps enemies with `IJobParallelFor` once there are 32 or more: spawn that many and confirm
      behaviour is unchanged.
- [ ] To keep comparing against v1.00.01 on the old editor, use the `~/unity3d` copy; this folder no longer opens in 2019.2.

## Gameplay (compare side by side with the v1.00.01 build)
- [ ] An enemy spawns every 3 s at a random spawn point and chases the player.
- [ ] Shooting: trigger fires at most every 0.15 s; muzzle light, particles, line and haptics play.
- [ ] 5 shots (20 damage) kill an enemy; hurt sound and hit particles play on every hit.
- [ ] Dead enemy plays the death animation, sinks at 2.5/s and disappears 2 s after death.
- [ ] Score +10 per kill; HUD "Score" and "Enemies" counters update.
- [ ] An enemy in range hurts the player for 10 every 0.5 s; health bar, red flash and hurt sound work.
- [ ] At 0 health: "Game Over!" (or "High Score!" when beaten), enemies stop spawning, enemies play PlayerDead.
- [ ] After `time_until_reset` the restart prompt appears; the "A" button reloads the scene and the run restarts.
- [ ] Pause (Esc / start menu): game freezes, menu canvas toggles; unpause resumes. Nothing spawns while paused.

## Persistence
- [ ] High score survives quitting and relaunching (`save_v1.bin` under `Application.persistentDataPath`).
- [ ] With an old `save.bin` present (and no `save_v1.bin`), the old high score is shown once and the file becomes `save.bin.migrated`.
- [ ] A corrupt `save.bin` leaves the high score at 0 without errors.

## Platforms
- [ ] Windows standalone: `Assets/Plugins/SbdCore/x86_64/sbd_core.dll` is loaded (no DllNotFoundException).
- [ ] Linux editor/standalone: `libsbd_core.so` is loaded.
- [ ] Quest (Android arm64): build and confirm `Plugins/SbdCore/Android/arm64-v8a/libsbd_core.so` is packaged and loads.

## Known, intentional differences
- Score is awarded at the moment of death (core rule); v1.00.01 awarded it when the death animation event started sinking.
- Despawn is measured 2 s from death (core `sink_duration`), v1.00.01 measured 2 s from the start of sinking.
- Sinking still starts from the death clip's animation event (`EnemyHealth.StartSinking`).
- Gameplay numbers now come from `Assets/Resources/balance.json` (a synced copy of `data/balance.json`); values serialized on prefabs/scene objects are ignored.
- Restart still reloads scene 0; `GameHost` survives the reload and sends the core a RESTART command.
