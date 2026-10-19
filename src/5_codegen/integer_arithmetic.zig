const p = @import("../4_semantics/primitives/schema.zig");

pub const Bounds = p.IntegerRange;
pub const bounds = p.integerRangeForWidth;

// Compatibility boundary for semantic integer constants and range checks.
// Execution itself uses the selected native-width scalar representation.
pub fn evaluate(operator: p.BinaryOperator, left: i128, right: i128, range: Bounds) error{DivisionByZero}!i128 {
    const numeric = @import("numeric_value.zig").Value;
    const result = numeric.fromInteger(left, range).binary(operator, numeric.fromInteger(right, range)) catch |err| switch (err) {
        error.DivisionByZero => return error.DivisionByZero,
        error.MismatchedNumericTypes => unreachable,
    };
    return result.integer();
}

test "integer primitives wrap at each width including full unsigned products" {
    const std = @import("std");
    for ([_]u7{ 8, 16, 32, 64 }) |bits| {
        for ([_]bool{ false, true }) |signed| {
            const range = bounds(bits, signed);
            try std.testing.expectEqual(range.minimum, try evaluate(.addition, range.maximum, 1, range));
            try std.testing.expectEqual(range.maximum, try evaluate(.subtraction, range.minimum, 1, range));
        }
    }
    const unsigned = bounds(64, false);
    try std.testing.expectEqual(@as(i128, 1), try evaluate(.multiplication, unsigned.maximum, unsigned.maximum, unsigned));
    const signed = bounds(64, true);
    try std.testing.expectEqual(signed.minimum, try evaluate(.division, signed.minimum, -1, signed));
    try std.testing.expectEqual(@as(i128, 0), try evaluate(.modulo, signed.minimum, -1, signed));
    try std.testing.expectEqual(@as(i128, -2), try evaluate(.division, -7, 3, signed));
    try std.testing.expectEqual(@as(i128, -1), try evaluate(.modulo, -7, 3, signed));
    try std.testing.expectError(error.DivisionByZero, evaluate(.division, 1, 0, signed));
    try std.testing.expectError(error.DivisionByZero, evaluate(.modulo, 1, 0, unsigned));
}
