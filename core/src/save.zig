//! Versioned little-endian save format: SaveV1 { magic, version, high_score } = 12 bytes.
const std = @import("std");
const types = @import("types.zig");

pub const magic: u32 = 0x53444253; // "SBDS"
pub const version: u32 = 1;
pub const size_v1: usize = 12;

/// Returns bytes written, or 0 if the buffer is too small.
pub fn write(high_score: i32, buf: []u8) u32 {
    if (buf.len < size_v1) return 0;
    std.mem.writeInt(u32, buf[0..4], magic, .little);
    std.mem.writeInt(u32, buf[4..8], version, .little);
    std.mem.writeInt(i32, buf[8..12], high_score, .little);
    return @intCast(size_v1);
}

/// Returns the high score (>= 0) or a negative SaveErr code.
pub fn read(buf: []const u8) i32 {
    if (buf.len < size_v1) return types.SaveErr.truncated;
    if (std.mem.readInt(u32, buf[0..4], .little) != magic) return types.SaveErr.bad_magic;
    if (std.mem.readInt(u32, buf[4..8], .little) != version) return types.SaveErr.bad_version;
    const hs = std.mem.readInt(i32, buf[8..12], .little);
    if (hs < 0) return types.SaveErr.bad_value;
    return hs;
}

test "round trip and corruption" {
    var b: [16]u8 = undefined;
    try std.testing.expectEqual(@as(u32, 12), write(420, &b));
    try std.testing.expectEqual(@as(i32, 420), read(b[0..12]));
    try std.testing.expectEqual(@as(u32, 0), write(1, b[0..11]));
    try std.testing.expectEqual(types.SaveErr.truncated, read(b[0..11]));
    var bad = b;
    bad[0] ^= 0xff;
    try std.testing.expectEqual(types.SaveErr.bad_magic, read(bad[0..12]));
    bad = b;
    bad[4] = 9;
    try std.testing.expectEqual(types.SaveErr.bad_version, read(bad[0..12]));
    _ = write(-5, &b);
    try std.testing.expectEqual(types.SaveErr.bad_value, read(b[0..12]));
}
