const std = @import("std");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const graph_mod = @import("graph.zig");

pub fn verify(
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    diagnostics: *diagnostics_mod.Diagnostics,
    selected_test_name: ?[]const u8,
) !void {
    var state = State{
        .allocator = allocator,
        .graph = graph,
        .diagnostics = diagnostics,
        .seen_once = std.AutoHashMap(graph_mod.GlobalFunctionId, graph_mod.GlobalNodeId).init(allocator),
        .active_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
    };
    defer state.seen_once.deinit();
    defer state.active_functions.deinit();

    if (selected_test_name) |wanted| {
        for (graph.functions.items, 0..) |function, raw| {
            if (!function.flags.is_test) continue;
            const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, graph.text(declaration.name), wanted)) continue;
            try state.walkFunction(@enumFromInt(@as(u32, @intCast(raw))));
        }
    } else {
        for (graph.functions.items, 0..) |function, raw| {
            if (function.flags.is_test) continue;
            const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, graph.text(declaration.name), "main")) continue;
            try state.walkFunction(@enumFromInt(@as(u32, @intCast(raw))));
        }
    }

    if (state.had_error) return error.Reported;
}

const State = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    diagnostics: *diagnostics_mod.Diagnostics,
    seen_once: std.AutoHashMap(graph_mod.GlobalFunctionId, graph_mod.GlobalNodeId),
    active_functions: std.AutoHashMap(graph_mod.GlobalFunctionId, void),
    had_error: bool = false,

    fn walkFunction(self: *State, function_id: graph_mod.GlobalFunctionId) anyerror!void {
        if (self.active_functions.contains(function_id)) return;
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return;
        try self.active_functions.put(function_id, {});
        defer _ = self.active_functions.remove(function_id);
        try self.walkBlock(body);
    }

    fn walkBlock(self: *State, block_id: graph_mod.GlobalBlockId) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id|
            try self.walkNode(node_id);
    }

    fn walkNode(self: *State, node_id: graph_mod.GlobalNodeId) anyerror!void {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .declaration,
            .binding_use,
            .reach_directive,
            .int_literal,
            .float_literal,
            .char_literal,
            .string_literal,
            .bool_literal,
            .break_statement,
            .continue_statement,
            .type_literal,
            => {},
            .binding_declaration => |binding_id| {
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (binding.initialization) |value| try self.walkNode(value);
            },
            .move_value => |value| try self.walkNode(value),
            .assignment => |assignment| try self.walkNode(assignment.value),
            .auto_deinit_binding => |auto_id| {
                const auto = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
                if (auto.input) |input| try self.walkNode(input);
                if (auto.deinit_fn) |callee| try self.walkCall(node_id, callee);
            },
            .function_call => |call| {
                try self.walkNode(call.input);
                if (call.consumes_auto_deinit) |value| try self.walkNode(value);
                if (call.initializes_auto_deinit) |value| try self.walkNode(value);
                try self.walkCall(node_id, call.callee);
            },
            .virtualize => |id| {
                const virtualize = self.graph.virtualizes.items[@intFromEnum(id)];
                try self.walkNode(virtualize.value);
            },
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.walkNode(call.handle);
                try self.walkNode(call.input);
                if (call.consumes_auto_deinit) |value| try self.walkNode(value);
                const registry = self.graph.virtual_registries.items[@intFromEnum(call.safety_methods)];
                for (self.graph.function_refs.items[registry.implementations.start..][0..registry.implementations.len]) |callee|
                    try self.walkCall(node_id, callee);
            },
            .code_block => |block| try self.walkBlock(block),
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value|
                    try self.walkNode(value);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.walkNode(field.value);
            },
            .struct_field_access => |access| try self.walkNode(access.value),
            .choice_literal => |literal| if (literal.payload) |payload| try self.walkNode(payload),
            .choice_payload_access => |access| try self.walkNode(access.value),
            .nullable_unwrap_or => |id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                try self.walkNode(unwrap.nullable_value);
                try self.walkNode(unwrap.fallback_value);
            },
            .testing_expect_error => |id| {
                const value = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                try self.walkNode(value.expected_reason);
                try self.walkNode(value.actual_result);
                try self.walkCall(node_id, value.test_fail_function);
            },
            .error_propagation => |id| {
                const value = self.graph.error_propagations.items[@intFromEnum(id)];
                try self.walkNode(value.errable_value);
                for (self.graph.node_refs.items[value.cleanup_nodes.start..][0..value.cleanup_nodes.len]) |cleanup|
                    try self.walkNode(cleanup);
            },
            .error_context => |id| {
                const value = self.graph.error_contexts.items[@intFromEnum(id)];
                try self.walkNode(value.errable_value);
                try self.walkNode(value.context);
                for (self.graph.node_refs.items[value.cleanup_nodes.start..][0..value.cleanup_nodes.len]) |cleanup|
                    try self.walkNode(cleanup);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value|
                    try self.walkNode(value);
            },
            .array_index => |access| {
                try self.walkNode(access.array_ptr);
                try self.walkNode(access.index);
            },
            .array_store => |store| {
                try self.walkNode(store.array_ptr);
                try self.walkNode(store.index);
                try self.walkNode(store.value);
            },
            .struct_field_store => |store| {
                try self.walkNode(store.struct_ptr);
                try self.walkNode(store.value);
            },
            .binary_operation => |operation| {
                try self.walkNode(operation.left);
                try self.walkNode(operation.right);
            },
            .comparison => |operation| {
                try self.walkNode(operation.left);
                try self.walkNode(operation.right);
            },
            .logical_operation => |operation| {
                try self.walkNode(operation.left);
                try self.walkNode(operation.right);
            },
            .return_statement => |ret| {
                if (ret.expression) |value| try self.walkNode(value);
                for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |cleanup|
                    try self.walkNode(cleanup);
            },
            .if_statement => |statement| {
                try self.walkNode(statement.condition);
                try self.walkBlock(statement.then_block);
                if (statement.else_block) |block| try self.walkBlock(block);
            },
            .while_statement => |statement| {
                try self.walkNode(statement.condition);
                try self.walkBlock(statement.body);
            },
            .for_statement => |statement| {
                if (statement.init) |value| try self.walkNode(value);
                try self.walkNode(statement.condition);
                if (statement.increment) |value| try self.walkNode(value);
                try self.walkBlock(statement.body);
            },
            .switch_statement => |id| {
                const value = self.graph.switches.items[@intFromEnum(id)];
                try self.walkNode(value.expression);
                for (self.graph.switch_cases.items[value.cases.start..][0..value.cases.len]) |case| {
                    try self.walkNode(case.value);
                    try self.walkBlock(case.body);
                }
                if (value.default_block) |block| try self.walkBlock(block);
            },
            .address_of => |value| try self.walkNode(value),
            .dereference => |value| try self.walkNode(value.pointer),
            .pointer_assignment => |assignment| {
                try self.walkNode(assignment.pointer);
                try self.walkNode(assignment.value);
            },
            .type_initializer => |initializer| {
                try self.walkNode(initializer.args);
                try self.walkCall(node_id, initializer.init_fn);
            },
            .explicit_cast => |cast| try self.walkNode(cast.value),
        }
    }

    fn walkCall(self: *State, call_node: graph_mod.GlobalNodeId, callee: graph_mod.GlobalFunctionId) anyerror!void {
        const function = self.graph.functions.items[@intFromEnum(callee)];
        if (function.flags.is_once) try self.consumeOnce(call_node, callee);
        try self.walkFunction(callee);
    }

    fn consumeOnce(self: *State, call_node: graph_mod.GlobalNodeId, callee: graph_mod.GlobalFunctionId) anyerror!void {
        const result = try self.seen_once.getOrPut(callee);
        if (!result.found_existing) {
            result.value_ptr.* = call_node;
            return;
        }

        const declaration = self.graph.declarations.items[@intFromEnum(self.graph.functions.items[@intFromEnum(callee)].declaration)];
        const first_node = self.graph.nodes.items[@intFromEnum(result.value_ptr.*)];
        const current_node = self.graph.nodes.items[@intFromEnum(call_node)];
        const first_location = self.location(first_node.source);
        const current_location = self.location(current_node.source);
        const first_position = self.diagnostics.lineColumn(first_location);
        try self.diagnostics.add(
            current_location,
            .semantic,
            "once function '{s}' is consumed more than once from the reachable entrypoint graph (first use at {s}:{d}:{d})",
            .{
                self.graph.text(declaration.name),
                self.diagnostics.path(first_location),
                first_position.line,
                first_position.column,
            },
        );
        self.had_error = true;
    }

    fn location(self: *const State, source: @import("../primitives/schema.zig").SourceRef) tok.Location {
        if (@as(usize, source.file_index) < self.graph.files.items.len) {
            const graph_file = self.graph.files.items[source.file_index];
            const module = self.graph.modules.items[@intFromEnum(graph_file.module)];
            const wanted_dir = self.graph.text(module.dir);
            const wanted_name = self.graph.text(graph_file.path);
            for (self.diagnostics.source_files, 0..) |file, index| {
                if (!std.mem.eql(u8, std.fs.path.basename(file.path), wanted_name)) continue;
                const dir = std.fs.path.dirname(file.path) orelse ".";
                if (!std.mem.eql(u8, dir, wanted_dir)) continue;
                return .{ .file = @enumFromInt(@as(u32, @intCast(index))), .offset = source.offset };
            }
        }
        const fallback: u32 = if (self.diagnostics.source_files.len == 0)
            0
        else
            @intCast(@min(@as(usize, source.file_index), self.diagnostics.source_files.len - 1));
        return .{ .file = @enumFromInt(fallback), .offset = source.offset };
    }
};
