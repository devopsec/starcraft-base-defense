//! Fixed-capacity FIFO ring buffer for events and commands. Never allocates after init.
const std = @import("std");
const types = @import("types.zig");

pub fn Ring(comptime T: type) type {
    return struct {
        const Self = @This();

        buf: []T,
        head: usize = 0,
        len: usize = 0,
        dropped: u32 = 0,

        pub fn init(alloc: std.mem.Allocator, capacity: usize) !Self {
            return .{ .buf = try alloc.alloc(T, capacity) };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            alloc.free(self.buf);
        }

        pub fn push(self: *Self, item: T) bool {
            if (self.len == self.buf.len) {
                self.dropped +%= 1;
                return false;
            }
            self.buf[(self.head + self.len) % self.buf.len] = item;
            self.len += 1;
            return true;
        }

        /// Copies up to out.len items in FIFO order and removes them.
        pub fn pop(self: *Self, out: []T) usize {
            const n = @min(out.len, self.len);
            for (0..n) |i| out[i] = self.buf[(self.head + i) % self.buf.len];
            self.head = (self.head + n) % self.buf.len;
            self.len -= n;
            return n;
        }

        pub fn clear(self: *Self) void {
            self.head = 0;
            self.len = 0;
        }
    };
}

pub const EventQueue = Ring(types.Event);
pub const CmdQueue = Ring(types.Cmd);

test "ring drains in order across several polls" {
    var q = try EventQueue.init(std.testing.allocator, 4);
    defer q.deinit(std.testing.allocator);
    for (0..6) |i| {
        const ok = q.push(.{ .kind = @intCast(i), .entity = 0, .value = 0, .effect_id = 0, .pos = .{} });
        try std.testing.expectEqual(i < 4, ok);
    }
    try std.testing.expectEqual(@as(u32, 2), q.dropped);
    var out: [3]types.Event = undefined;
    try std.testing.expectEqual(@as(usize, 3), q.pop(&out));
    try std.testing.expectEqual(@as(u32, 0), out[0].kind);
    try std.testing.expectEqual(@as(u32, 2), out[2].kind);
    try std.testing.expectEqual(@as(usize, 1), q.pop(&out));
    try std.testing.expectEqual(@as(u32, 3), out[0].kind);
    try std.testing.expectEqual(@as(usize, 0), q.pop(&out));
}
