const graph_mod = @import("module_semantic_graph.zig");

/// Enforce the ModuleSema -> GlobalSema contract.
///
/// A pending operation must describe semantic intent precisely enough that one
/// global subsystem owns it. `PendingExpressionKind.other` was a migration
/// escape hatch that erased that intent; allowing it past this boundary turns
/// missing local lowering into a late, order-dependent GlobalSema failure.
pub fn verify(graph: *const graph_mod.ModuleSemanticGraph) !void {
    for (graph.semantic.pending_operations.items) |operation| switch (operation) {
        .resolve_expression => |expression| if (expression.kind == .other)
            return error.GenericPendingSemanticHole,
        else => {},
    };
}

test "module pending contract rejects generic expression holes" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.pending_operations.append(allocator, .{ .resolve_expression = .{
        .node = @enumFromInt(0),
        .kind = .other,
    } });
    try std.testing.expectError(error.GenericPendingSemanticHole, verify(&graph));
}
