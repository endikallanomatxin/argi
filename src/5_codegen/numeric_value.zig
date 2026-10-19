const std = @import("std");
const p = @import("../4_semantics/primitives/schema.zig");

// Execution scalars retain their representation. Semantic literals and checked
// range calculations may be wider; they are narrowed at the execution boundary.
pub const Value = union(enum) {
    int8: i8,
    int16: i16,
    int32: i32,
    int64: i64,
    uint8: u8,
    uint16: u16,
    uint32: u32,
    uint64: u64,
    float16: f16,
    float32: f32,
    float64: f64,

    pub fn fromInteger(value: i128, range: p.IntegerRange) Value {
        inline for (.{ i8, i16, i32, i64, u8, u16, u32, u64 }) |T| {
            if (range.minimum == std.math.minInt(T) and range.maximum == std.math.maxInt(T)) {
                const narrowed: T = if (@typeInfo(T).int.signedness == .signed)
                    @truncate(value)
                else
                    @truncate(@as(u128, @bitCast(value)));
                return @unionInit(Value, tag(T), narrowed);
            }
        }
        unreachable; // Argi's supported integer widths are checked before execution.
    }

    pub fn integer(self: Value) i128 {
        return switch (self) {
            inline .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64 => |value| value,
            else => unreachable,
        };
    }

    pub fn binary(left: Value, operator: p.BinaryOperator, right: Value) error{ DivisionByZero, MismatchedNumericTypes }!Value {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return error.MismatchedNumericTypes;
        return switch (left) {
            inline else => |a, kind| blk: {
                const b = @field(right, @tagName(kind));
                const T = @TypeOf(a);
                const result: T = if (@typeInfo(T) == .int) switch (operator) {
                    .addition => a +% b,
                    .subtraction => a -% b,
                    .multiplication => a *% b,
                    .division => {
                        if (b == 0) return error.DivisionByZero;
                        if (@typeInfo(T).int.signedness == .signed and a == std.math.minInt(T) and b == -1) break :blk @unionInit(Value, @tagName(kind), a);
                        break :blk @unionInit(Value, @tagName(kind), @divTrunc(a, b));
                    },
                    .modulo => {
                        if (b == 0) return error.DivisionByZero;
                        if (@typeInfo(T).int.signedness == .signed and a == std.math.minInt(T) and b == -1) break :blk @unionInit(Value, @tagName(kind), 0);
                        break :blk @unionInit(Value, @tagName(kind), @rem(a, b));
                    },
                } else switch (operator) {
                    .addition => a + b,
                    .subtraction => a - b,
                    .multiplication => a * b,
                    .division => a / b,
                    .modulo => @rem(a, b),
                };
                break :blk @unionInit(Value, @tagName(kind), result);
            },
        };
    }

    pub fn compare(left: Value, operator: p.ComparisonOperator, right: Value) error{MismatchedNumericTypes}!bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return error.MismatchedNumericTypes;
        return switch (left) {
            inline else => |a, kind| blk: {
                const b = @field(right, @tagName(kind));
                break :blk switch (operator) {
                    .equal => a == b,
                    .not_equal => if (@typeInfo(@TypeOf(a)) == .float)
                        !std.math.isNan(a) and !std.math.isNan(b) and a != b
                    else
                        a != b,
                    .less_than => a < b,
                    .less_than_or_equal => a <= b,
                    .greater_than => a > b,
                    .greater_than_or_equal => a >= b,
                };
            },
        };
    }
};

fn tag(comptime T: type) []const u8 {
    return switch (T) {
        i8 => "int8",
        i16 => "int16",
        i32 => "int32",
        i64 => "int64",
        u8 => "uint8",
        u16 => "uint16",
        u32 => "uint32",
        u64 => "uint64",
        else => @compileError("not an execution integer"),
    };
}

test "numeric values execute with their integer widths and float precision" {
    inline for (.{ i8, i16, i32, i64, u8, u16, u32, u64 }) |T| {
        const maximum = @unionInit(Value, tag(T), std.math.maxInt(T));
        const one = @unionInit(Value, tag(T), 1);
        const wrapped = try maximum.binary(.addition, one);
        try std.testing.expectEqual(@as(T, std.math.minInt(T)), @field(wrapped, tag(T)));
    }
    inline for (.{ i8, i16, i32, i64 }) |T| {
        const minimum = @unionInit(Value, tag(T), std.math.minInt(T));
        const negative_one = @unionInit(Value, tag(T), -1);
        try std.testing.expectEqualDeep(minimum, try minimum.binary(.division, negative_one));
        try std.testing.expectEqual(@as(i128, 0), (try minimum.binary(.modulo, negative_one)).integer());
        try std.testing.expectError(error.DivisionByZero, minimum.binary(.division, @unionInit(Value, tag(T), 0)));
    }
    const half: Value = .{ .float16 = 2048 };
    try std.testing.expectEqual(@as(f16, 2048), (try half.binary(.addition, .{ .float16 = 1 })).float16);
    const single: Value = .{ .float32 = 16777216 };
    const double: Value = .{ .float64 = 16777216 };
    try std.testing.expectEqual(@as(f32, 16777216), (try single.binary(.addition, .{ .float32 = 1 })).float32);
    try std.testing.expectEqual(@as(f64, 16777217), (try double.binary(.addition, .{ .float64 = 1 })).float64);
    const nan: Value = .{ .float32 = std.math.nan(f32) };
    try std.testing.expect(!try nan.compare(.less_than, single));
    try std.testing.expect(!try nan.compare(.equal, nan));
    try std.testing.expect(!try nan.compare(.not_equal, single));
    try std.testing.expectError(error.MismatchedNumericTypes, single.binary(.addition, double));
    try std.testing.expect(@sizeOf(Value) <= 16);
}
