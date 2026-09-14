from pathlib import Path

p = Path('src/4_semantics/global/ownership.zig')
s = p.read_text()
marker = 'test "error propagation cleanup captures active lexical obligations" {'
start = s.index(marker)
s = s[:start] + r'''test "error propagation cleanup captures active lexical obligations" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const empty = try graph.addString(allocator, "");

    const deferred_node: global_sg.GlobalNodeId = @enumFromInt(0);
    const propagation_node: global_sg.GlobalNodeId = @enumFromInt(1);
    const assignment_node: global_sg.GlobalNodeId = @enumFromInt(2);
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .int_literal = 0 },
    });
    try graph.error_propagations.append(allocator, .{
        .errable_value = deferred_node,
        .cleanup_nodes = .{ .start = 0, .len = 0 },
        .ok_variant = @enumFromInt(0),
        .ok_value_field_index = null,
        .error_variant = @enumFromInt(0),
        .propagated_errable_type = int_ty,
        .propagated_error_variant = @enumFromInt(0),
        .ok_payload_type = int_ty,
        .error_payload_type = int_ty,
        .propagated_error_payload_type = int_ty,
        .diagnostic_line = 0,
        .diagnostic_column = 0,
        .diagnostic_source_line = empty,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .error_propagation = @enumFromInt(0) },
    });
    try graph.bindings.append(allocator, .{
        .name = empty,
        .source = source,
        .ty = int_ty,
        .mutability = .variable,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = propagation_node } },
    });

    var core: core_mod.Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
    };
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = &core,
    };
    defer resolver.deinit();

    try resolver.finalizeExpressionCleanup(assignment_node, &.{}, &.{deferred_node});
    const cleanup = graph.error_propagations.items[0].cleanup_nodes;
    try std.testing.expectEqual(@as(u32, 1), cleanup.len);
    try std.testing.expectEqual(deferred_node, graph.node_refs.items[cleanup.start]);
}
'''
p.write_text(s)
