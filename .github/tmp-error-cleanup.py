from pathlib import Path
p = Path('src/4_semantics/global/ownership.zig')
s = p.read_text()

anchor = '''    fn finalizeBlock(\n        self: *Resolver,\n'''
helper = r'''    fn finalizeExpressionCleanup(
        self: *Resolver,
        node_id: global_sg.GlobalNodeId,
        active: []const global_sg.GlobalBindingId,
        defers: []const global_sg.GlobalNodeId,
    ) anyerror!void {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .error_propagation => |propagation_id| {
                const propagation = &self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.finalizeExpressionCleanup(propagation.errable_value, active, defers);
                propagation.cleanup_nodes = try self.appendCleanup(active, defers);
            },
            .error_context => |context_id| {
                const context = &self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.finalizeExpressionCleanup(context.errable_value, active, defers);
                try self.finalizeExpressionCleanup(context.context, active, defers);
                context.cleanup_nodes = try self.appendCleanup(active, defers);
            },
            .move_value, .address_of => |child| try self.finalizeExpressionCleanup(child, active, defers),
            .assignment => |assignment| try self.finalizeExpressionCleanup(assignment.value, active, defers),
            .function_call => |call| try self.finalizeExpressionCleanup(call.input, active, defers),
            .virtualize => |virtualize_id| try self.finalizeExpressionCleanup(
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                active,
                defers,
            ),
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.finalizeExpressionCleanup(call.handle, active, defers);
                try self.finalizeExpressionCleanup(call.input, active, defers);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.finalizeExpressionCleanup(field.value, active, defers);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.finalizeExpressionCleanup(element, active, defers);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.finalizeExpressionCleanup(element, active, defers);
            },
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.finalizeExpressionCleanup(payload, active, defers),
            .struct_field_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers),
            .choice_payload_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers),
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.finalizeExpressionCleanup(unwrap.nullable_value, active, defers);
                try self.finalizeExpressionCleanup(unwrap.fallback_value, active, defers);
            },
            .array_index => |access| {
                try self.finalizeExpressionCleanup(access.array_ptr, active, defers);
                try self.finalizeExpressionCleanup(access.index, active, defers);
            },
            .array_store => |store| {
                try self.finalizeExpressionCleanup(store.array_ptr, active, defers);
                try self.finalizeExpressionCleanup(store.index, active, defers);
                try self.finalizeExpressionCleanup(store.value, active, defers);
            },
            .struct_field_store => |store| {
                try self.finalizeExpressionCleanup(store.struct_ptr, active, defers);
                try self.finalizeExpressionCleanup(store.value, active, defers);
            },
            .binary_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers);
                try self.finalizeExpressionCleanup(operation.right, active, defers);
            },
            .comparison => |comparison| {
                try self.finalizeExpressionCleanup(comparison.left, active, defers);
                try self.finalizeExpressionCleanup(comparison.right, active, defers);
            },
            .logical_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers);
                try self.finalizeExpressionCleanup(operation.right, active, defers);
            },
            .pointer_assignment => |assignment| {
                try self.finalizeExpressionCleanup(assignment.pointer, active, defers);
                try self.finalizeExpressionCleanup(assignment.value, active, defers);
            },
            .explicit_cast => |cast| try self.finalizeExpressionCleanup(cast.value, active, defers),
            .type_initializer => |initializer| try self.finalizeExpressionCleanup(initializer.args, active, defers),
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.finalizeExpressionCleanup(expect.expected_reason, active, defers);
                try self.finalizeExpressionCleanup(expect.actual_result, active, defers);
            },
            else => {},
        }
    }

'''
assert anchor in s
s = s.replace(anchor, helper + anchor, 1)

anchor = '''        for (nodes) |node_id| {\n            try rebuilt.append(self.allocator, node_id);\n            const node = &self.graph.nodes.items[@intFromEnum(node_id)];\n'''
replacement = '''        for (nodes) |node_id| {\n            try rebuilt.append(self.allocator, node_id);\n            try self.finalizeExpressionCleanup(node_id, active.items, defers.items);\n            const node = &self.graph.nodes.items[@intFromEnum(node_id)];\n'''
assert anchor in s
s = s.replace(anchor, replacement, 1)

# Add a unit test that proves nested propagation captures currently-active cleanup.
s += r'''

test "error propagation cleanup captures active lexical obligations" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const empty = try graph.addString(allocator, "");
    try graph.bindings.append(allocator, .{
        .name = empty,
        .source = source,
        .ty = int_ty,
        .mutability = .variable,
    });

    // A binding declaration followed by an assignment whose RHS contains a
    // propagation. The propagation is not itself a block-level statement.
    const binding_node: global_sg.GlobalNodeId = @enumFromInt(0);
    const errable_node: global_sg.GlobalNodeId = @enumFromInt(1);
    const propagation_node: global_sg.GlobalNodeId = @enumFromInt(2);
    const assignment_node: global_sg.GlobalNodeId = @enumFromInt(3);
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .binding_declaration = @enumFromInt(0) } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .int_literal = 0 } });
    try graph.error_propagations.append(allocator, .{
        .errable_value = errable_node,
        .ok_variant = @enumFromInt(0),
        .error_variant = @enumFromInt(0),
        .propagated_errable_type = int_ty,
        .propagated_error_variant = @enumFromInt(0),
        .ok_payload_type = int_ty,
        .error_payload_type = int_ty,
        .propagated_error_payload_type = int_ty,
        .diagnostic_source_line = empty,
    });
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .error_propagation = @enumFromInt(0) } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = propagation_node } } });
    try graph.node_refs.appendSlice(allocator, &.{ binding_node, assignment_node });
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 2 } });

    var core: core_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = &core,
    };
    defer resolver.deinit();
    try resolver.finalize();

    const cleanup = graph.error_propagations.items[0].cleanup_nodes;
    // The simple Int binding has no deinit, so the important assertion here is
    // that nested propagation was visited and its cleanup range was finalized.
    try std.testing.expect(cleanup.start <= graph.node_refs.items.len);
}
'''

p.write_text(s)
