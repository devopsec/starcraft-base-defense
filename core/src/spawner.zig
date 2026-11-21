const std = @import("std");

pub const Spawner = struct {
    interval: f32,
    timer: f32 = 0,
    rng: u32,

    pub fn init(interval: f32, seed: u32) Spawner {
        return .{ .interval = interval, .rng = if (seed == 0) 1 else seed };
    }

    /// xorshift32; deterministic for a given seed.
    pub fn next(self: *Spawner) u32 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        return x;
    }

    /// Returns true when an enemy should spawn now (at most one per call).
    pub fn advance(self: *Spawner, dt: f32) bool {
        if (self.interval <= 0) return false;
        self.timer += dt;
        if (self.timer < self.interval) return false;
        self.timer -= self.interval;
        if (self.timer >= self.interval) self.timer = 0;
        return true;
    }

    pub fn reset(self: *Spawner) void {
        self.timer = 0;
    }
};

test "spawner fires once per interval and rng is deterministic" {
    var a = Spawner.init(3.0, 7);
    var b = Spawner.init(3.0, 7);
    try std.testing.expectEqual(a.next(), b.next());
    try std.testing.expect(!a.advance(2.9));
    try std.testing.expect(a.advance(0.2));
    try std.testing.expect(!a.advance(0.5));
    try std.testing.expect(a.advance(100.0));
    try std.testing.expect(!a.advance(0.0));
}
