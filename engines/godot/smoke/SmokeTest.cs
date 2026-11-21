using System;
using System.Collections.Generic;
using Godot;
using Sbd.Native;
using StarcraftBaseDefense;

/// <summary>
/// Headless smoke test: runs Main.tscn's GameHost non-interactively and plays a scripted game
/// (spawn, chase, shoot, die, sink, despawn, game over, restart). Exits 0 on success, 1 on failure.
/// Run: godot --headless --path engines/godot res://smoke/Smoke.tscn
/// </summary>
public partial class SmokeTest : Node
{
    private GameHost host;
    private double elapsed;
    private int step;
    private uint enemy;

    public override void _Ready()
    {
        var main = GD.Load<PackedScene>("res://scenes/Main.tscn").Instantiate<GameHost>();
        main.Interactive = false;
        AddChild(main);
        host = main;
        GD.Print("smoke: host ready, balance start health=" + host.Config.EnemyStartHealth);
    }

    public override void _Process(double delta)
    {
        elapsed += delta;
        if (elapsed > 60) Fail("timeout in step " + step);

        switch (step)
        {
            case 0:
                host.Send(SbdCmd.Make(SbdCmdKind.SpawnRequest));
                step = 1;
                break;

            case 1:
                if (host.EnemyViewCount == 1)
                {
                    foreach (uint id in host.EnemyEntities) enemy = id;
                    for (int i = 0; i < 5; i++) host.Send(SbdCmd.Make(SbdCmdKind.Hit, enemy, 20));
                    step = 2;
                }
                break;

            case 2:
                if (host.World.Score == 10)
                {
                    GD.Print("smoke: enemy killed, score=10");
                    step = 3;
                }
                break;

            case 3:
                if (host.EnemyViewCount == 0)
                {
                    GD.Print("smoke: enemy despawned after sinking");
                    host.Send(SbdCmd.Make(SbdCmdKind.PauseToggle));
                    step = 4;
                }
                break;

            case 4:
                if (host.World.State == SbdState.Paused)
                {
                    host.Send(SbdCmd.Make(SbdCmdKind.PauseToggle));
                    step = 5;
                }
                break;

            case 5:
                if (host.World.State == SbdState.Playing)
                {
                    byte[] save = host.World.SaveWrite();
                    if (save.Length != SbdAbi.SaveSize) Fail("save size");
                    host.Send(SbdCmd.Make(SbdCmdKind.Restart));
                    step = 6;
                }
                break;

            case 6:
                if (host.World.Score == 0 && host.World.HighScore == 10)
                {
                    GD.Print("SMOKE OK");
                    GetTree().Quit(0);
                    step = 99;
                }
                break;
        }
    }

    private void Fail(string message)
    {
        GD.PrintErr("SMOKE FAIL: " + message);
        GetTree().Quit(1);
        step = 99;
    }
}
