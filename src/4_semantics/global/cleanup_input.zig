const g = @import("graph.zig");
const types = @import("types.zig");

// Validate projections in a captured argument without selecting operations or
// reconstructing executable source expressions.
pub fn inputProjectionType(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, projection: @import("../primitives/schema.zig").CleanupInputProjection) !g.GlobalTypeId {
    return switch (projection) {
        .field => |index| blk: {
            const fields = types.fields(graph, ty) orelse return error.InvalidCleanupPlan;
            if (index >= fields.len) return error.InvalidCleanupPlan;
            break :blk graph.fields.items[fields.start + index].ty;
        },
        .element => |index| blk: {
            const length = types.arrayLength(graph, ty) orelse return error.InvalidCleanupPlan;
            if (index >= length) return error.InvalidCleanupPlan;
            break :blk types.arrayElement(graph, ty) orelse return error.InvalidCleanupPlan;
        },
    };
}

test "captured cleanup projections distinguish fields from bounded elements" {
    const std = @import("std");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 2 } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = .{ .file_index = 0, .offset = 0 } });
    const array = try inputProjectionType(&graph, @enumFromInt(2), .{ .field = 0 });
    try std.testing.expectEqual(@as(g.GlobalTypeId, @enumFromInt(0)), try inputProjectionType(&graph, array, .{ .element = 1 }));
    try std.testing.expectError(error.InvalidCleanupPlan, inputProjectionType(&graph, array, .{ .element = 2 }));
    try std.testing.expectError(error.InvalidCleanupPlan, inputProjectionType(&graph, array, .{ .field = 0 }));
    try std.testing.expectError(error.InvalidCleanupPlan, inputProjectionType(&graph, @enumFromInt(2), .{ .element = 0 }));
}
