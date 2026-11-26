const std = @import("std");

/// Maps an implementation's input positions to the two sources available at
/// a virtual call. Capture order belongs to the context layout. Public input
/// order is the implementation's declaration order after removing captures.
pub const Source = union(enum) {
    capture: u32,
    argument: u32,
};

pub const ContextCapture = struct {
    input: u32,
    field: u32,
};

pub fn bind(positions: []Source, captures: []const u32) error{InvalidVirtualCapture}!void {
    for (positions) |*position| position.* = .{ .argument = 0 };
    for (captures, 0..) |position, index| {
        try bindCapture(positions, position, @intCast(index));
    }
    numberArguments(positions);
}

/// The capture payload is the field index of the borrowed context record.
pub fn bindContext(positions: []Source, captures: []const ContextCapture) error{InvalidVirtualCapture}!void {
    for (positions) |*position| position.* = .{ .argument = 0 };
    for (captures) |capture| try bindCapture(positions, capture.input, capture.field);
    numberArguments(positions);
}

fn bindCapture(positions: []Source, input: u32, capture: u32) error{InvalidVirtualCapture}!void {
    if (input >= positions.len or positions[input] == .capture) return error.InvalidVirtualCapture;
    positions[input] = .{ .capture = capture };
}

fn numberArguments(positions: []Source) void {
    var next: u32 = 0;
    for (positions) |*position| {
        if (position.* == .capture) continue;
        position.* = .{ .argument = next };
        next += 1;
    }
}

/// Classify a signature input without allocating a full position table.
pub fn sourceForInput(input: u32, captures: []const u32) Source {
    var preceding: u32 = 0;
    for (captures, 0..) |position, index| {
        if (position == input) return .{ .capture = @intCast(index) };
        if (position < input) preceding += 1;
    }
    return .{ .argument = input - preceding };
}

/// Find the full signature slot corresponding to a residual argument.
pub fn inputForArgument(positions: []const Source, argument: usize) ?usize {
    for (positions, 0..) |position, index| {
        if (position == .argument and position.argument == argument) return index;
    }
    return null;
}

test "virtual binding keeps capture order and residual argument order independent" {
    var positions: [5]Source = undefined;
    try bind(&positions, &.{ 3, 1 });
    try std.testing.expectEqualDeep([5]Source{
        .{ .argument = 0 },
        .{ .capture = 1 },
        .{ .argument = 1 },
        .{ .capture = 0 },
        .{ .argument = 2 },
    }, positions);
    for (positions, 0..) |position, index|
        try std.testing.expectEqualDeep(position, sourceForInput(@intCast(index), &.{ 3, 1 }));
    try std.testing.expectEqual(@as(?usize, 0), inputForArgument(&positions, 0));
    try std.testing.expectEqual(@as(?usize, 2), inputForArgument(&positions, 1));
    try std.testing.expectEqual(@as(?usize, 4), inputForArgument(&positions, 2));
    try std.testing.expectEqual(@as(?usize, null), inputForArgument(&positions, 3));
    try std.testing.expectError(error.InvalidVirtualCapture, bind(&positions, &.{ 1, 1 }));
    try std.testing.expectError(error.InvalidVirtualCapture, bind(&positions, &.{5}));
}

test "virtual binding selects record fields independently of input order" {
    var positions: [4]Source = undefined;
    try bindContext(&positions, &.{
        .{ .input = 2, .field = 0 },
        .{ .input = 0, .field = 3 },
    });
    try std.testing.expectEqualDeep([4]Source{
        .{ .capture = 3 },
        .{ .argument = 0 },
        .{ .capture = 0 },
        .{ .argument = 1 },
    }, positions);
    try std.testing.expectError(error.InvalidVirtualCapture, bindContext(&positions, &.{
        .{ .input = 1, .field = 0 },
        .{ .input = 1, .field = 3 },
    }));
}
