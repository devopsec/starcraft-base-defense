using System.Runtime.InteropServices;

namespace Sbd.Native
{
    // Blittable mirrors of core/include/sbd.h. Sizes are asserted in SbdAbi.AssertLayout().
    public static class SbdCmdKind
    {
        public const uint SpawnRequest = 0, Hit = 1, EnemyInRange = 2, Fire = 3, PauseToggle = 4, Restart = 5;
    }

    public static class SbdEvKind
    {
        public const uint EnemySpawned = 0, EnemyHurt = 1, EnemyDied = 2, EnemySink = 3, EnemyDespawn = 4,
            PlayerHurt = 5, PlayerDied = 6, Score = 7, State = 8, Effect = 9, Shot = 10;
    }

    public static class SbdState
    {
        public const uint Playing = 0, Paused = 1, GameOver = 2, Restarting = 3;
    }

    public static class SbdFx
    {
        public const uint Hit = 1, Death = 2, DeathSink = 3, PlayerHurt = 4, Muzzle = 5, Spawn = 6;
    }

    public static class SbdSaveErr
    {
        public const int Truncated = -1, BadMagic = -2, BadVersion = -3, BadValue = -4;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SbdVec3
    {
        public float X, Y, Z;

        public SbdVec3(float x, float y, float z)
        {
            X = x;
            Y = y;
            Z = z;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SbdConfig
    {
        public uint EnemyStartHealth;
        public uint EnemyScore;
        public uint PlayerStartHealth;
        public uint EnemyAttackDamage;
        public float EnemyAttackCooldown;
        public float SpawnInterval;
        public float SinkSpeed;
        public float SinkDuration;
        public float FireRate;
        public uint WeaponDamage;
        public uint Seed;
        public uint MaxEnemies;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SbdCmd
    {
        public uint Kind;
        public uint Target;
        public int Amount;
        public SbdVec3 Point;

        public static SbdCmd Make(uint kind, uint target = 0, int amount = 0, SbdVec3 point = default(SbdVec3))
        {
            return new SbdCmd { Kind = kind, Target = target, Amount = amount, Point = point };
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SbdEvent
    {
        public uint Kind;
        public uint Entity;
        public int Value;
        public uint EffectId;
        public SbdVec3 Pos;
    }
}
