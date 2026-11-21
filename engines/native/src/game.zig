//! Native host logic, mirroring the Godot adapter: the core owns the rules, this file owns positions, chasing,
//! hitscan and presentation state. No SDL/wgpu here, so it runs headless and in unit tests.
const std = @import("std");
const core = @import("sbd_core");
const input = @import("input.zig");

const T = core.types;
const World = core.world.World;

pub const V3 = @Vector(3, f32);

pub const enemy_speed: f32 = 3.0;
pub const attack_range: f32 = 1.5;
pub const enemy_radius: f32 = 0.6;
pub const enemy_center_y: f32 = 0.6;
pub const player_speed: f32 = 6.0;
pub const eye_height: f32 = 1.6;
pub const arena_half: f32 = 19.5;
pub const spawn_points = [_]V3{ .{ -16, 0, -16 }, .{ 16, 0, -16 }, .{ 16, 0, 16 }, .{ -16, 0, 16 } };

/// Engine-side job split, same numbers as the other adapters.
pub const parallel_threshold: u32 = 32;
pub const chunk_size: u32 = 16;

pub const EnemyView = struct {
    entity: T.Entity,
    pos: V3,
    sinking: bool = false,
    in_range: bool = false,
    hurt_flash: f32 = 0,
};

pub const Effect = struct {
    id: u32,
    pos: V3,
    ttl: f32,
};

pub const Player = struct {
    pos: V3 = .{ 0, 0, 0 },
    yaw: f32 = 0,
    pitch: f32 = 0,

    pub fn eye(self: Player) V3 {
        return self.pos + V3{ 0, eye_height, 0 };
    }

    /// yaw 0 looks down -Z; positive yaw turns right.
    pub fn forward(self: Player) V3 {
        const cp = @cos(self.pitch);
        return .{ @sin(self.yaw) * cp, @sin(self.pitch), -@cos(self.yaw) * cp };
    }
};

pub const max_effects = 64;

pub const Game = struct {
    gpa: std.mem.Allocator,
    world: *World,
    cfg: T.Config,
    weapon_range: f32,
    /// Optional job system for enemy ranges; null runs them serially on the caller.
    io: ?std.Io,

    player: Player = .{},
    enemies: std.ArrayList(EnemyView) = .empty,
    pending: std.ArrayList(T.Cmd) = .empty,
    effects: [max_effects]Effect = undefined,
    effect_count: usize = 0,
    player_flash: f32 = 0,
    muzzle_flash: f32 = 0,

    high_score_at_run_start: i32 = 0,
    /// Set when a run ended with a new high score; the host persists the save and clears it.
    save_dirty: bool = false,
    new_high_score: bool = false,
    stats: Stats = .{},

    pub const Stats = struct {
        parallel_frames: u32 = 0,
        shots: u32 = 0,
        hits: u32 = 0,
    };

    pub fn init(gpa: std.mem.Allocator, cfg: T.Config, weapon_range: f32, io: ?std.Io) !Game {
        const w = try World.create(gpa, cfg);
        errdefer w.destroy();
        var g: Game = .{ .gpa = gpa, .world = w, .cfg = cfg, .weapon_range = weapon_range, .io = io };
        // Everything the frame loop needs is reserved here: no allocation per frame.
        try g.enemies.ensureTotalCapacity(gpa, @max(cfg.max_enemies, 1) * 2);
        try g.pending.ensureTotalCapacity(gpa, 256);
        return g;
    }

    pub fn deinit(self: *Game) void {
        self.enemies.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.world.destroy();
    }

    pub fn send(self: *Game, c: T.Cmd) void {
        self.pending.appendBounded(c) catch {
            self.flush();
            self.pending.appendAssumeCapacity(c);
        };
    }

    pub fn loadSave(self: *Game, bytes: []const u8) i32 {
        const r = self.world.saveRead(bytes);
        if (r == 0) self.high_score_at_run_start = self.world.score.high_score;
        return r;
    }

    pub fn writeSave(self: *const Game, buf: []u8) u32 {
        return self.world.saveWrite(buf);
    }

    pub fn state(self: *const Game) u32 {
        return self.world.state.state;
    }

    pub fn score(self: *const Game) i32 {
        return self.world.score.score;
    }

    pub fn highScore(self: *const Game) i32 {
        return self.world.score.high_score;
    }

    pub fn playerHealth(self: *const Game) i32 {
        return self.world.player.health;
    }

    /// One frame: input -> commands -> begin / step_enemies(ranges) / resolve -> events.
    pub fn frame(self: *Game, dt_in: f32, a: input.Actions) void {
        const dt = if (std.math.isFinite(dt_in) and dt_in > 0) @min(dt_in, core.world.max_dt) else 0;
        self.applyInput(dt, a);
        self.moveEnemies(dt);
        self.flush();
        self.world.begin(dt);
        self.stepEnemies();
        self.world.resolve();
        self.drainEvents();
        self.fadeEffects(dt);
    }

    fn applyInput(self: *Game, dt: f32, a: input.Actions) void {
        if (a.pause) self.send(cmd(T.CmdKind.pause_toggle, 0, 0, .{}));
        if (a.restart and self.state() == T.State.game_over) self.send(cmd(T.CmdKind.restart, 0, 0, .{}));
        if (self.state() != T.State.playing) return;

        const p = &self.player;
        p.yaw = @mod(p.yaw + a.look[0], std.math.tau);
        p.pitch = std.math.clamp(p.pitch + a.look[1], -1.4, 1.4);
        const right = V3{ @cos(p.yaw), 0, @sin(p.yaw) };
        const fwd = V3{ @sin(p.yaw), 0, -@cos(p.yaw) };
        const step = (right * splat(a.move[0]) + fwd * splat(a.move[1])) * splat(player_speed * dt);
        p.pos += step;
        p.pos[0] = std.math.clamp(p.pos[0], -arena_half, arena_half);
        p.pos[2] = std.math.clamp(p.pos[2], -arena_half, arena_half);

        if (a.fire) self.send(cmd(T.CmdKind.fire, 0, 0, toVec(p.eye())));
    }

    fn moveEnemies(self: *Game, dt: f32) void {
        const playing = self.state() == T.State.playing;
        for (self.enemies.items) |*e| {
            e.hurt_flash = @max(0, e.hurt_flash - dt);
            if (e.sinking) {
                e.pos[1] -= self.cfg.sink_speed * dt;
                continue;
            }
            if (!playing) continue;
            var to = self.player.pos - e.pos;
            to[1] = 0;
            const dist = @sqrt(@reduce(.Add, to * to));
            if (dist > attack_range * 0.9 and dist > 1e-4) {
                const travel = @min(enemy_speed * dt, dist - attack_range * 0.9);
                e.pos += to * splat(travel / dist);
            }
            const now_in = dist <= attack_range;
            if (now_in != e.in_range) {
                e.in_range = now_in;
                self.send(cmd(T.CmdKind.enemy_in_range, e.entity, @intFromBool(now_in), .{}));
            }
        }
    }

    fn flush(self: *Game) void {
        var rest = self.pending.items;
        while (rest.len > 0) {
            const n = self.world.push(rest);
            if (n == 0) break; // queue full: drop like the C ABI would
            rest = rest[n..];
        }
        self.pending.clearRetainingCapacity();
    }

    fn stepEnemies(self: *Game) void {
        const count = self.world.enemies.high_water;
        const dt = self.world.dt;
        const io = self.io orelse return self.world.stepEnemies(0, count, dt);
        if (count < parallel_threshold) return self.world.stepEnemies(0, count, dt);

        // Disjoint ranges are what the core allows to run concurrently; the core itself never spawns threads.
        var group: std.Io.Group = .init;
        var begin: u32 = 0;
        while (begin < count) : (begin += chunk_size) {
            group.async(io, stepRange, .{ self.world, begin, @min(begin + chunk_size, count), dt });
        }
        group.await(io) catch {};
        self.stats.parallel_frames += 1;
    }

    fn stepRange(w: *World, begin: u32, end: u32, dt: f32) void {
        w.stepEnemies(begin, end, dt);
    }

    fn drainEvents(self: *Game) void {
        var buf: [64]T.Event = undefined;
        while (true) {
            const n = self.world.poll(&buf);
            if (n == 0) break;
            for (buf[0..n]) |e| self.dispatch(e);
        }
    }

    fn dispatch(self: *Game, e: T.Event) void {
        switch (e.kind) {
            T.EvKind.enemy_spawned => {
                const roll: usize = @intCast(@max(e.value, 0));
                self.enemies.appendBounded(.{ .entity = e.entity, .pos = spawn_points[roll % spawn_points.len] }) catch {};
            },
            T.EvKind.enemy_hurt => if (self.find(e.entity)) |v| {
                v.hurt_flash = 0.15;
            },
            T.EvKind.enemy_died => if (self.find(e.entity)) |v| {
                v.sinking = true;
                v.in_range = false;
            },
            T.EvKind.enemy_despawn => self.remove(e.entity),
            T.EvKind.player_hurt => self.player_flash = 0.25,
            T.EvKind.shot => self.onShot(e.value),
            T.EvKind.effect => self.addEffect(e),
            T.EvKind.state => self.onState(@intCast(e.value)),
            else => {},
        }
    }

    fn onShot(self: *Game, damage: i32) void {
        self.stats.shots += 1;
        self.muzzle_flash = 0.06;
        const origin = self.player.eye();
        const hit = raycast(self.enemies.items, origin, self.player.forward(), self.weapon_range) orelse return;
        self.stats.hits += 1;
        const v = self.enemies.items[hit.index];
        self.send(cmd(T.CmdKind.hit, v.entity, damage, toVec(hit.point)));
    }

    fn onState(self: *Game, s: u32) void {
        switch (s) {
            T.State.game_over => {
                self.new_high_score = self.highScore() > self.high_score_at_run_start;
                if (self.new_high_score) self.save_dirty = true;
            },
            T.State.restarting => {
                self.enemies.clearRetainingCapacity();
                self.effect_count = 0;
                self.new_high_score = false;
                self.high_score_at_run_start = self.highScore();
                self.player = .{};
            },
            else => {},
        }
    }

    fn addEffect(self: *Game, e: T.Event) void {
        const ttl: f32 = switch (e.effect_id) {
            T.Fx.hit => 0.15,
            T.Fx.death, T.Fx.spawn => 0.4,
            else => return,
        };
        if (self.effect_count == max_effects) return;
        var pos = V3{ e.pos.x, e.pos.y, e.pos.z };
        if (e.effect_id == T.Fx.spawn or e.effect_id == T.Fx.death) {
            if (self.find(e.entity)) |v| pos = v.pos + V3{ 0, enemy_center_y, 0 };
        }
        self.effects[self.effect_count] = .{ .id = e.effect_id, .pos = pos, .ttl = ttl };
        self.effect_count += 1;
    }

    fn fadeEffects(self: *Game, dt: f32) void {
        self.player_flash = @max(0, self.player_flash - dt);
        self.muzzle_flash = @max(0, self.muzzle_flash - dt);
        var i: usize = 0;
        while (i < self.effect_count) {
            self.effects[i].ttl -= dt;
            if (self.effects[i].ttl <= 0) {
                self.effect_count -= 1;
                self.effects[i] = self.effects[self.effect_count];
            } else i += 1;
        }
    }

    pub fn find(self: *Game, entity: T.Entity) ?*EnemyView {
        for (self.enemies.items) |*v| if (v.entity == entity) return v;
        return null;
    }

    fn remove(self: *Game, entity: T.Entity) void {
        for (self.enemies.items, 0..) |v, i| {
            if (v.entity == entity) {
                _ = self.enemies.swapRemove(i);
                return;
            }
        }
    }

    /// Turns the player to look at a world point (used by the scripted smoke run and XR-less aim assist).
    pub fn aimAt(self: *Game, target: V3) void {
        const d = target - self.player.eye();
        self.player.yaw = std.math.atan2(d[0], -d[2]);
        self.player.pitch = std.math.atan2(d[1], @sqrt(d[0] * d[0] + d[2] * d[2]));
    }
};

pub const Hit = struct { index: usize, point: V3, distance: f32 };

/// Nearest living enemy (sphere at body center) hit by the ray, within `range`.
pub fn raycast(views: []const EnemyView, origin: V3, dir: V3, range: f32) ?Hit {
    var best: ?Hit = null;
    for (views, 0..) |v, i| {
        if (v.sinking) continue;
        const center = v.pos + V3{ 0, enemy_center_y, 0 };
        const t = raySphere(origin, dir, center, enemy_radius) orelse continue;
        if (t > range) continue;
        if (best == null or t < best.?.distance) best = .{ .index = i, .point = origin + dir * splat(t), .distance = t };
    }
    return best;
}

/// Distance along a unit `dir` to the first intersection with the sphere, or null.
pub fn raySphere(origin: V3, dir: V3, center: V3, radius: f32) ?f32 {
    const oc = origin - center;
    const b = @reduce(.Add, oc * dir);
    const c = @reduce(.Add, oc * oc) - radius * radius;
    const disc = b * b - c;
    if (disc < 0) return null;
    const s = @sqrt(disc);
    const t0 = -b - s;
    if (t0 >= 0) return t0;
    const t1 = -b + s;
    return if (t1 >= 0) 0 else null; // origin inside the sphere
}

pub fn cmd(kind: u32, target: T.Entity, amount: i32, point: T.Vec3) T.Cmd {
    return .{ .kind = kind, .target = target, .amount = amount, .point = point };
}

fn toVec(v: V3) T.Vec3 {
    return .{ .x = v[0], .y = v[1], .z = v[2] };
}

fn splat(x: f32) V3 {
    return @splat(x);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn quiet() T.Config {
    var c = T.Config.default;
    c.spawn_interval = 1000;
    return c;
}

test "ray hits the nearest living enemy and skips sinking ones" {
    const views = [_]EnemyView{
        .{ .entity = 1, .pos = .{ 0, 0, -10 } },
        .{ .entity = 2, .pos = .{ 0, 0, -5 }, .sinking = true },
        .{ .entity = 3, .pos = .{ 0, 0, -20 } },
    };
    const origin = V3{ 0, enemy_center_y, 0 };
    const h = raycast(&views, origin, .{ 0, 0, -1 }, 100).?;
    try testing.expectEqual(@as(usize, 0), h.index);
    try testing.expectApproxEqAbs(10 - enemy_radius, h.distance, 1e-4);
    try testing.expect(raycast(&views, origin, .{ 0, 0, -1 }, 5) == null);
    try testing.expect(raycast(&views, origin, .{ 1, 0, 0 }, 100) == null);
}

test "enemy chases, reports in-range once, and hurts the player" {
    var g = try Game.init(testing.allocator, quiet(), 100, null);
    defer g.deinit();
    g.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    g.frame(1.0 / 60.0, .{});
    try testing.expectEqual(@as(usize, 1), g.enemies.items.len);
    var t: f32 = 0;
    while (t < 12 and g.playerHealth() == 100) : (t += 1.0 / 60.0) g.frame(1.0 / 60.0, .{});
    try testing.expect(g.enemies.items[0].in_range);
    try testing.expect(g.playerHealth() < 100);
}

test "aim and fire kills an enemy through the core" {
    var g = try Game.init(testing.allocator, quiet(), 100, null);
    defer g.deinit();
    g.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    g.frame(1.0 / 60.0, .{});
    var frames: u32 = 0;
    while (g.score() == 0 and frames < 600) : (frames += 1) {
        const v = g.enemies.items[0];
        g.aimAt(v.pos + V3{ 0, enemy_center_y, 0 });
        g.frame(1.0 / 60.0, .{ .fire = true });
    }
    try testing.expectEqual(@as(i32, 10), g.score());
    try testing.expect(g.stats.hits >= 5);
}

test "parallel stepping through std.Io matches serial stepping" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a = try Game.init(testing.allocator, quiet(), 100, threaded.io());
    defer a.deinit();
    var b = try Game.init(testing.allocator, quiet(), 100, null);
    defer b.deinit();
    for (0..40) |_| {
        a.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
        b.send(cmd(T.CmdKind.spawn_request, 0, 0, .{}));
    }
    for (0..900) |_| {
        a.frame(1.0 / 60.0, .{});
        b.frame(1.0 / 60.0, .{});
    }
    try testing.expect(a.stats.parallel_frames > 0);
    try testing.expectEqual(b.playerHealth(), a.playerHealth());
    try testing.expectEqual(b.state(), a.state());
    try testing.expectEqual(T.State.game_over, a.state());
}
