//! C ABI. Must stay in sync with include/sbd.h (checked by tests/abi_test.c).
const std = @import("std");
const types = @import("types.zig");
const world_mod = @import("world.zig");

const World = world_mod.World;

fn allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

export fn sbd_abi_version() callconv(.c) u32 {
    return types.abi_version;
}

export fn sbd_config_default(out: ?*types.Config) callconv(.c) void {
    if (out) |o| o.* = types.Config.default;
}

export fn sbd_world_create(cfg: ?*const types.Config) callconv(.c) ?*World {
    const c = if (cfg) |p| p.* else types.Config.default;
    return World.create(allocator(), c) catch null;
}

export fn sbd_world_destroy(w: ?*World) callconv(.c) void {
    if (w) |p| p.destroy();
}

export fn sbd_world_push(w: ?*World, cmds: ?[*]const types.Cmd, n: u32) callconv(.c) u32 {
    const p = w orelse return 0;
    const c = cmds orelse return 0;
    return p.push(c[0..n]);
}

export fn sbd_world_tick(w: ?*World, dt: f32) callconv(.c) void {
    if (w) |p| p.tick(dt);
}

export fn sbd_world_begin(w: ?*World, dt: f32) callconv(.c) void {
    if (w) |p| p.begin(dt);
}

export fn sbd_world_enemy_count(w: ?*const World) callconv(.c) u32 {
    return if (w) |p| p.enemies.high_water else 0;
}

export fn sbd_world_step_enemies(w: ?*World, begin: u32, end: u32, dt: f32) callconv(.c) void {
    if (w) |p| p.stepEnemies(begin, end, dt);
}

export fn sbd_world_resolve(w: ?*World) callconv(.c) void {
    if (w) |p| p.resolve();
}

export fn sbd_world_poll(w: ?*World, out: ?[*]types.Event, cap: u32) callconv(.c) u32 {
    const p = w orelse return 0;
    const o = out orelse return 0;
    return p.poll(o[0..cap]);
}

export fn sbd_world_score(w: ?*const World) callconv(.c) i32 {
    return if (w) |p| p.score.score else 0;
}

export fn sbd_world_high_score(w: ?*const World) callconv(.c) i32 {
    return if (w) |p| p.score.high_score else 0;
}

export fn sbd_world_state(w: ?*const World) callconv(.c) u32 {
    return if (w) |p| p.state.state else types.State.game_over;
}

export fn sbd_world_player_health(w: ?*const World) callconv(.c) i32 {
    return if (w) |p| p.player.health else 0;
}

export fn sbd_save_write(w: ?*const World, buf: ?[*]u8, cap: u32) callconv(.c) u32 {
    const p = w orelse return 0;
    const b = buf orelse return 0;
    return p.saveWrite(b[0..cap]);
}

export fn sbd_save_read(w: ?*World, buf: ?[*]const u8, len: u32) callconv(.c) i32 {
    const p = w orelse return types.SaveErr.truncated;
    const b = buf orelse return types.SaveErr.truncated;
    return p.saveRead(b[0..len]);
}
