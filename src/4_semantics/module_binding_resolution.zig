const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");

/// Record bindings whose type is intentionally deferred to GlobalSema.
///
/// This is a construction relation, not part of the binding payload. Keeping it
/// sparse preserves the compact final Binding representation while preventing a
/// temporary `Any` payload from being mistaken for a known semantic type.
pub fn collect(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph) !u32 {
    graph.semantic.unresolved_binding_types.clearRetainingCapacity();

    for (graph.semantic.pending_operations.items) |operation| switch (operation) {
        .resolve_for_each => |value| try appendUnique(allocator, graph, value.binding),
        .resolve_match_case => |value| if (value.payload_binding) |binding|
            try appendUnique(allocator, graph, binding),
        else => {},
    };

    return @intCast(graph.semantic.unresolved_binding_types.items.len);
}

fn appendUnique(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph, binding: anytype) !void {
    if (@intFromEnum(binding) >= graph.semantic.bindings.items.len)
        return error.InvalidUnresolvedModuleBinding;
    for (graph.semantic.unresolved_binding_types.items) |existing|
        if (existing == binding) return;
    try graph.semantic.unresolved_binding_types.append(allocator, binding);
}

test "binding resolution collection follows pending control operations" {
    const entities = @import("module_semantic_entities.zig");
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    try graph.semantic.pending_operations.append(allocator, .{ .resolve_for_each = .{
        .node = @enumFromInt(0),
        .binding = @as(entities.ModuleBindingId, @enumFromInt(0)),
        .iterable = @enumFromInt(0),
        .body = @enumFromInt(0),
        .mode = .value,
    } });

    try std.testing.expectEqual(@as(u32, 1), try collect(allocator, &graph));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.semantic.unresolved_binding_types.items[0]));
}
