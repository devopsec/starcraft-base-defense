using System;
using System.Runtime.InteropServices;
#if NET5_0_OR_GREATER
using FastAttribute = System.Runtime.InteropServices.SuppressGCTransitionAttribute;
#endif

namespace Sbd.Native
{
    internal static unsafe class NativeMethods
    {
        private const string Lib = "sbd_core";

        // [Fast] marks constant-time getters: on .NET 5+ they skip the GC transition.
        // Never put it on calls that do real work (tick, step, create, destroy, save).

        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_abi_version();
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_config_default(SbdConfig* outCfg);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr sbd_world_create(SbdConfig* cfg);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_world_destroy(IntPtr w);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_world_push(IntPtr w, SbdCmd* cmds, uint n);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_world_tick(IntPtr w, float dt);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_world_begin(IntPtr w, float dt);
        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_world_enemy_count(IntPtr w);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_world_step_enemies(IntPtr w, uint begin, uint end, float dt);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern void sbd_world_resolve(IntPtr w);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_world_poll(IntPtr w, SbdEvent* outEvents, uint cap);
        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern int sbd_world_score(IntPtr w);
        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern int sbd_world_high_score(IntPtr w);
        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern int sbd_world_player_health(IntPtr w);
        [Fast] [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_world_state(IntPtr w);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern uint sbd_save_write(IntPtr w, byte* buf, uint cap);
        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] public static extern int sbd_save_read(IntPtr w, byte* buf, uint len);
    }

#if !NET5_0_OR_GREATER
    [AttributeUsage(AttributeTargets.Method)]
    internal sealed class FastAttribute : Attribute { }
#endif

    public static class SbdAbi
    {
        public const uint ExpectedVersion = 1;
        public const int SaveSize = 12;

        /// <summary>Throws if the managed struct layout or native ABI version differ from sbd.h.</summary>
        public static void AssertLayout()
        {
            if (Marshal.SizeOf(typeof(SbdVec3)) != 12) throw new InvalidOperationException("SbdVec3 size");
            if (Marshal.SizeOf(typeof(SbdConfig)) != 48) throw new InvalidOperationException("SbdConfig size");
            if (Marshal.SizeOf(typeof(SbdCmd)) != 24) throw new InvalidOperationException("SbdCmd size");
            if (Marshal.SizeOf(typeof(SbdEvent)) != 28) throw new InvalidOperationException("SbdEvent size");
            uint v = NativeMethods.sbd_abi_version();
            if (v != ExpectedVersion) throw new InvalidOperationException("sbd_core ABI version " + v + " != " + ExpectedVersion);
        }

        public static unsafe SbdConfig DefaultConfig()
        {
            SbdConfig c;
            NativeMethods.sbd_config_default(&c);
            return c;
        }
    }
}
