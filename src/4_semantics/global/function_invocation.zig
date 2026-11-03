const std = @import("std");
const graph_mod = @import("graph.zig");
const core_mod = @import("core.zig");
const types = @import("types.zig");
const call_context = @import("call_context.zig");
const primitives = @import("../primitives/schema.zig");

/// Turn a complete packed input record into an ordinary checked call. The
/// lexical owner ensures that even an effectful record expression runs once.
pub fn make(
    allocator: std.mem.Allocator,
    graph: *graph_mod.GlobalSemanticGraph,
    core: *core_mod.Resolver,
    function_id: graph_mod.GlobalFunctionId,
    packed_node: graph_mod.GlobalNodeId,
    context: call_context.Context,
    source: primitives.SourceRef,
) !?graph_mod.Node {
    if (core.functionSignaturePending(function_id)) return null;
    const function = graph.function(function_id);
    const packed_ty = graph.node(packed_node).ty orelse return null;
    if (graph.isTypeUnresolved(packed_ty)) return null;
    const fields = types.fields(graph, packed_ty) orelse return null;
    if (fields.len != function.input.len) return null;
    for (0..function.input.len) |index| {
        const expected = graph.fields.items[function.input.start + index];
        const actual = graph.fields.items[fields.start + index];
        if (!std.mem.eql(u8, graph.text(expected.name), graph.text(actual.name)) or
            !types.equal(graph, expected.ty, actual.ty)) return null;
    }

    var transaction = graph.beginTransaction(allocator);
    defer transaction.deinit();
    var committed = false;
    defer if (!committed) transaction.rollback();

    const binding: graph_mod.GlobalBindingId = @enumFromInt(graph.bindings.items.len);
    try graph.bindings.append(allocator, .{
        .name = try graph.addString(allocator, "#packed_arguments"),
        .source = source,
        .ty = packed_ty,
        .mutability = .constant,
        .initialization = packed_node,
    });
    const declaration = try appendNode(allocator, graph, source, null, .{ .binding_declaration = binding });
    const base = try appendNode(allocator, graph, source, packed_ty, .{ .binding_use = binding });
    var values: std.ArrayList(graph_mod.ValueField) = .empty;
    defer values.deinit(allocator);
    for (0..function.input.len) |index| {
        const field = graph.fields.items[function.input.start + index];
        const projection = try appendNode(allocator, graph, source, field.ty, .{ .struct_field_access = .{
            .value = base,
            .field_name = field.name,
            .field_index = @intCast(index),
        } });
        const moved = try appendNode(allocator, graph, source, field.ty, .{ .move_value = projection });
        try values.append(allocator, .{ .name = field.name, .value = moved });
    }
    const start: u32 = @intCast(graph.value_fields.items.len);
    try graph.value_fields.appendSlice(allocator, values.items);
    const input = try appendNode(allocator, graph, source, null, .{ .struct_value_literal = .{
        .fields = .{ .start = start, .len = @intCast(values.items.len) },
    } });
    if (core.matchCallInput(function.input, input) != .applicable) return null;
    if (!try core.completeRecordFieldsWithContext(function.input, input, context)) return null;
    const result_ty = try core.functionOutputType(function_id);
    const call = try appendNode(allocator, graph, source, result_ty, .{ .function_call = .{
        .callee = function_id,
        .input = input,
    } });
    const node_start: u32 = @intCast(graph.node_refs.items.len);
    try graph.node_refs.appendSlice(allocator, &.{ declaration, call });
    const block: graph_mod.GlobalBlockId = @enumFromInt(graph.blocks.items.len);
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = node_start, .len = 2 }, .ret_val = call });
    transaction.commit();
    committed = true;
    return .{ .source = source, .ty = result_ty, .content = .{ .value_sequence = block } };
}

fn appendNode(allocator: std.mem.Allocator, graph: *graph_mod.GlobalSemanticGraph, source: primitives.SourceRef, ty: ?graph_mod.GlobalTypeId, content: graph_mod.Node.Content) !graph_mod.GlobalNodeId {
    const id: graph_mod.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(allocator, .{ .source = source, .ty = ty, .content = content });
    return id;
}
