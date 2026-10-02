const std = @import("std");

/// Keep the mathematical value until contextual typing chooses a machine type.
/// The wider signed payload preserves both negative values and all u64 magnitudes;
/// it does not introduce a 128-bit runtime integer type.
pub fn integer(text: []const u8, negative: bool) !i128 {
    const magnitude = std.fmt.parseInt(u64, text, 0) catch return error.InvalidIntegerLiteral;
    const value: i128 = magnitude;
    return if (negative) -value else value;
}

pub fn integerWithDiagnostic(text: []const u8, negative: bool, diagnostics: ?*@import("../1_base/diagnostic.zig").Diagnostics, location: @import("../2_tokens/token.zig").Location) !i128 {
    return integer(text, negative) catch |err| {
        if (diagnostics) |bag| {
            try bag.add(location, .semantic, "integer literal magnitude exceeds the supported 64-bit range", .{});
            return error.Reported;
        }
        return err;
    };
}

pub fn float(text: []const u8, negative: bool) !f64 {
    const value = std.fmt.parseFloat(f64, text) catch return error.InvalidFloatLiteral;
    return if (negative) -value else value;
}

test "integer payload preserves extrema and rejects overflow" {
    try std.testing.expectEqual(@as(i128, std.math.minInt(i64)), try integer("9223372036854775808", true));
    try std.testing.expectEqual(@as(i128, std.math.maxInt(i64)), try integer("9223372036854775807", false));
    try std.testing.expectEqual(@as(i128, std.math.maxInt(u64)), try integer("18446744073709551615", false));
    try std.testing.expectEqual(@as(i128, 255), try integer("0xff", false));
    try std.testing.expectError(error.InvalidIntegerLiteral, integer("18446744073709551616", false));
    try std.testing.expectEqual(@as(i128, -9223372036854775809), try integer("9223372036854775809", true));
    try std.testing.expectError(error.InvalidFloatLiteral, float("broken", false));
}
