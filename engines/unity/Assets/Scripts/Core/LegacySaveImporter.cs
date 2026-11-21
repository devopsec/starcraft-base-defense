using System;
using System.IO;
using System.Runtime.Serialization.Formatters.Binary;

/// <summary>
/// Shape of the pre-core save file. Must keep the exact type name and field so BinaryFormatter
/// can still read old "save.bin" files (assembly name Assembly-CSharp is unchanged).
/// </summary>
[Serializable]
public class SaveGameObject
{
    public int high_score;
}

/// <summary>One-time import of the old BinaryFormatter save. Only used under Unity's Mono runtime.</summary>
public static class LegacySaveImporter
{
    public const string LegacyFileName = "save.bin";

    /// <summary>Returns the legacy high score, or 0 if the stream is empty, corrupt or negative.</summary>
    public static int ReadHighScore(Stream stream)
    {
        try
        {
            BinaryFormatter bf = new BinaryFormatter();
            SaveGameObject save = bf.Deserialize(stream) as SaveGameObject;
            return save != null && save.high_score > 0 ? save.high_score : 0;
        }
        catch (Exception)
        {
            return 0;
        }
    }

    /// <summary>Reads &lt;dir&gt;/save.bin if present. On success the file is renamed to save.bin.migrated.</summary>
    public static bool TryImport(string directory, out int highScore)
    {
        highScore = 0;
        string path = Path.Combine(directory, LegacyFileName);
        if (!File.Exists(path)) return false;
        try
        {
            using (FileStream fs = File.OpenRead(path)) highScore = ReadHighScore(fs);
            string migrated = path + ".migrated";
            if (File.Exists(migrated)) File.Delete(migrated);
            File.Move(path, migrated);
            return true;
        }
        catch (Exception)
        {
            highScore = 0;
            return false;
        }
    }
}
