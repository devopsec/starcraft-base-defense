//! data/balance.json -> core Config. The repo copy is embedded at build time; `--balance <path>` overrides it.
const std = @import("std");
const core = @import("sbd_core");

pub const embedded = @embedFile("balance.json");

pub const Balance = struct {
    config: core.types.Config,
    weapon_range: f32,
};

const Json = struct {
    version: u32,
    enemy: struct {
        start_health: u32,
        score_value: u32,
        sink_speed: f32,
        sink_duration: f32,
        attack_damage: u32,
        attack_cooldown: f32,
    },
    spawner: struct { spawn_interval: f32, max_alive: u32 },
    player: struct { start_health: u32 },
    weapon: struct { damage_per_shot: u32, fire_rate: f32, range: f32 },
    seed: u32,
};

pub fn parse(gpa: std.mem.Allocator, text: []const u8) !Balance {
    const parsed = try std.json.parseFromSlice(Json, gpa, text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const j = parsed.value;
    if (j.version != 1) return error.UnsupportedBalanceVersion;
    return .{
        .config = .{
            .enemy_start_health = j.enemy.start_health,
            .enemy_score = j.enemy.score_value,
            .player_start_health = j.player.start_health,
            .enemy_attack_damage = j.enemy.attack_damage,
            .enemy_attack_cooldown = j.enemy.attack_cooldown,
            .spawn_interval = j.spawner.spawn_interval,
            .sink_speed = j.enemy.sink_speed,
            .sink_duration = j.enemy.sink_duration,
            .fire_rate = j.weapon.fire_rate,
            .weapon_damage = j.weapon.damage_per_shot,
            .seed = j.seed,
            .max_enemies = j.spawner.max_alive,
        },
        .weapon_range = j.weapon.range,
    };
}

test "embedded balance.json matches the core defaults" {
    const b = try parse(std.testing.allocator, embedded);
    try std.testing.expectEqual(core.types.Config.default, b.config);
    try std.testing.expectEqual(@as(f32, 100), b.weapon_range);
}

test "unknown version is rejected" {
    const text =
        \\{"version":2,"enemy":{"start_health":1,"score_value":1,"sink_speed":1,"sink_duration":1,"attack_damage":1,"attack_cooldown":1},
        \\"spawner":{"spawn_interval":1,"max_alive":1},"player":{"start_health":1},
        \\"weapon":{"damage_per_shot":1,"fire_rate":1,"range":1},"seed":1}
    ;
    try std.testing.expectError(error.UnsupportedBalanceVersion, parse(std.testing.allocator, text));
}
