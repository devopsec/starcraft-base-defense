using System;
using System.IO;
using Sbd.Native;
using UnityEngine;

/// <summary>Reads and writes the core's versioned save bytes under Application.persistentDataPath.</summary>
public static class UnitySaveStore
{
    public const string FileName = "save_v1.bin";

    public static string Directory { get { return Application.persistentDataPath; } }
    private static string FilePath { get { return Path.Combine(Directory, FileName); } }

    /// <summary>Loads the high score into the world; migrates the legacy save.bin once if needed.</summary>
    public static void Load(SbdWorld world)
    {
        string path = FilePath;
        if (File.Exists(path))
        {
            try
            {
                int rc = world.SaveRead(File.ReadAllBytes(path));
                if (rc != 0) Debug.LogWarning("SbdCore: ignoring unreadable save (" + rc + ")");
                return;
            }
            catch (Exception e)
            {
                Debug.LogWarning("SbdCore: could not read save: " + e.Message);
                return;
            }
        }

        int legacy;
        if (LegacySaveImporter.TryImport(Directory, out legacy) && legacy > 0)
        {
            byte[] bytes = SbdSave.Encode(legacy);
            world.SaveRead(bytes);
            Write(bytes);
        }
    }

    public static void Save(SbdWorld world)
    {
        Write(world.SaveWrite());
    }

    private static void Write(byte[] bytes)
    {
        try
        {
            if (!System.IO.Directory.Exists(Directory)) System.IO.Directory.CreateDirectory(Directory);
            string tmp = FilePath + ".tmp";
            File.WriteAllBytes(tmp, bytes);
            if (File.Exists(FilePath)) File.Delete(FilePath);
            File.Move(tmp, FilePath);
        }
        catch (Exception e)
        {
            Debug.LogWarning("SbdCore: could not write save: " + e.Message);
        }
    }
}
