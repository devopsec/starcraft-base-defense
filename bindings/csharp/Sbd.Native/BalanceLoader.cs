using System;
using System.Collections.Generic;
using System.Globalization;

namespace Sbd.Native
{
    /// <summary>Reads data/balance.json (nested objects of numbers) into an SbdConfig. No external JSON dependency.</summary>
    public static class BalanceLoader
    {
        public static SbdConfig Parse(string json)
        {
            Dictionary<string, double> v = Flatten(json);
            SbdConfig c = SbdAbi.DefaultConfig();
            c.EnemyStartHealth = U(v, "enemy.start_health", c.EnemyStartHealth);
            c.EnemyScore = U(v, "enemy.score_value", c.EnemyScore);
            c.SinkSpeed = F(v, "enemy.sink_speed", c.SinkSpeed);
            c.SinkDuration = F(v, "enemy.sink_duration", c.SinkDuration);
            c.EnemyAttackDamage = U(v, "enemy.attack_damage", c.EnemyAttackDamage);
            c.EnemyAttackCooldown = F(v, "enemy.attack_cooldown", c.EnemyAttackCooldown);
            c.SpawnInterval = F(v, "spawner.spawn_interval", c.SpawnInterval);
            c.MaxEnemies = U(v, "spawner.max_alive", c.MaxEnemies);
            c.PlayerStartHealth = U(v, "player.start_health", c.PlayerStartHealth);
            c.WeaponDamage = U(v, "weapon.damage_per_shot", c.WeaponDamage);
            c.FireRate = F(v, "weapon.fire_rate", c.FireRate);
            c.Seed = U(v, "seed", c.Seed);
            return c;
        }

        private static uint U(Dictionary<string, double> v, string k, uint d)
        {
            double x;
            return v.TryGetValue(k, out x) && x >= 0 ? (uint)x : d;
        }

        private static float F(Dictionary<string, double> v, string k, float d)
        {
            double x;
            return v.TryGetValue(k, out x) ? (float)x : d;
        }

        /// <summary>Flattens {"a":{"b":1}} into "a.b" = 1. Non-numeric values are skipped.</summary>
        public static Dictionary<string, double> Flatten(string json)
        {
            Dictionary<string, double> result = new Dictionary<string, double>();
            List<string> path = new List<string>();
            int i = 0;
            string pendingKey = null;
            while (i < json.Length)
            {
                char ch = json[i];
                if (ch == '"')
                {
                    int end = json.IndexOf('"', i + 1);
                    if (end < 0) throw new FormatException("unterminated string");
                    string s = json.Substring(i + 1, end - i - 1);
                    i = end + 1;
                    int j = i;
                    while (j < json.Length && char.IsWhiteSpace(json[j])) j++;
                    if (j < json.Length && json[j] == ':') pendingKey = s;
                }
                else if (ch == '{')
                {
                    path.Add(pendingKey ?? "");
                    pendingKey = null;
                    i++;
                }
                else if (ch == '}')
                {
                    if (path.Count > 0) path.RemoveAt(path.Count - 1);
                    i++;
                }
                else if (ch == '-' || (ch >= '0' && ch <= '9'))
                {
                    int j = i;
                    while (j < json.Length && "+-.eE0123456789".IndexOf(json[j]) >= 0) j++;
                    double d;
                    if (pendingKey != null && double.TryParse(json.Substring(i, j - i), NumberStyles.Float, CultureInfo.InvariantCulture, out d))
                        result[Join(path, pendingKey)] = d;
                    pendingKey = null;
                    i = j;
                }
                else i++;
            }
            return result;
        }

        private static string Join(List<string> path, string key)
        {
            string p = "";
            foreach (string s in path) if (s.Length > 0) p += s + ".";
            return p + key;
        }
    }
}
