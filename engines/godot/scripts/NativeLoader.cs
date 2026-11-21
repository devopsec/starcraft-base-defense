using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Godot;
using Sbd.Native;

namespace StarcraftBaseDefense;

/// <summary>Resolves the "sbd_core" native library for Sbd.Native from res://native or next to the executable.</summary>
public static class NativeLoader
{
    private static bool installed;

    public static void Install()
    {
        if (installed) return;
        installed = true;
        NativeLibrary.SetDllImportResolver(typeof(SbdWorld).Assembly, Resolve);
    }

    private static IntPtr Resolve(string name, Assembly assembly, DllImportSearchPath? path)
    {
        if (name != "sbd_core") return IntPtr.Zero;
        string file = OperatingSystem.IsWindows() ? "sbd_core.dll" : "libsbd_core.so";
        string[] dirs =
        {
            ProjectSettings.GlobalizePath("res://native"),
            AppContext.BaseDirectory,
            Path.GetDirectoryName(OS.GetExecutablePath()) ?? "",
        };
        foreach (string dir in dirs)
        {
            string full = Path.Combine(dir, file);
            if (File.Exists(full) && NativeLibrary.TryLoad(full, out IntPtr handle)) return handle;
        }
        return IntPtr.Zero;
    }
}
