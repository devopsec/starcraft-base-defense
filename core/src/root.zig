//! sbd_core: engine-agnostic Starcraft Base Defense gameplay core.
pub const types = @import("types.zig");
pub const world = @import("world.zig");
pub const enemies = @import("enemies.zig");
pub const spawner = @import("spawner.zig");
pub const player = @import("player.zig");
pub const weapon = @import("weapon.zig");
pub const score = @import("score.zig");
pub const save = @import("save.zig");
pub const game_state = @import("game_state.zig");
pub const events = @import("events.zig");
pub const abi = @import("abi.zig");

comptime {
    _ = abi; // force the exports into the library
}

test {
    @import("std").testing.refAllDecls(@This());
    _ = world;
    _ = enemies;
    _ = spawner;
    _ = player;
    _ = weapon;
    _ = score;
    _ = save;
    _ = game_state;
    _ = events;
}
