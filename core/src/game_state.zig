const std = @import("std");
const types = @import("types.zig");

pub const GameState = struct {
    state: u32 = types.State.playing,

    pub fn isPlaying(self: GameState) bool {
        return self.state == types.State.playing;
    }

    /// Returns the new state if the toggle changed anything.
    pub fn togglePause(self: *GameState) ?u32 {
        switch (self.state) {
            types.State.playing => self.state = types.State.paused,
            types.State.paused => self.state = types.State.playing,
            else => return null,
        }
        return self.state;
    }

    pub fn gameOver(self: *GameState) bool {
        if (self.state == types.State.game_over) return false;
        self.state = types.State.game_over;
        return true;
    }
};

test "pause toggle is ignored after game over" {
    var g: GameState = .{};
    try std.testing.expectEqual(@as(?u32, types.State.paused), g.togglePause());
    try std.testing.expectEqual(@as(?u32, types.State.playing), g.togglePause());
    try std.testing.expect(g.gameOver());
    try std.testing.expectEqual(@as(?u32, null), g.togglePause());
}
