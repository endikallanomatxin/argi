const graph_mod = @import("module_semantic_graph.zig");
const views = @import("module_semantic_views.zig");
const verify = @import("semantic_verify.zig");

/// Validate materialized generic shapes. Partial ModuleSGs may omit shapes while
/// migration is in progress; complete ModuleSGs require exactly one shape for
/// every resolved generic type.
pub fn verifyGenericInstances(graph: *const graph_mod.ModuleSemanticGraph, require_complete: bool) !void {
    var resolved_generic_count: usize = 0;
    for (0..views.typeCount(graph)) |index| {
        const ty = try views.typeView(graph, @enumFromInt(@as(u32, @intCast(index))));
        switch (ty) {
            .resolved => |resolved| switch (resolved) {
                .generic => resolved_generic_count += 1,
                else => {},
            },
            .external => {},
        }
    }

    if (require_complete and resolved_generic_count != graph.semantic.generic_instances.items.len)
        return error.IncompleteGenericMaterialization;

    for (graph.semantic.generic_instances.items, 0..) |instance, index| {
        if (!verify.idFits(instance.type_id, views.typeCount(graph))) return error.InvalidGenericMaterialization;
        const ty = try views.typeView(graph, instance.type_id);
        switch (ty) {
            .resolved => |resolved| switch (resolved) {
                .generic => {},
                else => return error.InvalidGenericMaterialization,
            },
            .external => return error.InvalidGenericMaterialization,
        }
        for (graph.semantic.generic_instances.items[0..index]) |previous|
            if (previous.type_id == instance.type_id) return error.InvalidGenericMaterialization;

        switch (instance.shape) {
            .structure => |shape| if (!verify.rangeFits(shape.fields, views.fieldCount(graph))) return error.InvalidGenericMaterialization,
            .choice => |shape| if (!verify.rangeFits(shape.variants, views.variantCount(graph))) return error.InvalidGenericMaterialization,
            .array => |shape| if (!verify.idFits(shape.element, views.typeCount(graph))) return error.InvalidGenericMaterialization,
            .alias => |target| if (!verify.idFits(target, views.typeCount(graph))) return error.InvalidGenericMaterialization,
        }
    }
}

test "complete generic materialization requires one shape per generic type" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.resolved_types.append(allocator, .{ .generic = .{
        .base = @enumFromInt(0),
        .arguments = .{ .start = 0, .len = 0 },
    } });
    try std.testing.expectError(error.IncompleteGenericMaterialization, verifyGenericInstances(&graph, true));
}