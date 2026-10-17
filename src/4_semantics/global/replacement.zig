const g = @import("graph.zig");
const types = @import("types.zig");

// A replacement is an ordered checked transition, not an arbitrary expression
// that happens to call a destructor. Keep ordinary graph nodes inside it so
// reachability, safety and summaries observe every effect and lexical owner.
pub const Plan = struct {
    block: g.GlobalBlockId,
    prepared: g.GlobalBindingId,
    cleanup: g.GlobalAutoDeinitId,
    result: g.GlobalNodeId,
};

pub fn plan(graph: *const g.GlobalSemanticGraph, id: g.GlobalNodeId) !Plan {
    const node = graph.node(id);
    const block_id = switch (node.content) {
        .replacement_value => |block| block,
        else => return error.InvalidReplacementPlan,
    };
    const block = graph.blocks.items[@intFromEnum(block_id)];
    const nodes = graph.node_refs.items[block.nodes.start..][0..block.nodes.len];
    if (nodes.len < 3 or block.ret_val != nodes[2]) return error.InvalidReplacementPlan;
    const declaration = graph.node(nodes[0]).content;
    const cleanup = graph.node(nodes[1]).content;
    const result = graph.node(nodes[2]);
    if (declaration != .binding_declaration or cleanup != .auto_deinit_binding or
        result.content != .move_value) return error.InvalidReplacementPlan;
    const prepared = declaration.binding_declaration;
    const binding = graph.binding(prepared);
    const use = graph.node(result.content.move_value).content;
    if (binding.mutability != .constant or binding.deferred_initialization or
        binding.initialization == null or use != .binding_use or use.binding_use != prepared)
        return error.InvalidReplacementPlan;
    if (!types.equal(graph, node.ty orelse return error.InvalidReplacementPlan, binding.ty) or
        !types.equal(graph, result.ty orelse return error.InvalidReplacementPlan, binding.ty))
        return error.InvalidReplacementPlan;
    const selected = graph.auto_deinits.items[@intFromEnum(cleanup.auto_deinit_binding)];
    const previous_type = if (selected.target) |target|
        graph.node(target).ty orelse return error.InvalidReplacementPlan
    else
        graph.binding(selected.binding).ty;
    if (selected.binding == prepared or !types.equal(graph, previous_type, binding.ty))
        return error.InvalidReplacementPlan;
    // Finalization may append the prepared owner's guarded exit cleanup. The
    // result move disables it; no arbitrary effects may follow the transition.
    for (nodes[3..]) |tail| {
        const content = graph.node(tail).content;
        if (content != .auto_deinit_binding or
            graph.auto_deinits.items[@intFromEnum(content.auto_deinit_binding)].binding != prepared)
            return error.InvalidReplacementPlan;
    }
    return .{ .block = block_id, .prepared = prepared, .cleanup = cleanup.auto_deinit_binding, .result = nodes[2] };
}

test "checked replacement requires preparation cleanup and one moved result in order" {
    const std = @import("std");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "value");
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.bindings.appendSlice(a, &.{
        .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .variable },
        .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .constant, .initialization = @enumFromInt(0) },
    });
    try graph.auto_deinits.appendSlice(a, &.{
        .{ .binding = @enumFromInt(0), .deinit_fn = null },
        .{ .binding = @enumFromInt(1), .deinit_fn = null },
    });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } },
        .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(1) } },
        .{ .source = source, .ty = null, .content = .{ .auto_deinit_binding = @enumFromInt(0) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(1) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .move_value = @enumFromInt(3) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .replacement_value = @enumFromInt(0) } },
        .{ .source = source, .ty = null, .content = .{ .auto_deinit_binding = @enumFromInt(1) } },
    });
    try graph.node_refs.appendSlice(a, &.{ @enumFromInt(1), @enumFromInt(2), @enumFromInt(4), @enumFromInt(6) });
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 4 }, .ret_val = @enumFromInt(4) });
    const replacement: g.GlobalNodeId = @enumFromInt(5);
    const valid = try plan(&graph, replacement);
    try std.testing.expectEqual(@as(g.GlobalBindingId, @enumFromInt(1)), valid.prepared);
    std.mem.swap(g.GlobalNodeId, &graph.node_refs.items[0], &graph.node_refs.items[1]);
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    std.mem.swap(g.GlobalNodeId, &graph.node_refs.items[0], &graph.node_refs.items[1]);
    graph.nodes.items[3].content.binding_use = @enumFromInt(0);
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    graph.nodes.items[3].content.binding_use = @enumFromInt(1);
    graph.bindings.items[1].deferred_initialization = true;
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    graph.bindings.items[1].deferred_initialization = false;
    graph.nodes.items[6].content.auto_deinit_binding = @enumFromInt(0);
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    graph.nodes.items[6].content.auto_deinit_binding = @enumFromInt(1);
    graph.auto_deinits.items[0].binding = @enumFromInt(1);
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
}
