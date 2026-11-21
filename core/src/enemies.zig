//! Structure-of-arrays enemy storage with generational handles.
const std = @import("std");
const types = @import("types.zig");

pub const Phase = struct {
    pub const free: u8 = 0;
    pub const alive: u8 = 1;
    pub const sinking: u8 = 2;
};

pub const Flag = struct {
    pub const attack: u8 = 1;
    pub const despawn: u8 = 2;
};

pub const Enemies = struct {
    alloc: std.mem.Allocator,
    cap: u32,
    high_water: u32 = 0,
    live: u32 = 0, // phase == alive

    gen: []u16,
    phase: []u8,
    health: []i32,
    attack_timer: []f32,
    sink_time: []f32,
    in_range: []u8,
    flags: []u8,

    pub fn init(alloc: std.mem.Allocator, cap: u32) !Enemies {
        const n: usize = cap;
        var e: Enemies = .{
            .alloc = alloc,
            .cap = cap,
            .gen = try alloc.alloc(u16, n),
            .phase = undefined,
            .health = undefined,
            .attack_timer = undefined,
            .sink_time = undefined,
            .in_range = undefined,
            .flags = undefined,
        };
        errdefer alloc.free(e.gen);
        e.phase = try alloc.alloc(u8, n);
        errdefer alloc.free(e.phase);
        e.health = try alloc.alloc(i32, n);
        errdefer alloc.free(e.health);
        e.attack_timer = try alloc.alloc(f32, n);
        errdefer alloc.free(e.attack_timer);
        e.sink_time = try alloc.alloc(f32, n);
        errdefer alloc.free(e.sink_time);
        e.in_range = try alloc.alloc(u8, n);
        errdefer alloc.free(e.in_range);
        e.flags = try alloc.alloc(u8, n);
        @memset(e.gen, 1);
        @memset(e.phase, Phase.free);
        @memset(e.health, 0);
        @memset(e.attack_timer, 0);
        @memset(e.sink_time, 0);
        @memset(e.in_range, 0);
        @memset(e.flags, 0);
        return e;
    }

    pub fn deinit(self: *Enemies) void {
        self.alloc.free(self.gen);
        self.alloc.free(self.phase);
        self.alloc.free(self.health);
        self.alloc.free(self.attack_timer);
        self.alloc.free(self.sink_time);
        self.alloc.free(self.in_range);
        self.alloc.free(self.flags);
    }

    pub fn handle(self: *const Enemies, idx: u32) types.Entity {
        return (@as(u32, self.gen[idx]) << 16) | idx;
    }

    /// Returns the slot index for a live handle, or null for stale/invalid ones.
    pub fn lookup(self: *const Enemies, e: types.Entity) ?u32 {
        const idx = e & 0xffff;
        if (e == types.invalid_entity or idx >= self.cap) return null;
        if (self.gen[idx] != @as(u16, @truncate(e >> 16))) return null;
        if (self.phase[idx] == Phase.free) return null;
        return idx;
    }

    pub fn spawn(self: *Enemies, health: u32) ?types.Entity {
        var i: u32 = 0;
        while (i < self.cap) : (i += 1) {
            if (self.phase[i] != Phase.free) continue;
            self.phase[i] = Phase.alive;
            self.health[i] = @intCast(@min(health, std.math.maxInt(i32)));
            self.attack_timer[i] = 0;
            self.sink_time[i] = 0;
            self.in_range[i] = 0;
            self.flags[i] = 0;
            self.live += 1;
            if (i + 1 > self.high_water) self.high_water = i + 1;
            return self.handle(i);
        }
        return null;
    }

    pub fn release(self: *Enemies, idx: u32) void {
        if (self.phase[idx] == Phase.alive) self.live -= 1;
        self.phase[idx] = Phase.free;
        self.flags[idx] = 0;
        self.in_range[idx] = 0;
        self.gen[idx] +%= 1;
        if (self.gen[idx] == 0) self.gen[idx] = 1;
    }

    /// Parallel-safe: touches only slots in [begin, end); no events, no shared state.
    pub fn stepRange(self: *Enemies, begin: u32, end: u32, dt: f32, attack_cooldown: f32, sink_duration: f32) void {
        const hi = @min(end, self.high_water);
        var i = begin;
        while (i < hi) : (i += 1) {
            switch (self.phase[i]) {
                Phase.alive => {
                    self.attack_timer[i] += dt;
                    if (self.attack_timer[i] >= attack_cooldown and self.in_range[i] != 0) {
                        self.attack_timer[i] = 0;
                        self.flags[i] |= Flag.attack;
                    }
                },
                Phase.sinking => {
                    self.sink_time[i] += dt;
                    if (self.sink_time[i] >= sink_duration) self.flags[i] |= Flag.despawn;
                },
                else => {},
            }
        }
    }
};

test "stale handles are rejected after release" {
    var e = try Enemies.init(std.testing.allocator, 4);
    defer e.deinit();
    const a = e.spawn(100).?;
    try std.testing.expect(e.lookup(a) != null);
    e.release(e.lookup(a).?);
    try std.testing.expect(e.lookup(a) == null);
    const b = e.spawn(100).?;
    try std.testing.expect(a != b);
    try std.testing.expect(e.lookup(0) == null);
    try std.testing.expect(e.lookup(0x0001_0fff) == null);
}

test "spawn cap holds" {
    var e = try Enemies.init(std.testing.allocator, 2);
    defer e.deinit();
    try std.testing.expect(e.spawn(1) != null);
    try std.testing.expect(e.spawn(1) != null);
    try std.testing.expect(e.spawn(1) == null);
}
