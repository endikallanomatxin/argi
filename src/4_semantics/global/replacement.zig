const g = @import("graph.zig");
const types = @import("types.zig");
const lexical = @import("lexical_storage.zig");

// One checked transition owns the write, hence the destination evaluation,
// preparation, selected cleanup and commit. Ordinary nodes remain visible to
// safety, summaries and reachability; a value sequence alone is not replacement.
pub const Plan = struct {
    block: g.GlobalBlockId,
    write: g.GlobalNodeId,
    value: g.GlobalNodeId,
    prepared: g.GlobalBindingId,
    cleanup: g.GlobalAutoDeinitId,
    result: g.GlobalNodeId,
};

pub fn plan(graph: *const g.GlobalSemanticGraph, id: g.GlobalNodeId) !Plan {
    const node = graph.node(id);
    const block_id = switch (node.content) {
        .replacement => |block| block,
        else => return error.InvalidReplacementPlan,
    };
    const transition = graph.blocks.items[@intFromEnum(block_id)];
    if (transition.nodes.len != 1) return error.InvalidReplacementPlan;
    const write_id = graph.node_refs.items[transition.nodes.start];
    if (transition.ret_val != write_id) return error.InvalidReplacementPlan;
    const write = graph.node(write_id);
    if (node.ty != write.ty) return error.InvalidReplacementPlan;
    const value_id = switch (write.content) {
        .assignment => |x| x.value,
        .pointer_assignment => |x| x.value,
        .struct_field_store => |x| x.value,
        else => return error.InvalidReplacementDestination,
    };
    const value = graph.node(value_id);
    if (value.content != .value_sequence) return error.InvalidReplacementPlan;
    const preparation = graph.blocks.items[@intFromEnum(value.content.value_sequence)];
    const nodes = graph.node_refs.items[preparation.nodes.start..][0..preparation.nodes.len];
    if (nodes.len < 3 or preparation.ret_val != nodes[2]) return error.InvalidReplacementPlan;
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
    if (!types.equal(graph, value.ty orelse return error.InvalidReplacementPlan, binding.ty) or
        !types.equal(graph, result.ty orelse return error.InvalidReplacementPlan, binding.ty))
        return error.InvalidReplacementPlan;
    const selected = graph.auto_deinits.items[@intFromEnum(cleanup.auto_deinit_binding)];
    const previous_type = if (selected.target) |target|
        graph.node(target).ty orelse return error.InvalidReplacementPlan
    else
        graph.binding(selected.binding).ty;
    if (selected.binding == prepared or !types.equal(graph, previous_type, binding.ty))
        return error.InvalidReplacementPlan;
    switch (write.content) {
        .assignment => |x| {
            if (selected.binding != x.binding or selected.target != null or
                !types.equal(graph, graph.binding(x.binding).ty, binding.ty))
                return error.InvalidReplacementDestination;
        },
        inline .pointer_assignment, .struct_field_store => |x| {
            const target = x.cleanup_target orelse return error.InvalidReplacementDestination;
            const chosen = selected.target orelse return error.InvalidReplacementDestination;
            if (lexical.root(graph, target) != selected.binding or !lexical.equal(graph, chosen, target))
                return error.InvalidReplacementDestination;
        },
        else => unreachable,
    }
    // Guarded exit cleanup of the prepared temporary is allowed after its
    // move. No unrelated effects may be hidden between cleanup and commit.
    for (nodes[3..]) |tail| {
        const content = graph.node(tail).content;
        if (content != .auto_deinit_binding or
            graph.auto_deinits.items[@intFromEnum(content.auto_deinit_binding)].binding != prepared)
            return error.InvalidReplacementPlan;
    }
    return .{ .block = block_id, .write = write_id, .value = value_id, .prepared = prepared, .cleanup = cleanup.auto_deinit_binding, .result = nodes[2] };
}

test "checked replacement owns its destination preparation cleanup and commit" {
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
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .value_sequence = @enumFromInt(0) } },
        .{ .source = source, .ty = null, .content = .{ .auto_deinit_binding = @enumFromInt(1) } },
    });
    try graph.node_refs.appendSlice(a, &.{ @enumFromInt(1), @enumFromInt(2), @enumFromInt(4), @enumFromInt(6) });
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 4 }, .ret_val = @enumFromInt(4) });
    const value: g.GlobalNodeId = @enumFromInt(5);
    const write: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = value } } });
    const transition_start: u32 = @intCast(graph.node_refs.items.len);
    try graph.node_refs.append(a, write);
    try graph.blocks.append(a, .{ .nodes = .{ .start = transition_start, .len = 1 }, .ret_val = write });
    const replacement: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = null, .content = .{ .replacement = @enumFromInt(1) } });
    const valid = try plan(&graph, replacement);
    try std.testing.expectEqual(write, valid.write);
    try std.testing.expectEqual(value, valid.value);
    graph.nodes.items[@intFromEnum(write)].content.assignment.binding = @enumFromInt(1);
    try std.testing.expectError(error.InvalidReplacementDestination, plan(&graph, replacement));
    graph.nodes.items[@intFromEnum(write)].content.assignment.binding = @enumFromInt(0);
    graph.blocks.items[1].ret_val = null;
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    graph.blocks.items[1].ret_val = write;
    graph.blocks.items[1].nodes.len = 2;
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, replacement));
    graph.blocks.items[1].nodes.len = 1;
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    const target: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(0) } });
    const other: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(1) } });
    const pointer: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .address_of = target } });
    graph.auto_deinits.items[0].target = target;
    graph.nodes.items[@intFromEnum(write)].content = .{ .pointer_assignment = .{ .pointer = pointer, .value = value, .cleanup_target = target } };
    _ = try plan(&graph, replacement);
    graph.nodes.items[@intFromEnum(write)].content.pointer_assignment.cleanup_target = null;
    try std.testing.expectError(error.InvalidReplacementDestination, plan(&graph, replacement));
    graph.nodes.items[@intFromEnum(write)].content.pointer_assignment.cleanup_target = target;
    graph.auto_deinits.items[0].target = other;
    try std.testing.expectError(error.InvalidReplacementDestination, plan(&graph, replacement));
    graph.auto_deinits.items[0].target = null;
    graph.nodes.items[@intFromEnum(write)].content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = value } };
    // A generic value sequence is not by itself a lifecycle transition.
    try std.testing.expectError(error.InvalidReplacementPlan, plan(&graph, value));
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
