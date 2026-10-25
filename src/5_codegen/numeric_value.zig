const std = @import("std");
const p = @import("../4_semantics/primitives/schema.zig");

// Floating operations preserve the checked precision. Integer register bits
// and width-directed operations live in integer_arithmetic.zig.
pub const Value = union(enum) {
    float16: f16,
    float32: f32,
    float64: f64,

    pub fn binary(left: Value, operator: p.BinaryOperator, right: Value) error{MismatchedNumericTypes}!Value {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return error.MismatchedNumericTypes;
        return switch (left) {
            inline else => |a, kind| blk: {
                const b = @field(right, @tagName(kind));
                const T = @TypeOf(a);
                const result: T = switch (operator) {
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
                    .not_equal => !std.math.isNan(a) and !std.math.isNan(b) and a != b,
                    .less_than => a < b,
                    .less_than_or_equal => a <= b,
                    .greater_than => a > b,
                    .greater_than_or_equal => a >= b,
                };
            },
        };
    }
};

test "floating values execute with their concrete precision" {
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
