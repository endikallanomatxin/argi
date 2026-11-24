const std = @import("std");

/// Maps an implementation's input positions to the two sources available at
/// a virtual call. Capture order belongs to the context layout. Public input
/// order is the implementation's declaration order after removing captures.
pub const Source = union(enum) {
    capture: u32,
    argument: u32,
};

pub fn bind(positions: []Source, captures: []const u32) error{InvalidVirtualCapture}!void {
    for (positions) |*position| position.* = .{ .argument = 0 };
    for (captures, 0..) |position, index| {
        if (position >= positions.len or positions[position] == .capture) return error.InvalidVirtualCapture;
        positions[position] = .{ .capture = @intCast(index) };
    }
    var next: u32 = 0;
    for (positions) |*position| {
        if (position.* == .capture) continue;
        position.* = .{ .argument = next };
        next += 1;
    }
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
    try std.testing.expectError(error.InvalidVirtualCapture, bind(&positions, &.{ 1, 1 }));
    try std.testing.expectError(error.InvalidVirtualCapture, bind(&positions, &.{5}));
}
