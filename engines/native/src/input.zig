//! Device-independent action state. platform.zig translates SDL keyboard/mouse/gamepad and xr.zig
//! translates OpenXR input into `Key` presses and analog values; the game only sees `Actions`.
const std = @import("std");

pub const Key = enum { forward, back, left, right, fire, pause, restart, quit };

/// One frame of player intent.
pub const Actions = struct {
    /// x = strafe right, y = forward, each in [-1, 1].
    move: [2]f32 = .{ 0, 0 },
    /// Radians this frame: x = yaw (right positive), y = pitch (up positive).
    look: [2]f32 = .{ 0, 0 },
    fire: bool = false,
    pause: bool = false,
    restart: bool = false,
    quit: bool = false,
};

pub const mouse_sensitivity: f32 = 0.0025; // radians per pixel
pub const stick_look_speed: f32 = 2.5; // radians per second at full deflection
pub const stick_deadzone: f32 = 0.2;

/// Accumulates raw input between frames. Held keys are level-triggered, pause/restart/quit are edge-triggered.
pub const State = struct {
    held: std.EnumSet(Key) = .empty,
    pressed: std.EnumSet(Key) = .empty,
    mouse: [2]f32 = .{ 0, 0 },
    stick_move: [2]f32 = .{ 0, 0 },
    stick_look: [2]f32 = .{ 0, 0 },
    /// XR controller trigger (xr.zig) and gamepad right trigger, kept apart from keyboard/mouse fire.
    trigger: bool = false,
    pad_trigger: bool = false,

    pub fn key(self: *State, k: Key, down: bool) void {
        if (down) {
            if (!self.held.contains(k)) self.pressed.insert(k);
            self.held.insert(k);
        } else {
            self.held.remove(k);
        }
    }

    pub fn mouseMotion(self: *State, dx: f32, dy: f32) void {
        self.mouse[0] += dx;
        self.mouse[1] += dy;
    }

    /// Axis values in [-1, 1]; y is down-positive like SDL gamepads.
    pub fn moveStick(self: *State, x: f32, y: f32) void {
        self.stick_move = .{ deadzone(x), deadzone(y) };
    }

    pub fn lookStick(self: *State, x: f32, y: f32) void {
        self.stick_look = .{ deadzone(x), deadzone(y) };
    }

    /// Builds this frame's actions and clears the per-frame accumulators.
    pub fn take(self: *State, dt: f32) Actions {
        var a: Actions = .{};
        var mx: f32 = self.stick_move[0];
        var my: f32 = -self.stick_move[1];
        if (self.held.contains(.right)) mx += 1;
        if (self.held.contains(.left)) mx -= 1;
        if (self.held.contains(.forward)) my += 1;
        if (self.held.contains(.back)) my -= 1;
        const len = @sqrt(mx * mx + my * my);
        if (len > 1) {
            mx /= len;
            my /= len;
        }
        a.move = .{ mx, my };
        a.look = .{
            self.mouse[0] * mouse_sensitivity + self.stick_look[0] * stick_look_speed * dt,
            -self.mouse[1] * mouse_sensitivity - self.stick_look[1] * stick_look_speed * dt,
        };
        a.fire = self.held.contains(.fire) or self.trigger or self.pad_trigger;
        a.pause = self.pressed.contains(.pause);
        a.restart = self.pressed.contains(.restart);
        a.quit = self.pressed.contains(.quit);
        self.pressed = .empty;
        self.mouse = .{ 0, 0 };
        return a;
    }
};

fn deadzone(v: f32) f32 {
    if (@abs(v) < stick_deadzone) return 0;
    return std.math.clamp(v, -1, 1);
}

test "diagonal movement is normalized and keys combine" {
    var s: State = .{};
    s.key(.forward, true);
    s.key(.right, true);
    const a = s.take(0.016);
    try std.testing.expectApproxEqAbs(@as(f32, 1), a.move[0] * a.move[0] + a.move[1] * a.move[1], 1e-5);
    try std.testing.expect(a.move[0] > 0 and a.move[1] > 0);
}

test "pause is edge-triggered, fire is level-triggered" {
    var s: State = .{};
    s.key(.pause, true);
    s.key(.fire, true);
    try std.testing.expect(s.take(0.016).pause);
    s.key(.pause, true); // key repeat while held
    const a = s.take(0.016);
    try std.testing.expect(!a.pause);
    try std.testing.expect(a.fire);
    s.key(.pause, false);
    s.key(.pause, true);
    try std.testing.expect(s.take(0.016).pause);
}

test "mouse look accumulates and resets; stick deadzone" {
    var s: State = .{};
    s.mouseMotion(10, 0);
    s.mouseMotion(10, -4);
    const a = s.take(0.016);
    try std.testing.expectApproxEqAbs(20 * mouse_sensitivity, a.look[0], 1e-6);
    try std.testing.expectApproxEqAbs(4 * mouse_sensitivity, a.look[1], 1e-6);
    try std.testing.expectEqual(@as(f32, 0), s.take(0.016).look[0]);
    s.moveStick(0.1, -0.1);
    try std.testing.expectEqual(@as(f32, 0), s.take(0.016).move[1]);
    s.moveStick(0, -1);
    try std.testing.expectEqual(@as(f32, 1), s.take(0.016).move[1]);
}
