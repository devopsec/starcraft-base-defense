const std = @import("std");

pub const Score = struct {
    score: i32 = 0,
    high_score: i32 = 0,

    pub fn add(self: *Score, amount: i32) void {
        self.score +|= amount;
    }

    pub fn resetRun(self: *Score) void {
        self.score = 0;
    }

    /// Returns true when the high score changed.
    pub fn commitRun(self: *Score) bool {
        if (self.score > self.high_score) {
            self.high_score = self.score;
            return true;
        }
        return false;
    }
};

test "high score only grows" {
    var s: Score = .{};
    s.add(30);
    try std.testing.expect(s.commitRun());
    s.resetRun();
    s.add(10);
    try std.testing.expect(!s.commitRun());
    try std.testing.expectEqual(@as(i32, 30), s.high_score);
}
