const std = @import("std");
const diagnostics = @import("../1_base/diagnostic.zig");
const tok = @import("../2_tokens/token.zig");
const graph_mod = @import("global_semantic_graph.zig");
const types = @import("global_semantic_types.zig");
const facts = @import("global_safety_facts.zig");
const value_state = @import("value_state.zig");
const primitives = @import("semantic_primitives.zig");

/// Indexed temporal checker. Program identity is exclusively Global*Id; no
/// pointer identity or legacy SemanticGraph object participates in state.
///
/// Calls execute transactionally against a cloned caller state. Because
/// GlobalBindingId is unique program-wide, pointee Places survive the call and
/// mutations are committed directly without reconstructing symbolic pointer
/// identities. Recursive SCCs are recorded and will be upgraded to summaries
/// if a cycle actually carries temporal effects.
pub const SafetyChecker = struct {
    pub const Stats = struct {
        functions: usize = 0,
        calls: usize = 0,
        state_clones: u64 = 0,
        state_elements_copied: u64 = 0,
        primitive_calls: usize = 0,
        recursive_edges: usize = 0,
    };

    const StorageCapabilityState = enum { available, conditional, maybe_consumed, consumed };
    const OwnershipEdge = struct { owner: facts.ValidityRootId, owned: facts.ValidityRootId };
    const StorageGeneration = struct { storage: facts.Place, generation: facts.ValidityRootId };
    const OpaqueStorage = struct { storage: facts.Place, hidden_dependencies: []const facts.ValidityRootId };
    const ChoiceActive = struct { storage: facts.Place, variant_index: u32 };

    const FunctionState = struct {
        tracker: facts.Tracker,
        places: std.array_list.Managed(facts.PlaceFacts),
        storage_capabilities: std.array_list.Managed(StorageCapabilityState),
        ownership_edges: std.array_list.Managed(OwnershipEdge),
        storage_generations: std.array_list.Managed(StorageGeneration),
        opaque_storages: std.array_list.Managed(OpaqueStorage),
        choice_active: std.array_list.Managed(ChoiceActive),
        reachable: bool = true,

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
                .storage_capabilities = std.array_list.Managed(StorageCapabilityState).init(allocator),
                .ownership_edges = std.array_list.Managed(OwnershipEdge).init(allocator),
                .storage_generations = std.array_list.Managed(StorageGeneration).init(allocator),
                .opaque_storages = std.array_list.Managed(OpaqueStorage).init(allocator),
                .choice_active = std.array_list.Managed(ChoiceActive).init(allocator),
            };
        }

        fn deinit(self: *FunctionState) void {
            self.tracker.deinit();
            self.places.deinit();
            self.storage_capabilities.deinit();
            self.ownership_edges.deinit();
            self.storage_generations.deinit();
            self.opaque_storages.deinit();
            self.choice_active.deinit();
        }

        fn clone(self: *const FunctionState, allocator: std.mem.Allocator, stats: ?*Stats) !FunctionState {
            var out = FunctionState.init(allocator);
            errdefer out.deinit();
            try out.tracker.roots.appendSlice(self.tracker.roots.items);
            try out.places.appendSlice(self.places.items);
            try out.storage_capabilities.appendSlice(self.storage_capabilities.items);
            try out.ownership_edges.appendSlice(self.ownership_edges.items);
            try out.storage_generations.appendSlice(self.storage_generations.items);
            try out.opaque_storages.appendSlice(self.opaque_storages.items);
            try out.choice_active.appendSlice(self.choice_active.items);
            out.reachable = self.reachable;
            if (stats) |s| {
                s.state_clones += 1;
                s.state_elements_copied += @intCast(self.tracker.roots.items.len + self.places.items.len + self.storage_capabilities.items.len + self.ownership_edges.items.len + self.storage_generations.items.len + self.opaque_storages.items.len + self.choice_active.items.len);
            }
            return out;
        }
    };

    allocator: std.mem.Allocator,
    diagnostics: *diagnostics.Diagnostics,
    graph: *const graph_mod.GlobalSemanticGraph,
    call_stack: std.array_list.Managed(graph_mod.GlobalFunctionId),
    collect_stats: bool = false,
    stats: Stats = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        diags: *diagnostics.Diagnostics,
        graph: *const graph_mod.GlobalSemanticGraph,
    ) SafetyChecker {
        return .{
            .allocator = allocator,
            .diagnostics = diags,
            .graph = graph,
            .call_stack = std.array_list.Managed(graph_mod.GlobalFunctionId).init(allocator),
        };
    }

    pub fn deinit(self: *SafetyChecker) void {
        self.call_stack.deinit();
    }

    pub fn enableStats(self: *SafetyChecker) void { self.collect_stats = true; }

    pub fn analyze(self: *SafetyChecker) !void {
        self.stats = .{};
        const before = self.diagnostics.list.items.len;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null or function.safety_primitive != .none) continue;
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            var state = FunctionState.init(self.allocator);
            defer state.deinit();
            try self.seedFunctionInputs(function, &state);
            try self.call_stack.append(id);
            defer _ = self.call_stack.pop();
            try self.validateBlock(id, function.body.?, &state);
            if (self.collect_stats) self.stats.functions += 1;
        }
        if (self.diagnostics.list.items.len != before) return error.Reported;
    }

    fn seedFunctionInputs(self: *SafetyChecker, function: graph_mod.Function, state: *FunctionState) !void {
        var shared_pointer_root: ?facts.ValidityRootId = null;
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |binding| {
            const record = self.graph.bindings.items[@intFromEnum(binding)];
            const value: facts.ValueFacts = if (isPointer(self.graph, record.ty)) blk: {
                const root = shared_pointer_root orelse root_blk: {
                    const created = try state.tracker.establish(.fresh);
                    shared_pointer_root = created;
                    break :root_blk created;
                };
                break :blk .{ .dependencies = try self.oneDependency(root) };
            } else .{};
            try self.setPlace(state, .{ .root = binding }, .initialized, value);
        }
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding|
            try self.setPlace(state, .{ .root = binding }, .initialized, .{});
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        state: *FunctionState,
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!state.reachable) break;
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .binding_declaration => |binding| {
                    const record = self.graph.bindings.items[@intFromEnum(binding)];
                    const value = if (record.initialization) |initialization| try self.evaluate(function, initialization, state) else facts.ValueFacts{};
                    try self.setPlace(state, .{ .root = binding }, .initialized, value);
                },
                .assignment => |assignment| {
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.setPlace(state, .{ .root = assignment.binding }, .initialized, value);
                },
                .auto_deinit_binding => |auto_id| try self.applyAutoDeinit(function, auto_id, state),
                .struct_field_store => |store| {
                    const value = try self.evaluate(function, store.value, state);
                    if (try self.resolvePlace(store.struct_ptr, state)) |base|
                        try self.setPlace(state, try self.project(base, .{ .field = store.field_index }), .initialized, value);
                },
                .array_store => |store| {
                    const value = try self.evaluate(function, store.value, state);
                    if (try self.resolvePlace(store.array_ptr, state)) |base| {
                        const projection: facts.Projection = if (self.staticIndex(store.index)) |index| .{ .static_index = index } else .dynamic_index;
                        try self.setPlace(state, try self.project(base, projection), .initialized, value);
                    }
                },
                .pointer_assignment => |assignment| {
                    const pointer = try self.evaluate(function, assignment.pointer, state);
                    try self.requireLive(function, node.source, pointer, state);
                    const value = try self.evaluate(function, assignment.value, state);
                    if (pointer.referenced_place) |target| try self.setPlace(state, target, .initialized, value);
                },
                .if_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    var then_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer then_state.deinit();
                    if (statement.choice_test) |choice_test| self.refineChoice(&then_state, choice_test.choice_value, choice_test.variant, choice_test.then_has_variant);
                    try self.validateBlock(function, statement.then_block, &then_state);
                    var else_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer else_state.deinit();
                    if (statement.choice_test) |choice_test| self.refineChoice(&else_state, choice_test.choice_value, choice_test.variant, !choice_test.then_has_variant);
                    if (statement.else_block) |child| try self.validateBlock(function, child, &else_state);
                    try self.joinState(state, &then_state, &else_state);
                },
                .while_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    var body_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer body_state.deinit();
                    try self.validateBlock(function, statement.body, &body_state);
                    try self.joinState(state, state, &body_state);
                },
                .for_statement => |statement| {
                    if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);
                    _ = try self.evaluate(function, statement.condition, state);
                    var body_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer body_state.deinit();
                    try self.validateBlock(function, statement.body, &body_state);
                    if (statement.increment) |increment| _ = try self.evaluate(function, increment, &body_state);
                    try self.joinState(state, state, &body_state);
                },
                .switch_statement => |switch_id| try self.validateSwitch(function, switch_id, state),
                .return_statement => |ret| {
                    if (ret.expression) |expression| {
                        const value = try self.evaluate(function, expression, state);
                        try self.rejectEscapingLocalRoots(function, node.source, value, state);
                    }
                    for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |cleanup|
                        _ = try self.evaluate(function, cleanup, state);
                    state.reachable = false;
                },
                .break_statement, .continue_statement => state.reachable = false,
                else => _ = try self.evaluate(function, node_id, state),
            }
            try self.validateUniqueOwnership(function, node.source, state);
        }
        try self.endBlockStorage(block_id, state);
    }

    fn validateSwitch(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, switch_id: graph_mod.GlobalSwitchId, state: *FunctionState) !void {
        const sw = self.graph.switches.items[@intFromEnum(switch_id)];
        const choice = try self.evaluate(function, sw.expression, state);
        _ = choice;
        var joined: ?FunctionState = null;
        defer if (joined) |*value| value.deinit();
        for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
            var branch = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            defer branch.deinit();
            if (try self.resolvePlace(sw.expression, &branch)) |storage| self.setActiveVariant(&branch, storage, @intFromEnum(case.variant));
            try self.validateBlock(function, case.body, &branch);
            if (joined) |*existing| {
                var combined = try existing.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                try self.joinState(&combined, existing, &branch);
                existing.deinit();
                existing.* = combined;
            } else joined = try branch.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        }
        if (sw.default_block) |child| {
            var branch = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            defer branch.deinit();
            try self.validateBlock(function, child, &branch);
            if (joined) |*existing| try self.joinState(existing, existing, &branch) else joined = try branch.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        }
        if (joined) |*result| try self.copyState(state, result);
    }

    fn evaluate(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .binding_use => |binding| blk: {
                const place = self.getPlace(state, .{ .root = binding }) orelse break :blk .{};
                try self.requireInitialized(function, node.source, place.initializedness);
                break :blk place.value;
            },
            .move_value => |child| blk: {
                const value = try self.evaluate(function, child, state);
                if (try self.resolvePlace(child, state)) |storage| try self.setPlace(state, storage, .moved, value);
                break :blk value;
            },
            .address_of => |child| blk: {
                const storage = try self.resolvePlace(child, state) orelse break :blk .{};
                const root = try self.storageGeneration(state, storage);
                break :blk .{ .dependencies = try self.oneDependency(root), .referenced_place = storage };
            },
            .dereference => |deref| blk: {
                const pointer = try self.evaluate(function, deref.pointer, state);
                try self.requireLive(function, node.source, pointer, state);
                if (pointer.referenced_place) |storage| if (self.getPlace(state, storage)) |place| {
                    try self.requireInitialized(function, node.source, place.initializedness);
                    break :blk place.value;
                };
                break :blk .{};
            },
            .struct_field_access => |access| blk: {
                if (try self.resolvePlace(node_id, state)) |storage| if (self.getPlace(state, storage)) |place| break :blk place.value;
                const aggregate = try self.evaluate(function, access.value, state);
                for (aggregate.fields) |field| if (field.index == access.field_index) break :blk field.value.*;
                break :blk aggregate;
            },
            .array_index => |access| blk: {
                _ = try self.evaluate(function, access.array_ptr, state);
                _ = try self.evaluate(function, access.index, state);
                if (try self.resolvePlace(node_id, state)) |storage| if (self.getPlace(state, storage)) |place| break :blk place.value;
                break :blk .{};
            },
            .struct_value_literal => |literal| try self.evaluateStruct(function, literal, state),
            .list_literal => |literal| try self.evaluateList(function, literal, state),
            .array_literal => |literal| try self.evaluateArray(function, literal, state),
            .choice_literal => |literal| try self.evaluateChoice(function, literal, state),
            .choice_payload_access => |access| try self.evaluateChoicePayload(function, node.source, access, state),
            .function_call => |call| try self.evaluateCall(function, call, state),
            .virtual_call => |call_id| try self.evaluateVirtualCall(function, call_id, state),
            .nullable_unwrap_or => |unwrap_id| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                const value = try self.evaluate(function, unwrap.nullable_value, state);
                _ = value;
                break :blk try self.evaluate(function, unwrap.fallback_value, state);
            },
            .error_propagation => |prop_id| blk: {
                const prop = self.graph.error_propagations.items[@intFromEnum(prop_id)];
                const value = try self.evaluate(function, prop.errable_value, state);
                for (self.graph.node_refs.items[prop.cleanup_nodes.start..][0..prop.cleanup_nodes.len]) |cleanup| _ = try self.evaluate(function, cleanup, state);
                break :blk value;
            },
            .error_context => |ctx_id| blk: {
                const ctx = self.graph.error_contexts.items[@intFromEnum(ctx_id)];
                const value = try self.evaluate(function, ctx.errable_value, state);
                _ = try self.evaluate(function, ctx.context, state);
                for (self.graph.node_refs.items[ctx.cleanup_nodes.start..][0..ctx.cleanup_nodes.len]) |cleanup| _ = try self.evaluate(function, cleanup, state);
                break :blk value;
            },
            .auto_deinit_binding => |auto_id| blk: {
                try self.applyAutoDeinit(function, auto_id, state);
                break :blk .{};
            },
            .explicit_cast => |cast| blk: {
                const value = try self.evaluate(function, cast.value, state);
                if (isPointer(self.graph, cast.target_type) and !isPointer(self.graph, self.graph.nodes.items[@intFromEnum(cast.value)].ty orelse cast.target_type) and value.integer_address) {
                    try self.report(node.source, "an integer address cannot establish a safe reference; use an explicit root establishment boundary", .{});
                    break :blk .{};
                }
                break :blk value;
            },
            .binary_operation => |binary| blk: { _ = try self.evaluate(function, binary.left, state); _ = try self.evaluate(function, binary.right, state); break :blk .{}; },
            .comparison => |cmp| blk: { _ = try self.evaluate(function, cmp.left, state); _ = try self.evaluate(function, cmp.right, state); break :blk .{}; },
            .logical_operation => |logic| blk: { _ = try self.evaluate(function, logic.left, state); _ = try self.evaluate(function, logic.right, state); break :blk .{}; },
            .code_block => |block| blk: { try self.validateBlock(function, block, state); break :blk .{}; },
            .int_literal, .float_literal, .char_literal, .string_literal, .bool_literal, .declaration, .type_initializer, .testing_expect_error, .reach_directive, .virtualize, .break_statement, .continue_statement => .{},
            else => .{},
        };
    }

    fn evaluateCall(self: *SafetyChecker, caller: graph_mod.GlobalFunctionId, call: anytype, state: *FunctionState) !facts.ValueFacts {
        if (self.collect_stats) self.stats.calls += 1;
        const callee = self.graph.functions.items[@intFromEnum(call.callee)];
        var argument_nodes: []const graph_mod.GlobalValueFieldId = &.{};
        const input_node = self.graph.nodes.items[@intFromEnum(call.input)];
        if (input_node.content == .struct_value_literal) {
            const range = input_node.content.struct_value_literal.fields;
            argument_nodes = self.globalValueFieldIds(range);
        }

        var candidate = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer candidate.deinit();
        var values = try self.allocator.alloc(facts.ValueFacts, argument_nodes.len);
        defer self.allocator.free(values);
        for (argument_nodes, 0..) |field_id, index| {
            const field = self.graph.value_fields.items[@intFromEnum(field_id)];
            values[index] = try self.evaluate(caller, field.value, &candidate);
        }

        if (callee.safety_primitive != .none) {
            if (self.collect_stats) self.stats.primitive_calls += 1;
            const result = try self.evaluatePrimitive(caller, callee.safety_primitive, argument_nodes, values, &candidate, input_node.source);
            self.commitState(state, &candidate);
            return result;
        }
        if (callee.body == null) {
            // Foreign pointers are not made safe implicitly.
            if (callee.output.len == 1 and isPointer(self.graph, self.graph.fields.items[callee.output.start].ty)) return .{ .foreign_storage = true };
            return .{};
        }

        if (self.callStackContains(call.callee)) {
            if (self.collect_stats) self.stats.recursive_edges += 1;
            // Recursive SCC summaries are a performance/precision refinement.
            // Never manufacture a fresh safe reference at the cycle boundary.
            return .{};
        }

        try self.bindCallInputs(callee, values, &candidate);
        try self.call_stack.append(call.callee);
        defer _ = self.call_stack.pop();
        try self.validateBlock(call.callee, callee.body.?, &candidate);
        const result = try self.collectCallOutput(callee, &candidate);
        self.commitState(state, &candidate);
        return result;
    }

    fn evaluatePrimitive(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        primitive: primitives.SafetyPrimitive,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
        source: primitives.SourceRef,
    ) !facts.ValueFacts {
        _ = function;
        _ = argument_ids;
        return switch (primitive) {
            .none => .{},
            .raw_allocated_storage => blk: {
                const id: facts.StorageCapabilityId = @enumFromInt(state.storage_capabilities.items.len);
                try state.storage_capabilities.append(.available);
                break :blk .{ .foreign_storage = true, .storage_capabilities = try self.oneCapability(id) };
            },
            .establish_fresh_reference => blk: {
                try self.report(source, "fresh raw-to-safe reference establishment is restricted to compiler-owned storage boundaries", .{});
                break :blk .{};
            },
            .establish_allocation, .establish_inherited_reference, .establish_inherited_storage => blk: {
                const root = try state.tracker.establish(.fresh);
                if ((primitive == .establish_allocation or primitive == .establish_inherited_storage) and values.len != 0) {
                    for (values[0].storage_capabilities) |capability| {
                        const raw = @intFromEnum(capability);
                        if (raw >= state.storage_capabilities.items.len or state.storage_capabilities.items[raw] != .available)
                            try self.report(source, "physical storage capability has already been consumed", .{})
                        else state.storage_capabilities.items[raw] = .consumed;
                    }
                }
                break :blk .{ .dependencies = try self.oneDependency(root), .owned_roots = if (primitive == .establish_allocation) try self.oneRoot(root) else &.{} };
            },
            .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference, .restrict_reference, .read_reference => if (values.len != 0) values[0].referenceCopy() else .{},
            .relocate, .trusted_opaque_move, .trusted_opaque_move_in => blk: {
                if (values.len != 0) {
                    const value = values[values.len - 1];
                    for (value.owned_roots) |root| state.tracker.end(root);
                }
                break :blk .{};
            },
            .trusted_opaque_move_out => .{},
            .trusted_opaque_relocate, .trusted_opaque_drop, .trusted_opaque_mark_empty => .{},
        };
    }

    fn bindCallInputs(self: *SafetyChecker, function: graph_mod.Function, values: []const facts.ValueFacts, state: *FunctionState) !void {
        const ids = self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len];
        for (ids, 0..) |binding, index| try self.setPlace(state, .{ .root = binding }, .initialized, if (index < values.len) values[index] else .{});
    }

    fn collectCallOutput(self: *SafetyChecker, function: graph_mod.Function, state: *FunctionState) !facts.ValueFacts {
        const ids = self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
        if (ids.len == 0) return .{};
        if (ids.len == 1) return if (self.getPlace(state, .{ .root = ids[0] })) |place| place.value else .{};
        var fields = try self.allocator.alloc(facts.FieldFacts, ids.len);
        for (ids, 0..) |binding, index| {
            const value = if (self.getPlace(state, .{ .root = binding })) |place| place.value else facts.ValueFacts{};
            const owned = try self.allocator.create(facts.ValueFacts);
            owned.* = value;
            fields[index] = .{ .index = @intCast(index), .value = owned };
        }
        return .{ .fields = fields };
    }

    fn evaluateStruct(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, literal: anytype, state: *FunctionState) !facts.ValueFacts {
        const values = self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len];
        var fields = try self.allocator.alloc(facts.FieldFacts, values.len);
        for (values, 0..) |field, index| {
            const value = try self.evaluate(function, field.value, state);
            const owned = try self.allocator.create(facts.ValueFacts);
            owned.* = value;
            fields[index] = .{ .index = @intCast(index), .value = owned };
        }
        return .{ .fields = fields };
    }

    fn evaluateList(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, literal: anytype, state: *FunctionState) !facts.ValueFacts {
        var fields = try self.allocator.alloc(facts.FieldFacts, literal.elements.len);
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = try self.evaluate(function, node, state);
            const owned = try self.allocator.create(facts.ValueFacts);
            owned.* = value;
            fields[index] = .{ .index = @intCast(index), .value = owned };
        }
        return .{ .fields = fields };
    }

    fn evaluateArray(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, literal: anytype, state: *FunctionState) !facts.ValueFacts {
        return self.evaluateList(function, .{ .elements = literal.elements }, state);
    }

    fn evaluateChoice(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, literal: anytype, state: *FunctionState) !facts.ValueFacts {
        const index = variantIndex(self.graph, literal.choice_type, literal.variant) orelse 0;
        const payload = if (literal.payload) |node| try self.evaluate(function, node, state) else facts.ValueFacts{};
        const value = try self.allocator.create(facts.ValueFacts);
        value.* = payload;
        const variants = try self.allocator.alloc(facts.VariantFacts, 1);
        variants[0] = .{ .index = index, .value = value };
        return .{ .variants = variants, .known_choice_variant = index };
    }

    fn evaluateChoicePayload(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, access: anytype, state: *FunctionState) !facts.ValueFacts {
        const choice = try self.evaluate(function, access.value, state);
        const choice_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse return .{};
        const wanted = variantIndex(self.graph, choice_ty, access.variant) orelse return .{};
        if (try self.resolvePlace(access.value, state)) |storage| {
            if (!self.variantActive(state, storage, wanted)) {
                try self.report(source, "choice payload requires its variant to be proven active", .{});
                return .{};
            }
        } else if (choice.known_choice_variant != wanted) {
            try self.report(source, "choice payload access requires a proven active variant", .{});
            return .{};
        }
        for (choice.variants) |variant| if (variant.index == wanted) return variant.value.*;
        return .{};
    }

    fn evaluateVirtualCall(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalVirtualCallId, state: *FunctionState) !facts.ValueFacts {
        const call = self.graph.virtual_calls.items[@intFromEnum(id)];
        _ = try self.evaluate(function, call.handle, state);
        _ = try self.evaluate(function, call.input, state);
        return .{};
    }

    fn applyAutoDeinit(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalAutoDeinitId, state: *FunctionState) !void {
        _ = function;
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
        const storage = facts.Place{ .root = cleanup.binding };
        const current = self.getPlace(state, storage) orelse return;
        if (current.initializedness != .initialized) return;
        if (cleanup.deinit_fn) |deinit_fn| {
            if (cleanup.input) |input| {
                const call_node: graph_mod.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
                _ = call_node;
                // GlobalSema already resolved destructor identity/input. Safety
                // executes the same function body through a synthetic call path.
                const values = [_]facts.ValueFacts{current.value};
                var candidate = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                defer candidate.deinit();
                const fn_record = self.graph.functions.items[@intFromEnum(deinit_fn)];
                try self.bindCallInputs(fn_record, &values, &candidate);
                if (fn_record.body) |body| try self.validateBlock(deinit_fn, body, &candidate);
                self.commitState(state, &candidate);
                _ = input;
            }
        }
        for (current.value.owned_roots) |root| state.tracker.end(root);
        try self.setPlace(state, storage, .deinitialized, .{});
    }

    fn resolvePlace(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId, state: *FunctionState) !?facts.Place {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .binding_use => |binding| facts.Place{ .root = binding },
            .address_of => |child| self.resolvePlace(child, state),
            .dereference => |deref| blk: {
                const value = try self.evaluate(@enumFromInt(0), deref.pointer, state);
                break :blk value.referenced_place;
            },
            .struct_field_access => |access| if (try self.resolvePlace(access.value, state)) |base| try self.project(base, .{ .field = access.field_index }) else null,
            .array_index => |access| if (try self.resolvePlace(access.array_ptr, state)) |base| try self.project(base, if (self.staticIndex(access.index)) |index| .{ .static_index = index } else .dynamic_index) else null,
            else => null,
        };
    }

    fn project(self: *SafetyChecker, base: facts.Place, projection: facts.Projection) !facts.Place {
        const projections = try self.allocator.alloc(facts.Projection, base.projections.len + 1);
        @memcpy(projections[0..base.projections.len], base.projections);
        projections[base.projections.len] = projection;
        return .{ .root = base.root, .projections = projections };
    }

    fn storageGeneration(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) !facts.ValidityRootId {
        _ = self;
        for (state.storage_generations.items) |entry| if (entry.storage.eql(storage)) return entry.generation;
        const root = try state.tracker.establish(.fresh);
        try state.storage_generations.append(.{ .storage = storage, .generation = root });
        return root;
    }

    fn setPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, initializedness: value_state.Initializedness, value: facts.ValueFacts) !void {
        _ = self;
        for (state.places.items) |*entry| if (entry.storage.eql(storage)) {
            entry.initializedness = initializedness;
            entry.value = value;
            return;
        };
        try state.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
    }

    fn getPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) ?*facts.PlaceFacts {
        _ = self;
        for (state.places.items) |*entry| if (entry.storage.eql(storage)) return entry;
        return null;
    }

    fn requireInitialized(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, state: value_state.Initializedness) !void {
        _ = function;
        switch (state) {
            .initialized => {},
            .maybe_initialized => try self.report(source, "value may be uninitialized on this path", .{}),
            .moved => try self.report(source, "value was moved", .{}),
            .deinitialized => try self.report(source, "value was deinitialized", .{}),
        }
    }

    fn requireLive(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, value: facts.ValueFacts, state: *FunctionState) !void {
        _ = function;
        if (!state.tracker.dependenciesAreAlive(value)) try self.report(source, "reference depends on a root that has ended", .{});
    }

    fn rejectEscapingLocalRoots(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, value: facts.ValueFacts, state: *FunctionState) !void {
        _ = function;
        for (value.dependencies) |dependency| if (!state.tracker.isAlive(dependency.root)) {
            try self.report(source, "returned reference depends on a local root that has ended", .{});
            return;
        };
    }

    fn endBlockStorage(self: *SafetyChecker, block_id: graph_mod.GlobalBlockId, state: *FunctionState) !void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .binding_declaration => |binding| {
                var i: usize = 0;
                while (i < state.storage_generations.items.len) {
                    const entry = state.storage_generations.items[i];
                    if (entry.storage.root == binding) {
                        state.tracker.end(entry.generation);
                        _ = state.storage_generations.orderedRemove(i);
                    } else i += 1;
                }
                i = 0;
                while (i < state.places.items.len) {
                    if (state.places.items[i].storage.root == binding) _ = state.places.orderedRemove(i) else i += 1;
                }
            },
            else => {},
        };
    }

    fn joinState(self: *SafetyChecker, out: *FunctionState, left: *const FunctionState, right: *const FunctionState) !void {
        _ = self;
        // Root liveness is conservative: if either path ended it, joined state
        // cannot claim definitely-alive.
        const count = @min(left.tracker.roots.items.len, right.tracker.roots.items.len);
        for (0..count) |index| {
            const a = left.tracker.roots.items[index].state;
            const b = right.tracker.roots.items[index].state;
            out.tracker.roots.items[index].state = if (a == b) a else .maybe_alive;
        }
        for (out.places.items) |*place| {
            const a = findPlaceConst(left, place.storage);
            const b = findPlaceConst(right, place.storage);
            if (a == null or b == null) {
                place.initializedness = .maybe_initialized;
                continue;
            }
            if (a.?.initializedness != b.?.initializedness) place.initializedness = .maybe_initialized;
        }
        out.reachable = left.reachable or right.reachable;
    }

    fn copyState(self: *SafetyChecker, out: *FunctionState, source: *const FunctionState) !void {
        const clone = try source.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        out.deinit();
        out.* = clone;
    }

    fn commitState(self: *SafetyChecker, target: *FunctionState, candidate: *FunctionState) void {
        _ = self;
        const old = target.*;
        target.* = candidate.*;
        candidate.* = old;
    }

    fn validateUniqueOwnership(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, state: *FunctionState) !void {
        _ = function;
        for (state.ownership_edges.items, 0..) |edge, index| for (state.ownership_edges.items[index + 1 ..]) |other| {
            if (edge.owned == other.owned and edge.owner != other.owner) {
                try self.report(source, "resource has multiple live owners", .{});
                return;
            }
        };
    }

    fn refineChoice(self: *SafetyChecker, state: *FunctionState, node: graph_mod.GlobalNodeId, variant: graph_mod.GlobalVariantId, active: bool) void {
        if (!active) return;
        const storage = self.resolvePlace(node, state) catch null orelse return;
        const ty = self.graph.nodes.items[@intFromEnum(node)].ty orelse return;
        const index = variantIndex(self.graph, ty, variant) orelse return;
        self.setActiveVariant(state, storage, index);
    }

    fn setActiveVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {
        _ = self;
        for (state.choice_active.items) |*entry| if (entry.storage.eql(storage)) { entry.variant_index = index; return; };
        state.choice_active.append(.{ .storage = storage, .variant_index = index }) catch {};
    }

    fn variantActive(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) bool {
        _ = self;
        for (state.choice_active.items) |entry| if (entry.storage.eql(storage)) return entry.variant_index == index;
        return false;
    }

    fn staticIndex(self: *SafetyChecker, node: graph_mod.GlobalNodeId) ?usize {
        return switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .int_literal => |value| if (value >= 0) @intCast(value) else null,
            else => null,
        };
    }

    fn oneDependency(self: *SafetyChecker, root: facts.ValidityRootId) ![]const facts.ValidityDependency {
        const out = try self.allocator.alloc(facts.ValidityDependency, 1);
        out[0] = .{ .root = root };
        return out;
    }

    fn oneRoot(self: *SafetyChecker, root: facts.ValidityRootId) ![]const facts.ValidityRootId {
        const out = try self.allocator.alloc(facts.ValidityRootId, 1);
        out[0] = root;
        return out;
    }

    fn oneCapability(self: *SafetyChecker, capability: facts.StorageCapabilityId) ![]const facts.StorageCapabilityId {
        const out = try self.allocator.alloc(facts.StorageCapabilityId, 1);
        out[0] = capability;
        return out;
    }

    fn globalValueFieldIds(self: *SafetyChecker, range: primitives.Range(graph_mod.GlobalValueFieldId)) []const graph_mod.GlobalValueFieldId {
        // ValueFieldId is a dense table ID; materialize an ID slice only for
        // call analysis. This is cold safety state, never persisted.
        const ids = self.allocator.alloc(graph_mod.GlobalValueFieldId, range.len) catch return &.{};
        for (ids, 0..) |*id, offset| id.* = @enumFromInt(range.start + @as(u32, @intCast(offset)));
        return ids;
    }

    fn callStackContains(self: *SafetyChecker, id: graph_mod.GlobalFunctionId) bool {
        for (self.call_stack.items) |value| if (value == id) return true;
        return false;
    }

    fn report(self: *SafetyChecker, source: primitives.SourceRef, comptime fmt: []const u8, args: anytype) !void {
        const loc = self.location(source) orelse return;
        try self.diagnostics.add(loc, .semantic, fmt, args);
    }

    fn location(self: *SafetyChecker, source: primitives.SourceRef) ?tok.Location {
        if (source.file_index >= self.graph.files.items.len) return null;
        const file = self.graph.files.items[source.file_index];
        const path = self.graph.text(file.path);
        const id = self.diagnostics.source_db.findPath(path) orelse return null;
        return .{ .file = id, .offset = source.offset };
    }
};

fn findPlaceConst(state: *const SafetyChecker.FunctionState, storage: facts.Place) ?*const facts.PlaceFacts {
    for (state.places.items) |*entry| if (entry.storage.eql(storage)) return entry;
    return null;
}

fn isPointer(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return switch (graph.types.items[@intFromEnum(ty)]) { .pointer => true, else => false };
}

fn variantIndex(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId) ?u32 {
    const range = types.variants(graph, ty) orelse return null;
    const raw = @intFromEnum(variant);
    if (raw < range.start or raw >= range.start + range.len) return null;
    return raw - range.start;
}

test "global safety checker keys program state by compact ids" {
    try std.testing.expect(@sizeOf(graph_mod.GlobalBindingId) == 4);
    try std.testing.expect(@sizeOf(graph_mod.GlobalNodeId) == 4);
}
