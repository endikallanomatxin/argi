const p = @import("../4_semantics/primitives/schema.zig");

pub const Bounds = p.IntegerRange;
pub const bounds = p.integerRangeForWidth;

// Registers store canonical low bits; width and signedness come from checked
// slot types. Widened integers are confined to semantic constant boundaries.
pub fn encode(value: i128, range: Bounds) u64 {
    const raw: u64 = @truncate(@as(u128, @bitCast(value)));
    return raw & @as(u64, @intCast(range.maximum - range.minimum));
}

pub fn decode(bits: u64, range: Bounds) i128 {
    const mask: u64 = @intCast(range.maximum - range.minimum);
    const raw = bits & mask;
    return if (range.minimum < 0 and raw > range.maximum)
        @as(i128, raw) - (@as(i128, mask) + 1)
    else
        raw;
}

pub fn evaluateBits(operator: p.BinaryOperator, left: u64, right: u64, range: Bounds) error{DivisionByZero}!u64 {
    const std = @import("std");
    inline for (.{ i8, i16, i32, i64, u8, u16, u32, u64 }) |T| {
        if (range.minimum == std.math.minInt(T) and range.maximum == std.math.maxInt(T)) {
            const U = std.meta.Int(.unsigned, @bitSizeOf(T));
            const a: T = @bitCast(@as(U, @truncate(left)));
            const b: T = @bitCast(@as(U, @truncate(right)));
            const result: T = switch (operator) {
                .addition => a +% b,
                .subtraction => a -% b,
                .multiplication => a *% b,
                .division => blk: {
                    if (b == 0) return error.DivisionByZero;
                    if (@typeInfo(T).int.signedness == .signed and a == std.math.minInt(T) and b == -1) break :blk a;
                    break :blk @divTrunc(a, b);
                },
                .modulo => blk: {
                    if (b == 0) return error.DivisionByZero;
                    if (@typeInfo(T).int.signedness == .signed and a == std.math.minInt(T) and b == -1) break :blk 0;
                    break :blk @rem(a, b);
                },
            };
            return @as(U, @bitCast(result));
        }
    }
    unreachable;
}

pub fn compareBits(operator: p.ComparisonOperator, left: u64, right: u64, range: Bounds) bool {
    const std = @import("std");
    inline for (.{ i8, i16, i32, i64, u8, u16, u32, u64 }) |T| {
        if (range.minimum == std.math.minInt(T) and range.maximum == std.math.maxInt(T)) {
            const U = std.meta.Int(.unsigned, @bitSizeOf(T));
            const a: T = @bitCast(@as(U, @truncate(left)));
            const b: T = @bitCast(@as(U, @truncate(right)));
            return switch (operator) {
                .equal => a == b,
                .not_equal => a != b,
                .less_than => a < b,
                .less_than_or_equal => a <= b,
                .greater_than => a > b,
                .greater_than_or_equal => a >= b,
            };
        }
    }
    unreachable;
}

pub fn evaluate(operator: p.BinaryOperator, left: i128, right: i128, range: Bounds) error{DivisionByZero}!i128 {
    return decode(try evaluateBits(operator, encode(left, range), encode(right, range), range), range);
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

test "integer register bits carry no implicit sign or width" {
    const std = @import("std");
    for ([_]u7{ 8, 16, 32, 64 }) |width| {
        const signed = bounds(width, true);
        const unsigned = bounds(width, false);
        const ones = encode(-1, signed);
        try std.testing.expectEqual(@as(i128, -1), decode(ones, signed));
        try std.testing.expectEqual(unsigned.maximum, decode(ones, unsigned));
        try std.testing.expect(compareBits(.less_than, ones, 0, signed));
        try std.testing.expect(compareBits(.greater_than, ones, 0, unsigned));
        try std.testing.expectEqual(@as(u64, 1), try evaluateBits(.division, encode(signed.minimum, signed), encode(signed.minimum, signed), signed));
        try std.testing.expectEqual(encode(signed.minimum, signed), try evaluateBits(.division, encode(signed.minimum, signed), ones, signed));
    }
}
