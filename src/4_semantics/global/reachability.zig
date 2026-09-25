const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");

/// Reachability is construction state derived from the selected executable
/// root. It stays outside GlobalSG because final consumers only need the
/// resulting set of materialized function bodies.
pub const FunctionSet = struct {
    values: std.AutoHashMap(graph_mod.GlobalFunctionId, void),
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, void),
    nodes: std.AutoHashMap(graph_mod.GlobalNodeId, void),

    pub fn init(allocator: std.mem.Allocator) FunctionSet {
        return .{
            .values = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, void).init(allocator),
            .nodes = std.AutoHashMap(graph_mod.GlobalNodeId, void).init(allocator),
        };
    }

    pub fn deinit(self: *FunctionSet) void {
        self.values.deinit();
        self.bindings.deinit();
        self.nodes.deinit();
    }

    pub fn contains(self: *const FunctionSet, function: graph_mod.GlobalFunctionId) bool {
        return self.values.contains(function);
    }

    pub fn include(self: *FunctionSet, function: graph_mod.GlobalFunctionId) !bool {
        const result = try self.values.getOrPut(function);
        return !result.found_existing;
    }

    pub fn containsBinding(self: *const FunctionSet, binding: graph_mod.GlobalBindingId) bool {
        return self.bindings.contains(binding);
    }

    pub fn containsNode(self: *const FunctionSet, node: graph_mod.GlobalNodeId) bool {
        return self.nodes.contains(node);
    }
};

pub fn roots(
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    selected_test_name: ?[]const u8,
) !FunctionSet {
    var result = FunctionSet.init(allocator);
    errdefer result.deinit();
    for (graph.functions.items, 0..) |function, raw| {
        const declaration = graph.declaration(function.declaration);
        const name = graph.text(declaration.name);
        const entrypoint = if (selected_test_name) |wanted|
            function.flags.is_test and std.mem.eql(u8, name, wanted)
        else
            !function.flags.is_test and std.mem.eql(u8, name, "main");
        // Open Errable signatures are completed from their bodies and can be
        // inspected while resolving an otherwise reachable caller.
        if (entrypoint or function.flags.uses_inferred_error_reasons)
            _ = try result.include(@enumFromInt(@as(u32, @intCast(raw))));
        if (entrypoint) for (graph.fields.items[function.input.start..][0..function.input.len]) |field| {
            if (field.default_value != null or !std.mem.eql(u8, graph.text(field.name), "system")) continue;
            for (graph.functions.items, 0..) |candidate, candidate_raw| {
                const candidate_declaration = graph.declaration(candidate.declaration);
                if (!std.mem.eql(u8, graph.text(candidate_declaration.name), "init") or candidate.input.len != 1) continue;
                const receiver = graph.fields.items[candidate.input.start].ty;
                const pointer = switch (graph.types.items[@intFromEnum(receiver)]) {
                    .pointer => |value| value,
                    else => continue,
                };
                if (types.equal(graph, pointer.child, field.ty))
                    _ = try result.include(@enumFromInt(@as(u32, @intCast(candidate_raw))));
            }
        };
    }
    return result;
}

/// Extend a root set with every function referenced by its currently
/// materialized bodies. Calling this after each GlobalSema iteration makes
/// newly resolved direct and virtual calls participate in the next one.
pub fn expand(
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    functions: *FunctionSet,
) !bool {
    var state = State{
        .allocator = allocator,
        .graph = graph,
        .functions = functions,
        .visited_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
        .visited_nodes = std.AutoHashMap(graph_mod.GlobalNodeId, void).init(allocator),
    };
    defer state.visited_functions.deinit();
    defer state.visited_nodes.deinit();

    for (graph.roots.items) |node_id| try state.walkNode(node_id);

    var cursor: usize = 0;
    while (cursor < graph.functions.items.len) : (cursor += 1) {
        const function_id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(cursor)));
        if (functions.contains(function_id)) try state.walkFunction(function_id);
    }
    return state.changed;
}

const State = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    functions: *FunctionSet,
    visited_functions: std.AutoHashMap(graph_mod.GlobalFunctionId, void),
    visited_nodes: std.AutoHashMap(graph_mod.GlobalNodeId, void),
    changed: bool = false,

    fn includeFunction(self: *State, function_id: graph_mod.GlobalFunctionId) !void {
        if (try self.functions.include(function_id)) self.changed = true;
        try self.walkFunction(function_id);
    }

    fn walkFunction(self: *State, function_id: graph_mod.GlobalFunctionId) anyerror!void {
        if ((try self.visited_functions.getOrPut(function_id)).found_existing) return;
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        try self.includeBindingRange(function.input_bindings);
        try self.includeBindingRange(function.output_bindings);
        // Entry wrappers and omitted call arguments evaluate input defaults
        // outside the function body, so their callees are reachable as well.
        for (self.graph.fields.items[function.input.start..][0..function.input.len]) |field|
            if (field.default_value) |value| try self.walkNode(value);
        const body = function.body orelse return;
        try self.walkBlock(body);
    }

    fn includeBindingRange(self: *State, range: graph_mod.BindingRange) !void {
        for (0..range.len) |offset| {
            const raw = range.start + @as(u32, @intCast(offset));
            try self.functions.bindings.put(self.graph.binding_refs.items[raw], {});
        }
    }

    fn walkBlock(self: *State, block_id: graph_mod.GlobalBlockId) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id|
            try self.walkNode(node_id);
    }

    fn walkNode(self: *State, node_id: graph_mod.GlobalNodeId) anyerror!void {
        if ((try self.visited_nodes.getOrPut(node_id)).found_existing) return;
        try self.functions.nodes.put(node_id, {});
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .declaration, .reach_directive, .int_literal, .float_literal, .char_literal, .string_literal, .bool_literal, .break_statement, .continue_statement, .type_literal => {},
            .binding_use => |binding| try self.functions.bindings.put(binding, {}),
            .binding_declaration => |binding_id| {
                try self.functions.bindings.put(binding_id, {});
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (binding.initialization) |value| try self.walkNode(value);
            },
            .move_value, .denied_implicit_copy, .address_of => |value| try self.walkNode(value),
            .assignment => |value| {
                try self.functions.bindings.put(value.binding, {});
                try self.walkNode(value.value);
            },
            .auto_deinit_binding => |id| {
                const value = self.graph.auto_deinits.items[@intFromEnum(id)];
                try self.functions.bindings.put(value.binding, {});
                if (value.input) |input| try self.walkNode(input);
                if (value.deinit_fn) |callee| try self.includeFunction(callee);
                try self.includeAutoDeinitFields(value.fields);
            },
            .function_call => |call| {
                try self.walkNode(call.input);
                if (call.consumes_auto_deinit) |value| try self.walkNode(value);
                if (call.initializes_auto_deinit) |value| try self.walkNode(value);
                try self.includeFunction(call.callee);
                const callee = self.graph.functions.items[@intFromEnum(call.callee)];
                if (callee.safety_primitive == .trusted_opaque_drop and callee.input.len != 0) {
                    const slot_ty = self.graph.fields.items[callee.input.start].ty;
                    if (self.graph.resolvedSemanticType(slot_ty)) |semantic| switch (semantic) {
                        .pointer => |pointer| if (try types.deinitFunctionForInput(self.graph, pointer.child, callee.input)) |destructor|
                            try self.includeFunction(destructor),
                        else => {},
                    };
                }
            },
            .virtualize => |id| {
                const value = self.graph.virtualizes.items[@intFromEnum(id)];
                try self.walkNode(value.value);
                for (self.graph.function_refs.items[value.methods.start..][0..value.methods.len]) |method|
                    try self.includeFunction(method);
                for (self.graph.virtual_registry_refs.items[value.safety_methods.start..][0..value.safety_methods.len]) |registry_id| {
                    const registry = self.graph.virtual_registries.items[@intFromEnum(registry_id)];
                    for (self.graph.function_refs.items[registry.implementations.start..][0..registry.implementations.len]) |method|
                        try self.includeFunction(method);
                }
            },
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.walkNode(call.handle);
                try self.walkNode(call.input);
                if (call.consumes_auto_deinit) |value| try self.walkNode(value);
                const registry = self.graph.virtual_registries.items[@intFromEnum(call.safety_methods)];
                for (self.graph.function_refs.items[registry.implementations.start..][0..registry.implementations.len]) |callee|
                    try self.includeFunction(callee);
            },
            .code_block => |block| try self.walkBlock(block),
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value|
                    try self.walkNode(value);
            },
            .array_literal => |literal| {
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
                const value = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                try self.walkNode(value.nullable_value);
                try self.walkNode(value.fallback_value);
            },
            .testing_expect_error => |id| {
                const value = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                try self.walkNode(value.expected_reason);
                try self.walkNode(value.actual_result);
                try self.includeFunction(value.test_fail_function);
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
            .array_index => |value| {
                try self.walkNode(value.array_ptr);
                try self.walkNode(value.index);
            },
            .array_store => |value| {
                try self.walkNode(value.array_ptr);
                try self.walkNode(value.index);
                try self.walkNode(value.value);
            },
            .struct_field_store => |value| {
                try self.walkNode(value.struct_ptr);
                try self.walkNode(value.value);
            },
            .binary_operation => |value| {
                try self.walkNode(value.left);
                try self.walkNode(value.right);
            },
            .comparison => |value| {
                try self.walkNode(value.left);
                try self.walkNode(value.right);
            },
            .logical_operation => |value| {
                try self.walkNode(value.left);
                try self.walkNode(value.right);
            },
            .return_statement => |value| {
                if (value.expression) |expression| try self.walkNode(expression);
                for (self.graph.node_refs.items[value.cleanup.start..][0..value.cleanup.len]) |cleanup|
                    try self.walkNode(cleanup);
            },
            .if_statement => |value| {
                try self.walkNode(value.condition);
                try self.walkBlock(value.then_block);
                if (value.else_block) |block| try self.walkBlock(block);
            },
            .while_statement => |value| {
                try self.walkNode(value.condition);
                try self.walkBlock(value.body);
            },
            .for_statement => |value| {
                if (value.init) |child| try self.walkNode(child);
                try self.walkNode(value.condition);
                if (value.increment) |child| try self.walkNode(child);
                try self.walkBlock(value.body);
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
            .dereference => |value| try self.walkNode(value.pointer),
            .pointer_assignment => |value| {
                try self.walkNode(value.pointer);
                try self.walkNode(value.value);
            },
            .type_initializer => |value| {
                try self.walkNode(value.args);
                try self.includeFunction(value.init_fn);
            },
            .explicit_cast => |value| try self.walkNode(value.value),
        }
    }

    fn includeAutoDeinitFields(self: *State, range: @import("../primitives/schema.zig").Range(graph_mod.GlobalAutoDeinitFieldId)) anyerror!void {
        for (self.graph.auto_deinit_fields.items[range.start..][0..range.len]) |field| {
            if (field.input) |input| try self.walkNode(input);
            if (field.deinit_fn) |callee| try self.includeFunction(callee);
            try self.includeAutoDeinitFields(field.fields);
        }
    }
};

test "function binding ranges dereference binding refs" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const main_name = try graph.addString(allocator, "main");
    const unrelated_name = try graph.addString(allocator, "unrelated");
    const parameter_name = try graph.addString(allocator, "parameter");
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.bindings.append(allocator, .{
        .name = unrelated_name,
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    try graph.bindings.append(allocator, .{
        .name = parameter_name,
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    try graph.binding_refs.append(allocator, @enumFromInt(1));
    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = main_name,
        .source = .{ .file_index = 0, .offset = 0 },
        .function_id = @enumFromInt(0),
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .input_bindings = .{ .start = 0, .len = 1 },
    });

    var executable = try roots(allocator, &graph, null);
    defer executable.deinit();
    _ = try expand(allocator, &graph, &executable);
    try std.testing.expect(!executable.containsBinding(@enumFromInt(0)));
    try std.testing.expect(executable.containsBinding(@enumFromInt(1)));
}

test "reachability roots select main or one test" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const main_name = try graph.addString(allocator, "main");
    const test_name = try graph.addString(allocator, "selected");
    try graph.declarations.append(allocator, .{ .kind = .function, .name = main_name, .source = .{ .file_index = 0, .offset = 0 }, .function_id = @enumFromInt(0) });
    try graph.declarations.append(allocator, .{ .kind = .test_function, .name = test_name, .source = .{ .file_index = 0, .offset = 0 }, .function_id = @enumFromInt(1) });
    try graph.functions.append(allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
    try graph.functions.append(allocator, .{ .declaration = @enumFromInt(1), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 }, .flags = .{ .is_test = true } });

    var executable = try roots(allocator, &graph, null);
    defer executable.deinit();
    try std.testing.expect(executable.contains(@enumFromInt(0)));
    try std.testing.expect(!executable.contains(@enumFromInt(1)));
    var selected = try roots(allocator, &graph, "selected");
    defer selected.deinit();
    try std.testing.expect(!selected.contains(@enumFromInt(0)));
    try std.testing.expect(selected.contains(@enumFromInt(1)));
}
