using System;
using System.Collections.Generic;
using System.IO;
using Sbd.Native;
using Xunit;

namespace Sbd.Native.Tests
{
    public class WorldTests
    {
        private static SbdConfig Quiet()
        {
            SbdConfig c = SbdAbi.DefaultConfig();
            c.SpawnInterval = 1000f;
            return c;
        }

        private static List<SbdEvent> Drain(SbdWorld w)
        {
            List<SbdEvent> all = new List<SbdEvent>();
            SbdEvent[] buf = new SbdEvent[4];
            int n;
            while ((n = w.Poll(buf)) > 0)
                for (int i = 0; i < n; i++) all.Add(buf[i]);
            return all;
        }

        [Fact]
        public void LayoutAndVersionMatchHeader()
        {
            SbdAbi.AssertLayout();
            Assert.Equal(1, (int)SbdAbi.ExpectedVersion);
        }

        [Fact]
        public void ScriptedGame_KillSinkDespawnScore()
        {
            using (SbdWorld w = SbdWorld.Create(Quiet()))
            {
                w.Push(SbdCmd.Make(SbdCmdKind.SpawnRequest, 0, 0, new SbdVec3(1, 0, 2)));
                w.Tick(0.016f);
                List<SbdEvent> ev = Drain(w);
                Assert.Equal(SbdEvKind.EnemySpawned, ev[0].Kind);
                uint enemy = ev[0].Entity;

                SbdCmd[] hits = new SbdCmd[10];
                for (int i = 0; i < hits.Length; i++) hits[i] = SbdCmd.Make(SbdCmdKind.Hit, enemy, 10);
                Assert.Equal(10u, w.Push(hits, hits.Length));
                w.Tick(0.016f);
                for (int i = 0; i < 22; i++) w.Tick(0.1f);

                ev = Drain(w);
                List<uint> kinds = new List<uint>();
                foreach (SbdEvent e in ev) if (e.Kind != SbdEvKind.Effect) kinds.Add(e.Kind);
                int last = kinds.Count;
                Assert.Equal(SbdEvKind.EnemyDied, kinds[last - 4]);
                Assert.Equal(SbdEvKind.Score, kinds[last - 3]);
                Assert.Equal(SbdEvKind.EnemySink, kinds[last - 2]);
                Assert.Equal(SbdEvKind.EnemyDespawn, kinds[last - 1]);
                Assert.Equal(10, w.Score);
            }
        }

        [Fact]
        public void PlayerDeathLeadsToGameOver_HighScoreSurvivesSaveAndRestart()
        {
            using (SbdWorld w = SbdWorld.Create(Quiet()))
            {
                w.Push(SbdCmd.Make(SbdCmdKind.SpawnRequest));
                w.Push(SbdCmd.Make(SbdCmdKind.SpawnRequest));
                w.Tick(0.016f);
                List<SbdEvent> ev = Drain(w);
                uint a = ev[0].Entity;
                uint b = 0;
                foreach (SbdEvent e in ev) if (e.Kind == SbdEvKind.EnemySpawned && e.Entity != a) b = e.Entity;
                w.Push(SbdCmd.Make(SbdCmdKind.Hit, b, 100));
                w.Push(SbdCmd.Make(SbdCmdKind.EnemyInRange, a, 1));
                for (int i = 0; i < 200 && w.State != SbdState.GameOver; i++) w.Tick(0.1f);
                Assert.Equal(SbdState.GameOver, w.State);
                Assert.Equal(10, w.HighScore);

                byte[] save = w.SaveWrite();
                Assert.Equal(SbdAbi.SaveSize, save.Length);

                w.Push(SbdCmd.Make(SbdCmdKind.Restart));
                w.Tick(0.016f);
                Assert.Equal(SbdState.Playing, w.State);
                Assert.Equal(0, w.Score);
                Assert.Equal(10, w.HighScore);
                Assert.Equal(100, w.PlayerHealth);

                using (SbdWorld fresh = SbdWorld.Create(Quiet()))
                {
                    Assert.Equal(0, fresh.SaveRead(save));
                    Assert.Equal(10, fresh.HighScore);
                    Assert.Equal(SbdSaveErr.Truncated, fresh.SaveRead(new byte[3]));
                    save[0] ^= 0xff;
                    Assert.Equal(SbdSaveErr.BadMagic, fresh.SaveRead(save));
                }
            }
        }

        [Fact]
        public void SplitRangesEqualSingleTick()
        {
            Assert.Equal(Run(false), Run(true));
        }

        private static string Run(bool split)
        {
            SbdConfig c = SbdAbi.DefaultConfig();
            c.SpawnInterval = 0.4f;
            c.Seed = 99;
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            using (SbdWorld w = SbdWorld.Create(c))
            {
                for (int f = 0; f < 200; f++)
                {
                    if (f % 7 == 0)
                    {
                        // Events carry handles; ask the core for in-range on whatever spawned last time.
                    }
                    if (split)
                    {
                        w.Begin(0.05f);
                        uint n = w.EnemyCount;
                        w.StepEnemies(n / 2, n, 0.05f);
                        w.StepEnemies(0, n / 2, 0.05f);
                        w.Resolve();
                    }
                    else w.Tick(0.05f);
                    foreach (SbdEvent e in Drain(w)) sb.Append(e.Kind).Append(':').Append(e.Entity).Append(':').Append(e.Value).Append(';');
                }
            }
            Assert.True(sb.Length > 20);
            return sb.ToString();
        }

        [Fact]
        public void SpanPushAndPollMatchArrayOverloads()
        {
            using (SbdWorld w = SbdWorld.Create(Quiet()))
            {
                ReadOnlySpan<SbdCmd> spawns = stackalloc SbdCmd[]
                {
                    SbdCmd.Make(SbdCmdKind.SpawnRequest),
                    SbdCmd.Make(SbdCmdKind.SpawnRequest),
                };
                Assert.Equal(2u, w.Push(spawns));
                Assert.Equal(0u, w.Push(ReadOnlySpan<SbdCmd>.Empty));
                w.Tick(0.016f);
                Assert.Equal(2u, w.EnemyCount);

                Span<SbdEvent> one = stackalloc SbdEvent[1];
                int spawned = 0;
                while (w.Poll(one) == 1)
                    if (one[0].Kind == (uint)SbdEvKind.EnemySpawned) spawned++;
                Assert.Equal(2, spawned);
                Assert.Equal(0, w.Poll(Span<SbdEvent>.Empty));
            }
        }

        [Fact]
        public void ManagedSaveEncoderIsAcceptedByCore()
        {
            using (SbdWorld w = SbdWorld.Create(Quiet()))
            {
                Assert.Equal(0, w.SaveRead(SbdSave.Encode(1234)));
                Assert.Equal(1234, w.HighScore);
                Assert.Equal(SbdSaveErr.BadValue, w.SaveRead(SbdSave.Encode(-1)));
            }
        }

        [Fact]
        public void BalanceJsonLoadsIntoConfig()
        {
            SbdConfig c = BalanceLoader.Parse(File.ReadAllText("balance.json"));
            Assert.Equal(100u, c.EnemyStartHealth);
            Assert.Equal(100u, c.PlayerStartHealth);
            Assert.Equal(10u, c.EnemyScore);
            Assert.Equal(0.5f, c.EnemyAttackCooldown);
            Assert.Equal(3.0f, c.SpawnInterval);
            Assert.Equal(20u, c.WeaponDamage);
            Assert.Equal(0.15f, c.FireRate);
        }
    }
}
