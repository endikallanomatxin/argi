const std = @import("std");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const graph_mod = @import("graph.zig");

/// Retained semantic consumption, independent of executor storage. A rejected
/// compilation discards its fork; accepted commands extend the same root graph.
pub const Uses = std.AutoHashMap(graph_mod.GlobalFunctionId, FirstUse);

/// `uses` belongs to a speculative candidate; discard that fork on failure.
pub fn verifyContinuation(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, entry: graph_mod.GlobalFunctionId, uses: *Uses) !void {
    var state = State{
        .allocator = allocator,
        .graph = graph,
        .diagnostics = diagnostics,
        .seen_once = uses.*,
        .active_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
    };
    defer uses.* = state.seen_once;
    defer state.active_functions.deinit();
    try state.walkFunction(entry);
    if (state.had_error) return error.Reported;
}

/// Editor roots are independent entrypoints, not sequential invocations.
/// Check each with fresh once-use state and follow its resolved callees.
pub fn verifyModule(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, path: []const u8) !void {
    var roots = try @import("reachability.zig").moduleRoots(allocator, graph, path);
    defer roots.deinit();
    var entries = roots.values.keyIterator();
    while (entries.next()) |entry| {
        var uses = Uses.init(allocator);
        defer uses.deinit();
        try verifyContinuation(allocator, graph, diagnostics, entry.*, &uses);
    }
}

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
        .seen_once = std.AutoHashMap(graph_mod.GlobalFunctionId, FirstUse).init(allocator),
        .active_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(allocator),
    };
    defer state.seen_once.deinit();
    defer state.active_functions.deinit();

    var has_entry = false;
    for (graph.functions.items, 0..) |function, raw| {
        if (!function.flags.is_entry) continue;
        has_entry = true;
        try state.walkFunction(@enumFromInt(@as(u32, @intCast(raw))));
    }
    if (has_entry) {
        if (state.had_error) return error.Reported;
        return;
    }

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
    seen_once: Uses,
    active_functions: std.AutoHashMap(graph_mod.GlobalFunctionId, void),
    current_function: ?graph_mod.GlobalFunctionId = null,
    visited_nodes: ?*std.AutoHashMapUnmanaged(graph_mod.GlobalNodeId, void) = null,
    had_error: bool = false,
    callback_source: ?graph_mod.GlobalNodeId = null,
    isolation_source: ?graph_mod.GlobalNodeId = null,

    fn walkFunction(self: *State, function_id: graph_mod.GlobalFunctionId) anyerror!void {
        if (self.active_functions.contains(function_id)) return;
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        try self.active_functions.put(function_id, {});
        defer _ = self.active_functions.remove(function_id);
        const previous = self.current_function;
        self.current_function = function_id;
        defer self.current_function = previous;
        var visited: std.AutoHashMapUnmanaged(graph_mod.GlobalNodeId, void) = .empty;
        defer visited.deinit(self.allocator);
        const previous_nodes = self.visited_nodes;
        self.visited_nodes = &visited;
        defer self.visited_nodes = previous_nodes;
        // Completed call inputs evaluate defaults in their caller. Declaration
        // defaults are metadata, not additional executions in the callee.
        const body = function.body orelse return;
        try self.walkBlock(body);
    }

    fn walkBlock(self: *State, block_id: graph_mod.GlobalBlockId) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id|
            try self.walkNode(node_id);
        if (block.ret_val) |value| try self.walkNode(value);
    }

    fn walkNode(self: *State, node_id: graph_mod.GlobalNodeId) anyerror!void {
        // Lowered temporary preparation can share one effect node with the
        // value sequence that yields it. A new function visit gets a fresh set,
        // so separate calls through the same helper still consume separately.
        const visited = try self.visited_nodes.?.getOrPut(self.allocator, node_id);
        if (visited.found_existing) return;
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .function_address => |callee| {
                if (self.isolation_source) |origin| {
                    try self.isolationError(origin, "indirect or unresolved calls");
                    return;
                }
                // A foreign holder can invoke the address arbitrarily often.
                // Check the complete reachable body without consuming the
                // enclosing entrypoint's once-use state.
                if (self.callback_source == null) {
                    const outer = self.seen_once;
                    const outer_active = self.active_functions;
                    self.seen_once = Uses.init(self.allocator);
                    self.active_functions = std.AutoHashMap(graph_mod.GlobalFunctionId, void).init(self.allocator);
                    defer {
                        self.seen_once.deinit();
                        self.seen_once = outer;
                        self.active_functions.deinit();
                        self.active_functions = outer_active;
                    }
                    self.callback_source = node_id;
                    defer self.callback_source = null;
                    if (self.isIsolatedCallback(node.ty)) self.isolation_source = node_id;
                    defer self.isolation_source = null;
                    try self.walkCall(node_id, callee);
                } else try self.walkCall(node_id, callee);
            },
            .binding_use => |binding| try self.checkGlobalBinding(binding),
            .declaration,

            .int_literal,
            .float_literal,
            .char_literal,
            .string_literal,
            .bool_literal,
            .break_statement,
            .continue_statement,
            .abort_statement,
            .type_literal,
            .definition_literal,
            => {},
            .captured_expression => if (self.isolation_source) |origin| try self.isolationError(origin, "indirect or unresolved calls"),
            .binding_declaration => |binding_id| {
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (binding.initialization) |value| try self.walkNode(value);
            },
            .move_value, .denied_implicit_copy => |value| try self.walkNode(value),
            .assignment => |assignment| {
                try self.checkGlobalBinding(assignment.binding);
                try self.walkNode(assignment.value);
            },
            .auto_deinit_binding => |auto_id| {
                const auto = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
                if (auto.targetNode()) |target| try self.walkNode(target);
                if (auto.input) |input| try self.walkNode(input);
                if (auto.deinit_fn) |callee| try self.walkCall(node_id, callee);
            },
            // Cleanup targets describe already-evaluated argument identities.
            // Only the ordinary callee/input nodes execute at this boundary.
            .function_call => |call| {
                if (call.callee_value) |value| {
                    if (self.isolation_source) |origin| try self.isolationError(origin, "indirect calls");
                    try self.walkNode(value);
                }
                try self.walkNode(call.input);
                try self.walkCall(node_id, call.callee);
            },
            .virtualize => |id| {
                const virtualize = self.graph.virtualizes.items[@intFromEnum(id)];
                try self.walkNode(virtualize.value);
            },
            .virtual_call => |id| {
                if (self.isolation_source) |origin| try self.isolationError(origin, "indirect or unresolved calls");
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.walkNode(call.handle);
                try self.walkNode(call.input);
                const evidence = @import("contract_evidence.zig");
                const contract = evidence.virtualContractType(self.graph, call) orelse return error.InvalidVirtualContract;
                var candidates: evidence.PossibleVirtualMethods = .{ .graph = self.graph, .contract = contract, .method_index = call.method_index };
                var seen: std.AutoHashMapUnmanaged(graph_mod.GlobalFunctionId, void) = .empty;
                defer seen.deinit(self.allocator);
                while (candidates.next()) |callee| {
                    if ((try seen.getOrPut(self.allocator, callee)).found_existing) continue;
                    try self.walkCall(node_id, callee);
                }
            },
            .code_block, .value_sequence, .replacement => |block| try self.walkBlock(block),
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
            .error_propagation => |id| {
                const value = self.graph.error_propagations.items[@intFromEnum(id)];
                try self.walkNode(value.errable_value);
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

            .explicit_cast => |cast| try self.walkNode(cast.value),
        }
    }

    fn isIsolatedCallback(self: *const State, ty: ?graph_mod.GlobalTypeId) bool {
        const semantic = self.graph.resolvedSemanticType(ty orelse return false) orelse return false;
        if (semantic != .nominal) return false;
        const definition = self.graph.typeDefinition(semantic.nominal);
        if (definition.struct_layout != .c_function_pointer) return false;
        return self.graph.function(definition.function_id orelse return false).flags.is_isolated_callback;
    }

    fn checkGlobalBinding(self: *State, binding: graph_mod.GlobalBindingId) !void {
        const origin = self.isolation_source orelse return;
        if (!self.graph.isModuleBinding(binding) or @import("types.zig").isStaticBinding(self.graph, binding)) return;
        if (!self.plainGlobalType(self.graph.binding(binding).ty, 0)) try self.isolationError(origin, "nonplain global storage");
    }

    fn plainGlobalType(self: *const State, ty: graph_mod.GlobalTypeId, depth: usize) bool {
        if (depth > 128) return false;
        const semantic = self.graph.resolvedSemanticType(ty) orelse return false;
        return switch (semantic) {
            .builtin => |builtin| builtin != .Type and builtin != .Any,
            .array => |array| self.plainGlobalType(array.element, depth + 1),
            .structural => |record| blk: {
                for (self.graph.fields.items[record.fields.start..][0..record.fields.len]) |field|
                    if (!self.plainGlobalType(field.ty, depth + 1)) break :blk false;
                break :blk true;
            },
            .structural_choice => |choice| blk: {
                for (self.graph.variants.items[choice.variants.start..][0..choice.variants.len]) |variant|
                    if (variant.payload_type) |child| {
                        if (!self.plainGlobalType(child, depth + 1)) break :blk false;
                    };
                break :blk true;
            },
            else => false,
        };
    }

    fn isolationError(self: *State, address: graph_mod.GlobalNodeId, reason: []const u8) !void {
        try self.diagnostics.add(self.location(self.graph.node(address).source), .semantic, "isolated callback cannot access {s}", .{reason});
        self.had_error = true;
    }

    fn walkCall(self: *State, call_node: graph_mod.GlobalNodeId, callee: graph_mod.GlobalFunctionId) anyerror!void {
        const function = self.graph.functions.items[@intFromEnum(callee)];
        if (function.body == null) if (self.isolation_source) |origin| {
            try self.isolationError(origin, "foreign or unresolved functions");
            return;
        };
        if (function.flags.is_once and self.callback_source != null) {
            const source = self.graph.node(self.callback_source.?).source;
            try self.diagnostics.add(self.location(source), .semantic, "callback may be invoked repeatedly and cannot consume a once function", .{});
            self.had_error = true;
            return;
        }
        if (function.flags.is_comptime_host_entry) {
            // Every explicit host entry owns its acquisition scope, including
            // nested entries executed within the same VM invocation.
            const outer = self.seen_once;
            self.seen_once = Uses.init(self.allocator);
            defer {
                self.seen_once.deinit();
                self.seen_once = outer;
            }
            try self.walkFunction(callee);
            return;
        }
        if (function.flags.is_once and !try self.consumeOnce(call_node, callee)) return;
        try self.walkFunction(callee);
    }

    fn consumeOnce(self: *State, call_node: graph_mod.GlobalNodeId, callee: graph_mod.GlobalFunctionId) anyerror!bool {
        const result = try self.seen_once.getOrPut(callee);
        if (!result.found_existing) {
            result.value_ptr.* = .{ .node = call_node, .caller = self.current_function };
            return true;
        }

        const declaration = self.graph.declarations.items[@intFromEnum(self.graph.functions.items[@intFromEnum(callee)].declaration)];
        const first_node = self.graph.nodes.items[@intFromEnum(result.value_ptr.node)];
        const current_node = self.graph.nodes.items[@intFromEnum(call_node)];
        const first_location = self.diagnostics.presentedLocation(self.location(first_node.source));
        const current_location = self.diagnostics.presentedLocation(self.location(current_node.source));
        const first_position = self.diagnostics.lineColumn(first_location);
        try self.diagnostics.add(
            current_location,
            .semantic,
            "once function '{s}' is consumed more than once from the reachable entrypoint graph (first use at {s}:{d}:{d} via '{s}')",
            .{
                self.graph.text(declaration.name),
                self.diagnostics.path(first_location),
                first_position.line,
                first_position.column,
                if (result.value_ptr.caller) |caller| self.graph.text(self.graph.declaration(self.graph.functions.items[@intFromEnum(caller)].declaration).name) else "<entry>",
            },
        );
        self.had_error = true;
        return false;
    }

    fn location(self: *const State, source: @import("../primitives/schema.zig").SourceRef) tok.Location {
        if (@import("source_location.zig").find(self.graph, &self.diagnostics.source_db, source)) |found| return found;
        const fallback: u32 = if (self.diagnostics.source_files.len == 0)
            0
        else
            @intCast(@min(@as(usize, source.file_index), self.diagnostics.source_files.len - 1));
        return .{ .file = @enumFromInt(fallback), .offset = source.offset };
    }
};

const FirstUse = struct {
    node: graph_mod.GlobalNodeId,
    caller: ?graph_mod.GlobalFunctionId,
};
