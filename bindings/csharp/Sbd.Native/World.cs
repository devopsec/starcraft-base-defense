using System;
using Microsoft.Win32.SafeHandles;

namespace Sbd.Native
{
    /// <summary>Owning wrapper around an sbd_world*. Not thread-safe, except StepEnemies on disjoint ranges.</summary>
    public sealed unsafe class SbdWorld : SafeHandleZeroOrMinusOneIsInvalid
    {
        private SbdWorld() : base(true)
        {
        }

        public static SbdWorld Create(SbdConfig config)
        {
            SbdAbi.AssertLayout();
            IntPtr p = NativeMethods.sbd_world_create(&config);
            if (p == IntPtr.Zero) throw new OutOfMemoryException("sbd_world_create failed");
            SbdWorld w = new SbdWorld();
            w.SetHandle(p);
            return w;
        }

        protected override bool ReleaseHandle()
        {
            NativeMethods.sbd_world_destroy(handle);
            return true;
        }

        public uint Push(SbdCmd[] cmds, int count)
        {
            if (count <= 0) return 0;
            if (count > cmds.Length) throw new ArgumentOutOfRangeException("count");
            fixed (SbdCmd* p = cmds) return NativeMethods.sbd_world_push(handle, p, (uint)count);
        }

        public uint Push(SbdCmd cmd)
        {
            return NativeMethods.sbd_world_push(handle, &cmd, 1);
        }

        public uint Push(ReadOnlySpan<SbdCmd> cmds)
        {
            if (cmds.IsEmpty) return 0;
            fixed (SbdCmd* p = cmds) return NativeMethods.sbd_world_push(handle, p, (uint)cmds.Length);
        }

        public void Tick(float dt) { NativeMethods.sbd_world_tick(handle, dt); }
        public void Begin(float dt) { NativeMethods.sbd_world_begin(handle, dt); }
        public uint EnemyCount { get { return NativeMethods.sbd_world_enemy_count(handle); } }
        public void StepEnemies(uint begin, uint end, float dt) { NativeMethods.sbd_world_step_enemies(handle, begin, end, dt); }
        /// <summary>Raw-pointer variant for job systems that cannot capture managed objects (Unity Jobs).
        /// Pass DangerousGetHandle(); the world must stay alive until the jobs complete.</summary>
        public static void StepEnemies(IntPtr world, uint begin, uint end, float dt) { NativeMethods.sbd_world_step_enemies(world, begin, end, dt); }
        public void Resolve() { NativeMethods.sbd_world_resolve(handle); }

        /// <summary>Drains up to buffer.Length events; returns how many were written.</summary>
        public int Poll(SbdEvent[] buffer)
        {
            fixed (SbdEvent* p = buffer) return (int)NativeMethods.sbd_world_poll(handle, p, (uint)buffer.Length);
        }

        /// <summary>Drains up to buffer.Length events without requiring a heap array (stackalloc friendly).</summary>
        public int Poll(Span<SbdEvent> buffer)
        {
            if (buffer.IsEmpty) return 0;
            fixed (SbdEvent* p = buffer) return (int)NativeMethods.sbd_world_poll(handle, p, (uint)buffer.Length);
        }

        public int Score { get { return NativeMethods.sbd_world_score(handle); } }
        public int HighScore { get { return NativeMethods.sbd_world_high_score(handle); } }
        public int PlayerHealth { get { return NativeMethods.sbd_world_player_health(handle); } }
        public uint State { get { return NativeMethods.sbd_world_state(handle); } }

        public byte[] SaveWrite()
        {
            byte[] buf = new byte[SbdAbi.SaveSize];
            fixed (byte* p = buf)
            {
                uint n = NativeMethods.sbd_save_write(handle, p, (uint)buf.Length);
                if (n != buf.Length) throw new InvalidOperationException("sbd_save_write failed");
            }
            return buf;
        }

        /// <summary>Returns 0 on success or a negative SbdSaveErr code.</summary>
        public int SaveRead(byte[] data)
        {
            if (data == null || data.Length == 0) return SbdSaveErr.Truncated;
            fixed (byte* p = data) return NativeMethods.sbd_save_read(handle, p, (uint)data.Length);
        }
    }

    /// <summary>Managed encoder for SaveV1 (little-endian u32 magic "SBDS", u32 version, i32 high score).
    /// Used to import legacy saves; the core remains the authority and validates it on read.</summary>
    public static class SbdSave
    {
        public static byte[] Encode(int highScore)
        {
            byte[] b = new byte[SbdAbi.SaveSize];
            WriteU32(b, 0, 0x53444253u);
            WriteU32(b, 4, 1u);
            WriteU32(b, 8, unchecked((uint)highScore));
            return b;
        }

        private static void WriteU32(byte[] b, int o, uint v)
        {
            b[o] = (byte)v;
            b[o + 1] = (byte)(v >> 8);
            b[o + 2] = (byte)(v >> 16);
            b[o + 3] = (byte)(v >> 24);
        }
    }
}
