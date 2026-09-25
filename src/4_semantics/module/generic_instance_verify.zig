const graph_mod = @import("graph.zig");
const views = @import("views.zig");
const verify = @import("../semantic_verify.zig");

/// Validate generic shapes owned by ModuleSG. A resolved generic type is a
/// durable request for GlobalSema and does not require a module-local shape;
/// imported declarations and cross-module canonical identity are unavailable
/// at this boundary. GlobalSG verifies complete materialization after linking.
pub fn verifyGenericInstances(graph: *const graph_mod.ModuleSemanticGraph, require_complete: bool) !void {
    _ = require_complete;

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

test "complete modules may defer generic shapes to GlobalSema" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.types.append(allocator, .{ .resolved = .{ .generic = .{
        .base = @enumFromInt(0),
        .arguments = .{ .start = 0, .len = 0 },
    } } });
    try verifyGenericInstances(&graph, true);
}
