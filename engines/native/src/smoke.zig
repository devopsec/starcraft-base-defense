//! Headless scripted game (no window, GPU or XR): the native counterpart of the Godot smoke scene.
//! spawn -> kill -> sink/despawn -> pause -> restart -> save round-trip -> 40 enemies on the job system ->
//! shoot two -> die -> new high score -> restart. Progress and the verdict go to stdout, failures to stderr.
const std = @import("std");
const core = @import("sbd_core");
const game_mod = @import("game.zig");
const balance = @import("balance.zig");

const T = core.types;
const Game = game_mod.Game;
const cmd = game_mod.cmd;
const dt: f32 = 1.0 / 60.0;

var out_io: std.Io = undefined;

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "native smoke: " ++ fmt ++ "\n", args) catch return;
    std.Io.File.stdout().writeStreamingAll(out_io, line) catch {};
}

pub fn run(gpa: std.mem.Allocator, io: std.Io, bal: balance.Balance) !void {
    out_io = io;
    var g = try Game.init(gpa, bal.config, bal.weapon_range, io);
    defer g.deinit();

    // 1. spawn one enemy and kill it with direct hits (as the engine would after a raycast)
    g.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    try until(&g, 60, struct {
        fn f(x: *Game) bool {
            return x.enemies.items.len == 1;
        }
    }.f, "enemy spawned");
    const enemy = g.enemies.items[0].entity;
    for (0..5) |_| g.send(cmd(T.CmdKind.hit, enemy, 20, .{}));
    try until(&g, 10, struct {
        fn f(x: *Game) bool {
            return x.score() == 10;
        }
    }.f, "enemy killed, score=10");

    // 2. it sinks and despawns after sink_duration
    try until(&g, 60 * 5, struct {
        fn f(x: *Game) bool {
            return x.enemies.items.len == 0;
        }
    }.f, "enemy despawned after sinking");

    // 3. pause freezes the world, unpause resumes
    g.frame(dt, .{ .pause = true });
    try expect(g.state() == T.State.paused, "paused");
    g.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    for (0..30) |_| g.frame(dt, .{});
    try expect(g.enemies.items.len == 0, "no spawns while paused");
    g.frame(dt, .{ .pause = true });
    try expect(g.state() == T.State.playing, "resumed");

    // 4. restart keeps the high score; the save round-trips through a fresh world
    g.send(cmd(T.CmdKind.restart, 0, 0, .{}));
    g.frame(dt, .{});
    try expect(g.score() == 0 and g.highScore() == 10, "restart: score 0, high score 10");
    var buf: [64]u8 = undefined;
    const n = g.writeSave(&buf);
    {
        var fresh = try Game.init(gpa, bal.config, bal.weapon_range, null);
        defer fresh.deinit();
        try expect(fresh.loadSave(buf[0..n]) == 0 and fresh.highScore() == 10, "save round-trip");
        try expect(fresh.loadSave(buf[0 .. n - 1]) < 0, "truncated save rejected");
    }

    // 5. a crowd: enemy ranges run on the std.Io job system; shoot two through the hitscan path, then die
    for (0..40) |_| g.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    var frames: u32 = 0;
    while (g.score() < 20 and frames < 60 * 30) : (frames += 1) {
        if (nearestLiving(&g)) |target| g.aimAt(target);
        g.frame(dt, .{ .fire = true });
    }
    try expect(g.score() >= 20, "shot two enemies with the hitscan weapon");
    try expect(g.stats.parallel_frames > 0, "parallel enemy stepping used");
    say("{d} shots, {d} hits, {d} parallel frames", .{ g.stats.shots, g.stats.hits, g.stats.parallel_frames });
    try until(&g, 60 * 60, struct {
        fn f(x: *Game) bool {
            return x.state() == T.State.game_over;
        }
    }.f, "player died, game over");
    try expect(g.new_high_score and g.save_dirty and g.highScore() >= 20, "new high score flagged for saving");

    // 6. restart from game over through the input path
    g.frame(dt, .{ .restart = true });
    try expect(g.state() == T.State.playing and g.score() == 0 and g.enemies.items.len == 0, "restarted");
}

fn nearestLiving(g: *Game) ?game_mod.V3 {
    var best: ?game_mod.V3 = null;
    var best_d: f32 = std.math.inf(f32);
    for (g.enemies.items) |v| {
        if (v.sinking) continue;
        const d = v.pos - g.player.pos;
        const dd = @reduce(.Add, d * d);
        if (dd < best_d) {
            best_d = dd;
            best = v.pos + game_mod.V3{ 0, game_mod.enemy_center_y, 0 };
        }
    }
    return best;
}

fn until(g: *Game, max_frames: u32, comptime cond: fn (*Game) bool, what: []const u8) !void {
    var i: u32 = 0;
    while (i < max_frames) : (i += 1) {
        g.frame(dt, .{});
        if (cond(g)) {
            say("{s}", .{what});
            return;
        }
    }
    std.debug.print("NATIVE SMOKE FAIL: timed out waiting for: {s}\n", .{what});
    return error.SmokeFailed;
}

fn expect(ok: bool, what: []const u8) !void {
    if (!ok) {
        std.debug.print("NATIVE SMOKE FAIL: {s}\n", .{what});
        return error.SmokeFailed;
    }
    say("{s}", .{what});
}
