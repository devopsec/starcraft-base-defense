using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Godot;
using Sbd.Native;

namespace StarcraftBaseDefense;

/// <summary>
/// Owns the Zig core world and drives it from _Process: commands in, one tick, events out.
/// Enemy stepping is split into ranges on WorkerThreadPool when there are many enemies.
/// </summary>
public partial class GameHost : Node3D
{
    private const int ParallelThreshold = 32;
    private const int ChunkSize = 16;
    private const string SavePath = "user://save_v1.bin";

    [Export] public PackedScene EnemyScene;
    /// <summary>When false (smoke tests) no arena, player or HUD is created and input is ignored.</summary>
    [Export] public bool Interactive = true;

    public SbdWorld World { get; private set; }
    public SbdConfig Config { get; private set; }
    public int EnemiesAlive { get; private set; }
    public bool HighScoreFlag { get; private set; }
    public int EnemyViewCount { get { return views.Count; } }
    public IReadOnlyCollection<uint> EnemyEntities { get { return views.Keys; } }
    public PlayerController Player { get; private set; }

    private readonly Dictionary<uint, EnemyView> views = new Dictionary<uint, EnemyView>();
    private readonly List<SbdCmd> pending = new List<SbdCmd>();
    private Callable stepChunk;
    private uint stepCount;
    private float stepDt;
    private readonly SbdEvent[] eventBuffer = new SbdEvent[128];
    private readonly List<Marker3D> spawnPoints = new List<Marker3D>();
    private EffectPlayer effects;
    private Label scoreLabel;
    private Label centerLabel;
    private int highScoreAtRunStart;

    public override void _Ready()
    {
        NativeLoader.Install();
        Config = LoadConfig();
        World = SbdWorld.Create(Config);
        LoadHighScore();
        highScoreAtRunStart = World.HighScore;
        stepChunk = Callable.From<int>(StepChunk);

        effects = new EffectPlayer();
        AddChild(effects);
        BuildSpawnPoints();

        if (Interactive)
        {
            RegisterInput();
            BuildArena();
            BuildPlayer();
            BuildHud();
            Input.MouseMode = Input.MouseModeEnum.Captured;
        }
    }

    public override void _ExitTree()
    {
        if (World != null && !World.IsClosed)
        {
            SaveHighScore();
            World.Dispose();
        }
    }

    public override void _Notification(int what)
    {
        if (what == NotificationWMCloseRequest && World != null && !World.IsClosed) SaveHighScore();
    }

    public void Send(SbdCmd cmd)
    {
        pending.Add(cmd);
    }

    public override void _Process(double delta)
    {
        if (World == null || World.IsClosed) return;

        if (Interactive) CollectInput();
        FlushCommands();

        World.Begin((float)delta);
        StepEnemies((float)delta);
        World.Resolve();

        int n;
        while ((n = World.Poll(eventBuffer)) > 0)
        {
            for (int i = 0; i < n; i++) Dispatch(ref eventBuffer[i]);
        }

        if (Interactive) UpdateHud();
    }

    // ---- frame steps ----

    private void FlushCommands()
    {
        if (pending.Count == 0) return;
        World.Push(CollectionsMarshal.AsSpan(pending));
        pending.Clear();
    }

    private void StepEnemies(float dt)
    {
        uint count = World.EnemyCount;
        if (count < ParallelThreshold)
        {
            World.StepEnemies(0, count, dt);
            return;
        }

        // The Callable is created once in _Ready: per-frame state goes through fields, so nothing is allocated here.
        stepCount = count;
        stepDt = dt;
        int chunks = (int)((count + ChunkSize - 1) / ChunkSize);
        long group = WorkerThreadPool.AddGroupTask(stepChunk, chunks, -1, true, "sbd_step_enemies");
        WorkerThreadPool.WaitForGroupTaskCompletion(group);
    }

    private void StepChunk(int i)
    {
        uint begin = (uint)(i * ChunkSize);
        World.StepEnemies(begin, Math.Min(begin + ChunkSize, stepCount), stepDt);
    }

    private void CollectInput()
    {
        if (Input.IsActionJustPressed("sbd_pause")) Send(SbdCmd.Make(SbdCmdKind.PauseToggle));
        if (World.State == SbdState.GameOver && Input.IsActionJustPressed("sbd_restart")) Send(SbdCmd.Make(SbdCmdKind.Restart));
        if (Player != null && World.State == SbdState.Playing && Player.WantsToFire())
        {
            Vector3 m = Player.MuzzlePosition;
            Send(SbdCmd.Make(SbdCmdKind.Fire, 0, 0, new SbdVec3(m.X, m.Y, m.Z)));
        }
    }

    // ---- events ----

    private void Dispatch(ref SbdEvent e)
    {
        Vector3 pos = new Vector3(e.Pos.X, e.Pos.Y, e.Pos.Z);
        switch (e.Kind)
        {
            case SbdEvKind.EnemySpawned:
                SpawnView(e.Entity, e.Value);
                EnemiesAlive++;
                break;

            case SbdEvKind.EnemyDied:
                EnemiesAlive = Math.Max(0, EnemiesAlive - 1);
                if (views.TryGetValue(e.Entity, out EnemyView dying)) dying.OnDied();
                break;

            case SbdEvKind.EnemyDespawn:
                if (views.TryGetValue(e.Entity, out EnemyView gone))
                {
                    views.Remove(e.Entity);
                    if (IsInstanceValid(gone)) gone.QueueFree();
                }
                break;

            case SbdEvKind.Effect:
                effects.Play(e.EffectId, pos);
                break;

            case SbdEvKind.Shot:
                OnShot(e.Value);
                break;

            case SbdEvKind.State:
                OnState((uint)e.Value);
                break;
        }
    }

    private void SpawnView(uint entity, int roll)
    {
        if (EnemyScene == null || spawnPoints.Count == 0) return;
        var enemy = EnemyScene.Instantiate<EnemyView>();
        Marker3D point = spawnPoints[roll % spawnPoints.Count];
        AddChild(enemy);
        enemy.GlobalPosition = point.GlobalPosition;
        enemy.Init(entity, Player, Config.SinkSpeed, OnInRangeChanged);
        views[entity] = enemy;
    }

    private void OnInRangeChanged(uint entity, bool inRange)
    {
        Send(SbdCmd.Make(SbdCmdKind.EnemyInRange, entity, inRange ? 1 : 0));
    }

    private void OnShot(int damage)
    {
        if (Player == null) return;
        GodotObject collider = Player.Raycast(out Vector3 point);
        if (collider is EnemyView enemy)
        {
            Send(SbdCmd.Make(SbdCmdKind.Hit, enemy.Entity, damage, new SbdVec3(point.X, point.Y, point.Z)));
        }
    }

    private void OnState(uint state)
    {
        if (Player != null) Player.InputEnabled = state == SbdState.Playing;
        if (Interactive)
        {
            Input.MouseMode = state == SbdState.Playing ? Input.MouseModeEnum.Captured : Input.MouseModeEnum.Visible;
        }

        switch (state)
        {
            case SbdState.GameOver:
                HighScoreFlag = World.HighScore > highScoreAtRunStart;
                if (HighScoreFlag) SaveHighScore();
                SetCenter(HighScoreFlag ? "High Score!\n" + World.HighScore + "\n\nPress Enter to restart" : "Game Over!\n\nPress Enter to restart");
                break;
            case SbdState.Paused:
                SetCenter("Paused");
                break;
            case SbdState.Playing:
                SetCenter("");
                break;
            case SbdState.Restarting:
                foreach (EnemyView v in views.Values) if (IsInstanceValid(v)) v.QueueFree();
                views.Clear();
                EnemiesAlive = 0;
                HighScoreFlag = false;
                highScoreAtRunStart = World.HighScore;
                if (Player != null) Player.ResetPose();
                break;
        }
    }

    // ---- config & save ----

    private static SbdConfig LoadConfig()
    {
        const string path = "res://data/balance.json";
        if (!FileAccess.FileExists(path)) return SbdAbi.DefaultConfig();
        using FileAccess file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        return BalanceLoader.Parse(file.GetAsText());
    }

    private void LoadHighScore()
    {
        if (!FileAccess.FileExists(SavePath)) return;
        using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Read);
        int rc = World.SaveRead(file.GetBuffer((long)file.GetLength()));
        if (rc != 0) GD.PushWarning("sbd: ignoring unreadable save (" + rc + ")");
    }

    public void SaveHighScore()
    {
        using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Write);
        if (file == null)
        {
            GD.PushWarning("sbd: cannot write save: " + FileAccess.GetOpenError());
            return;
        }
        file.StoreBuffer(World.SaveWrite());
    }

    // ---- scene construction ----

    private void BuildSpawnPoints()
    {
        Vector3[] corners = { new Vector3(-16, 0, -16), new Vector3(16, 0, -16), new Vector3(16, 0, 16), new Vector3(-16, 0, 16) };
        foreach (Vector3 c in corners)
        {
            var marker = new Marker3D { Position = c };
            AddChild(marker);
            spawnPoints.Add(marker);
        }
    }

    private static void RegisterInput()
    {
        Bind("sbd_forward", Key.W);
        Bind("sbd_back", Key.S);
        Bind("sbd_left", Key.A);
        Bind("sbd_right", Key.D);
        Bind("sbd_pause", Key.Escape);
        Bind("sbd_restart", Key.Enter);
        if (!InputMap.HasAction("sbd_fire"))
        {
            InputMap.AddAction("sbd_fire");
            InputMap.ActionAddEvent("sbd_fire", new InputEventMouseButton { ButtonIndex = MouseButton.Left });
        }
    }

    private static void Bind(string action, Key key)
    {
        if (InputMap.HasAction(action)) return;
        InputMap.AddAction(action);
        InputMap.ActionAddEvent(action, new InputEventKey { PhysicalKeycode = key });
    }

    private void BuildArena()
    {
        AddChild(new DirectionalLight3D { RotationDegrees = new Vector3(-55, 30, 0) });
        AddChild(new WorldEnvironment
        {
            Environment = new Godot.Environment
            {
                BackgroundMode = Godot.Environment.BGMode.Color,
                BackgroundColor = new Color(0.08f, 0.1f, 0.14f),
                AmbientLightSource = Godot.Environment.AmbientSource.Color,
                AmbientLightColor = new Color(0.5f, 0.5f, 0.55f),
            },
        });

        var floor = new StaticBody3D { CollisionLayer = 1 };
        floor.AddChild(new MeshInstance3D
        {
            Mesh = new BoxMesh { Size = new Vector3(40, 0.2f, 40) },
            MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.25f, 0.28f, 0.25f) },
            Position = new Vector3(0, -0.1f, 0),
        });
        floor.AddChild(new CollisionShape3D { Shape = new BoxShape3D { Size = new Vector3(40, 0.2f, 40) }, Position = new Vector3(0, -0.1f, 0) });
        AddChild(floor);

        var navMesh = new NavigationMesh
        {
            Vertices = new[] { new Vector3(-20, 0, -20), new Vector3(20, 0, -20), new Vector3(20, 0, 20), new Vector3(-20, 0, 20) },
        };
        navMesh.AddPolygon(new[] { 0, 1, 2, 3 });
        AddChild(new NavigationRegion3D { NavigationMesh = navMesh });
    }

    private void BuildPlayer()
    {
        Player = new PlayerController { Name = "Player" };
        AddChild(Player);
    }

    private void BuildHud()
    {
        var layer = new CanvasLayer();
        AddChild(layer);

        var flash = new ColorRect { Color = new Color(1, 0, 0, 0), MouseFilter = Control.MouseFilterEnum.Ignore };
        flash.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        layer.AddChild(flash);
        effects.AttachFlash(flash);

        scoreLabel = new Label { Position = new Vector2(16, 12) };
        scoreLabel.AddThemeFontSizeOverride("font_size", 22);
        layer.AddChild(scoreLabel);

        centerLabel = new Label { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        centerLabel.AddThemeFontSizeOverride("font_size", 40);
        centerLabel.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        layer.AddChild(centerLabel);
    }

    private void UpdateHud()
    {
        scoreLabel.Text = "Score: " + World.Score + "    High Score: " + World.HighScore
                          + "\nHealth: " + World.PlayerHealth + "    Enemies: " + EnemiesAlive;
    }

    private void SetCenter(string text)
    {
        if (centerLabel != null) centerLabel.Text = text;
    }
}
