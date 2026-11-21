//! The simulation world. Frame flow: push -> begin -> step_enemies(ranges) -> resolve -> poll.
//! `tick` = begin + step over all enemies + resolve. The core never spawns threads.
const std = @import("std");
const types = @import("types.zig");
const ev = @import("events.zig");
const enemies_mod = @import("enemies.zig");
const Score = @import("score.zig").Score;
const GameState = @import("game_state.zig").GameState;
const Player = @import("player.zig").Player;
const Weapon = @import("weapon.zig").Weapon;
const Spawner = @import("spawner.zig").Spawner;
const save = @import("save.zig");

const Vec3 = types.Vec3;
const Entity = types.Entity;

pub const cmd_capacity = 1024;
pub const event_capacity = 8192;
pub const max_dt: f32 = 0.25;

pub const World = struct {
    alloc: std.mem.Allocator,
    cfg: types.Config,
    enemies: enemies_mod.Enemies,
    cmds: ev.CmdQueue,
    events: ev.EventQueue,
    score: Score = .{},
    state: GameState = .{},
    player: Player,
    weapon: Weapon,
    spawner: Spawner,
    dt: f32 = 0,

    pub fn create(alloc: std.mem.Allocator, config: types.Config) !*World {
        var cfg = config;
        if (cfg.max_enemies == 0) cfg.max_enemies = types.Config.default.max_enemies;
        cfg.max_enemies = @min(cfg.max_enemies, 0xffff);
        const self = try alloc.create(World);
        errdefer alloc.destroy(self);
        var en = try enemies_mod.Enemies.init(alloc, cfg.max_enemies);
        errdefer en.deinit();
        var cq = try ev.CmdQueue.init(alloc, cmd_capacity);
        errdefer cq.deinit(alloc);
        const eq = try ev.EventQueue.init(alloc, event_capacity);
        self.* = .{
            .alloc = alloc,
            .cfg = cfg,
            .enemies = en,
            .cmds = cq,
            .events = eq,
            .player = Player.init(cfg.player_start_health),
            .weapon = Weapon.init(cfg.fire_rate),
            .spawner = Spawner.init(cfg.spawn_interval, cfg.seed),
        };
        return self;
    }

    pub fn destroy(self: *World) void {
        const alloc = self.alloc;
        self.enemies.deinit();
        self.cmds.deinit(alloc);
        self.events.deinit(alloc);
        alloc.destroy(self);
    }

    // ---- public frame API ----

    /// Returns how many commands were accepted.
    pub fn push(self: *World, cmds: []const types.Cmd) u32 {
        var n: u32 = 0;
        for (cmds) |c| {
            if (!self.cmds.push(c)) break;
            n += 1;
        }
        return n;
    }

    pub fn tick(self: *World, dt: f32) void {
        self.begin(dt);
        self.stepEnemies(0, self.enemies.high_water, self.dt);
        self.resolve();
    }

    /// Serial: sanitizes dt and applies queued commands.
    pub fn begin(self: *World, dt: f32) void {
        self.dt = sanitizeDt(dt);
        var buf: [64]types.Cmd = undefined;
        while (true) {
            const n = self.cmds.pop(&buf);
            if (n == 0) break;
            for (buf[0..n]) |c| self.apply(c);
        }
        if (!self.state.isPlaying()) self.dt = 0;
    }

    /// Parallel-safe over disjoint ranges; uses the dt chosen by `begin` unless overridden.
    pub fn stepEnemies(self: *World, begin_idx: u32, end_idx: u32, dt: f32) void {
        if (!self.state.isPlaying()) return;
        self.enemies.stepRange(begin_idx, end_idx, sanitizeDt(dt), self.cfg.enemy_attack_cooldown, self.cfg.sink_duration);
    }

    /// Serial: converts per-enemy results into events, advances weapon and spawner.
    pub fn resolve(self: *World) void {
        if (!self.state.isPlaying()) return;
        self.weapon.advance(self.dt);
        const en = &self.enemies;
        var i: u32 = 0;
        while (i < en.high_water) : (i += 1) {
            const f = en.flags[i];
            if (f == 0) continue;
            en.flags[i] = 0;
            if (f & enemies_mod.Flag.attack != 0 and self.player.isAlive()) self.hurtPlayer();
            if (f & enemies_mod.Flag.despawn != 0) {
                self.emit(types.EvKind.enemy_despawn, en.handle(i), 0, 0, .{});
                en.release(i);
            }
        }
        if (self.state.isPlaying() and self.dt > 0 and self.spawner.advance(self.dt)) {
            self.spawnEnemy(.{});
        }
    }

    pub fn poll(self: *World, out: []types.Event) u32 {
        return @intCast(self.events.pop(out));
    }

    // ---- save ----

    pub fn saveWrite(self: *const World, buf: []u8) u32 {
        return save.write(self.score.high_score, buf);
    }

    pub fn saveRead(self: *World, buf: []const u8) i32 {
        const r = save.read(buf);
        if (r < 0) return r;
        self.score.high_score = r;
        return 0;
    }

    // ---- internals ----

    fn sanitizeDt(dt: f32) f32 {
        if (!std.math.isFinite(dt) or dt <= 0) return 0;
        return @min(dt, max_dt);
    }

    fn emit(self: *World, kind: u32, entity: Entity, value: i32, effect_id: u32, pos: Vec3) void {
        _ = self.events.push(.{ .kind = kind, .entity = entity, .value = value, .effect_id = effect_id, .pos = pos });
    }

    fn apply(self: *World, c: types.Cmd) void {
        switch (c.kind) {
            types.CmdKind.pause_toggle => {
                if (self.state.togglePause()) |s| self.emit(types.EvKind.state, 0, @intCast(s), 0, .{});
            },
            types.CmdKind.restart => self.restart(),
            else => {
                if (!self.state.isPlaying()) return;
                switch (c.kind) {
                    types.CmdKind.spawn_request => self.spawnEnemy(c.point),
                    types.CmdKind.hit => self.hit(c),
                    types.CmdKind.enemy_in_range => {
                        if (self.enemies.lookup(c.target)) |i| {
                            if (self.enemies.phase[i] == enemies_mod.Phase.alive)
                                self.enemies.in_range[i] = @intFromBool(c.amount != 0);
                        }
                    },
                    types.CmdKind.fire => {
                        if (self.weapon.tryFire()) {
                            self.emit(types.EvKind.shot, 0, @intCast(self.cfg.weapon_damage), 0, c.point);
                            self.emit(types.EvKind.effect, 0, 0, types.Fx.muzzle, c.point);
                        }
                    },
                    else => {},
                }
            },
        }
    }

    fn spawnEnemy(self: *World, pos: Vec3) void {
        if (!self.player.isAlive()) return;
        const e = self.enemies.spawn(self.cfg.enemy_start_health) orelse return;
        const roll: i32 = @intCast(self.spawner.next() & 0x7fffffff);
        self.emit(types.EvKind.enemy_spawned, e, roll, 0, pos);
        self.emit(types.EvKind.effect, e, 0, types.Fx.spawn, pos);
    }

    fn hit(self: *World, c: types.Cmd) void {
        const en = &self.enemies;
        const i = en.lookup(c.target) orelse return;
        if (en.phase[i] != enemies_mod.Phase.alive) return;
        const dmg: i32 = if (c.amount > 0) c.amount else @intCast(@min(self.cfg.weapon_damage, std.math.maxInt(i32)));
        en.health[i] -|= dmg;
        self.emit(types.EvKind.enemy_hurt, c.target, dmg, 0, c.point);
        self.emit(types.EvKind.effect, c.target, dmg, types.Fx.hit, c.point);
        if (en.health[i] > 0) return;

        en.phase[i] = enemies_mod.Phase.sinking;
        en.sink_time[i] = 0;
        en.in_range[i] = 0;
        en.live -= 1;
        const pts: i32 = @intCast(@min(self.cfg.enemy_score, std.math.maxInt(i32)));
        self.score.add(pts);
        self.emit(types.EvKind.enemy_died, c.target, pts, 0, c.point);
        self.emit(types.EvKind.effect, c.target, 0, types.Fx.death, c.point);
        self.emit(types.EvKind.score, 0, self.score.score, 0, .{});
        self.emit(types.EvKind.enemy_sink, c.target, 0, 0, .{});
        self.emit(types.EvKind.effect, c.target, 0, types.Fx.death_sink, c.point);
    }

    fn hurtPlayer(self: *World) void {
        const left = self.player.damage(self.cfg.enemy_attack_damage);
        self.emit(types.EvKind.player_hurt, 0, left, 0, .{});
        self.emit(types.EvKind.effect, 0, left, types.Fx.player_hurt, .{});
        if (left > 0) return;
        self.emit(types.EvKind.player_died, 0, 0, 0, .{});
        if (self.state.gameOver()) {
            _ = self.score.commitRun();
            self.emit(types.EvKind.state, 0, @intCast(types.State.game_over), 0, .{});
        }
    }

    fn restart(self: *World) void {
        const en = &self.enemies;
        var i: u32 = 0;
        while (i < en.high_water) : (i += 1) {
            if (en.phase[i] == enemies_mod.Phase.free) continue;
            self.emit(types.EvKind.enemy_despawn, en.handle(i), 0, 0, .{});
            en.release(i);
        }
        en.high_water = 0;
        _ = self.score.commitRun();
        self.score.resetRun();
        self.player.reset();
        self.weapon.reset();
        self.spawner.reset();
        self.state.state = types.State.restarting;
        self.emit(types.EvKind.state, 0, @intCast(types.State.restarting), 0, .{});
        self.state.state = types.State.playing;
        self.emit(types.EvKind.state, 0, @intCast(types.State.playing), 0, .{});
        self.emit(types.EvKind.score, 0, 0, 0, .{});
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn quietConfig() types.Config {
    var c = types.Config.default;
    c.spawn_interval = 1000; // no automatic spawns unless a test wants them
    return c;
}

fn drain(w: *World, out: *std.ArrayList(types.Event)) !void {
    var buf: [16]types.Event = undefined;
    while (true) {
        const n = w.poll(&buf);
        if (n == 0) break;
        try out.appendSlice(testing.allocator, buf[0..n]);
    }
}

fn firstSpawned(w: *World) !Entity {
    _ = w.push(&.{.{ .kind = types.CmdKind.spawn_request, .target = 0, .amount = 0, .point = .{} }});
    w.tick(0.016);
    var buf: [16]types.Event = undefined;
    const n = w.poll(&buf);
    for (buf[0..n]) |e| if (e.kind == types.EvKind.enemy_spawned) return e.entity;
    return error.NoSpawn;
}

fn kinds(list: []const types.Event, alloc: std.mem.Allocator) ![]u32 {
    var k: std.ArrayList(u32) = .empty;
    for (list) |e| if (e.kind != types.EvKind.effect) try k.append(alloc, e.kind);
    return k.toOwnedSlice(alloc);
}

test "kill, sink, despawn, score" {
    const w = try World.create(testing.allocator, quietConfig());
    defer w.destroy();
    const e = try firstSpawned(w);
    var hits: [10]types.Cmd = undefined;
    for (&hits) |*h| h.* = .{ .kind = types.CmdKind.hit, .target = e, .amount = 10, .point = .{} };
    _ = w.push(&hits);
    w.tick(0.016);
    for (0..22) |_| w.tick(0.1); // dt is clamped to max_dt, so advance in small steps
    var list: std.ArrayList(types.Event) = .empty;
    defer list.deinit(testing.allocator);
    try drain(w, &list);
    const k = try kinds(list.items, testing.allocator);
    defer testing.allocator.free(k);
    const hurt = types.EvKind.enemy_hurt;
    try testing.expectEqual(@as(usize, 10), std.mem.count(u32, k, &.{hurt}));
    const want = [_]u32{ types.EvKind.enemy_died, types.EvKind.score, types.EvKind.enemy_sink, types.EvKind.enemy_despawn };
    try testing.expectEqualSlices(u32, &want, k[k.len - 4 ..]);
    try testing.expectEqual(@as(i32, 10), w.score.score);
    try testing.expectEqual(@as(u32, 0), w.enemies.live);
}

test "stale and dead handles are ignored" {
    const w = try World.create(testing.allocator, quietConfig());
    defer w.destroy();
    const e = try firstSpawned(w);
    _ = w.push(&.{ .{ .kind = types.CmdKind.hit, .target = e, .amount = 500, .point = .{} }, .{ .kind = types.CmdKind.hit, .target = e, .amount = 500, .point = .{} }, .{ .kind = types.CmdKind.hit, .target = 0x00ff_0001, .amount = 5, .point = .{} } });
    w.tick(0.016);
    try testing.expectEqual(@as(i32, 10), w.score.score);
}

test "enemy attacks at cooldown cadence, player dies, high score kept" {
    const w = try World.create(testing.allocator, quietConfig());
    defer w.destroy();
    const a = try firstSpawned(w);
    const b = try firstSpawned(w);
    _ = w.push(&.{.{ .kind = types.CmdKind.hit, .target = b, .amount = 100, .point = .{} }}); // score 10
    _ = w.push(&.{.{ .kind = types.CmdKind.enemy_in_range, .target = a, .amount = 1, .point = .{} }});
    var hurts: u32 = 0;
    var died = false;
    var buf: [16]types.Event = undefined;
    var t: u32 = 0;
    while (t < 200 and !died) : (t += 1) {
        w.tick(0.1);
        while (true) {
            const n = w.poll(&buf);
            if (n == 0) break;
            for (buf[0..n]) |e| {
                if (e.kind == types.EvKind.player_hurt) hurts += 1;
                if (e.kind == types.EvKind.player_died) died = true;
            }
        }
    }
    try testing.expect(died);
    try testing.expectEqual(@as(u32, 10), hurts);
    try testing.expectEqual(types.State.game_over, w.state.state);
    try testing.expectEqual(@as(i32, 10), w.score.high_score);
    // game over freezes everything
    w.tick(1.0);
    try testing.expectEqual(@as(u32, 0), w.poll(&buf));
    // restart: score reset, high score kept
    _ = w.push(&.{.{ .kind = types.CmdKind.restart, .target = 0, .amount = 0, .point = .{} }});
    w.tick(0.016);
    try testing.expectEqual(types.State.playing, w.state.state);
    try testing.expectEqual(@as(i32, 0), w.score.score);
    try testing.expectEqual(@as(i32, 10), w.score.high_score);
    try testing.expectEqual(@as(i32, 100), w.player.health);
    try testing.expectEqual(@as(u32, 0), w.enemies.live);
    try testing.expect(w.enemies.lookup(a) == null);
}

test "pause freezes the simulation" {
    var cfg = types.Config.default;
    cfg.spawn_interval = 0.5;
    const w = try World.create(testing.allocator, cfg);
    defer w.destroy();
    _ = w.push(&.{.{ .kind = types.CmdKind.pause_toggle, .target = 0, .amount = 0, .point = .{} }});
    w.tick(0.016);
    var buf: [16]types.Event = undefined;
    try testing.expectEqual(@as(u32, 1), w.poll(&buf));
    try testing.expectEqual(types.EvKind.state, buf[0].kind);
    for (0..20) |_| w.tick(0.2);
    try testing.expectEqual(@as(u32, 0), w.poll(&buf));
    try testing.expectEqual(@as(u32, 0), w.enemies.live);
    _ = w.push(&.{.{ .kind = types.CmdKind.pause_toggle, .target = 0, .amount = 0, .point = .{} }});
    for (0..10) |_| w.tick(0.2);
    try testing.expect(w.enemies.live > 0);
}

test "spawner spawns on interval and respects the cap" {
    var cfg = types.Config.default;
    cfg.spawn_interval = 1.0;
    cfg.max_enemies = 3;
    const w = try World.create(testing.allocator, cfg);
    defer w.destroy();
    for (0..100) |_| w.tick(0.1);
    try testing.expectEqual(@as(u32, 3), w.enemies.live);
}

test "weapon fire rate gates shot events; bad dt is harmless" {
    const w = try World.create(testing.allocator, quietConfig());
    defer w.destroy();
    const fire: types.Cmd = .{ .kind = types.CmdKind.fire, .target = 0, .amount = 0, .point = .{} };
    _ = w.push(&.{ fire, fire });
    w.tick(0.0);
    w.tick(-5.0);
    w.tick(std.math.nan(f32));
    var buf: [16]types.Event = undefined;
    const n = w.poll(&buf);
    var shots: u32 = 0;
    for (buf[0..n]) |e| if (e.kind == types.EvKind.shot) {
        shots += 1;
    };
    try testing.expectEqual(@as(u32, 1), shots);
}

fn runScript(split: bool, out: *std.ArrayList(types.Event)) !void {
    var cfg = types.Config.default;
    cfg.spawn_interval = 0.4;
    cfg.seed = 1234;
    const w = try World.create(testing.allocator, cfg);
    defer w.destroy();
    var frame: u32 = 0;
    while (frame < 300) : (frame += 1) {
        if (frame % 7 == 0) {
            var i: u32 = 0;
            while (i < w.enemies.high_water) : (i += 1) {
                if (w.enemies.phase[i] != enemies_mod.Phase.alive) continue;
                const h = w.enemies.handle(i);
                _ = w.push(&.{ .{ .kind = types.CmdKind.enemy_in_range, .target = h, .amount = @intCast(i % 2), .point = .{} }, .{ .kind = types.CmdKind.hit, .target = h, .amount = 35, .point = .{} } });
            }
        }
        if (split) {
            w.begin(0.05);
            const n = w.enemies.high_water;
            const mid = n / 2;
            w.stepEnemies(mid, n, w.dt);
            w.stepEnemies(0, mid, w.dt);
            w.resolve();
        } else w.tick(0.05);
        try drain(w, out);
    }
}

test "deterministic replay and split-range equivalence" {
    var a: std.ArrayList(types.Event) = .empty;
    defer a.deinit(testing.allocator);
    var b: std.ArrayList(types.Event) = .empty;
    defer b.deinit(testing.allocator);
    var c: std.ArrayList(types.Event) = .empty;
    defer c.deinit(testing.allocator);
    try runScript(false, &a);
    try runScript(false, &b);
    try runScript(true, &c);
    try testing.expect(a.items.len > 50);
    try testing.expectEqualSlices(u8, std.mem.sliceAsBytes(a.items), std.mem.sliceAsBytes(b.items));
    try testing.expectEqualSlices(u8, std.mem.sliceAsBytes(a.items), std.mem.sliceAsBytes(c.items));
}

test "high score survives save round trip" {
    const w = try World.create(testing.allocator, quietConfig());
    defer w.destroy();
    w.score.high_score = 777;
    var b: [12]u8 = undefined;
    try testing.expectEqual(@as(u32, 12), w.saveWrite(&b));
    const w2 = try World.create(testing.allocator, quietConfig());
    defer w2.destroy();
    try testing.expectEqual(@as(i32, 0), w2.saveRead(&b));
    try testing.expectEqual(@as(i32, 777), w2.score.high_score);
    try testing.expect(w2.saveRead(b[0..5]) < 0);
    try testing.expectEqual(@as(i32, 777), w2.score.high_score);
}
