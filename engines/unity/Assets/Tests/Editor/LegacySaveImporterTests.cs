using System.IO;
using System.Runtime.Serialization.Formatters.Binary;
using NUnit.Framework;
using UnityEngine;

public class LegacySaveImporterTests
{
    private static byte[] LegacyBytes(int highScore)
    {
        using (MemoryStream ms = new MemoryStream())
        {
            new BinaryFormatter().Serialize(ms, new SaveGameObject { high_score = highScore });
            return ms.ToArray();
        }
    }

    [Test]
    public void ReadsHighScoreFromBinaryFormatterStream()
    {
        using (MemoryStream ms = new MemoryStream(LegacyBytes(777)))
            Assert.AreEqual(777, LegacySaveImporter.ReadHighScore(ms));
    }

    [Test]
    public void CorruptOrEmptyStreamYieldsZero()
    {
        using (MemoryStream ms = new MemoryStream(new byte[] { 1, 2, 3, 4, 5 }))
            Assert.AreEqual(0, LegacySaveImporter.ReadHighScore(ms));
        using (MemoryStream ms = new MemoryStream(new byte[0]))
            Assert.AreEqual(0, LegacySaveImporter.ReadHighScore(ms));
    }

    [Test]
    public void MissingFileIsNotImported()
    {
        string dir = Path.Combine(Path.GetTempPath(), "sbd_legacy_" + System.Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            int hs;
            Assert.IsFalse(LegacySaveImporter.TryImport(dir, out hs));
            Assert.AreEqual(0, hs);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Test]
    public void ImportReadsOnceAndRenamesTheFile()
    {
        string dir = Path.Combine(Path.GetTempPath(), "sbd_legacy_" + System.Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllBytes(Path.Combine(dir, LegacySaveImporter.LegacyFileName), LegacyBytes(420));
            int hs;
            Assert.IsTrue(LegacySaveImporter.TryImport(dir, out hs));
            Assert.AreEqual(420, hs);
            Assert.IsFalse(File.Exists(Path.Combine(dir, LegacySaveImporter.LegacyFileName)));
            Assert.IsTrue(File.Exists(Path.Combine(dir, LegacySaveImporter.LegacyFileName + ".migrated")));
            Assert.IsFalse(LegacySaveImporter.TryImport(dir, out hs));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Test]
    public void UnityBalanceCopyMatchesSharedBalanceFile()
    {
        string shared = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../data/balance.json"));
        string copy = Path.Combine(Application.dataPath, "Resources/balance.json");
        Assert.IsTrue(File.Exists(shared), shared);
        Assert.AreEqual(File.ReadAllText(shared), File.ReadAllText(copy), "run tools/sync-unity-core.sh");
    }
}
