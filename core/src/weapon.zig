const std = @import("std");

pub const Weapon = struct {
    fire_rate: f32,
    timer: f32,

    pub fn init(fire_rate: f32) Weapon {
        return .{ .fire_rate = fire_rate, .timer = fire_rate };
    }

    pub fn advance(self: *Weapon, dt: f32) void {
        self.timer += dt;
    }

    /// Consumes the cooldown if a shot is allowed.
    pub fn tryFire(self: *Weapon) bool {
        if (self.timer < self.fire_rate) return false;
        self.timer = 0;
        return true;
    }

    pub fn reset(self: *Weapon) void {
        self.timer = self.fire_rate;
    }
};

test "fire rate gates shots" {
    var w = Weapon.init(0.15);
    try std.testing.expect(w.tryFire());
    try std.testing.expect(!w.tryFire());
    w.advance(0.1);
    try std.testing.expect(!w.tryFire());
    w.advance(0.06);
    try std.testing.expect(w.tryFire());
}
