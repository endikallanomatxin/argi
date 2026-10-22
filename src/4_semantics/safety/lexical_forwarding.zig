const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const primitives = @import("../primitives/schema.zig");

// Exact identity is a lexical proof, not a consequence of may-dependencies.
// Each owning link must move. Reference forwarding may coexist with independent
// moved owners; unknown calls and control flow still cannot certify identity.
pub fn proves(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, relation: primitives.MethodSafetyContract.Dependency, owning: bool) !bool {
    const block = graph.blocks.items[@intFromEnum(function.body orelse return false)];
    if (relation.input_index >= function.input_bindings.len or relation.output_index >= function.output_bindings.len) return false;
    const input = graph.binding_refs.items[function.input_bindings.start + relation.input_index];
    const output = graph.binding_refs.items[function.output_bindings.start + relation.output_index];
    if (!owning and graph.binding(input).mutability != .constant) return false;
    var links = std.array_list.Managed(graph_mod.GlobalBindingId).init(allocator);
    defer links.deinit();
    try links.append(input);
    var assigned = false;
    for (graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |id| switch (graph.node(id).content) {
        .binding_declaration => |binding| {
            const record = graph.binding(binding);
            if (record.deferred_initialization or binding == output or linksContains(links.items, binding)) return false;
            const initializer = record.initialization orelse return false;
            if (!isForwardingLink(graph, initializer, links.items, owning)) {
                if (owning or !independentMove(graph, initializer, links.items, output)) return false;
                continue;
            }
            try links.append(binding);
        },
        .assignment => |assignment| {
            if (assignment.binding != output or assigned) return false;
            if (!isForwardingLink(graph, assignment.value, links.items, owning)) return false;
            assigned = true;
        },
        .auto_deinit_binding => {},
        .return_statement => |ret| return ret.expression == null and assigned,
        else => return false,
    };
    return assigned;
}

fn linksContains(links: []const graph_mod.GlobalBindingId, binding: graph_mod.GlobalBindingId) bool {
    return std.mem.indexOfScalar(graph_mod.GlobalBindingId, links, binding) != null;
}

fn isForwardingLink(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalNodeId, links: []const graph_mod.GlobalBindingId, owning: bool) bool {
    var expression = graph.node(id).content;
    if (owning) {
        if (expression != .move_value) return false;
        expression = graph.node(expression.move_value).content;
    }
    return expression == .binding_use and linksContains(links, expression.binding_use);
}

fn independentMove(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalNodeId, links: []const graph_mod.GlobalBindingId, output: graph_mod.GlobalBindingId) bool {
    const expression = graph.node(id).content;
    if (expression != .move_value) return false;
    const moved = graph.node(expression.move_value).content;
    return moved == .binding_use and moved.binding_use != output and !linksContains(links, moved.binding_use);
}

test "reference forwarding permits independent moved owners without consuming its source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
    });
    for (0..4) |index| try graph.bindings.append(a, .{
        .name = .{ .start = 0, .len = 0 },
        .source = source,
        .ty = if (index < 2) @enumFromInt(1) else @enumFromInt(0),
        .mutability = if (index == 1) .variable else .constant,
        .initialization = if (index == 3) @enumFromInt(1) else null,
    });
    try graph.binding_refs.appendSlice(a, &.{ @enumFromInt(0), @enumFromInt(2), @enumFromInt(1) });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(2) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .move_value = @enumFromInt(0) } },
        .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(3) } },
        .{ .source = source, .ty = @enumFromInt(1), .content = .{ .binding_use = @enumFromInt(0) } },
        .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(1), .value = @enumFromInt(3) } } },
        .{ .source = source, .ty = @enumFromInt(1), .content = .{ .move_value = @enumFromInt(3) } },
    });
    try graph.node_refs.appendSlice(a, &.{ @enumFromInt(2), @enumFromInt(4) });
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 2 } });
    const function: graph_mod.Function = .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 2 },
        .output = .{ .start = 2, .len = 1 },
        .input_bindings = .{ .start = 0, .len = 2 },
        .output_bindings = .{ .start = 2, .len = 1 },
        .body = @enumFromInt(0),
    };
    const relation: primitives.MethodSafetyContract.Dependency = .{ .input_index = 0, .output_index = 0 };
    try std.testing.expect(try proves(a, &graph, function, relation, false));
    try std.testing.expect(!try proves(a, &graph, function, relation, true));
    graph.bindings.items[3].initialization = @enumFromInt(5);
    try std.testing.expect(!try proves(a, &graph, function, relation, false));
}
