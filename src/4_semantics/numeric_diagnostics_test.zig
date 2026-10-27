//! Source-level checks use the same frontend and Safety path as program builds.
const std = @import("std");
const checkSource = @import("source_test_support.zig").checkSource;

const LiteralCase = struct {
    name: []const u8,
    ty: []const u8,
    literal: []const u8,
    mutable: bool = false,
    diagnostic: ?[]const u8 = null,
    marker: ?[]const u8 = null,
};

fn checkLiteral(case: LiteralCase) !void {
    const source = try std.fmt.allocPrint(std.testing.allocator, "main := () -> () {{\n    value {s} {s} = {s}\n}}\n", .{ if (case.mutable) "::" else ":", case.ty, case.literal });
    defer std.testing.allocator.free(source);
    try checkSource(case.name, source, case.marker orelse case.literal, case.diagnostic, true);
}

test "source numeric diagnostics enforce integer boundaries" {
    const cases = [_]LiteralCase{
        .{ .name = "int8_upper", .ty = "Int8", .literal = "128", .diagnostic = "integer literal 128 does not fit in 'Int8' (min -128, max 127)" },
        .{ .name = "int8_lower", .ty = "Int8", .literal = "-129", .diagnostic = "integer literal -129 does not fit in 'Int8' (min -128, max 127)" },
        .{ .name = "int64_upper", .ty = "Int64", .literal = "9223372036854775808", .diagnostic = "integer literal 9223372036854775808 does not fit in 'Int64' (min -9223372036854775808, max 9223372036854775807)" },
        .{ .name = "int64_lower", .ty = "Int64", .literal = "-9223372036854775809", .diagnostic = "integer literal -9223372036854775809 does not fit in 'Int64' (min -9223372036854775808, max 9223372036854775807)" },
        .{ .name = "unsigned_negative", .ty = "UInt64", .literal = "-1", .diagnostic = "integer literal -1 does not fit in 'UInt64' (min 0, max 18446744073709551615)" },
        .{ .name = "int8_max", .ty = "Int8", .literal = "127" },
        .{ .name = "int8_min", .ty = "Int8", .literal = "-128" },
        .{ .name = "int64_max", .ty = "Int64", .literal = "9223372036854775807" },
        .{ .name = "int64_min", .ty = "Int64", .literal = "-9223372036854775808" },
        .{ .name = "unsigned_zero", .ty = "UInt64", .literal = "0" },
        .{ .name = "unsigned_max", .ty = "UInt64", .literal = "18446744073709551615" },
    };
    for (cases) |case| if (case.diagnostic == null) try checkLiteral(case);
    for (cases) |case| if (case.diagnostic != null) try checkLiteral(case);
}

test "source numeric diagnostics reject implicit integer float conversions" {
    const cases = [_]LiteralCase{
        .{ .name = "float_to_integer", .ty = "UInt32", .literal = "1.5", .mutable = true, .marker = "value", .diagnostic = "cannot assign numeric value of type 'Float32' to destination of type 'UInt32'; implicit numeric conversion is not supported" },
        .{ .name = "integer_to_float", .ty = "Float32", .literal = "1", .mutable = true, .marker = "value", .diagnostic = "cannot assign numeric value of type 'Int32' to destination of type 'Float32'; implicit numeric conversion is not supported" },
        .{ .name = "integer", .ty = "UInt32", .literal = "1", .mutable = true },
        .{ .name = "float", .ty = "Float32", .literal = "1.5", .mutable = true },
    };
    for (cases) |case| try checkLiteral(case);
}

test "source numeric diagnostics locate overflowing specialized literals" {
    const source =
        \\maximum := #(.T: Type) () -> (.result: T) { result = 18446744073709551616 }
        \\main := () -> () { value ::= maximum#(.T: UInt64)().result }
    ;
    try checkSource("generic_magnitude", source, "18446744073709551616", "integer literal magnitude exceeds the supported 64-bit range", true);
}
