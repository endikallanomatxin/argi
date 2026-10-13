const std = @import("std");
const graph_mod = @import("graph.zig");

/// Standard lifecycle identities belong to bundled core. A same-named user
/// contract cannot change compiler construction or cleanup semantics.
pub fn standardDeclaration(graph: *const graph_mod.GlobalSemanticGraph, name: []const u8) ?graph_mod.GlobalDeclId {
    for (graph.declarations.items, 0..) |declaration, index| {
        if (declaration.kind != .abstract_type or !std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(index)));
        const owner = graph.moduleForDeclaration(id) orelse continue;
        if (graph.modules.items[@intFromEnum(owner)].is_bundled_core) return id;
    }
    return null;
}

pub fn initializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Init");
}

pub fn deinitializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Deinit");
}

fn participantOfOperation(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId, name: []const u8) ?graph_mod.GlobalTypeId {
    const declaration = standardDeclaration(graph, name) orelse return null;
    for (graph.contract_conformances.items) |conformance| {
        if (conformance.declaration != declaration or conformance.participants.len == 0) continue;
        for (graph.function_refs.items[conformance.operations.start..][0..conformance.operations.len]) |operation| {
            if (operation != function) continue;
            return graph.generic_arguments.items[conformance.participants.start].value.type;
        }
    }
    return null;
}
