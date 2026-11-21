using System;
using System.Collections.Generic;
using Sbd.Native;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Jobs;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>
/// Owns the Zig core world. Views send commands (Send) and react to events; nothing else mutates game state.
/// Created automatically before the first scene loads and kept across scene reloads (the game's restart).
/// </summary>
[DefaultExecutionOrder(-100)]
public class GameHost : MonoBehaviour
{
    private static GameHost instance;

    public static GameHost Instance { get { return instance; } }

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void Bootstrap()
    {
        if (instance != null) return;
        GameObject go = new GameObject("GameHost");
        DontDestroyOnLoad(go);
        instance = go.AddComponent<GameHost>();
    }

    // Views register themselves in Awake.
    public PlayerHealth Player;
    public PlayerShooting Shooter;
    public EnemyManager Spawner;

    public readonly EntityViewRegistry Registry = new EntityViewRegistry();

    public SbdConfig Config { get; private set; }
    public int Score { get { return world.Score; } }
    public int HighScore { get { return world.HighScore; } }
    public int PlayerHealthValue { get { return world.PlayerHealth; } }
    public uint State { get { return world.State; } }
    public bool IsGameOver { get { return world.State == SbdState.GameOver; } }
    public int EnemiesAlive { get; private set; }

    /// <summary>True once this run beat the high score that was stored when the run started.</summary>
    public bool HighScoreFlag { get; private set; }

    private SbdWorld world;
    private readonly List<SbdCmd> pending = new List<SbdCmd>(32);
    private SbdCmd[] cmdBuffer = new SbdCmd[32];
    private readonly SbdEvent[] eventBuffer = new SbdEvent[128];
    private int highScoreAtRunStart;
    private bool firstSceneLoaded;

    private void Awake()
    {
        if (instance != null && instance != this)
        {
            Destroy(gameObject);
            return;
        }
        instance = this;

        TextAsset balance = Resources.Load<TextAsset>("balance");
        Config = balance != null ? BalanceLoader.Parse(balance.text) : SbdAbi.DefaultConfig();
        world = SbdWorld.Create(Config);
        UnitySaveStore.Load(world);
        highScoreAtRunStart = world.HighScore;

        SceneManager.sceneLoaded += OnSceneLoaded;
    }

    private void OnDestroy()
    {
        SceneManager.sceneLoaded -= OnSceneLoaded;
        if (instance == this)
        {
            if (world != null && !world.IsClosed)
            {
                UnitySaveStore.Save(world);
                world.Dispose();
            }
            instance = null;
        }
    }

    private void OnApplicationQuit()
    {
        if (world != null && !world.IsClosed) UnitySaveStore.Save(world);
    }

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        if (!firstSceneLoaded)
        {
            firstSceneLoaded = true;
            return;
        }

        // The scene was reloaded (restart): drop stale enemy views and restart the core run.
        // Scene views already re-registered themselves in Awake (which runs before this callback);
        // references to destroyed views compare equal to null, so they need no clearing.
        Registry.Clear();
        EnemiesAlive = 0;
        HighScoreFlag = false;
        highScoreAtRunStart = world.HighScore;
        Send(SbdCmd.Make(SbdCmdKind.Restart));
    }

    public void Send(SbdCmd cmd)
    {
        pending.Add(cmd);
    }

    public void TogglePause()
    {
        Send(SbdCmd.Make(SbdCmdKind.PauseToggle));
    }

    /// <summary>Persists the high score now (also happens on quit and when the host is destroyed).</summary>
    public void SaveNow()
    {
        if (world != null && !world.IsClosed) UnitySaveStore.Save(world);
    }

    private const int ParallelThreshold = 32;
    private const int ChunkSize = 16;

    /// <summary>One chunk of enemies per index; chunks are disjoint, which is what the core requires.</summary>
    private struct StepEnemiesJob : IJobParallelFor
    {
        [NativeDisableUnsafePtrRestriction] public IntPtr World;
        public uint Count;
        public float Dt;

        public void Execute(int index)
        {
            uint begin = (uint)(index * ChunkSize);
            SbdWorld.StepEnemies(World, begin, Math.Min(begin + ChunkSize, Count), Dt);
        }
    }

    private void StepEnemies(float dt)
    {
        uint count = world.EnemyCount;
        if (count < ParallelThreshold)
        {
            world.StepEnemies(0, count, dt);
            return;
        }

        StepEnemiesJob job = new StepEnemiesJob { World = world.DangerousGetHandle(), Count = count, Dt = dt };
        int chunks = (int)((count + ChunkSize - 1) / ChunkSize);
        job.Schedule(chunks, 1).Complete();
    }

    private void LateUpdate()
    {
        if (world == null || world.IsClosed) return;

        if (pending.Count > 0)
        {
            if (cmdBuffer.Length < pending.Count) cmdBuffer = new SbdCmd[pending.Count * 2];
            pending.CopyTo(cmdBuffer);
            world.Push(cmdBuffer, pending.Count);
            pending.Clear();
        }

        float dt = Time.deltaTime;
        world.Begin(dt);
        StepEnemies(dt);
        world.Resolve();

        int n;
        while ((n = world.Poll(eventBuffer)) > 0)
        {
            for (int i = 0; i < n; i++) Dispatch(ref eventBuffer[i]);
        }
    }

    private void Dispatch(ref SbdEvent e)
    {
        EnemyHealth view;
        switch (e.Kind)
        {
            case SbdEvKind.EnemySpawned:
                EnemiesAlive++;
                if (Spawner != null)
                {
                    EnemyHealth created = Spawner.SpawnView(e.Entity, e.Value);
                    if (created != null) Registry.Add(e.Entity, created);
                }
                break;

            case SbdEvKind.EnemyHurt:
                if (Registry.TryGet(e.Entity, out view)) view.OnHurt(e.Value, new Vector3(e.Pos.X, e.Pos.Y, e.Pos.Z));
                break;

            case SbdEvKind.EnemyDied:
                EnemiesAlive = Mathf.Max(0, EnemiesAlive - 1);
                if (Registry.TryGet(e.Entity, out view)) view.OnDied();
                break;

            case SbdEvKind.EnemyDespawn:
                if (Registry.TryGet(e.Entity, out view)) Destroy(view.gameObject);
                Registry.Remove(e.Entity);
                break;

            case SbdEvKind.PlayerHurt:
                if (Player != null) Player.OnHurt(e.Value);
                break;

            case SbdEvKind.PlayerDied:
                if (Player != null) Player.OnDied();
                break;

            case SbdEvKind.State:
                if (e.Value == (int)SbdState.GameOver)
                {
                    HighScoreFlag = world.HighScore > highScoreAtRunStart;
                    if (HighScoreFlag) SaveNow();
                }
                break;

            case SbdEvKind.Shot:
                if (Shooter != null) Shooter.OnShot(e.Value);
                break;
        }
    }
}
