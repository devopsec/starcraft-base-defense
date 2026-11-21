using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Sbd.Native;
using Stride.CommunityToolkit.Engine;
using Stride.CommunityToolkit.Extensions;
using Stride.CommunityToolkit.Games;
using Stride.CommunityToolkit.Helpers;
using Stride.CommunityToolkit.Rendering;
using Stride.CommunityToolkit.Rendering.Compositing;
using Stride.CommunityToolkit.Rendering.ProceduralModels;
using Stride.Core.Mathematics;
using Stride.Core.Threading;
using Stride.Engine;
using Stride.Input;
using Stride.Physics;

namespace StarcraftBaseDefense.Adapter;

/// <summary>
/// Owns the Zig core world: commands in, one tick per frame, events out.
/// Enemy stepping is split into ranges with Stride's Dispatcher.For when there are many enemies.
/// </summary>
public class GameHost : SyncScript
{
    private const int ParallelThreshold = 32;
    private const int ChunkSize = 16;

    public PlayerController Player;

    private SbdWorld world;
    private Action<int> stepChunk;
    private uint stepCount;
    private float stepDt;
    private SbdConfig config;
    private readonly Dictionary<uint, EnemyView> views = new Dictionary<uint, EnemyView>();
    private readonly List<SbdCmd> pending = new List<SbdCmd>();
    private readonly SbdEvent[] eventBuffer = new SbdEvent[128];
    private readonly Vector3[] spawnPoints =
    {
        new Vector3(-16, 0, -16), new Vector3(16, 0, -16), new Vector3(16, 0, 16), new Vector3(-16, 0, 16),
    };
    private int enemiesAlive;
    private int highScoreAtRunStart;
    private bool highScoreFlag;
    private string centerText = "";
    private float hurtFlash;

    private static string SavePath
    {
        get
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "StarcraftBaseDefense");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "save_v1.bin");
        }
    }

    public override void Start()
    {
        string balance = Path.Combine(AppContext.BaseDirectory, "balance.json");
        config = File.Exists(balance) ? BalanceLoader.Parse(File.ReadAllText(balance)) : SbdAbi.DefaultConfig();
        world = SbdWorld.Create(config);
        if (File.Exists(SavePath)) world.SaveRead(File.ReadAllBytes(SavePath));
        highScoreAtRunStart = world.HighScore;
        Player.Host = this;
    }

    public override void Cancel()
    {
        if (world != null && !world.IsClosed)
        {
            SaveHighScore();
            world.Dispose();
        }
    }

    public void Send(SbdCmd cmd)
    {
        pending.Add(cmd);
    }

    public override void Update()
    {
        if (world == null || world.IsClosed) return;
        float dt = (float)Game.UpdateTime.Elapsed.TotalSeconds;

        if (Input.IsKeyPressed(Keys.Escape)) Send(SbdCmd.Make(SbdCmdKind.PauseToggle));
        if (world.State == SbdState.GameOver && Input.IsKeyPressed(Keys.Enter)) Send(SbdCmd.Make(SbdCmdKind.Restart));
        if (world.State == SbdState.Playing && Player.WantsToFire)
        {
            Vector3 m = Player.MuzzlePosition;
            Send(SbdCmd.Make(SbdCmdKind.Fire, 0, 0, new SbdVec3(m.X, m.Y, m.Z)));
        }

        if (pending.Count > 0)
        {
            world.Push(CollectionsMarshal.AsSpan(pending));
            pending.Clear();
        }

        world.Begin(dt);
        StepEnemies(dt);
        world.Resolve();

        int n;
        while ((n = world.Poll(eventBuffer)) > 0)
        {
            for (int i = 0; i < n; i++) Dispatch(ref eventBuffer[i]);
        }

        DrawHud(dt);
    }

    private void StepEnemies(float dt)
    {
        uint count = world.EnemyCount;
        if (count < ParallelThreshold)
        {
            world.StepEnemies(0, count, dt);
            return;
        }

        // stepChunk is created once: per-frame state goes through fields, so nothing is allocated here.
        stepCount = count;
        stepDt = dt;
        int chunks = (int)((count + ChunkSize - 1) / ChunkSize);
        Dispatcher.For(0, chunks, stepChunk ??= StepChunk);
    }

    private void StepChunk(int i)
    {
        uint begin = (uint)(i * ChunkSize);
        world.StepEnemies(begin, Math.Min(begin + ChunkSize, stepCount), stepDt);
    }

    private void Dispatch(ref SbdEvent e)
    {
        switch (e.Kind)
        {
            case SbdEvKind.EnemySpawned:
                SpawnView(e.Entity, e.Value);
                enemiesAlive++;
                break;

            case SbdEvKind.EnemyDied:
                enemiesAlive = Math.Max(0, enemiesAlive - 1);
                if (views.TryGetValue(e.Entity, out EnemyView dying)) dying.OnDied();
                break;

            case SbdEvKind.EnemyDespawn:
                if (views.TryGetValue(e.Entity, out EnemyView gone))
                {
                    views.Remove(e.Entity);
                    gone.Entity.Scene = null;
                }
                break;

            case SbdEvKind.Effect:
                if (e.EffectId == SbdFx.PlayerHurt) hurtFlash = 0.35f;
                // Other effect IDs (hit, death, muzzle, spawn) map to particle emitters when assets exist.
                break;

            case SbdEvKind.Shot:
                OnShot(e.Value);
                break;

            case SbdEvKind.State:
                OnState((uint)e.Value);
                break;
        }
    }

    private void SpawnView(uint entityId, int roll)
    {
        Vector3 point = spawnPoints[roll % spawnPoints.Length];
        Entity entity = Shapes.Capsule((Game)Game, "Enemy", 0.8f, 0.4f, Color.OrangeRed);
        entity.Transform.Position = point + new Vector3(0, 0.6f, 0);

        var body = new RigidbodyComponent { IsKinematic = true, ColliderShape = new CapsuleColliderShape(false, 0.4f, 1.2f, ShapeOrientation.UpY) };
        entity.Add(body);

        var view = new EnemyView { Target = Player.Entity, SinkSpeed = config.SinkSpeed, OnInRangeChanged = OnInRangeChanged, EntityId = entityId };
        entity.Add(view);
        Entity.Scene.Entities.Add(entity);
        views[entityId] = view;
    }

    private void OnInRangeChanged(uint entityId, bool inRange)
    {
        Send(SbdCmd.Make(SbdCmdKind.EnemyInRange, entityId, inRange ? 1 : 0));
    }

    private void OnShot(int damage)
    {
        if (Player.Raycast(this.GetSimulation(), out Vector3 point, out EnemyView enemy))
        {
            Send(SbdCmd.Make(SbdCmdKind.Hit, enemy.EntityId, damage, new SbdVec3(point.X, point.Y, point.Z)));
        }
    }

    private void OnState(uint state)
    {
        Player.InputEnabled = state == SbdState.Playing;
        Input.UnlockMousePosition();
        if (state == SbdState.Playing) Input.LockMousePosition(true);

        switch (state)
        {
            case SbdState.GameOver:
                highScoreFlag = world.HighScore > highScoreAtRunStart;
                if (highScoreFlag) SaveHighScore();
                centerText = (highScoreFlag ? "High Score!  " + world.HighScore : "Game Over!") + "   (Enter to restart)";
                break;
            case SbdState.Paused:
                centerText = "Paused";
                break;
            case SbdState.Playing:
                centerText = "";
                break;
            case SbdState.Restarting:
                foreach (EnemyView v in views.Values) v.Entity.Scene = null;
                views.Clear();
                enemiesAlive = 0;
                highScoreFlag = false;
                highScoreAtRunStart = world.HighScore;
                Player.ResetPose();
                break;
        }
    }

    private void SaveHighScore()
    {
        try
        {
            File.WriteAllBytes(SavePath, world.SaveWrite());
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("sbd: cannot write save: " + ex.Message);
        }
    }

    private void DrawHud(float dt)
    {
        hurtFlash = Math.Max(0, hurtFlash - dt);
        DebugText.Print("Score: " + world.Score + "   High Score: " + world.HighScore, new Int2(16, 12));
        DebugText.Print("Health: " + world.PlayerHealth + "   Enemies: " + enemiesAlive + (hurtFlash > 0 ? "   !!" : ""), new Int2(16, 32));
        if (centerText.Length > 0) DebugText.Print(centerText, new Int2(Game.Window.ClientBounds.Width / 2 - 120, Game.Window.ClientBounds.Height / 2));
    }
}
