const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");

/// Reachability is construction state derived from the selected executable
/// root. It stays outside GlobalSG because final consumers only need the
/// resulting set of materialized function bodies.
const OperationInstance = struct {
    operation: @import("../primitives/schema.zig").ContractOperationIdentity,
    function: graph_mod.GlobalFunctionId,
};

pub const FunctionSet = struct {
    values: std.AutoHashMap(graph_mod.GlobalFunctionId, void),
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, void),
    nodes: std.AutoHashMap(graph_mod.GlobalNodeId, void),
    operations: std.AutoHashMap(OperationInstance, void),
    virtualizes: std.AutoHashMap(graph_mod.GlobalVirtualizeId, void),
    cleanup_functions: std.AutoHashMap(graph_mod.GlobalFunctionId, void),

    pub fn init(allocator: std.mem.Allocator) FunctionSet {
        return .{
            .values = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, void).init(allocator),
            .nodes = std.AutoHashMap(graph_mod.GlobalNodeId, void).init(allocator),
            .operations = std.AutoHashMap(OperationInstance, void).init(allocator),
            .virtualizes = std.AutoHashMap(graph_mod.GlobalVirtualizeId, void).init(allocator),
            .cleanup_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
        };
    }

    pub fn clone(self: *const FunctionSet, allocator: std.mem.Allocator) !FunctionSet {
        var result = FunctionSet.init(allocator);
        errdefer result.deinit();
        inline for (@typeInfo(FunctionSet).@"struct".fields) |field|
            @field(result, field.name) = try @field(self, field.name).cloneWithAllocator(allocator);
        return result;
    }

    pub fn deinit(self: *FunctionSet) void {
        self.values.deinit();
        self.bindings.deinit();
        self.nodes.deinit();
        self.operations.deinit();
        self.virtualizes.deinit();
        self.cleanup_functions.deinit();
    }

    pub fn contains(self: *const FunctionSet, function: graph_mod.GlobalFunctionId) bool {
        return self.values.contains(function);
    }

    pub fn include(self: *FunctionSet, function: graph_mod.GlobalFunctionId) !bool {
        const result = try self.values.getOrPut(function);
        return !result.found_existing;
    }

    // Proof selection belongs to the compilation unit. Sharing a method body
    // with selected cleanup does not select unrelated contract operations.
    pub fn requiresConformance(self: *const FunctionSet, graph: *const graph_mod.GlobalSemanticGraph, proof: graph_mod.ContractSafetyConformance) bool {
        if (self.operations.contains(.{ .operation = proof.selection, .function = proof.method })) return true;
        if (!self.cleanup_functions.contains(proof.method)) return false;
        const conformance = graph.contract_conformances.items[proof.selection.conformance];
        return @import("standard_contracts.zig").standardDefinition(graph, "Deinit") == conformance.declaration;
    }

    pub fn containsBinding(self: *const FunctionSet, binding: graph_mod.GlobalBindingId) bool {
        return self.bindings.contains(binding);
    }

    pub fn containsNode(self: *const FunctionSet, node: graph_mod.GlobalNodeId) bool {
        return self.nodes.contains(node);
    }
};

/// Conservative runtime roots retain tracing and inferred-signature helpers,
/// but exclude operations retained only to prove conformance.
pub fn executionRoots(
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    selected_test_name: ?[]const u8,
) !FunctionSet {
    var result = FunctionSet.init(allocator);
    errdefer result.deinit();
    const has_entry = for (graph.functions.items) |function| {
        if (function.flags.is_entry) break true;
    } else false;
    for (graph.functions.items, 0..) |function, raw| {
        const declaration = graph.declaration(function.declaration);
        const name = graph.text(declaration.name);
        const entrypoint = if (has_entry) function.flags.is_entry else if (selected_test_name) |wanted|
            function.flags.is_test and std.mem.eql(u8, name, wanted)
        else
            !function.flags.is_test and std.mem.eql(u8, name, "main");
        // Open Errable signatures are completed from their bodies and can be
        // inspected while resolving an otherwise reachable caller.
        const trace_runtime = function.flags.isTraceSupport();
        if (entrypoint or trace_runtime or function.flags.is_c_export or function.flags.uses_inferred_error_reasons)
            _ = try result.include(@enumFromInt(@as(u32, @intCast(raw))));
    }
    return result;
}

/// Generated propagation and source-location operations call these ordinary
/// core functions without a source-level call edge. Explicit execution roots
/// need the same support whether they originate in a program or a REPL command.
pub fn includeRuntimeSupport(graph: *const graph_mod.GlobalSemanticGraph, functions: *FunctionSet) !void {
    for (graph.functions.items, 0..) |function, raw| {
        if (function.flags.isTraceSupport()) _ = try functions.include(@enumFromInt(@as(u32, @intCast(raw))));
    }
}

/// Extend a root set with every function referenced by its currently
/// materialized bodies. Calling this after each GlobalSema iteration makes
/// newly resolved direct and virtual calls participate in the next one.
pub fn expand(
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    functions: *FunctionSet,
) !bool {
    var state = try State.init(allocator, graph, functions);
    defer state.deinit();

    for (graph.roots.items) |node_id| try state.walkNode(node_id);

    var cursor: usize = 0;
    while (cursor < graph.functions.items.len) : (cursor += 1) {
        const function_id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(cursor)));
        if (functions.contains(function_id)) try state.walkFunction(function_id);
    }
    return state.changed;
}

// Closed function dependencies without executable-program roots. Evaluation
// and interactive submissions must not pull unrelated main/global work into
// their proof merely because it exists in the retained graph.
pub fn expressionUnit(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, root: graph_mod.GlobalNodeId) !FunctionSet {
    var result = FunctionSet.init(allocator);
    errdefer result.deinit();
    var state = try State.init(allocator, graph, &result);
    defer state.deinit();
    try state.walkNode(root);
    return result;
}

pub fn dependencyUnit(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, roots: []const graph_mod.GlobalFunctionId) !FunctionSet {
    for (roots) |root| if (@intFromEnum(root) >= graph.functions.items.len) return error.InvalidEntry;
    var result = FunctionSet.init(allocator);
    errdefer result.deinit();
    var state = try State.init(allocator, graph, &result);
    defer state.deinit();
    for (roots) |root| try state.includeFunction(root);
    return result;
}

/// Initial summary worklist order, placing concrete dependencies before callers.
/// Cycles retain a deterministic DFS order and still require fixed-point work.
/// Reuse the complete graph traversal, including cleanup and callback bodies.
pub fn dependencyOrder(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, functions: []const graph_mod.GlobalFunctionId) ![]graph_mod.GlobalFunctionId {
    var included = FunctionSet.init(allocator);
    defer included.deinit();
    var order: std.ArrayList(graph_mod.GlobalFunctionId) = .empty;
    errdefer order.deinit(allocator);
    var state = try State.init(allocator, graph, &included);
    defer state.deinit();
    state.dependency_order = &order;
    for (functions) |function| try state.walkFunction(function);
    return order.toOwnedSlice(allocator);
}

const State = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    functions: *FunctionSet,
    visited_functions: std.DynamicBitSetUnmanaged,
    visited_nodes: std.DynamicBitSetUnmanaged,
    changed: bool = false,
    dependency_order: ?*std.ArrayList(graph_mod.GlobalFunctionId) = null,

    // The graph is borrowed read-only for one traversal. Dense IDs allow
    // temporary marks without hashing; each expansion starts with fresh marks
    // so newly resolved nodes and completed bodies are always revisited.
    fn init(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, functions: *FunctionSet) !State {
        var visited_functions = try std.DynamicBitSetUnmanaged.initEmpty(allocator, graph.functions.items.len);
        errdefer visited_functions.deinit(allocator);
        const visited_nodes = try std.DynamicBitSetUnmanaged.initEmpty(allocator, graph.nodes.items.len);
        return .{ .allocator = allocator, .graph = graph, .functions = functions, .visited_functions = visited_functions, .visited_nodes = visited_nodes };
    }

    fn deinit(self: *State) void {
        self.visited_functions.deinit(self.allocator);
        self.visited_nodes.deinit(self.allocator);
    }

    fn includeCleanupFunction(self: *State, function_id: graph_mod.GlobalFunctionId) !void {
        try self.functions.cleanup_functions.put(function_id, {});
        try self.includeFunction(function_id);
    }

    fn includeFunction(self: *State, function_id: graph_mod.GlobalFunctionId) !void {
        if (try self.functions.include(function_id)) self.changed = true;
        try self.walkFunction(function_id);
    }

    fn walkFunction(self: *State, function_id: graph_mod.GlobalFunctionId) anyerror!void {
        const raw = @intFromEnum(function_id);
        if (self.visited_functions.isSet(raw)) return;
        self.visited_functions.set(raw);
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        try self.includeBindingRange(function.input_bindings);
        try self.includeBindingRange(function.output_bindings);
        // Entry wrappers and omitted call arguments evaluate input defaults
        // outside the function body, so their callees are reachable as well.
        for (self.graph.fields.items[function.input.start..][0..function.input.len]) |field|
            if (field.default_value) |value| try self.walkNode(value);
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding|
            if (self.graph.binding(binding).initialization) |value| try self.walkNode(value);
        const body = function.body orelse return;
        try self.walkBlock(body);
        if (self.dependency_order) |order| if (function.safety_primitive == .none)
            try order.append(self.allocator, function_id);
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
        if (block.ret_val) |value| try self.walkNode(value);
    }

    fn walkNode(self: *State, node_id: graph_mod.GlobalNodeId) anyerror!void {
        const raw = @intFromEnum(node_id);
        if (self.visited_nodes.isSet(raw)) return;
        self.visited_nodes.set(raw);
        try self.functions.nodes.put(node_id, {});
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .captured_expression, .declaration, .int_literal, .float_literal, .char_literal, .string_literal, .bool_literal, .break_statement, .continue_statement, .abort_statement, .type_literal, .definition_literal => {},
            .binding_use => |binding| try self.functions.bindings.put(binding, {}),
            .binding_declaration => |binding_id| {
                try self.functions.bindings.put(binding_id, {});
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (binding.initialization) |value| try self.walkNode(value);
                if (binding.cleanup_arguments) |value| try self.walkNode(value);
            },
            .move_value, .denied_implicit_copy => |value| try self.walkNode(value),
            .address_of => |value| {
                // Materialized address temporaries can be re-evaluated. Their
                // selected cleanup is executed before the deferred assignment.
                const child = self.graph.node(value);
                if (child.content == .assignment) {
                    const binding = self.graph.binding(child.content.assignment.binding);
                    if (binding.deferred_initialization) if (binding.reinitialize_cleanup) |cleanup|
                        try self.walkNode(cleanup);
                }
                try self.walkNode(value);
            },
            .assignment => |value| {
                try self.functions.bindings.put(value.binding, {});
                try self.walkNode(value.value);
            },
            .auto_deinit_binding => |id| {
                const value = self.graph.auto_deinits.items[@intFromEnum(id)];
                if (value.ownerBinding()) |binding| try self.functions.bindings.put(binding, {});
                if (value.targetNode()) |target| try self.walkNode(target);
                if (value.input) |input| try self.walkNode(input);
                if (value.deinit_fn) |callee| try self.includeCleanupFunction(callee);
                try self.includeAutoDeinitFields(value.fields);
            },
            .function_address => |id| try self.includeFunction(id),
            .function_call => |call| {
                if (self.graph.callOperation(call)) |operation| try self.functions.operations.put(.{ .operation = operation, .function = call.callee }, {});
                if (call.callee_value) |value| try self.walkNode(value);
                try self.walkNode(call.input);
                try self.includeFunction(call.callee);
            },
            .virtualize => |id| {
                try self.functions.virtualizes.put(id, {});
                const value = self.graph.virtualizes.items[@intFromEnum(id)];
                try self.walkNode(value.value);
                for (self.graph.function_refs.items[value.methods.start..][0..value.methods.len]) |method|
                    try self.includeFunction(method);
            },
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.walkNode(call.handle);
                try self.walkNode(call.input);
                // A virtual call uses its declared effects. Concrete bodies
                // are retained by the handle constructions that selected them.
            },
            .code_block, .value_sequence, .replacement => |block| try self.walkBlock(block),
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value|
                    try self.walkNode(value);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value|
                    try self.walkNode(value);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.assumed_fields.start..][0..literal.assumed_fields.len]) |field|
                    try self.walkNode(field.value);
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
            .error_propagation => |id| {
                const value = self.graph.error_propagations.items[@intFromEnum(id)];
                try self.walkNode(value.errable_value);
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
                    if (case.payload_binding) |binding| try self.functions.bindings.put(binding, {});
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

            .explicit_cast => |value| try self.walkNode(value.value),
        }
    }

    fn includeAutoDeinitFields(self: *State, range: @import("../primitives/schema.zig").Range(graph_mod.GlobalAutoDeinitFieldId)) anyerror!void {
        for (self.graph.auto_deinit_fields.items[range.start..][0..range.len]) |field| {
            if (field.input) |input| try self.walkNode(input);
            if (field.deinit_fn) |callee| try self.includeCleanupFunction(callee);
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

    var executable = try executionRoots(allocator, &graph, null);
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

    var executable = try executionRoots(allocator, &graph, null);
    defer executable.deinit();
    try std.testing.expect(executable.contains(@enumFromInt(0)));
    try std.testing.expect(!executable.contains(@enumFromInt(1)));
    var selected = try executionRoots(allocator, &graph, "selected");
    defer selected.deinit();
    try std.testing.expect(!selected.contains(@enumFromInt(0)));
    try std.testing.expect(selected.contains(@enumFromInt(1)));

    var binding = std.mem.zeroes(graph_mod.ContractOperationBinding);
    binding.materialized_function = @enumFromInt(1);
    try graph.contract_operation_bindings.append(allocator, binding);
    try graph.contract_conformances.append(allocator, .{
        .declaration = @enumFromInt(0),
        .participants = .{ .start = 0, .len = 0 },
        .associated_arguments = .{ .start = 0, .len = 0 },
        .operation_bindings = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    var runtime = try executionRoots(allocator, &graph, null);
    defer runtime.deinit();
    _ = try expand(allocator, &graph, &runtime);
    try std.testing.expect(runtime.contains(@enumFromInt(0)));
    try std.testing.expect(!runtime.contains(@enumFromInt(1)));
}

test "summary dependency order handles late callees and recursive cycles" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.nodes.appendSlice(allocator, &.{
        .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } } },
        .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(1), .input = @enumFromInt(0) } } },
        .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = @enumFromInt(0) } } },
    });
    try graph.node_refs.appendSlice(allocator, &.{ @enumFromInt(1), @enumFromInt(2) });
    try graph.blocks.appendSlice(allocator, &.{
        .{ .nodes = .{ .start = 0, .len = 1 } },
        .{ .nodes = .{ .start = 1, .len = 0 } },
    });
    for (0..2) |index| try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(index),
    });
    const functions = [_]graph_mod.GlobalFunctionId{ @enumFromInt(0), @enumFromInt(1) };
    const ordered = try dependencyOrder(allocator, &graph, &functions);
    defer allocator.free(ordered);
    try std.testing.expectEqualSlices(graph_mod.GlobalFunctionId, &.{ @enumFromInt(1), @enumFromInt(0) }, ordered);
    graph.blocks.items[1].nodes.len = 1;
    const recursive = try dependencyOrder(allocator, &graph, &functions);
    defer allocator.free(recursive);
    try std.testing.expectEqualSlices(graph_mod.GlobalFunctionId, ordered, recursive);
}

test "runtime support follows metadata independently of declaration spelling" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    // Support inclusion must not consult declaration names or module paths.
    // Metadata-only synthetic functions suffice to exercise that boundary.
    try graph.functions.appendSlice(a, &.{
        .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } },
        .{ .declaration = @enumFromInt(1), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } },
        .{ .declaration = @enumFromInt(2), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } },
        .{ .declaration = @enumFromInt(3), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 }, .flags = .{ .is_source_location_resolver = true } },
    });
    var retained = FunctionSet.init(a);
    defer retained.deinit();
    try includeRuntimeSupport(&graph, &retained);
    try std.testing.expect(!retained.contains(@enumFromInt(0)));
    for (0..3) |index| try std.testing.expect(!retained.contains(@enumFromInt(index)));
    try std.testing.expect(retained.contains(@enumFromInt(3)));
}

test "reachability revisits completed bodies after pool growth and releases failed traversals" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.nodes.appendSlice(allocator, &.{
        .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } } },
        .{ .source = source, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(1), .input = @enumFromInt(0) } } },
    });
    try graph.node_refs.append(allocator, @enumFromInt(1));
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 1 } });
    for (0..2) |index| try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = if (index == 0) @enumFromInt(0) else null,
    });
    var selected = FunctionSet.init(allocator);
    defer selected.deinit();
    _ = try selected.include(@enumFromInt(0));
    try std.testing.expect(try expand(allocator, &graph, &selected));
    try std.testing.expect(selected.contains(@enumFromInt(1)));

    // A previously reached signature gains a body calling a newly added
    // function. The next expansion must revisit it with the new pool bounds.
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(2), .input = @enumFromInt(0) } } });
    try graph.node_refs.append(allocator, @enumFromInt(2));
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 1, .len = 1 } });
    graph.functions.items[1].body = @enumFromInt(1);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(0), // Recursive edge back to function 1.
    });
    try std.testing.expect(try expand(allocator, &graph, &selected));
    try std.testing.expect(selected.contains(@enumFromInt(2)));
    try std.testing.expect(!try expand(allocator, &graph, &selected));

    try std.testing.checkAllAllocationFailures(allocator, struct {
        fn traverse(a: std.mem.Allocator, g: *const graph_mod.GlobalSemanticGraph) !void {
            const roots = [_]graph_mod.GlobalFunctionId{@enumFromInt(0)};
            var dependencies = try dependencyUnit(a, g, &roots);
            defer dependencies.deinit();
            try std.testing.expect(dependencies.contains(@enumFromInt(2)));
            _ = try expand(a, g, &dependencies);
            const ordered = try dependencyOrder(a, g, &roots);
            defer a.free(ordered);
            try std.testing.expectEqualSlices(graph_mod.GlobalFunctionId, &.{ @enumFromInt(2), @enumFromInt(1), @enumFromInt(0) }, ordered);
            var expression = try expressionUnit(a, g, @enumFromInt(1));
            defer expression.deinit();
            try std.testing.expect(expression.contains(@enumFromInt(2)));
        }
    }.traverse, .{&graph});
}

test "selected safety proofs distinguish operation specializations" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var unit = FunctionSet.init(allocator);
    defer unit.deinit();
    const selection = @import("../primitives/schema.zig").ContractOperationIdentity{ .conformance = 0, .index = 1 };
    var proof = std.mem.zeroes(graph_mod.ContractSafetyConformance);
    proof.selection = selection;
    proof.method = @enumFromInt(0);
    try unit.operations.put(.{ .operation = selection, .function = @enumFromInt(0) }, {});
    try std.testing.expect(unit.requiresConformance(&graph, proof));
    proof.method = @enumFromInt(1);
    try std.testing.expect(!unit.requiresConformance(&graph, proof));
    try unit.operations.put(.{ .operation = selection, .function = @enumFromInt(1) }, {});
    try std.testing.expect(unit.requiresConformance(&graph, proof));
    proof.selection.index = 2;
    try std.testing.expect(!unit.requiresConformance(&graph, proof));
}

test "match payload bindings are reachable even when their body never reads them" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    for (0..2) |_| try graph.bindings.append(a, .{
        .name = .{ .start = 0, .len = 0 },
        .source = source,
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = null, .content = .{ .bool_literal = true } },
        .{ .source = source, .ty = null, .content = .{ .int_literal = 0 } },
        .{ .source = source, .ty = null, .content = .{ .switch_statement = @enumFromInt(0) } },
    });
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 0 } });
    try graph.switch_cases.append(a, .{ .value = @enumFromInt(1), .variant = @enumFromInt(0), .body = @enumFromInt(0), .payload_binding = @enumFromInt(1) });
    try graph.switches.append(a, .{ .expression = @enumFromInt(0), .cases = .{ .start = 0, .len = 1 }, .default_block = null });
    var unit = try expressionUnit(a, &graph, @enumFromInt(2));
    defer unit.deinit();
    try std.testing.expect(unit.containsBinding(@enumFromInt(1)));
    try std.testing.expect(!unit.containsBinding(@enumFromInt(0)));
    try std.testing.expect(unit.containsNode(@enumFromInt(0)));
    try std.testing.expect(unit.containsNode(@enumFromInt(1)));
}
