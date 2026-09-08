const std = @import("std");

/// Parse the sign separately so the minimum signed value is representable.
/// TODO: preserve unsigned magnitudes above maxInt(i64) until contextual type
/// resolution; the current signed payload cannot distinguish them from negatives.
pub fn integer(text: []const u8, negative: bool) !i64 {
    const magnitude = std.fmt.parseInt(u64, text, 0) catch return error.InvalidIntegerLiteral;
    if (!negative) return std.math.cast(i64, magnitude) orelse error.InvalidIntegerLiteral;
    if (magnitude > @as(u64, 1) << 63) return error.InvalidIntegerLiteral;
    if (magnitude == @as(u64, 1) << 63) return std.math.minInt(i64);
    return -@as(i64, @intCast(magnitude));
}

pub fn float(text: []const u8, negative: bool) !f64 {
    const value = std.fmt.parseFloat(f64, text) catch return error.InvalidFloatLiteral;
    return if (negative) -value else value;
}

test "integer payload preserves extrema and rejects overflow" {
    try std.testing.expectEqual(std.math.minInt(i64), try integer("9223372036854775808", true));
    try std.testing.expectEqual(std.math.maxInt(i64), try integer("9223372036854775807", false));
    try std.testing.expectError(error.InvalidIntegerLiteral, integer("18446744073709551615", false));
    try std.testing.expectEqual(@as(i64, 255), try integer("0xff", false));
    try std.testing.expectError(error.InvalidIntegerLiteral, integer("18446744073709551616", false));
    try std.testing.expectError(error.InvalidIntegerLiteral, integer("9223372036854775809", true));
    try std.testing.expectError(error.InvalidFloatLiteral, float("broken", false));
}
