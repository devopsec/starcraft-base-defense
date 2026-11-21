const std = @import("std");

pub const Player = struct {
    health: i32,
    start_health: i32,

    pub fn init(start_health: u32) Player {
        const h: i32 = @intCast(@min(start_health, std.math.maxInt(i32)));
        return .{ .health = h, .start_health = h };
    }

    pub fn isAlive(self: Player) bool {
        return self.health > 0;
    }

    pub fn reset(self: *Player) void {
        self.health = self.start_health;
    }

    /// Returns remaining health (clamped at 0).
    pub fn damage(self: *Player, amount: u32) i32 {
        const a: i32 = @intCast(@min(amount, std.math.maxInt(i32)));
        self.health = @max(self.health -| a, 0);
        return self.health;
    }
};

test "player dies at zero" {
    var p = Player.init(25);
    try std.testing.expectEqual(@as(i32, 15), p.damage(10));
    try std.testing.expectEqual(@as(i32, 0), p.damage(100));
    try std.testing.expect(!p.isAlive());
    p.reset();
    try std.testing.expect(p.isAlive());
}
