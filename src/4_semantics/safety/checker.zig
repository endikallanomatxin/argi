const std = @import("std");
const diagnostics = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const facts = @import("facts.zig");
const summary_engine = @import("summaries.zig");
const summary_infer = @import("summary_infer.zig");
const value_state = @import("../value_state.zig");
const primitives = @import("../primitives/schema.zig");

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
    const ChoiceRejected = struct { storage: facts.Place, variant_index: u32 };
    const ChoiceTemporaryActive = struct { expression: graph_mod.GlobalNodeId, variant_index: u32 };

    const FunctionState = struct {
        tracker: facts.Tracker,
        places: std.array_list.Managed(facts.PlaceFacts),
        storage_capabilities: std.array_list.Managed(StorageCapabilityState),
        ownership_edges: std.array_list.Managed(OwnershipEdge),
        storage_generations: std.array_list.Managed(StorageGeneration),
        lexical_storage_generations: std.array_list.Managed(facts.ValidityRootId),
        opaque_storages: std.array_list.Managed(OpaqueStorage),
        choice_active: std.array_list.Managed(ChoiceActive),
        choice_rejected: std.array_list.Managed(ChoiceRejected),
        choice_temporary_active: std.array_list.Managed(ChoiceTemporaryActive),
        reachable: bool = true,

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
                .storage_capabilities = std.array_list.Managed(StorageCapabilityState).init(allocator),
                .ownership_edges = std.array_list.Managed(OwnershipEdge).init(allocator),
                .storage_generations = std.array_list.Managed(StorageGeneration).init(allocator),
                .lexical_storage_generations = std.array_list.Managed(facts.ValidityRootId).init(allocator),
                .opaque_storages = std.array_list.Managed(OpaqueStorage).init(allocator),
                .choice_active = std.array_list.Managed(ChoiceActive).init(allocator),
                .choice_rejected = std.array_list.Managed(ChoiceRejected).init(allocator),
                .choice_temporary_active = std.array_list.Managed(ChoiceTemporaryActive).init(allocator),
            };
        }

        fn deinit(self: *FunctionState) void {
            self.tracker.deinit();
            self.places.deinit();
            self.storage_capabilities.deinit();
            self.ownership_edges.deinit();
            self.storage_generations.deinit();
            self.lexical_storage_generations.deinit();
            self.opaque_storages.deinit();
            self.choice_active.deinit();
            self.choice_rejected.deinit();
            self.choice_temporary_active.deinit();
        }

        fn clone(self: *const FunctionState, allocator: std.mem.Allocator, stats: ?*Stats) !FunctionState {
            var out = FunctionState.init(allocator);
            errdefer out.deinit();
            try out.tracker.roots.appendSlice(self.tracker.roots.items);
            try out.places.appendSlice(self.places.items);
            try out.storage_capabilities.appendSlice(self.storage_capabilities.items);
            try out.ownership_edges.appendSlice(self.ownership_edges.items);
            try out.storage_generations.appendSlice(self.storage_generations.items);
            try out.lexical_storage_generations.appendSlice(self.lexical_storage_generations.items);
            try out.opaque_storages.appendSlice(self.opaque_storages.items);
            try out.choice_active.appendSlice(self.choice_active.items);
            try out.choice_rejected.appendSlice(self.choice_rejected.items);
            try out.choice_temporary_active.appendSlice(self.choice_temporary_active.items);
            out.reachable = self.reachable;
            if (stats) |s| {
                s.state_clones += 1;
                s.state_elements_copied += @intCast(self.tracker.roots.items.len + self.places.items.len + self.storage_capabilities.items.len + self.ownership_edges.items.len + self.storage_generations.items.len + self.lexical_storage_generations.items.len + self.opaque_storages.items.len + self.choice_active.items.len + self.choice_rejected.items.len + self.choice_temporary_active.items.len);
            }
            return out;
        }
    };

    const LoopTransfers = struct {
        break_state: ?FunctionState = null,
        continue_state: ?FunctionState = null,

        fn deinit(self: *LoopTransfers) void {
            if (self.break_state) |*state| state.deinit();
            if (self.continue_state) |*state| state.deinit();
        }
    };

    const LoopRootPhi = struct {
        storage: facts.Place,
        root: facts.ValidityRootId,
    };

    const LoopJoinContext = struct {
        roots: std.array_list.Managed(LoopRootPhi),

        fn init(allocator: std.mem.Allocator) LoopJoinContext {
            return .{ .roots = std.array_list.Managed(LoopRootPhi).init(allocator) };
        }

        fn deinit(self: *LoopJoinContext) void {
            self.roots.deinit();
        }
    };

    allocator: std.mem.Allocator,
    diagnostics: *diagnostics.Diagnostics,
    graph: *graph_mod.GlobalSemanticGraph,
    call_stack: std.array_list.Managed(graph_mod.GlobalFunctionId),
    active_summaries: ?*summary_engine.Engine = null,
    active_summary_inference: ?*summary_infer.Infer = null,
    collect_stats: bool = false,
    stats: Stats = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        diags: *diagnostics.Diagnostics,
        graph: *graph_mod.GlobalSemanticGraph,
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

    pub fn enableStats(self: *SafetyChecker) void {
        self.collect_stats = true;
    }

    pub fn analyze(self: *SafetyChecker) !void {
        self.stats = .{};
        const before = self.diagnostics.list.items.len;
        try self.validateNominalChoiceLayouts();

        var engine = summary_engine.Engine.init(self.allocator);
        defer engine.deinit();
        var inference = summary_infer.Infer.init(self.allocator, self.graph, &engine);
        defer inference.deinit();
        try inference.inferOutputFixedPoint();
        self.active_summaries = &engine;
        self.active_summary_inference = &inference;
        defer self.active_summary_inference = null;
        defer self.active_summaries = null;

        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null or function.safety_primitive != .none) continue;
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            var state = FunctionState.init(self.allocator);
            defer state.deinit();
            try self.seedFunctionInputs(function, &state);
            try self.call_stack.append(id);
            defer _ = self.call_stack.pop();
            try self.validateBlock(id, function.body.?, &state, null);
            if (state.reachable) try self.rejectEscapingOutputBindings(id, &state);
            if (self.collect_stats) self.stats.functions += 1;
        }
        if (self.diagnostics.list.items.len != before) return error.Reported;
    }

    fn validateNominalChoiceLayouts(self: *SafetyChecker) !void {
        for (self.graph.declarations.items) |declaration| {
            if (declaration.choice_layout != .c_enum) continue;
            const variants = declaration.choice_variants orelse continue;
            for (self.graph.variants.items[variants.start..][0..variants.len]) |variant| {
                if (variant.payload_type == null) continue;
                try self.report(variant.source, "CEnum variant '..{s}' cannot carry a payload", .{self.graph.text(variant.name)});
            }
        }
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
        // Outputs without defaults are storage to be filled by the body.
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding| {
            const record = self.graph.binding(binding);
            try self.setPlace(state, .{ .root = binding }, if (record.initialization == null) .deinitialized else .initialized, .{});
        }
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        state: *FunctionState,
        loop_transfers: ?*LoopTransfers,
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!state.reachable) break;
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .binding_declaration => |binding| {
                    const record = self.graph.bindings.items[@intFromEnum(binding)];
                    const value = if (record.initialization) |initialization| blk: {
                        try self.validateContextualIntegerLiteral(initialization, record.ty);
                        break :blk try self.evaluate(function, initialization, state);
                    } else facts.ValueFacts{};
                    try self.setPlace(state, .{ .root = binding }, if (record.initialization != null) .initialized else .deinitialized, value);
                },
                .assignment => |assignment| {
                    const binding = self.graph.binding(assignment.binding);
                    if (binding.mutability == .constant and self.initializednessAtPlace(state, .{ .root = assignment.binding }) == .initialized)
                        try self.report(node.source, "binding '{s}' is constant and cannot be reassigned after initialization", .{self.graph.text(binding.name)});
                    try self.validateContextualIntegerLiteral(assignment.value, self.graph.binding(assignment.binding).ty);
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.setPlace(state, .{ .root = assignment.binding }, .initialized, value);
                },
                .auto_deinit_binding => |auto_id| try self.applyAutoDeinit(function, auto_id, state),
                .struct_field_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, node.source, store.struct_ptr, state) orelse continue;
                    const value = try self.evaluate(function, store.value, state);
                    try self.recordOpaqueWrite(state, pointer, value);
                    if (try self.resolvePlace(store.struct_ptr, state)) |base|
                        try self.setPlace(state, try self.project(base, .{ .field = store.field_index }), .initialized, value);
                },
                .array_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, node.source, store.array_ptr, state) orelse continue;
                    _ = try self.evaluate(function, store.index, state);
                    const value = try self.evaluate(function, store.value, state);
                    try self.recordOpaqueWrite(state, pointer, value);
                    if (try self.resolvePlace(store.array_ptr, state)) |base| {
                        const projection: facts.Projection = if (self.staticIndex(store.index)) |index| .{ .static_index = index } else .dynamic_index;
                        try self.setPlace(state, try self.project(base, projection), .initialized, value);
                    }
                },
                .pointer_assignment => |assignment| {
                    var pointer = try self.evaluate(function, assignment.pointer, state);
                    if (pointer.referenced_place) |target| {
                        if (self.initializednessAtPlace(state, target) == .deinitialized and pointer.opaque_provenance.len == 0) {
                            const old_generation = try self.storageGeneration(state, target);
                            try self.refreshStorageGenerationChecked(node.source, state, target);
                            const generation = try self.storageGeneration(state, target);
                            // Only the precise pointer used to initialize storage
                            // follows its new generation; historical aliases do not.
                            pointer = try self.replaceValueRoots(pointer, &.{old_generation}, generation);
                            if (try self.resolvePlace(assignment.pointer, state)) |pointer_storage|
                                try self.setPlace(state, pointer_storage, .initialized, pointer);
                        }
                    }
                    try self.requireLive(function, node.source, pointer, state);
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.recordOpaqueWrite(state, pointer, value);
                    if (pointer.referenced_place) |target| try self.setPlace(state, target, .initialized, value);
                },
                .if_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    var then_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer then_state.deinit();
                    if (statement.choice_test) |choice_test| try self.refineChoice(&then_state, choice_test.choice_value, choice_test.variant, choice_test.then_has_variant);
                    try self.validateBlock(function, statement.then_block, &then_state, loop_transfers);
                    var else_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    defer else_state.deinit();
                    if (statement.choice_test) |choice_test| try self.refineChoice(&else_state, choice_test.choice_value, choice_test.variant, !choice_test.then_has_variant);
                    if (statement.else_block) |child| try self.validateBlock(function, child, &else_state, loop_transfers);
                    try self.joinState(state, &then_state, &else_state);
                },
                .while_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    try self.validateLoop(function, statement.body, state, null);
                },
                .for_statement => |statement| {
                    if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);
                    _ = try self.evaluate(function, statement.condition, state);
                    try self.validateLoop(function, statement.body, state, statement.increment);
                },
                .switch_statement => |switch_id| try self.validateSwitch(function, switch_id, state, loop_transfers),
                .return_statement => |ret| {
                    if (ret.expression) |expression| {
                        const value = try self.evaluate(function, expression, state);
                        try self.rejectEscapingLocalRoots(function, node.source, value, state);
                    }
                    try self.rejectEscapingOutputBindings(function, state);
                    for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |cleanup|
                        _ = try self.evaluate(function, cleanup, state);
                    state.reachable = false;
                },
                .break_statement => {
                    if (loop_transfers) |transfers| try self.mergeLoopTransfer(&transfers.break_state, state);
                    state.reachable = false;
                },
                .continue_statement => {
                    if (loop_transfers) |transfers| try self.mergeLoopTransfer(&transfers.continue_state, state);
                    state.reachable = false;
                },
                .code_block => |nested| try self.validateBlock(function, nested, state, loop_transfers),
                else => _ = try self.evaluate(function, node_id, state),
            }
            try self.validateUniqueOwnership(function, node.source, state);
            if (!state.reachable) {
                try self.endBlockStorage(block_id, state);
                if (loop_transfers) |transfers| {
                    if (transfers.break_state) |*break_state| try self.endBlockStorage(block_id, break_state);
                    if (transfers.continue_state) |*continue_state| try self.endBlockStorage(block_id, continue_state);
                }
                return;
            }
        }
        try self.endBlockStorage(block_id, state);
    }

    fn validateSwitch(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        switch_id: graph_mod.GlobalSwitchId,
        state: *FunctionState,
        loop_transfers: ?*LoopTransfers,
    ) !void {
        const sw = self.graph.switches.items[@intFromEnum(switch_id)];
        const choice = try self.evaluate(function, sw.expression, state);
        var joined: ?FunctionState = null;
        defer if (joined) |*value| value.deinit();
        for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
            var branch = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            defer branch.deinit();
            try self.refineChoice(&branch, sw.expression, case.variant, true);
            if (case.payload_binding) |binding| {
                const wanted = variantIndex(self.graph, self.graph.nodes.items[@intFromEnum(sw.expression)].ty.?, case.variant) orelse 0;
                var payload: facts.ValueFacts = .{};
                for (choice.variants) |variant| if (variant.index == wanted) {
                    payload = variant.value.*;
                    break;
                };
                try self.activateConditionalOwnedRoots(&branch, payload);
                try self.setPlace(&branch, .{ .root = binding }, .initialized, switch (case.payload_mode) {
                    .value, .move => payload,
                    .borrow, .mut_borrow => payload.referenceCopy(),
                });
                if (case.payload_mode == .move) if (try self.resolvePlace(sw.expression, &branch)) |storage| {
                    var transferred = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer transferred.deinit();
                    try collectOwnedRoots(payload, &transferred);
                    try self.setPlace(&branch, storage, .initialized, try self.withoutOwnedRoots(choice, transferred.items));
                };
            }
            try self.validateBlock(function, case.body, &branch, loop_transfers);
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
            try self.validateBlock(function, child, &branch, loop_transfers);
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
                try self.validateAddressAccess(function, node.source, child, state);
                const storage = try self.resolvePlace(child, state);
                const opaque_provenance = try self.opaqueProvenanceForAccess(child, state);
                var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                if (opaque_provenance.len == 0) {
                    if (storage) |target| try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, target) });
                } else {
                    for (opaque_provenance) |provenance|
                        try appendDependencyFact(&dependencies, .{ .root = provenance.generation });
                }
                break :blk .{
                    .dependencies = try dependencies.toOwnedSlice(),
                    .referenced_place = storage,
                    .opaque_provenance = opaque_provenance,
                };
            },
            .dereference => |deref| blk: {
                const pointer = try self.evaluatePointerUse(function, node.source, deref.pointer, state) orelse break :blk .{};
                var value: facts.ValueFacts = .{};
                if (pointer.referenced_place) |storage| {
                    const initializedness = self.initializednessAtPlace(state, storage);
                    try self.requireInitialized(function, node.source, initializedness);
                    value = self.valueAtPlace(state, storage) orelse .{};
                }
                break :blk try self.envelopeOpaqueRead(state, value, node.ty, pointer);
            },
            .struct_field_access => |access| blk: {
                if (try self.resolvePlace(node_id, state)) |storage| {
                    const initializedness = self.initializednessAtPlace(state, storage);
                    try self.requireInitialized(function, node.source, initializedness);
                    if (self.valueAtPlace(state, storage)) |value| {
                        const provenance = try self.opaqueProvenanceCarriedByAccess(access.value, state);
                        break :blk try self.addOpaqueReadEnvelope(value, node.ty, provenance);
                    }
                }
                const aggregate = try self.evaluate(function, access.value, state);
                for (aggregate.fields) |field| if (field.index == access.field_index) break :blk field.value.*;
                break :blk aggregate;
            },
            .array_index => |access| blk: {
                const pointer = try self.evaluatePointerUse(function, node.source, access.array_ptr, state) orelse break :blk .{};
                _ = try self.evaluate(function, access.index, state);
                var value: facts.ValueFacts = .{};
                if (pointer.referenced_place) |base| {
                    const projection: facts.Projection = if (self.staticIndex(access.index)) |index| .{ .static_index = index } else .dynamic_index;
                    const storage = try self.project(base, projection);
                    const initializedness = self.initializednessAtPlace(state, storage);
                    try self.requireInitialized(function, node.source, initializedness);
                    value = self.valueAtPlace(state, storage) orelse .{};
                }
                break :blk try self.envelopeOpaqueRead(state, value, node.ty, pointer);
            },
            .struct_value_literal => |literal| try self.evaluateStruct(function, literal, state),
            .list_literal => |literal| try self.evaluateList(function, literal, state),
            .array_literal => |literal| try self.evaluateArray(function, literal, state),
            .choice_literal => |literal| try self.evaluateChoice(function, literal, state),
            .choice_payload_access => |access| try self.evaluateChoicePayload(function, node.source, access, state),
            .function_call => |call| try self.evaluateCall(function, node_id, call, state),
            .virtual_call => |call_id| try self.evaluateVirtualCall(function, call_id, state),
            .virtualize => |virtualize_id| blk: {
                const virtualize = self.graph.virtualizes.items[@intFromEnum(virtualize_id)];
                if (self.active_summary_inference) |inference| {
                    for (self.graph.virtual_registry_refs.items[virtualize.safety_methods.start..][0..virtualize.safety_methods.len]) |registry_id| {
                        const merged = try inference.virtualSummary(registry_id);
                        if (merged == null and inference.virtualSummaryInvalid(registry_id)) {
                            try self.report(
                                virtualize.source,
                                "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
                                .{},
                            );
                            break;
                        }
                    }
                }
                var value = (try self.evaluate(function, virtualize.value, state)).referenceCopy();
                value.virtual_methods = self.graph.function_refs.items[virtualize.methods.start..][0..virtualize.methods.len];
                break :blk value;
            },
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
                // An integer value cannot acquire reference provenance merely
                // by casting it, even when its numeric value is zero.
                if (isPointer(self.graph, cast.target_type) and !isPointer(self.graph, self.graph.nodes.items[@intFromEnum(cast.value)].ty orelse cast.target_type)) {
                    try self.report(node.source, "an integer address cannot establish a safe reference; use an explicit root establishment boundary", .{});
                    break :blk .{};
                }
                break :blk value;
            },
            .binary_operation => |binary| blk: {
                _ = try self.evaluate(function, binary.left, state);
                _ = try self.evaluate(function, binary.right, state);
                break :blk .{};
            },
            .comparison => |cmp| blk: {
                _ = try self.evaluate(function, cmp.left, state);
                _ = try self.evaluate(function, cmp.right, state);
                break :blk .{};
            },
            .logical_operation => |logic| blk: {
                _ = try self.evaluate(function, logic.left, state);
                var right_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                defer right_state.deinit();
                if (self.choiceTestFromCondition(logic.left)) |choice_test| {
                    const left_has_variant = logic.operator == .and_;
                    try self.refineChoice(
                        &right_state,
                        choice_test.choice_value,
                        choice_test.variant,
                        left_has_variant == choice_test.then_has_variant,
                    );
                }
                _ = try self.evaluate(function, logic.right, &right_state);
                try self.joinState(state, state, &right_state);
                break :blk .{};
            },
            .code_block => |block| blk: {
                try self.validateBlock(function, block, state, null);
                break :blk .{};
            },
            .int_literal => |value| blk: {
                try self.validateIntegerLiteral(node.source, node.ty, value);
                break :blk .{};
            },
            .float_literal, .char_literal, .string_literal, .bool_literal, .declaration, .type_initializer, .testing_expect_error, .reach_directive, .break_statement, .continue_statement => .{},
            else => .{},
        };
    }

    fn evaluateCall(
        self: *SafetyChecker,
        caller: graph_mod.GlobalFunctionId,
        call_node: graph_mod.GlobalNodeId,
        call: anytype,
        state: *FunctionState,
    ) !facts.ValueFacts {
        if (self.collect_stats) self.stats.calls += 1;
        var candidate = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        const result = try self.evaluateCallCandidate(caller, call_node, call, &candidate);
        if (self.diagnostics.list.items.len != diagnostic_count) return .{};
        self.commitState(state, &candidate);
        return result;
    }

    fn evaluateCallCandidate(
        self: *SafetyChecker,
        caller: graph_mod.GlobalFunctionId,
        call_node: ?graph_mod.GlobalNodeId,
        call: anytype,
        state: *FunctionState,
    ) !facts.ValueFacts {
        const callee = self.graph.functions.items[@intFromEnum(call.callee)];
        var argument_nodes: []const graph_mod.GlobalValueFieldId = &.{};
        const input_node = self.graph.nodes.items[@intFromEnum(call.input)];
        if (input_node.content == .struct_value_literal) {
            const range = input_node.content.struct_value_literal.fields;
            argument_nodes = self.globalValueFieldIds(range);
        }

        var values = try self.allocator.alloc(facts.ValueFacts, argument_nodes.len);
        defer self.allocator.free(values);
        for (argument_nodes, 0..) |field_id, index| {
            const field = self.graph.value_fields.items[@intFromEnum(field_id)];
            values[index] = try self.evaluate(caller, field.value, state);
        }

        if (callee.safety_primitive != .none) {
            if (self.collect_stats) self.stats.primitive_calls += 1;
            return self.evaluatePrimitive(caller, callee.safety_primitive, argument_nodes, values, state, input_node.source);
        }
        if (callee.body == null) {
            // Argument evaluation is still part of the successful call and is
            // committed by the outer transaction. Foreign pointers themselves
            // do not become safe references implicitly.
            if (callee.output.len == 1 and isPointer(self.graph, self.graph.fields.items[callee.output.start].ty))
                return .{ .foreign_storage = true };
            return .{};
        }

        if (self.callStackContains(call.callee) and self.collect_stats) self.stats.recursive_edges += 1;
        return (try self.applyFunctionSummary(input_node.source, call_node, call.callee, argument_nodes, values, state)) orelse .{};
    }

    fn applyFunctionSummary(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        call_node: ?graph_mod.GlobalNodeId,
        callee: graph_mod.GlobalFunctionId,
        argument_nodes: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?facts.ValueFacts {
        const engine = self.active_summaries orelse return null;
        const summary = engine.summaryFor(callee) orelse return null;
        if (!try self.validateSummaryRequiredLive(source, summary, values, state)) return facts.ValueFacts{};
        if (call_node) |node| self.recordFunctionCallAutoDeinit(node, summary, argument_nodes);
        try self.applySummaryEffects(source, summary, argument_nodes, values, state);
        return try self.instantiateSummaryOutputs(summary.outputs, values, state);
    }

    fn recordFunctionCallAutoDeinit(
        self: *SafetyChecker,
        call_node: graph_mod.GlobalNodeId,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
    ) void {
        const node = &self.graph.nodes.items[@intFromEnum(call_node)];
        if (node.content != .function_call) return;
        for (summary.input_post_states) |post_state| {
            if (post_state.target.projections.len != 0 or post_state.target.input_index >= argument_ids.len) continue;
            const field = self.graph.value_fields.items[@intFromEnum(argument_ids[post_state.target.input_index])];
            if (self.graph.nodes.items[@intFromEnum(field.value)].content != .address_of or self.rootBinding(field.value) == null) continue;
            if (post_state.requires_available_destination)
                node.content.function_call.initializes_auto_deinit = field.value;
            if (post_state.initializedness == .deinitialized or post_state.initializedness == .moved)
                node.content.function_call.consumes_auto_deinit = field.value;
        }
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
                        else
                            state.storage_capabilities.items[raw] = .consumed;
                    }
                }
                break :blk .{
                    .dependencies = try self.oneDependency(root),
                    .owned_roots = if (primitive == .establish_allocation) try self.oneRoot(root) else &.{},
                };
            },
            .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference, .restrict_reference, .read_reference => if (values.len != 0) values[0].referenceCopy() else .{},
            .relocate => try self.relocatePrimitive(source, values, state),
            .trusted_opaque_move, .trusted_opaque_move_in => blk: {
                try self.applyOpaqueMovePrimitive(function, source, argument_ids, values, state);
                break :blk .{};
            },
            .trusted_opaque_move_out => try self.opaqueMoveOutPrimitive(argument_ids, values, state),
            .trusted_opaque_relocate => blk: {
                if (values.len != 0) try self.rejectOpaqueRelocation(source, state, values[0]);
                break :blk .{};
            },
            .trusted_opaque_mark_empty => blk: {
                if (try self.primitiveArgumentStorage(argument_ids, values, 0, state)) |storage|
                    self.markOpaqueStorageEmpty(state, storage);
                break :blk .{};
            },
            // Slot destruction is trusted runtime behavior. Domain emptiness is
            // communicated explicitly by mark_empty and by summaries.
            .trusted_opaque_drop => .{},
        };
    }

    fn relocatePrimitive(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        if (values.len != 2) return .{};
        const source_place = values[0].referenced_place orelse return .{};
        const destination = values[1].referenced_place orelse return .{};
        if (source_place.eql(destination)) {
            try self.report(source, "relocate requires distinct source and destination places", .{});
            return .{};
        }
        const source_state = self.initializednessAtPlace(state, source_place);
        if (source_state != .initialized) {
            try self.requireInitialized(@enumFromInt(0), source, source_state);
            return .{};
        }
        switch (self.initializednessAtPlace(state, destination)) {
            .initialized => {
                try self.report(source, "relocate destination is initialized", .{});
                return .{};
            },
            .maybe_initialized => {
                try self.report(source, "relocate destination may be initialized", .{});
                return .{};
            },
            .deinitialized => try self.refreshStorageGenerationChecked(source, state, destination),
            .moved => {},
        }
        const value = self.valueAtPlace(state, source_place) orelse return .{};
        try self.setPlace(state, destination, .initialized, value);
        try self.setPlace(state, source_place, .moved, .{});
        return .{};
    }

    fn applyOpaqueMovePrimitive(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        if (values.len == 3) {
            try self.closeOpaqueOwnedRoots(source, values[2], state, null);
            if (try self.primitiveArgumentStorage(argument_ids, values, 0, state)) |storage| {
                try self.markOpaqueArgumentAccess(argument_ids, 1, state, storage);
                try self.hideOpaqueDependencies(state, storage, values[2]);
                return;
            }
            const root_binding = self.primitiveArgumentRootBinding(argument_ids, 0);
            if (root_binding != null and self.functionInputIndex(function, root_binding.?) != null) return;
            if (valueHasDependency(values[2]))
                try self.report(source, "opaque ownership storage requires an identifiable storage domain place", .{});
            return;
        }
        if (values.len == 2) {
            if (hasExternalOpaqueDependency(values[1], values[1].owned_roots)) {
                try self.report(source, "opaque ownership storage cannot hide dependencies on external roots", .{});
                return;
            }
            try self.closeOpaqueOwnedRoots(source, values[1], state, null);
            if (try self.inferOpaqueDomain(state, values[0])) |storage| {
                try self.markOpaqueArgumentAccess(argument_ids, 0, state, storage);
                try self.hideOpaqueDependencies(state, storage, values[1]);
            }
        }
    }

    fn opaqueMoveOutPrimitive(
        self: *SafetyChecker,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        const root = try state.tracker.establish(.fresh);
        state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        if (try self.primitiveArgumentStorage(argument_ids, values, 0, state)) |storage| {
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency| {
                    if (self.opaqueDependencyIsInternalToStorage(state, storage, dependency)) continue;
                    try appendDependencyFact(&dependencies, .{ .root = dependency });
                }
            }
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try self.oneRoot(root),
        };
    }

    fn primitiveArgumentStorage(
        self: *SafetyChecker,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        index: usize,
        state: *FunctionState,
    ) !?facts.Place {
        if (index >= values.len) return null;
        if (values[index].referenced_place) |storage| return storage;
        if (index >= argument_ids.len) return null;
        const argument = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
        return self.resolvePlace(argument, state);
    }

    fn markOpaqueArgumentAccess(
        self: *SafetyChecker,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        index: usize,
        state: *FunctionState,
        storage: facts.Place,
    ) !void {
        if (index >= argument_ids.len) return;
        const argument = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
        const pointer_place = try self.resolvePlace(argument, state) orelse return;
        const pointer = self.getPlace(state, pointer_place) orelse return;
        try self.addOpaqueAccessProvenance(state, &pointer.value, storage);
    }

    fn addOpaqueAccessProvenance(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: *facts.ValueFacts,
        storage: facts.Place,
    ) !void {
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        try provenances.appendSlice(pointer.opaque_provenance);
        for (provenances.items) |provenance| if (provenance.storage.eql(storage)) return;

        var inferred = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        defer inferred.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, pointer.*, &inferred);
        for (inferred.items) |provenance|
            if (provenance.storage.eql(storage)) try appendOpaqueProvenanceFact(&provenances, provenance);

        var found = false;
        for (provenances.items) |provenance| if (provenance.storage.eql(storage)) {
            found = true;
            break;
        };
        if (!found) {
            var domain_already_opaque = false;
            for (state.opaque_storages.items) |opaque_storage| if (opaque_storage.storage.eql(storage)) {
                domain_already_opaque = true;
                break;
            };
            if (!domain_already_opaque) try appendOpaqueProvenanceFact(&provenances, .{
                .storage = storage,
                .generation = try self.storageGeneration(state, storage),
            });
        }
        pointer.opaque_provenance = try provenances.toOwnedSlice();
    }

    fn inferOpaqueDomain(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
    ) !?facts.Place {
        var storages = std.array_list.Managed(facts.Place).init(self.allocator);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &storages);
        if (storages.items.len != 0) return storages.items[0];
        var index = state.places.items.len;
        while (index > 0) {
            index -= 1;
            const candidate = state.places.items[index];
            if (candidate.initializedness != .initialized) continue;
            for (pointer.dependencies) |dependency|
                if (valueContainsOwnedRoot(candidate.value, dependency.root)) return candidate.storage;
        }
        return null;
    }

    fn rejectOpaqueRelocation(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        pointer: facts.ValueFacts,
    ) !void {
        var storages = std.array_list.Managed(facts.Place).init(self.allocator);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &storages);
        for (storages.items) |storage| {
            const generation = try self.storageGeneration(state, storage);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                var invalidates_dependency = containsRoot(opaque_storage.hidden_dependencies, generation);
                if (!invalidates_dependency) {
                    const storage_value = self.valueAtPlace(state, storage) orelse facts.ValueFacts{};
                    for (opaque_storage.hidden_dependencies) |dependency| {
                        if (!valueContainsOwnedRoot(storage_value, dependency)) continue;
                        invalidates_dependency = true;
                        break;
                    }
                }
                if (!invalidates_dependency) continue;
                try self.report(source, "relocation would invalidate a hidden opaque dependency", .{});
                return;
            }
        }
    }

    fn primitiveArgumentRootBinding(
        self: *SafetyChecker,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        index: usize,
    ) ?graph_mod.GlobalBindingId {
        if (index >= argument_ids.len) return null;
        const node = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
        return self.rootBinding(node);
    }

    fn rootBinding(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId) ?graph_mod.GlobalBindingId {
        return switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .binding_use => |binding| binding,
            .move_value, .address_of => |child| self.rootBinding(child),
            .struct_field_access => |access| self.rootBinding(access.value),
            .array_index => |access| self.rootBinding(access.array_ptr),
            .dereference => |access| self.rootBinding(access.pointer),
            .choice_payload_access => |access| self.rootBinding(access.value),
            else => null,
        };
    }

    fn functionInputIndex(
        self: *SafetyChecker,
        function_id: graph_mod.GlobalFunctionId,
        binding: graph_mod.GlobalBindingId,
    ) ?usize {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const inputs = self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len];
        for (inputs, 0..) |candidate, index| if (candidate == binding) return index;
        return null;
    }

    fn validateSummaryRequiredLive(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        summary: facts.SafetySummary,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !bool {
        const before = self.diagnostics.list.items.len;
        for (summary.required_live_inputs) |path| {
            if (path.input_index >= arguments.len) continue;
            var value = try self.projectValueFacts(arguments[path.input_index], path.projections);
            if (path.projections.len != 0) if (arguments[path.input_index].referenced_place) |base| {
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                if (self.valueAtPlace(state, target)) |stored| value = stored;
            };
            try self.requireLive(@enumFromInt(0), source, value, state);
        }
        return self.diagnostics.list.items.len == before;
    }

    fn applySummaryEffects(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        try self.applySummaryOpaqueStorageEmpties(summary, argument_ids, arguments, state);
        try self.applySummaryInputPostStates(source, summary, argument_ids, arguments, state);
        try self.applySummaryOpaqueStorageEmpties(summary, argument_ids, arguments, state);
        try self.applySummaryOpaqueStorageEffects(summary, argument_ids, arguments, state);
    }

    fn applySummaryInputPostStates(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator);
        defer fresh_roots.deinit();
        var fresh_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator);
        defer fresh_capabilities.deinit();

        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            const index: usize = @intCast(post_state.target.input_index);

            if (post_state.opaque_ownership == .none and post_state.initializedness == .initialized and
                post_state.may_repopulate_opaque_storage)
            {
                var storages = std.array_list.Managed(facts.Place).init(self.allocator);
                defer storages.deinit();
                try self.collectOpaqueDomainsAccessedBy(state, arguments[index], &storages);
                if (storages.items.len != 0) {
                    var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer hidden.deinit();
                    try self.instantiateOpaqueDependencies(post_state.value, arguments, state, &fresh_roots, &hidden);
                    for (storages.items) |storage| try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
                }
            }

            if (post_state.opaque_ownership == .ambiguous) {
                try self.report(source, "opaque ownership consumption has no single representable storage", .{});
                continue;
            }
            if (post_state.opaque_ownership == .definite or post_state.opaque_ownership == .conditional) {
                const consumed = try self.resolveSummaryInputPath(post_state.target, argument_ids, arguments, state);
                const projected = try self.projectValueFacts(arguments[index], post_state.target.projections);
                const value = if (consumed) |target|
                    if (self.valueAtPlace(state, target)) |stored| stored else projected
                else
                    projected;

                if (post_state.opaque_storage) |opaque_path| {
                    const storage = try self.resolveSummaryInputPath(opaque_path, argument_ids, arguments, state) orelse continue;
                    try self.closeOpaqueOwnedRoots(source, value, state, consumed);
                    if (consumed) |target| try self.setPlace(state, target, .moved, .{});
                    try self.hideOpaqueDependencies(state, storage, value);
                } else {
                    if (hasExternalOpaqueDependency(value, value.owned_roots))
                        try self.report(source, "opaque ownership storage cannot hide dependencies on external roots", .{});
                    try self.closeOpaqueOwnedRoots(source, value, state, consumed);
                    if (consumed) |target| try self.setPlace(state, target, .moved, .{});
                }
                continue;
            }

            const target = try self.resolveSummaryInputPath(post_state.target, argument_ids, arguments, state) orelse {
                if (post_state.ends_previous_roots and post_state.target.projections.len == 0) {
                    for (arguments[index].dependencies) |dependency| _ = try self.endRoot(source, state, dependency.root);
                }
                continue;
            };

            if (post_state.requires_available_destination) {
                if (self.getPlace(state, target)) |current| {
                    if (current.initializedness == .initialized) {
                        try self.report(source, "relocate destination is initialized", .{});
                        continue;
                    }
                    if (current.initializedness == .maybe_initialized) {
                        try self.report(source, "relocate destination may be initialized", .{});
                        continue;
                    }
                }
            }

            const reinitializes_dead_place = post_state.initializedness == .initialized and
                (if (self.getPlace(state, target)) |current| current.initializedness == .deinitialized else false);
            const previous_value = self.valueAtPlace(state, target);
            if (post_state.ends_previous_roots) if (previous_value) |previous| {
                for (previous.owned_roots) |root| _ = try self.endRoot(source, state, root);
            };
            if (post_state.initializedness == .deinitialized)
                try self.endStorageGenerationsUnder(source, state, target);
            if (!post_state.requires_available_destination and (reinitializes_dead_place or post_state.refreshes_storage_generation))
                try self.refreshStorageGenerationChecked(source, state, target);

            const value = if (post_state.initializedness == .initialized)
                try self.instantiateOutputWithFresh(post_state.value, arguments, state, &fresh_roots, &fresh_capabilities)
            else
                facts.ValueFacts{};
            try self.setPlace(state, target, post_state.initializedness, value);
        }
    }

    fn resolveSummaryInputPath(
        self: *SafetyChecker,
        path_value: facts.InputPath,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?facts.Place {
        if (path_value.input_index >= arguments.len) return null;
        const index: usize = @intCast(path_value.input_index);
        var target = arguments[index].referenced_place orelse blk: {
            if (index >= argument_ids.len) return null;
            const argument = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
            const storage = try self.resolvePlace(argument, state) orelse return null;
            // An abstract pointer input has no concrete pointee Place. Its
            // binding stores the pointer itself, so writing a pointee summary
            // there would replace the pointer's own temporal dependencies.
            if (isPointer(self.graph, self.graph.binding(storage.root).ty) and
                arguments[index].referenced_place == null) return null;
            break :blk storage;
        };
        for (path_value.projections) |projection| target = try self.project(target, projection);
        return target;
    }

    fn applySummaryOpaqueStorageEffects(
        self: *SafetyChecker,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_effects) |effect| {
            const storage = try self.resolveSummaryInputPath(effect.storage, argument_ids, arguments, state) orelse continue;
            var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer hidden.deinit();
            var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator);
            defer fresh_roots.deinit();
            try self.instantiateOpaqueDependencies(effect.hidden_dependencies, arguments, state, &fresh_roots, &hidden);

            var hidden_owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer hidden_owned.deinit();
            for (effect.hidden_dependencies.input_dependencies) |dependency| {
                if (dependency.path.input_index >= arguments.len) continue;
                const value = try self.projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
                try collectOwnedRoots(value, &hidden_owned);
            }

            var external = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer external.deinit();
            for (hidden.items) |dependency| {
                var internal_generation = false;
                for (arguments) |argument| if (valueContainsOpaqueGeneration(argument, storage, dependency)) {
                    internal_generation = true;
                    break;
                };
                if (!internal_generation and !containsRoot(hidden_owned.items, dependency))
                    try appendRootFact(&external, dependency);
            }
            try self.mergeLiveOpaqueDependencies(state, storage, external.items);
        }
    }

    fn applySummaryOpaqueStorageEmpties(
        self: *SafetyChecker,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_empties) |empty_path| {
            const storage = try self.resolveSummaryInputPath(empty_path, argument_ids, arguments, state) orelse continue;
            self.markOpaqueStorageEmpty(state, storage);
        }
    }

    fn instantiateOpaqueDependencies(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
        hidden: *std.array_list.Managed(facts.ValidityRootId),
    ) !void {
        for (effect.fresh_dependencies) |fresh|
            try appendRootFact(hidden, try self.instantiateFreshRoot(fresh, state, fresh_roots));
        for (effect.input_places) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            var target = arguments[input_path.input_index].referenced_place orelse continue;
            for (input_path.projections) |projection| target = try self.project(target, projection);
            try appendRootFact(hidden, try self.storageGeneration(state, target));
        }
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            const input = try self.projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
            try self.collectOpaqueHiddenDependencies(state, input, hidden);
        }
        for (effect.input_place_values) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            var input = try self.projectValueFacts(arguments[input_path.input_index], input_path.projections);
            if (arguments[input_path.input_index].referenced_place) |base| {
                var target = base;
                for (input_path.projections) |projection| target = try self.project(target, projection);
                if (self.valueAtPlace(state, target)) |stored| input = stored;
            }
            try self.collectOpaqueHiddenDependencies(state, input, hidden);
        }
        for (effect.opaque_generation_dependencies) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            const input = try self.projectValueFacts(arguments[input_path.input_index], input_path.projections);
            var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
            defer provenances.deinit();
            try self.collectOpaqueProvenancesRecursively(state, input, &provenances);
            for (provenances.items) |provenance| try appendRootFact(hidden, provenance.generation);
        }
        for (effect.opaque_storage_dependencies) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            var storage = arguments[input_path.input_index].referenced_place orelse continue;
            for (input_path.projections) |projection| storage = try self.project(storage, projection);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency|
                    if (!self.opaqueDependencyIsInternalToStorage(state, storage, dependency))
                        try appendRootFact(hidden, dependency);
            }
        }
        for (effect.fields) |field|
            try self.instantiateOpaqueDependencies(field.value.*, arguments, state, fresh_roots, hidden);
        for (effect.variants) |variant|
            try self.instantiateOpaqueDependencies(variant.value.*, arguments, state, fresh_roots, hidden);
    }

    fn instantiateSummaryOutputs(
        self: *SafetyChecker,
        outputs: []const facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        if (outputs.len == 0) return .{};
        if (outputs.len == 1) return self.instantiateOutput(outputs[0], arguments, state);
        const fields = try self.allocator.alloc(facts.FieldFacts, outputs.len);
        var aggregate: facts.ValueFacts = .{};
        for (outputs, 0..) |effect, index| {
            const value = try self.allocator.create(facts.ValueFacts);
            value.* = try self.instantiateOutput(effect, arguments, state);
            fields[index] = .{ .index = @intCast(index), .value = value };
            aggregate = try self.mergeValueFacts(aggregate, value.*);
        }
        aggregate.fields = fields;
        return aggregate;
    }

    fn instantiateOutput(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator);
        defer fresh_roots.deinit();
        var fresh_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator);
        defer fresh_capabilities.deinit();
        return self.instantiateOutputWithFresh(effect, arguments, state, &fresh_roots, &fresh_capabilities);
    }

    fn instantiateOutputWithFresh(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
        fresh_capabilities: *std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId),
    ) !facts.ValueFacts {
        var result: facts.ValueFacts = .{};
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (effect.fresh_dependencies) |fresh| {
            const root = try self.instantiateFreshRoot(fresh, state, fresh_roots);
            try appendDependencyFact(&dependencies, .{ .root = root });
        }
        for (effect.opaque_generation_dependencies) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            const input = try self.projectValueFacts(arguments[input_path.input_index], input_path.projections);
            var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
            defer provenances.deinit();
            try self.collectOpaqueProvenancesRecursively(state, input, &provenances);
            for (provenances.items) |provenance| try appendDependencyFact(&dependencies, .{ .root = provenance.generation });
        }
        for (effect.opaque_storage_dependencies) |input_path| {
            if (input_path.input_index >= arguments.len) continue;
            var storage = arguments[input_path.input_index].referenced_place orelse continue;
            for (input_path.projections) |projection| storage = try self.project(storage, projection);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency|
                    if (!self.opaqueDependencyIsInternalToStorage(state, storage, dependency))
                        try appendDependencyFact(&dependencies, .{ .root = dependency });
            }
        }

        var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (effect.fresh_owned_roots) |fresh| {
            const root = try self.instantiateFreshRoot(fresh, state, fresh_roots);
            state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
            try appendRootFact(&owned, root);
        }
        result.owned_roots = try owned.toOwnedSlice();

        var capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator);
        for (effect.fresh_storage_capabilities) |fresh|
            try appendCapabilityFact(&capabilities, try self.instantiateFreshCapability(fresh, state, fresh_capabilities));
        result.storage_capabilities = try capabilities.toOwnedSlice();

        var referenced_place: ?facts.Place = null;
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            if (arguments[path.input_index].referenced_place) |base| {
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, target) });
                referenced_place = target;
            }
        }
        result.dependencies = try dependencies.toOwnedSlice();

        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            var input = try self.projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
            if (!dependency.transfers_ownership) input.owned_roots = &.{};
            result = try self.mergeValueFacts(result, input);
        }
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            var input = try self.projectValueFacts(arguments[path.input_index], path.projections);
            if (arguments[path.input_index].referenced_place) |base| {
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                if (self.valueAtPlace(state, target)) |stored| input = stored;
            }
            result = try self.mergeValueFacts(result, input);
        }

        if (effect.fields.len != 0) {
            const variants = result.variants;
            const fields = try self.allocator.alloc(facts.FieldFacts, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(field.value.*, arguments, state, fresh_roots, fresh_capabilities);
                fields[index] = .{ .index = field.index, .value = value };
                result = try self.mergeValueFacts(result, value.*);
            }
            result.fields = fields;
            result.variants = variants;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const first_root = state.tracker.roots.items.len;
                const first_capability = state.storage_capabilities.items.len;
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(variant.value.*, arguments, state, fresh_roots, fresh_capabilities);
                for (state.tracker.roots.items[first_root..]) |*root| root.state = .conditional;
                for (state.storage_capabilities.items[first_capability..]) |*capability| capability.* = .conditional;
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        result.integer_address = effect.integer_address;
        result.foreign_storage = result.foreign_storage or effect.foreign_storage;
        result.known_choice_variant = effect.known_choice_variant;
        if (referenced_place) |target| result.referenced_place = target;
        return result;
    }

    fn instantiateFreshRoot(
        self: *SafetyChecker,
        source: facts.FreshEffectSource,
        state: *FunctionState,
        fresh: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
    ) !facts.ValidityRootId {
        _ = self;
        if (fresh.get(source)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try fresh.put(source, root);
        return root;
    }

    fn instantiateFreshCapability(
        self: *SafetyChecker,
        source: facts.FreshEffectSource,
        state: *FunctionState,
        fresh: *std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId),
    ) !facts.StorageCapabilityId {
        _ = self;
        if (fresh.get(source)) |capability| return capability;
        const capability: facts.StorageCapabilityId = @enumFromInt(state.storage_capabilities.items.len);
        try state.storage_capabilities.append(.available);
        try fresh.put(source, capability);
        return capability;
    }

    fn projectValueFacts(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        projections: []const facts.Projection,
    ) !facts.ValueFacts {
        var current = value;
        for (projections) |projection| {
            switch (projection) {
                .field => |wanted| {
                    var found: ?facts.ValueFacts = null;
                    for (current.fields) |field| if (field.index == wanted) {
                        found = field.value.*;
                        break;
                    };
                    current = found orelse current;
                },
                .variant => |wanted| {
                    var found: ?facts.ValueFacts = null;
                    for (current.variants) |variant| if (variant.index == wanted) {
                        found = variant.value.*;
                        break;
                    };
                    current = found orelse current;
                },
                .static_index => |wanted| {
                    var found: ?facts.ValueFacts = null;
                    for (current.fields) |field| if (field.index == wanted) {
                        found = field.value.*;
                        break;
                    };
                    current = found orelse current;
                },
                .dynamic_index => {
                    var merged: facts.ValueFacts = .{};
                    for (current.fields) |field| merged = try self.mergeValueFacts(merged, field.value.*);
                    if (current.fields.len != 0) current = merged;
                },
                .dereference => {},
            }
        }
        return current;
    }

    fn mergeValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (left.dependencies) |value| try appendDependencyFact(&dependencies, value);
        for (right.dependencies) |value| try appendDependencyFact(&dependencies, value);
        var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (left.owned_roots) |value| try appendRootFact(&owned, value);
        for (right.owned_roots) |value| try appendRootFact(&owned, value);
        var capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator);
        for (left.storage_capabilities) |value| try appendCapabilityFact(&capabilities, value);
        for (right.storage_capabilities) |value| try appendCapabilityFact(&capabilities, value);
        var opaque_provenance = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        for (left.opaque_provenance) |value| try appendOpaqueProvenanceFact(&opaque_provenance, value);
        for (right.opaque_provenance) |value| try appendOpaqueProvenanceFact(&opaque_provenance, value);

        var fields = std.array_list.Managed(facts.FieldFacts).init(self.allocator);
        for (left.fields) |left_field| {
            var merged = left_field.value.*;
            for (right.fields) |right_field| if (right_field.index == left_field.index) {
                merged = try self.mergeValueFacts(merged, right_field.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = merged;
            try fields.append(.{ .index = left_field.index, .value = stored });
        }
        for (right.fields) |right_field| {
            var found = false;
            for (left.fields) |left_field| if (left_field.index == right_field.index) {
                found = true;
                break;
            };
            if (!found) try fields.append(right_field);
        }

        var variants = std.array_list.Managed(facts.VariantFacts).init(self.allocator);
        for (left.variants) |left_variant| {
            var merged = left_variant.value.*;
            for (right.variants) |right_variant| if (right_variant.index == left_variant.index) {
                merged = try self.mergeValueFacts(merged, right_variant.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = merged;
            try variants.append(.{ .index = left_variant.index, .value = stored });
        }
        for (right.variants) |right_variant| {
            var found = false;
            for (left.variants) |left_variant| if (left_variant.index == right_variant.index) {
                found = true;
                break;
            };
            if (!found) try variants.append(right_variant);
        }

        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .variants = try variants.toOwnedSlice(),
            .known_choice_variant = if (left.known_choice_variant != null and left.known_choice_variant == right.known_choice_variant) left.known_choice_variant else null,
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .storage_capabilities = try capabilities.toOwnedSlice(),
            .referenced_place = if (left.referenced_place != null and right.referenced_place != null and left.referenced_place.?.eql(right.referenced_place.?)) left.referenced_place else null,
            .opaque_provenance = try opaque_provenance.toOwnedSlice(),
            .virtual_methods = if (std.mem.eql(graph_mod.GlobalFunctionId, left.virtual_methods, right.virtual_methods)) left.virtual_methods else &.{},
        };
    }

    fn withoutOwnedRoots(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        removed: []const facts.ValidityRootId,
    ) !facts.ValueFacts {
        // A moved payload no longer belongs to the choice. Remove its roots
        // from the residual aggregate without changing historical aliases.
        var result = value;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (value.dependencies) |dependency| if (!containsRoot(removed, dependency.root)) try appendDependencyFact(&dependencies, dependency);
        result.dependencies = try dependencies.toOwnedSlice();
        var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (value.owned_roots) |root| if (!containsRoot(removed, root)) try appendRootFact(&owned, root);
        result.owned_roots = try owned.toOwnedSlice();
        if (value.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
            for (value.fields, 0..) |field, index| {
                const child = try self.allocator.create(facts.ValueFacts);
                child.* = try self.withoutOwnedRoots(field.value.*, removed);
                fields[index] = .{ .index = field.index, .value = child };
            }
            result.fields = fields;
        }
        if (value.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
            for (value.variants, 0..) |variant, index| {
                const child = try self.allocator.create(facts.ValueFacts);
                child.* = try self.withoutOwnedRoots(variant.value.*, removed);
                variants[index] = .{ .index = variant.index, .value = child };
            }
            result.variants = variants;
        }
        return result;
    }

    fn initializednessAtPlace(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
    ) value_state.Initializedness {
        var projection_count = storage.projections.len;
        while (true) {
            const prefix = facts.Place{ .root = storage.root, .projections = storage.projections[0..projection_count] };
            if (self.getPlace(state, prefix)) |stored| return stored.initializedness;
            if (projection_count == 0) return .initialized;
            projection_count -= 1;
        }
    }

    fn valueAtPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) ?facts.ValueFacts {
        if (self.getPlace(state, storage)) |exact| return exact.value;
        var projection_count = storage.projections.len;
        while (projection_count > 0) {
            projection_count -= 1;
            const prefix = facts.Place{ .root = storage.root, .projections = storage.projections[0..projection_count] };
            if (self.getPlace(state, prefix)) |ancestor|
                return self.projectValueFacts(ancestor.value, storage.projections[projection_count..]) catch null;
        }
        return null;
    }

    fn refreshStorageGeneration(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) !void {
        _ = self;
        var index: usize = 0;
        var replaced = false;
        while (index < state.storage_generations.items.len) {
            const entry = state.storage_generations.items[index];
            if (!storage.isPrefixOf(entry.storage)) {
                index += 1;
                continue;
            }
            state.tracker.end(entry.generation);
            if (entry.storage.eql(storage)) {
                state.storage_generations.items[index].generation = try state.tracker.establish(.fresh);
                replaced = true;
                index += 1;
            } else {
                _ = state.storage_generations.orderedRemove(index);
            }
        }
        if (!replaced)
            try state.storage_generations.append(.{ .storage = storage, .generation = try state.tracker.establish(.fresh) });
    }

    fn evaluatePointerUse(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        pointer_node: graph_mod.GlobalNodeId,
        state: *FunctionState,
    ) !?facts.ValueFacts {
        const diagnostic_count = self.diagnostics.list.items.len;
        const pointer = try self.evaluate(function, pointer_node, state);
        if (self.diagnostics.list.items.len != diagnostic_count) return null;
        try self.requireLive(function, source, pointer, state);
        if (self.diagnostics.list.items.len != diagnostic_count) return null;
        return pointer;
    }

    fn opaqueProvenanceForAccess(
        self: *SafetyChecker,
        node_id: graph_mod.GlobalNodeId,
        state: *FunctionState,
    ) ![]const facts.OpaqueProvenance {
        return switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .binding_use => |binding| blk: {
                const value = self.getPlace(state, .{ .root = binding }) orelse break :blk &.{};
                break :blk try self.currentOpaqueProvenancesForValue(state, value.value);
            },
            .move_value, .address_of => |child| self.opaqueProvenanceForAccess(child, state),
            .struct_field_access => |access| self.opaqueProvenanceForAccess(access.value, state),
            .choice_payload_access => |access| self.opaqueProvenanceForAccess(access.value, state),
            .array_index => |access| self.opaqueProvenanceCarriedByPointerNode(access.array_ptr, state),
            .dereference => |access| self.opaqueProvenanceCarriedByPointerNode(access.pointer, state),
            else => &.{},
        };
    }

    fn opaqueProvenanceCarriedByAccess(
        self: *SafetyChecker,
        node_id: graph_mod.GlobalNodeId,
        state: *FunctionState,
    ) ![]const facts.OpaqueProvenance {
        return switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .move_value => |child| self.opaqueProvenanceCarriedByAccess(child, state),
            .struct_field_access => |access| self.opaqueProvenanceCarriedByAccess(access.value, state),
            .choice_payload_access => |access| self.opaqueProvenanceCarriedByAccess(access.value, state),
            .array_index => |access| self.opaqueProvenanceCarriedByPointerNode(access.array_ptr, state),
            .dereference => |access| self.opaqueProvenanceCarriedByPointerNode(access.pointer, state),
            else => &.{},
        };
    }

    fn opaqueProvenanceCarriedByPointerNode(
        self: *SafetyChecker,
        node_id: graph_mod.GlobalNodeId,
        state: *FunctionState,
    ) ![]const facts.OpaqueProvenance {
        const pointer_place = try self.resolvePlace(node_id, state) orelse return &.{};
        const pointer = self.getPlace(state, pointer_place) orelse return &.{};
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        try self.collectOpaqueProvenancesCarriedBy(state, pointer.value, &provenances);
        return provenances.toOwnedSlice();
    }

    fn currentOpaqueProvenancesForValue(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
    ) ![]const facts.OpaqueProvenance {
        var storages = std.array_list.Managed(facts.Place).init(self.allocator);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, value, &storages);
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        for (storages.items) |storage| try appendOpaqueProvenanceFact(&provenances, .{
            .storage = storage,
            .generation = try self.storageGeneration(state, storage),
        });
        return provenances.toOwnedSlice();
    }

    fn envelopeOpaqueRead(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        ty: ?graph_mod.GlobalTypeId,
        pointer: facts.ValueFacts,
    ) !facts.ValueFacts {
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        defer provenances.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, pointer, &provenances);
        return self.addOpaqueReadEnvelope(value, ty, provenances.items);
    }

    fn addOpaqueReadEnvelope(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        ty: ?graph_mod.GlobalTypeId,
        provenances: []const facts.OpaqueProvenance,
    ) !facts.ValueFacts {
        const value_type = ty orelse return value;
        if (!self.typeContainsPointer(value_type)) return self.nonPointerOpaqueRead(value, value_type);
        // A projected pointer borrows its parent's generation. Conservative
        // parent facts must not turn that borrow into ownership of the parent.
        const projected = if (isPointer(self.graph, value_type)) value.referenceCopy() else value;
        if (provenances.len == 0) return projected;

        var result = projected;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (value.dependencies) |dependency| try appendDependencyFact(&dependencies, dependency);
        for (provenances) |provenance| try appendDependencyFact(&dependencies, .{ .root = provenance.generation });
        result.dependencies = try dependencies.toOwnedSlice();

        if (value.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
            for (value.fields, 0..) |field, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = try self.addOpaqueReadEnvelope(
                    field.value.*,
                    self.fieldTypeAt(value_type, field.index),
                    provenances,
                );
                fields[index] = .{ .index = field.index, .value = stored };
            }
            result.fields = fields;
        }
        if (value.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
            for (value.variants, 0..) |variant, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = try self.addOpaqueReadEnvelope(
                    variant.value.*,
                    self.variantPayloadTypeAt(value_type, variant.index),
                    provenances,
                );
                variants[index] = .{ .index = variant.index, .value = stored };
            }
            result.variants = variants;
        }
        return result;
    }

    /// Remove lifetime/ownership facts from a pointer-free opaque read while
    /// preserving structural value facts. Choice discriminants and aggregate
    /// projections describe the value itself, not the storage envelope that
    /// happened to contain it.
    fn nonPointerOpaqueRead(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        ty: graph_mod.GlobalTypeId,
    ) !facts.ValueFacts {
        var result = value.scalarOpaqueRead();
        result.known_choice_variant = value.known_choice_variant;

        if (value.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
            for (value.fields, 0..) |field, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = if (self.fieldTypeAt(ty, field.index)) |field_ty|
                    try self.nonPointerOpaqueRead(field.value.*, field_ty)
                else
                    field.value.scalarOpaqueRead();
                fields[index] = .{ .index = field.index, .value = stored };
            }
            result.fields = fields;
        }
        if (value.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
            for (value.variants, 0..) |variant, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = if (self.variantPayloadTypeAt(ty, variant.index)) |payload_ty|
                    try self.nonPointerOpaqueRead(variant.value.*, payload_ty)
                else
                    variant.value.scalarOpaqueRead();
                variants[index] = .{ .index = variant.index, .value = stored };
            }
            result.variants = variants;
        }
        return result;
    }

    fn fieldTypeAt(
        self: *SafetyChecker,
        ty: graph_mod.GlobalTypeId,
        index: u32,
    ) ?graph_mod.GlobalTypeId {
        if (types.arrayElement(self.graph, ty)) |element| return element;
        const range = types.fields(self.graph, ty) orelse return null;
        if (index >= range.len) return null;
        return self.graph.fields.items[range.start + index].ty;
    }

    fn variantPayloadTypeAt(
        self: *SafetyChecker,
        ty: graph_mod.GlobalTypeId,
        index: u32,
    ) ?graph_mod.GlobalTypeId {
        const range = types.variants(self.graph, ty) orelse return null;
        if (index >= range.len) return null;
        return self.graph.variants.items[range.start + index].payload_type;
    }

    fn typeContainsPointer(self: *SafetyChecker, ty: graph_mod.GlobalTypeId) bool {
        const semantic = self.graph.resolvedSemanticType(ty) orelse return false;
        return switch (semantic) {
            .pointer, .virtual => true,
            .array => |array| self.typeContainsPointer(array.element),
            .nullable, .inferred_errable => |child| self.typeContainsPointer(child),
            .builtin => false,
            .declared, .structural => blk: {
                const range = types.fields(self.graph, ty) orelse break :blk self.choiceTypeContainsPointer(ty);
                for (self.graph.fields.items[range.start..][0..range.len]) |field|
                    if (self.typeContainsPointer(field.ty)) break :blk true;
                break :blk false;
            },
            .structural_choice, .inferred_choice => self.choiceTypeContainsPointer(ty),
            .generic => blk: {
                const instance = types.genericInstance(self.graph, ty) orelse break :blk false;
                break :blk switch (instance.shape) {
                    .array => |shape| self.typeContainsPointer(shape.element),
                    .alias => |target| self.typeContainsPointer(target),
                    .structure => |shape| fields_blk: {
                        for (self.graph.fields.items[shape.fields.start..][0..shape.fields.len]) |field|
                            if (self.typeContainsPointer(field.ty)) break :fields_blk true;
                        break :fields_blk false;
                    },
                    .choice => |shape| variants_blk: {
                        for (self.graph.variants.items[shape.variants.start..][0..shape.variants.len]) |variant|
                            if (variant.payload_type) |payload|
                                if (self.typeContainsPointer(payload)) break :variants_blk true;
                        break :variants_blk false;
                    },
                };
            },
        };
    }

    fn choiceTypeContainsPointer(self: *SafetyChecker, ty: graph_mod.GlobalTypeId) bool {
        const range = types.variants(self.graph, ty) orelse return false;
        for (self.graph.variants.items[range.start..][0..range.len]) |variant|
            if (variant.payload_type) |payload|
                if (self.typeContainsPointer(payload)) return true;
        return false;
    }

    fn mergeOpaqueStorage(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
        dependencies: []const facts.ValidityRootId,
    ) !void {
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            var merged = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            try merged.appendSlice(opaque_storage.hidden_dependencies);
            for (dependencies) |dependency| try appendRootFact(&merged, dependency);
            opaque_storage.hidden_dependencies = try merged.toOwnedSlice();
            return;
        }
        var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (dependencies) |dependency| try appendRootFact(&hidden, dependency);
        try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = try hidden.toOwnedSlice() });
    }

    fn markOpaqueStorageEmpty(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) void {
        _ = self;
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            opaque_storage.hidden_dependencies = &.{};
            return;
        }
    }

    fn mergeLiveOpaqueDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
        dependencies: []const facts.ValidityRootId,
    ) !void {
        var live = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer live.deinit();
        for (dependencies) |dependency| if (state.tracker.isAlive(dependency)) try appendRootFact(&live, dependency);
        try self.mergeOpaqueStorage(state, storage, live.items);
    }

    fn collectOpaqueHiddenDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        hidden: *std.array_list.Managed(facts.ValidityRootId),
    ) !void {
        for (value.dependencies) |dependency| try appendRootFact(hidden, dependency.root);
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
        defer provenances.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, value, &provenances);
        for (provenances.items) |provenance| try appendRootFact(hidden, provenance.generation);
        for (value.fields) |field| try self.collectOpaqueHiddenDependencies(state, field.value.*, hidden);
        for (value.variants) |variant| try self.collectOpaqueHiddenDependencies(state, variant.value.*, hidden);
    }

    fn hideOpaqueDependencies(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, value: facts.ValueFacts) !void {
        var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer hidden.deinit();
        try self.collectOpaqueHiddenDependencies(state, value, &hidden);
        try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
    }

    fn collectOpaqueDomainsAccessedBy(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        result: *std.array_list.Managed(facts.Place),
    ) !void {
        for (pointer.opaque_provenance) |provenance| try appendPlaceFact(result, provenance.storage);
        for (state.opaque_storages.items) |opaque_storage| {
            if (self.valueAtPlace(state, opaque_storage.storage)) |storage_value| {
                for (pointer.dependencies) |dependency|
                    if (valueContainsOwnedRoot(storage_value, dependency.root)) try appendPlaceFact(result, opaque_storage.storage);
            }
            for (state.storage_generations.items) |entry| {
                if (!opaque_storage.storage.isPrefixOf(entry.storage)) continue;
                for (pointer.dependencies) |dependency|
                    if (dependency.root == entry.generation) try appendPlaceFact(result, opaque_storage.storage);
            }
        }
    }

    fn recordOpaqueWrite(self: *SafetyChecker, state: *FunctionState, pointer: facts.ValueFacts, value: facts.ValueFacts) !void {
        // Slot contents remain opaque, but every reference stored through an
        // access to the domain must constrain the lifetime of its target.
        var domains = std.array_list.Managed(facts.Place).init(self.allocator);
        defer domains.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &domains);
        for (domains.items) |domain| try self.hideOpaqueDependencies(state, domain, value);
    }

    fn collectOpaqueProvenancesCarriedBy(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        result: *std.array_list.Managed(facts.OpaqueProvenance),
    ) !void {
        for (pointer.opaque_provenance) |provenance| try appendOpaqueProvenanceFact(result, provenance);
        for (state.opaque_storages.items) |opaque_storage| {
            if (self.valueAtPlace(state, opaque_storage.storage)) |storage_value| {
                for (pointer.dependencies) |dependency|
                    if (valueContainsOwnedRoot(storage_value, dependency.root)) try appendOpaqueProvenanceFact(result, .{
                        .storage = opaque_storage.storage,
                        .generation = dependency.root,
                    });
            }
            for (state.storage_generations.items) |entry| {
                if (!opaque_storage.storage.isPrefixOf(entry.storage)) continue;
                for (pointer.dependencies) |dependency|
                    if (dependency.root == entry.generation) try appendOpaqueProvenanceFact(result, .{
                        .storage = opaque_storage.storage,
                        .generation = dependency.root,
                    });
            }
        }
    }

    fn collectOpaqueProvenancesRecursively(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        result: *std.array_list.Managed(facts.OpaqueProvenance),
    ) !void {
        try self.collectOpaqueProvenancesCarriedBy(state, value, result);
        for (value.fields) |field| try self.collectOpaqueProvenancesRecursively(state, field.value.*, result);
        for (value.variants) |variant| try self.collectOpaqueProvenancesRecursively(state, variant.value.*, result);
    }

    fn opaqueDependencyIsInternalToStorage(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
        root: facts.ValidityRootId,
    ) bool {
        if (self.valueAtPlace(state, storage)) |storage_value|
            if (valueContainsOwnedRoot(storage_value, root) or valueDependsOnRoot(storage_value, root)) return true;
        for (state.storage_generations.items) |entry|
            if (storage.isPrefixOf(entry.storage) and entry.generation == root) return true;
        for (state.places.items) |entry|
            if (valueContainsOpaqueGeneration(entry.value, storage, root)) return true;
        return false;
    }

    fn endRoot(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        root: facts.ValidityRootId,
    ) !bool {
        return self.endRoots(source, state, &.{root});
    }

    fn endRoots(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        roots: []const facts.ValidityRootId,
    ) !bool {
        for (roots) |root| {
            var externally_hidden = false;
            for (state.opaque_storages.items) |opaque_storage| {
                if (!containsRoot(opaque_storage.hidden_dependencies, root)) continue;
                if (self.opaqueDependencyIsInternalToStorage(state, opaque_storage.storage, root)) continue;
                externally_hidden = true;
                break;
            }
            if (!externally_hidden) continue;
            try self.report(source, "cannot end a root while opaque storage hides a dependency on it", .{});
            return false;
        }
        for (roots) |root| state.tracker.end(root);
        return true;
    }

    fn closeOpaqueOwnedRoots(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        value: facts.ValueFacts,
        state: *FunctionState,
        consumed_source: ?facts.Place,
    ) !void {
        var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer roots.deinit();
        try collectOwnedRoots(value, &roots);
        for (roots.items) |root| {
            for (state.places.items) |candidate| {
                if (consumed_source) |consumed| if (consumed.isPrefixOf(candidate.storage)) continue;
                if (candidate.initializedness != .initialized or !valueDependsOnRoot(candidate.value, root)) continue;
                try self.report(source, "opaque ownership storage requires no live external aliases to the consumed root", .{});
                return;
            }
        }
        _ = try self.endRoots(source, state, roots.items);
    }

    fn endStorageGenerationsUnder(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        storage: facts.Place,
    ) !void {
        for (state.storage_generations.items) |entry| {
            if (storage.isPrefixOf(entry.storage)) {
                _ = try self.endRoot(source, state, entry.generation);
            }
        }
    }

    fn refreshStorageGenerationChecked(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        storage: facts.Place,
    ) !void {
        for (state.storage_generations.items) |entry| {
            if (!storage.isPrefixOf(entry.storage)) continue;
            if (!try self.endRoot(source, state, entry.generation)) return;
        }
        try self.refreshStorageGeneration(state, storage);
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
        const choice_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse return .{};
        const wanted = variantIndex(self.graph, choice_ty, access.variant) orelse return .{};
        const resolved = try self.resolvePlace(access.value, state);
        const choice = if (resolved) |storage| blk: {
            const stored = self.valueAtPlace(state, storage) orelse facts.ValueFacts{};
            const provenance = try self.opaqueProvenanceCarriedByAccess(access.value, state);
            break :blk try self.addOpaqueReadEnvelope(stored, choice_ty, provenance);
        } else try self.evaluate(function, access.value, state);

        if (resolved) |storage| {
            if (!self.variantActive(state, storage, wanted)) {
                if (self.activeVariant(state, storage) != null) {
                    try self.report(source, "choice payload '..{d}' is not active", .{wanted});
                } else {
                    try self.report(source, "choice payload '..{d}' requires its variant to be proven active", .{wanted});
                }
                return .{};
            }
        } else if (choice.known_choice_variant != wanted and !self.temporaryVariantActive(state, access.value, wanted)) {
            try self.report(source, "choice payload access requires a proven active variant", .{});
            return .{};
        }
        for (choice.variants) |variant| if (variant.index == wanted) return variant.value.*;
        return .{};
    }

    fn evaluateVirtualCall(self: *SafetyChecker, caller: graph_mod.GlobalFunctionId, id: graph_mod.GlobalVirtualCallId, state: *FunctionState) !facts.ValueFacts {
        if (self.collect_stats) self.stats.calls += 1;
        const call = self.graph.virtual_calls.items[@intFromEnum(id)];
        const input_node = self.graph.nodes.items[@intFromEnum(call.input)];
        if (input_node.content != .struct_value_literal) {
            _ = try self.evaluate(caller, call.handle, state);
            _ = try self.evaluate(caller, call.input, state);
            return .{};
        }

        const range = input_node.content.struct_value_literal.fields;
        const argument_nodes = self.globalValueFieldIds(range);
        var candidate = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        var values = try self.allocator.alloc(facts.ValueFacts, argument_nodes.len);
        defer self.allocator.free(values);
        for (argument_nodes, 0..) |field_id, index| {
            const field = self.graph.value_fields.items[@intFromEnum(field_id)];
            values[index] = try self.evaluate(caller, field.value, &candidate);
        }

        if (call.self_input_index >= values.len) return .{};
        // The call argument points at the Virtual wrapper, while the exact
        // implementation facts are stored in that wrapper's value. Recover
        // them when available; parameters and joined values still fall back
        // to the program-wide virtual summary below.
        var receiver = values[call.self_input_index];
        if (receiver.referenced_place) |wrapper| {
            if (self.valueAtPlace(&candidate, wrapper)) |stored| {
                if (stored.referenced_place != null) {
                    values[call.self_input_index] = stored;
                    receiver = stored;
                }
            }
        }
        if (call.method_index >= receiver.virtual_methods.len) {
            const result = (try self.applyVirtualSummaryFallback(
                call,
                input_node.source,
                argument_nodes,
                values,
                &candidate,
            )) orelse facts.ValueFacts{};
            if (self.diagnostics.list.items.len != diagnostic_count) return .{};
            self.commitState(state, &candidate);
            return result;
        }
        const callee_id = receiver.virtual_methods[call.method_index];
        const callee = self.graph.functions.items[@intFromEnum(callee_id)];

        if (callee.safety_primitive != .none) {
            if (self.collect_stats) self.stats.primitive_calls += 1;
            const result = try self.evaluatePrimitive(caller, callee.safety_primitive, argument_nodes, values, &candidate, input_node.source);
            if (self.diagnostics.list.items.len != diagnostic_count) return .{};
            self.commitState(state, &candidate);
            return result;
        }
        if (callee.body == null) {
            const result: facts.ValueFacts = if (callee.output.len == 1 and isPointer(self.graph, self.graph.fields.items[callee.output.start].ty))
                .{ .foreign_storage = true }
            else
                .{};
            if (self.diagnostics.list.items.len != diagnostic_count) return .{};
            self.commitState(state, &candidate);
            return result;
        }
        if (self.callStackContains(callee_id) and self.collect_stats) self.stats.recursive_edges += 1;
        const result = (try self.applyFunctionSummary(input_node.source, null, callee_id, argument_nodes, values, &candidate)) orelse facts.ValueFacts{};
        if (self.diagnostics.list.items.len != diagnostic_count) return .{};
        self.commitState(state, &candidate);
        return result;
    }

    fn applyVirtualSummaryFallback(
        self: *SafetyChecker,
        call: graph_mod.VirtualCall,
        source: primitives.SourceRef,
        argument_nodes: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?facts.ValueFacts {
        const inference = self.active_summary_inference orelse return null;
        const summary = try inference.virtualSummary(call.safety_methods) orelse {
            if (inference.virtualSummaryInvalid(call.safety_methods))
                try self.report(
                    source,
                    "virtual method '{s}' has incompatible safety effects across implementations",
                    .{self.graph.text(call.method_name)},
                );
            return null;
        };
        if (!try self.validateSummaryRequiredLive(source, summary, values, state)) return facts.ValueFacts{};
        try self.applySummaryEffects(source, summary, argument_nodes, values, state);
        return try self.instantiateSummaryOutputs(summary.outputs, values, state);
    }

    fn applyAutoDeinit(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        id: graph_mod.GlobalAutoDeinitId,
        state: *FunctionState,
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
        const storage = facts.Place{ .root = cleanup.binding };
        switch (self.initializednessAtPlace(state, storage)) {
            .initialized => if (cleanup.deinit_fn != null) {
                try self.evaluateResolvedAutoDeinit(function, cleanup, storage, state);
            } else if (cleanup.fields.len == 0) {
                if (self.getPlace(state, storage)) |owned_value| {
                    const source = self.graph.bindings.items[@intFromEnum(cleanup.binding)].source;
                    var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer roots.deinit();
                    try collectOwnedRoots(owned_value.value, &roots);
                    if (!try self.endRoots(source, state, roots.items)) return;
                }
                try self.setPlace(state, storage, .deinitialized, .{});
            } else {
                const diagnostic_count = self.diagnostics.list.items.len;
                try self.evaluateStructuralAutoDeinit(function, cleanup.fields, storage, state);
                if (self.diagnostics.list.items.len == diagnostic_count)
                    try self.setPlace(state, storage, .deinitialized, .{});
            },
            .maybe_initialized, .moved, .deinitialized => {},
        }
    }

    fn evaluateResolvedAutoDeinit(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        cleanup: graph_mod.AutoDeinit,
        storage: facts.Place,
        state: *FunctionState,
    ) !void {
        return self.evaluateResolvedDeinit(
            function,
            cleanup.deinit_fn orelse return,
            cleanup.input orelse return,
            cleanup.self_field_index,
            storage,
            state,
        );
    }

    fn evaluateStructuralAutoDeinit(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        fields: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        storage: facts.Place,
        state: *FunctionState,
    ) !void {
        for (self.graph.auto_deinit_fields.items[fields.start..][0..fields.len]) |field| {
            const field_storage = try self.project(storage, .{ .field = field.field_index });
            if (self.initializednessAtPlace(state, field_storage) != .initialized) continue;
            if (field.deinit_fn) |deinit_fn| {
                try self.evaluateResolvedDeinit(
                    function,
                    deinit_fn,
                    field.input orelse continue,
                    field.self_field_index,
                    field_storage,
                    state,
                );
            } else {
                try self.evaluateStructuralAutoDeinit(function, field.fields, field_storage, state);
                try self.setPlace(state, field_storage, .deinitialized, .{});
            }
        }
    }

    fn evaluateResolvedDeinit(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        deinit_fn: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
        self_field_index: u32,
        storage: facts.Place,
        state: *FunctionState,
    ) !void {
        const input_node = self.graph.nodes.items[@intFromEnum(input)];
        if (input_node.content != .struct_value_literal) return;
        const range = input_node.content.struct_value_literal.fields;
        const argument_ids = self.globalValueFieldIds(range);

        var candidate = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        var values = try self.allocator.alloc(facts.ValueFacts, argument_ids.len);
        defer self.allocator.free(values);
        for (argument_ids, 0..) |field_id, index| {
            const field = self.graph.value_fields.items[@intFromEnum(field_id)];
            values[index] = if (index == self_field_index)
                .{
                    .dependencies = try self.oneDependency(try self.storageGeneration(&candidate, storage)),
                    .referenced_place = storage,
                }
            else
                try self.evaluate(function, field.value, &candidate);
        }

        if (self.active_summaries) |engine| {
            if (engine.summaryFor(deinit_fn)) |summary| {
                if (!try self.validateSummaryRequiredLive(input_node.source, summary, values, &candidate)) return;
                try self.applySummaryEffects(input_node.source, summary, argument_ids, values, &candidate);
            } else {
                try self.evaluateResolvedDeinitBody(deinit_fn, values, &candidate);
            }
        } else {
            try self.evaluateResolvedDeinitBody(deinit_fn, values, &candidate);
        }
        if (self.diagnostics.list.items.len != diagnostic_count) return;
        self.commitState(state, &candidate);
    }

    fn evaluateResolvedDeinitBody(
        self: *SafetyChecker,
        deinit_fn: graph_mod.GlobalFunctionId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        const function = self.graph.functions.items[@intFromEnum(deinit_fn)];
        if (function.safety_primitive != .none) return;
        try self.bindCallInputs(function, values, state);
        if (function.body) |body| {
            try self.call_stack.append(deinit_fn);
            defer _ = self.call_stack.pop();
            try self.validateBlock(deinit_fn, body, state, null);
        }
    }

    // Taking an address does not read the destination, but every pointer used
    // to reach it must still refer to a live storage generation.
    fn validateAddressAccess(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, node_id: graph_mod.GlobalNodeId, state: *FunctionState) !void {
        switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .dereference => |access| {
                _ = try self.evaluatePointerUse(function, source, access.pointer, state);
            },
            .struct_field_access => |access| try self.validateAddressAccess(function, source, access.value, state),
            .choice_payload_access => |access| try self.validateAddressAccess(function, source, access.value, state),
            .array_index => |access| {
                _ = try self.evaluatePointerUse(function, source, access.array_ptr, state);
                _ = try self.evaluate(function, access.index, state);
            },
            else => {},
        }
    }

    fn resolvePlace(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId, state: *FunctionState) !?facts.Place {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .binding_use => |binding| facts.Place{ .root = binding },
            .move_value => |child| self.resolvePlace(child, state),
            .address_of => |child| self.resolvePlace(child, state),
            .dereference => |deref| blk: {
                const value = try self.evaluate(@enumFromInt(0), deref.pointer, state);
                break :blk value.referenced_place;
            },
            .struct_field_access => |access| if (try self.resolvePlace(access.value, state)) |base| try self.project(base, .{ .field = access.field_index }) else null,
            .choice_payload_access => |access| blk: {
                const base = try self.resolvePlace(access.value, state) orelse break :blk null;
                const choice_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse break :blk null;
                const index = variantIndex(self.graph, choice_ty, access.variant) orelse break :blk null;
                break :blk try self.project(base, .{ .variant = index });
            },
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
        self.invalidateChoiceRefinements(state, storage);
        // Replacing an aggregate invalidates facts recorded for its old
        // projections. Otherwise a later read can observe stale facts from a
        // preceding iteration rather than the newly assigned aggregate.
        var index: usize = 0;
        while (index < state.places.items.len) {
            const candidate = state.places.items[index].storage;
            if (!candidate.eql(storage) and storage.isPrefixOf(candidate)) {
                _ = state.places.orderedRemove(index);
            } else index += 1;
        }
        var stored = false;
        for (state.places.items) |*entry| if (entry.storage.eql(storage)) {
            entry.initializedness = initializedness;
            entry.value = value;
            stored = true;
            break;
        };
        if (!stored)
            try state.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
        if (initializedness == .initialized)
            try self.recordKnownChoiceVariants(state, storage, value);
    }

    fn recordKnownChoiceVariants(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
        value: facts.ValueFacts,
    ) !void {
        if (value.known_choice_variant) |variant_index|
            self.setActiveVariant(state, storage, variant_index);
        for (value.fields) |field|
            try self.recordKnownChoiceVariants(
                state,
                try self.project(storage, .{ .field = field.index }),
                field.value.*,
            );
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

    fn rejectEscapingLocalRoots(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        if (self.valueDependsOnLocalStorage(function, value, state)) {
            try self.report(source, "function output cannot depend on a local storage generation that ends before return", .{});
            return;
        }
        if (valueDependsOnDeadRoot(value, state))
            try self.report(source, "returned reference depends on a root that has ended", .{});
    }

    fn rejectEscapingOutputBindings(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        state: *FunctionState,
    ) !void {
        const record = self.graph.functions.items[@intFromEnum(function)];
        for (self.graph.binding_refs.items[record.output_bindings.start..][0..record.output_bindings.len]) |binding| {
            const storage = facts.Place{ .root = binding };
            const output = self.valueAtPlace(state, storage) orelse continue;
            if (self.initializednessAtPlace(state, storage) != .initialized or
                !self.typeContainsPointer(self.graph.bindings.items[@intFromEnum(binding)].ty)) continue;
            try self.rejectEscapingLocalRoots(function, self.graph.bindings.items[@intFromEnum(binding)].source, output, state);
        }
    }

    fn valueDependsOnLocalStorage(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        value: facts.ValueFacts,
        state: *const FunctionState,
    ) bool {
        for (value.dependencies) |dependency|
            if (self.isLocalStorageGeneration(function, state, dependency.root)) return true;
        for (value.fields) |field|
            if (self.valueDependsOnLocalStorage(function, field.value.*, state)) return true;
        for (value.variants) |variant|
            if (self.valueDependsOnLocalStorage(function, variant.value.*, state)) return true;
        return false;
    }

    fn isLocalStorageGeneration(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        state: *const FunctionState,
        root: facts.ValidityRootId,
    ) bool {
        if (containsRoot(state.lexical_storage_generations.items, root)) return true;
        const record = self.graph.functions.items[@intFromEnum(function)];
        const inputs = self.graph.binding_refs.items[record.input_bindings.start..][0..record.input_bindings.len];
        for (state.storage_generations.items) |entry| {
            if (entry.generation != root) continue;
            for (inputs) |input| if (input == entry.storage.root) return false;
            return true;
        }
        return false;
    }

    fn endBlockStorage(self: *SafetyChecker, block_id: graph_mod.GlobalBlockId, state: *FunctionState) !void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .binding_declaration => |binding| {
                var i: usize = 0;
                while (i < state.storage_generations.items.len) {
                    const entry = state.storage_generations.items[i];
                    if (entry.storage.root == binding) {
                        try appendRootFact(&state.lexical_storage_generations, entry.generation);
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

    fn joinState(self: *SafetyChecker, destination: *FunctionState, left: *const FunctionState, right: *const FunctionState) !void {
        if (!left.reachable) return self.copyState(destination, right);
        if (!right.reachable) return self.copyState(destination, left);

        var joined = FunctionState.init(self.allocator);
        errdefer joined.deinit();

        const root_count = @max(left.tracker.roots.items.len, right.tracker.roots.items.len);
        for (0..root_count) |index| {
            const id: facts.ValidityRootId = @enumFromInt(index);
            const left_state: @TypeOf(left.tracker.roots.items[0].state) = if (index < left.tracker.roots.items.len)
                left.tracker.roots.items[index].state
            else if (self.storageGenerationWasOnlyMaterializedIn(id, right, left))
                .alive
            else
                .dead;
            const right_state: @TypeOf(right.tracker.roots.items[0].state) = if (index < right.tracker.roots.items.len)
                right.tracker.roots.items[index].state
            else if (self.storageGenerationWasOnlyMaterializedIn(id, left, right))
                .alive
            else
                .dead;
            const left_owned = index < left.tracker.roots.items.len and left.tracker.roots.items[index].owned_resource;
            const right_owned = index < right.tracker.roots.items.len and right.tracker.roots.items[index].owned_resource;
            try joined.tracker.roots.append(.{
                .id = id,
                .state = if (left_state == right_state) left_state else .maybe_alive,
                .owned_resource = left_owned or right_owned,
            });
        }

        const capability_count = @max(left.storage_capabilities.items.len, right.storage_capabilities.items.len);
        for (0..capability_count) |index| {
            const left_state: StorageCapabilityState = if (index < left.storage_capabilities.items.len)
                left.storage_capabilities.items[index]
            else
                .consumed;
            const right_state: StorageCapabilityState = if (index < right.storage_capabilities.items.len)
                right.storage_capabilities.items[index]
            else
                .consumed;
            try joined.storage_capabilities.append(if (left_state == right_state) left_state else .maybe_consumed);
        }

        for (left.places.items) |left_place| {
            var merged = left_place;
            if (findPlaceConst(right, left_place.storage)) |right_place| {
                merged.initializedness = joinInitializedness(left_place.initializedness, right_place.initializedness);
                merged.value = try self.mergeValueFacts(left_place.value, right_place.value);
            }
            try joined.places.append(merged);
        }
        for (right.places.items) |right_place| {
            if (findPlaceConst(left, right_place.storage) == null) try joined.places.append(right_place);
        }

        for (left.ownership_edges.items) |edge| try joined.ownership_edges.append(edge);
        for (right.ownership_edges.items) |edge| {
            var found = false;
            for (joined.ownership_edges.items) |existing| {
                if (existing.owner == edge.owner and existing.owned == edge.owned) {
                    found = true;
                    break;
                }
            }
            if (!found) try joined.ownership_edges.append(edge);
        }

        try joined.storage_generations.appendSlice(left.storage_generations.items);
        for (right.storage_generations.items) |candidate| {
            var found = false;
            for (joined.storage_generations.items) |existing| {
                if (existing.storage.eql(candidate.storage)) {
                    found = true;
                    break;
                }
            }
            if (!found) try joined.storage_generations.append(candidate);
        }
        for (left.lexical_storage_generations.items) |root| try appendRootFact(&joined.lexical_storage_generations, root);
        for (right.lexical_storage_generations.items) |root| try appendRootFact(&joined.lexical_storage_generations, root);

        for (left.opaque_storages.items) |opaque_storage|
            try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);
        for (right.opaque_storages.items) |opaque_storage|
            try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);

        for (left.choice_active.items) |candidate| for (right.choice_active.items) |other| {
            if (candidate.storage.eql(other.storage) and candidate.variant_index == other.variant_index) {
                try joined.choice_active.append(candidate);
                break;
            }
        };
        for (left.choice_rejected.items) |candidate| for (right.choice_rejected.items) |other| {
            if (candidate.storage.eql(other.storage) and candidate.variant_index == other.variant_index) {
                try joined.choice_rejected.append(candidate);
                break;
            }
        };
        for (left.choice_temporary_active.items) |candidate| for (right.choice_temporary_active.items) |other| {
            if (candidate.expression == other.expression and candidate.variant_index == other.variant_index) {
                try joined.choice_temporary_active.append(candidate);
                break;
            }
        };

        joined.reachable = true;
        destination.deinit();
        destination.* = joined;
    }

    fn validateLoop(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        body: graph_mod.GlobalBlockId,
        state: *FunctionState,
        increment: ?graph_mod.GlobalNodeId,
    ) !void {
        // Structural storage exists before control enters the loop. Materialize
        // its generations before cloning entry state so first address-taking
        // in the body is not mistaken for a conditionally created lifetime.
        const existing_places = try self.allocator.dupe(facts.PlaceFacts, state.places.items);
        for (existing_places) |place_facts| _ = try self.storageGeneration(state, place_facts.storage);

        var entry = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer entry.deinit();
        var current = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
        defer current.deinit();
        var last_break: ?FunctionState = null;
        defer if (last_break) |*break_state| break_state.deinit();
        var join_context = LoopJoinContext.init(self.allocator);
        defer join_context.deinit();

        for (0..8) |_| {
            var iteration = try current.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            defer iteration.deinit();
            var transfers: LoopTransfers = .{};
            defer transfers.deinit();

            try self.validateBlock(function, body, &iteration, &transfers);
            if (transfers.continue_state) |*continue_state|
                try self.mergeLoopTransfer(&iteration, continue_state);
            if (iteration.reachable) {
                if (increment) |node| _ = try self.evaluate(function, node, &iteration);
            }

            if (last_break) |*break_state| break_state.deinit();
            last_break = if (transfers.break_state) |*break_state|
                try break_state.clone(self.allocator, if (self.collect_stats) &self.stats else null)
            else
                null;

            var next = try entry.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            try self.joinState(&next, &entry, &iteration);
            try self.widenLoopOwnedRoots(&join_context, &next, &entry, &iteration);
            if (statesEqual(&current, &next)) {
                if (last_break) |*break_state| try self.mergeLoopTransfer(&next, break_state);
                try self.copyState(state, &next);
                next.deinit();
                return;
            }
            current.deinit();
            current = next;
        }

        if (last_break) |*break_state| try self.mergeLoopTransfer(&current, break_state);
        try self.copyState(state, &current);
    }

    fn widenLoopOwnedRoots(
        self: *SafetyChecker,
        context: *LoopJoinContext,
        joined: *FunctionState,
        left: *const FunctionState,
        right: *const FunctionState,
    ) !void {
        for (joined.places.items) |*joined_place| {
            if (self.initializednessAtPlace(@constCast(left), joined_place.storage) != .initialized or
                self.initializednessAtPlace(@constCast(right), joined_place.storage) != .initialized) continue;
            const left_value = self.valueAtPlace(@constCast(left), joined_place.storage) orelse facts.ValueFacts{};
            const right_value = self.valueAtPlace(@constCast(right), joined_place.storage) orelse facts.ValueFacts{};

            const existing_phi = loopRootPhiForStorage(context, joined_place.storage);
            var left_only = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer left_only.deinit();
            for (left_value.owned_roots) |root|
                if ((existing_phi == null or root != existing_phi.?) and !containsRoot(right_value.owned_roots, root)) try appendRootFact(&left_only, root);
            var right_only = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer right_only.deinit();
            for (right_value.owned_roots) |root|
                if ((existing_phi == null or root != existing_phi.?) and !containsRoot(left_value.owned_roots, root)) try appendRootFact(&right_only, root);

            for (left_value.owned_roots) |root| {
                if (existing_phi != null and root == existing_phi.?) continue;
                if (!containsRoot(right_value.owned_roots, root)) continue;
                const index = @intFromEnum(root);
                const left_alive = index < left.tracker.roots.items.len and left.tracker.isAlive(root);
                const right_alive = index < right.tracker.roots.items.len and right.tracker.isAlive(root);
                if (left_alive and !right_alive) try appendRootFact(&left_only, root);
                if (right_alive and !left_alive) try appendRootFact(&right_only, root);
            }

            var stale_alternative: ?facts.ValidityRootId = null;
            if (left_only.items.len == 0 and right_only.items.len == 1) {
                for (right_value.owned_roots) |root| {
                    if (!containsRoot(left_value.owned_roots, root)) continue;
                    const index = @intFromEnum(root);
                    const left_alive = index < left.tracker.roots.items.len and left.tracker.isAlive(root);
                    const right_alive = index < right.tracker.roots.items.len and right.tracker.isAlive(root);
                    if (left_alive or right_alive) continue;
                    try appendRootFact(&left_only, root);
                    stale_alternative = root;
                    break;
                }
                var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer left_dependencies.deinit();
                try collectDependencyRoots(left_value, &left_dependencies);
                for (left_dependencies.items) |root| {
                    if (stale_alternative != null) break;
                    const index = @intFromEnum(root);
                    if (!valueDependsOnRoot(right_value, root) or containsRoot(left_value.owned_roots, root) or
                        containsRoot(right_value.owned_roots, root) or index >= left.tracker.roots.items.len or
                        index >= right.tracker.roots.items.len or !left.tracker.roots.items[index].owned_resource or
                        !left.tracker.isAlive(root) or right.tracker.isAlive(root)) continue;
                    try appendRootFact(&left_only, root);
                    stale_alternative = root;
                    break;
                }
                if (stale_alternative == null) {
                    var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer right_dependencies.deinit();
                    try collectDependencyRoots(right_value, &right_dependencies);
                    for (right_dependencies.items) |root| {
                        const index = @intFromEnum(root);
                        if (valueDependsOnRoot(left_value, root) or containsRoot(right_value.owned_roots, root) or
                            index >= right.tracker.roots.items.len or !right.tracker.roots.items[index].owned_resource or
                            right.tracker.isAlive(root)) continue;
                        try appendRootFact(&left_only, root);
                        stale_alternative = root;
                        break;
                    }
                }
            } else if (right_only.items.len == 0 and left_only.items.len == 1) {
                for (left_value.owned_roots) |root| {
                    if (!containsRoot(right_value.owned_roots, root)) continue;
                    const index = @intFromEnum(root);
                    const left_alive = index < left.tracker.roots.items.len and left.tracker.isAlive(root);
                    const right_alive = index < right.tracker.roots.items.len and right.tracker.isAlive(root);
                    if (left_alive or right_alive) continue;
                    try appendRootFact(&right_only, root);
                    stale_alternative = root;
                    break;
                }
                var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer right_dependencies.deinit();
                try collectDependencyRoots(right_value, &right_dependencies);
                for (right_dependencies.items) |root| {
                    if (stale_alternative != null) break;
                    const index = @intFromEnum(root);
                    if (!valueDependsOnRoot(left_value, root) or containsRoot(left_value.owned_roots, root) or
                        containsRoot(right_value.owned_roots, root) or index >= left.tracker.roots.items.len or
                        index >= right.tracker.roots.items.len or !right.tracker.roots.items[index].owned_resource or
                        !right.tracker.isAlive(root) or left.tracker.isAlive(root)) continue;
                    try appendRootFact(&right_only, root);
                    stale_alternative = root;
                    break;
                }
                if (stale_alternative == null) {
                    var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer left_dependencies.deinit();
                    try collectDependencyRoots(left_value, &left_dependencies);
                    for (left_dependencies.items) |root| {
                        const index = @intFromEnum(root);
                        if (valueDependsOnRoot(right_value, root) or containsRoot(left_value.owned_roots, root) or
                            index >= left.tracker.roots.items.len or !left.tracker.roots.items[index].owned_resource or
                            left.tracker.isAlive(root)) continue;
                        try appendRootFact(&right_only, root);
                        stale_alternative = root;
                        break;
                    }
                }
            }

            if (left_only.items.len == 0 and right_only.items.len == 0) {
                var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer left_dependencies.deinit();
                try collectDependencyRoots(left_value, &left_dependencies);
                var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer right_dependencies.deinit();
                try collectDependencyRoots(right_value, &right_dependencies);
                for (left_dependencies.items) |root| {
                    const index = @intFromEnum(root);
                    if ((existing_phi == null or root != existing_phi.?) and
                        !containsRoot(right_dependencies.items, root) and index < left.tracker.roots.items.len and
                        left.tracker.roots.items[index].owned_resource and left.tracker.isAlive(root))
                        try appendRootFact(&left_only, root);
                }
                for (right_dependencies.items) |root| {
                    const index = @intFromEnum(root);
                    if ((existing_phi == null or root != existing_phi.?) and
                        !containsRoot(left_dependencies.items, root) and index < right.tracker.roots.items.len and
                        right.tracker.roots.items[index].owned_resource and right.tracker.isAlive(root))
                        try appendRootFact(&right_only, root);
                }
            }
            if (left_only.items.len == 0 and right_only.items.len == 0) continue;
            if (left_only.items.len + right_only.items.len > 2) continue;
            if (left_only.items.len > 1) {
                var alive: usize = 0;
                for (left_only.items) |root| {
                    if (left.tracker.isAlive(root)) alive += 1;
                }
                if (right_only.items.len != 0 or alive != 1) continue;
            }
            if (right_only.items.len > 1) {
                var alive: usize = 0;
                for (right_only.items) |root| {
                    if (right.tracker.isAlive(root)) alive += 1;
                }
                if (left_only.items.len != 0 or alive != 1) continue;
            }

            var alternatives: [2]facts.ValidityRootId = undefined;
            var alternative_count: usize = 0;
            for (left_only.items) |root| {
                alternatives[alternative_count] = root;
                alternative_count += 1;
            }
            for (right_only.items) |root| {
                alternatives[alternative_count] = root;
                alternative_count += 1;
            }

            var safe = true;
            for (alternatives[0..alternative_count]) |root| {
                const index = @intFromEnum(root);
                const left_stale_remnant = stale_alternative == root and index < left.tracker.roots.items.len and !left.tracker.isAlive(root);
                const right_stale_remnant = stale_alternative == root and index < right.tracker.roots.items.len and !right.tracker.isAlive(root);
                if ((valueDependsOnRoot(left_value, root) and !containsRoot(left_value.owned_roots, root) and !left_stale_remnant) or
                    (valueDependsOnRoot(right_value, root) and !containsRoot(right_value.owned_roots, root) and !right_stale_remnant))
                {
                    safe = false;
                    break;
                }
            }
            if (!safe) continue;

            const logical_storage = if (existing_phi != null)
                loopRootPhiStorage(context, existing_phi.?).?
            else
                self.loopPhiOwnerStorage(joined, joined_place.storage, alternatives[0..alternative_count]);
            const phi = try self.loopRootPhi(context, joined, logical_storage);
            for (joined.places.items) |*related| {
                if (!logical_storage.isPrefixOf(related.storage)) continue;
                related.value = try self.replaceValueRoots(related.value, alternatives[0..alternative_count], phi);
            }
            self.replaceOwnershipEdgeRoots(joined, alternatives[0..alternative_count], phi);
        }
        self.trimUnreferencedLoopRoots(context, joined);
    }

    fn trimUnreferencedLoopRoots(self: *SafetyChecker, context: *const LoopJoinContext, state: *FunctionState) void {
        while (state.tracker.roots.items.len != 0) {
            const root: facts.ValidityRootId = @enumFromInt(state.tracker.roots.items.len - 1);
            var referenced = false;
            for (context.roots.items) |entry| if (entry.root == root) {
                referenced = true;
                break;
            };
            if (!referenced) referenced = rootIsStructurallyReferenced(state, root);
            if (referenced) return;
            var lexical_index: usize = 0;
            while (lexical_index < state.lexical_storage_generations.items.len) {
                if (state.lexical_storage_generations.items[lexical_index] == root)
                    _ = state.lexical_storage_generations.orderedRemove(lexical_index)
                else
                    lexical_index += 1;
            }
            _ = state.tracker.roots.pop();
        }
        _ = self;
    }

    fn loopPhiOwnerStorage(
        self: *SafetyChecker,
        state: *const FunctionState,
        fallback: facts.Place,
        roots: []const facts.ValidityRootId,
    ) facts.Place {
        _ = self;
        var result = fallback;
        for (state.places.items) |candidate| {
            if (candidate.storage.root != fallback.root or candidate.storage.projections.len <= result.projections.len) continue;
            var contains = false;
            for (roots) |root| if (containsRoot(candidate.value.owned_roots, root)) {
                contains = true;
                break;
            };
            if (contains) result = candidate.storage;
        }
        return result;
    }

    fn replaceOwnershipEdgeRoots(
        self: *SafetyChecker,
        state: *FunctionState,
        sources: []const facts.ValidityRootId,
        replacement: facts.ValidityRootId,
    ) void {
        var write: usize = 0;
        for (state.ownership_edges.items) |edge| {
            const rewritten = OwnershipEdge{
                .owner = if (containsRoot(sources, edge.owner)) replacement else edge.owner,
                .owned = if (containsRoot(sources, edge.owned)) replacement else edge.owned,
            };
            var duplicate = false;
            for (state.ownership_edges.items[0..write]) |existing| {
                if (existing.owner == rewritten.owner and existing.owned == rewritten.owned) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                state.ownership_edges.items[write] = rewritten;
                write += 1;
            }
        }
        state.ownership_edges.shrinkRetainingCapacity(write);
        _ = self;
    }

    fn loopRootPhi(
        self: *SafetyChecker,
        context: *LoopJoinContext,
        state: *FunctionState,
        storage: facts.Place,
    ) !facts.ValidityRootId {
        _ = self;
        for (context.roots.items) |entry| if (entry.storage.eql(storage)) {
            const index = @intFromEnum(entry.root);
            if (index < state.tracker.roots.items.len) {
                state.tracker.roots.items[index].state = .alive;
                state.tracker.roots.items[index].owned_resource = true;
            }
            return entry.root;
        };
        const root = try state.tracker.establish(.fresh);
        state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
        try context.roots.append(.{ .storage = storage, .root = root });
        return root;
    }

    fn replaceValueRoots(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        sources: []const facts.ValidityRootId,
        replacement: facts.ValidityRootId,
    ) !facts.ValueFacts {
        var result = value;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (value.dependencies) |dependency|
            try appendDependencyFact(&dependencies, .{ .root = if (containsRoot(sources, dependency.root)) replacement else dependency.root });
        result.dependencies = try dependencies.toOwnedSlice();
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (value.owned_roots) |root|
            try appendRootFact(&owned_roots, if (containsRoot(sources, root)) replacement else root);
        result.owned_roots = try owned_roots.toOwnedSlice();
        const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
        for (value.fields, 0..) |field, index| {
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = try self.replaceValueRoots(field.value.*, sources, replacement);
            fields[index] = .{ .index = field.index, .value = stored };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
        for (value.variants, 0..) |variant, index| {
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = try self.replaceValueRoots(variant.value.*, sources, replacement);
            variants[index] = .{ .index = variant.index, .value = stored };
        }
        result.variants = variants;
        return result;
    }

    fn mergeLoopTransfer(self: *SafetyChecker, destination: anytype, source: *const FunctionState) !void {
        const Destination = @TypeOf(destination.*);
        if (comptime Destination == ?FunctionState) {
            if (destination.*) |*current| {
                var joined = try current.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                try self.joinState(&joined, current, source);
                current.deinit();
                current.* = joined;
            } else {
                destination.* = try source.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            }
        } else {
            if (!destination.*.reachable) {
                try self.copyState(destination, source);
            } else {
                var joined = try destination.*.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                try self.joinState(&joined, destination, source);
                destination.deinit();
                destination.* = joined;
            }
        }
    }

    /// Storage generations are created lazily when a Place first needs one. If
    /// only one branch materialized that fact, the other branch still preserves
    /// the same live storage generation while the Place itself is initialized.
    fn storageGenerationWasOnlyMaterializedIn(
        self: *SafetyChecker,
        root: facts.ValidityRootId,
        materialized: *const FunctionState,
        other: *const FunctionState,
    ) bool {
        _ = self;
        var storage: ?facts.Place = null;
        for (materialized.storage_generations.items) |entry| if (entry.generation == root) {
            storage = entry.storage;
            break;
        };
        const target = storage orelse return false;
        for (other.storage_generations.items) |entry| if (entry.storage.eql(target)) return false;

        var projection_count = target.projections.len;
        while (true) {
            const prefix = facts.Place{ .root = target.root, .projections = target.projections[0..projection_count] };
            if (findPlaceConst(other, prefix)) |stored| return stored.initializedness == .initialized;
            if (projection_count == 0) return false;
            projection_count -= 1;
        }
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

    fn refineChoice(self: *SafetyChecker, state: *FunctionState, node: graph_mod.GlobalNodeId, variant: graph_mod.GlobalVariantId, active: bool) !void {
        const ty = self.graph.nodes.items[@intFromEnum(node)].ty orelse return;
        const index = variantIndex(self.graph, ty, variant) orelse return;
        const storage = try self.resolvePlace(node, state);
        if (storage == null) {
            if (active) try self.setTemporaryActiveVariant(state, node, index);
            return;
        }
        const target = storage.?;
        if (active) {
            if (self.valueAtPlace(state, target)) |value|
                for (value.variants) |payload| if (payload.index == index) {
                    try self.activateConditionalOwnedRoots(state, payload.value.*);
                    break;
                };
            self.clearRejectedVariant(state, target, index);
            self.setActiveVariant(state, target, index);
            return;
        }

        self.clearActiveVariant(state, target, index);
        self.setRejectedVariant(state, target, index);

        // Once every other variant has been rejected, the remaining one is
        // proven active. Temporary expressions only retain positive proofs;
        // negative refinement needs stable storage identity.
        const variants = types.variants(self.graph, ty) orelse return;
        var remaining: ?u32 = null;
        for (0..variants.len) |offset| {
            const candidate: u32 = @intCast(offset);
            if (self.variantRejected(state, target, candidate)) continue;
            if (remaining != null) return;
            remaining = candidate;
        }
        if (remaining) |only| self.setActiveVariant(state, target, only);
    }

    fn activateConditionalOwnedRoots(self: *SafetyChecker, state: *FunctionState, value: facts.ValueFacts) !void {
        var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer roots.deinit();
        try collectOwnedRoots(value, &roots);
        for (roots.items) |root| {
            const entry = &state.tracker.roots.items[@intFromEnum(root)];
            if (entry.state == .conditional) entry.state = .alive;
        }
    }

    fn choiceTestFromCondition(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId) ?primitives.ChoiceTagTest(graph_mod.Ids) {
        const comparison = switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .comparison => |value| value,
            else => return null,
        };
        if (comparison.operator != .equal and comparison.operator != .not_equal) return null;

        var choice_node = comparison.left;
        var tag_node = comparison.right;
        const tag = switch (self.graph.nodes.items[@intFromEnum(tag_node)].content) {
            .int_literal => |value| value,
            else => blk: {
                choice_node = comparison.right;
                tag_node = comparison.left;
                break :blk switch (self.graph.nodes.items[@intFromEnum(tag_node)].content) {
                    .int_literal => |value| value,
                    else => return null,
                };
            },
        };

        const choice_type = self.graph.nodes.items[@intFromEnum(choice_node)].ty orelse return null;
        const variants = types.variants(self.graph, choice_type) orelse return null;
        for (0..variants.len) |offset| {
            const raw = variants.start + @as(u32, @intCast(offset));
            if (self.graph.variants.items[raw].value != tag) continue;
            return .{
                .choice_value = choice_node,
                .choice_type = choice_type,
                .variant = @enumFromInt(raw),
                .then_has_variant = comparison.operator == .equal,
            };
        }
        return null;
    }

    fn setActiveVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {
        for (state.choice_active.items) |*entry| if (entry.storage.eql(storage)) {
            entry.variant_index = index;
            self.clearRejectedVariant(state, storage, index);
            return;
        };
        state.choice_active.append(.{ .storage = storage, .variant_index = index }) catch {};
        self.clearRejectedVariant(state, storage, index);
    }

    fn clearActiveVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {
        _ = self;
        var cursor: usize = 0;
        while (cursor < state.choice_active.items.len) {
            const entry = state.choice_active.items[cursor];
            if (entry.storage.eql(storage) and entry.variant_index == index) {
                _ = state.choice_active.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    fn setTemporaryActiveVariant(self: *SafetyChecker, state: *FunctionState, expression: graph_mod.GlobalNodeId, index: u32) !void {
        _ = self;
        for (state.choice_temporary_active.items) |*entry| {
            if (entry.expression != expression) continue;
            entry.variant_index = index;
            return;
        }
        try state.choice_temporary_active.append(.{ .expression = expression, .variant_index = index });
    }

    fn temporaryVariantActive(self: *SafetyChecker, state: *const FunctionState, expression: graph_mod.GlobalNodeId, index: u32) bool {
        _ = self;
        for (state.choice_temporary_active.items) |entry|
            if (entry.expression == expression) return entry.variant_index == index;
        return false;
    }

    fn setRejectedVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {
        _ = self;
        for (state.choice_rejected.items) |entry|
            if (entry.storage.eql(storage) and entry.variant_index == index) return;
        state.choice_rejected.append(.{ .storage = storage, .variant_index = index }) catch {};
    }

    fn clearRejectedVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {
        _ = self;
        var cursor: usize = 0;
        while (cursor < state.choice_rejected.items.len) {
            const entry = state.choice_rejected.items[cursor];
            if (entry.storage.eql(storage) and entry.variant_index == index) {
                _ = state.choice_rejected.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    fn variantRejected(self: *SafetyChecker, state: *const FunctionState, storage: facts.Place, index: u32) bool {
        _ = self;
        for (state.choice_rejected.items) |entry|
            if (entry.storage.eql(storage) and entry.variant_index == index) return true;
        return false;
    }

    fn invalidateChoiceRefinements(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) void {
        _ = self;
        var cursor: usize = 0;
        while (cursor < state.choice_active.items.len) {
            if (storage.isPrefixOf(state.choice_active.items[cursor].storage)) {
                _ = state.choice_active.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
        cursor = 0;
        while (cursor < state.choice_rejected.items.len) {
            if (storage.isPrefixOf(state.choice_rejected.items[cursor].storage)) {
                _ = state.choice_rejected.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    fn variantActive(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) bool {
        return if (self.activeVariant(state, storage)) |active| active == index else false;
    }

    fn activeVariant(self: *SafetyChecker, state: *const FunctionState, storage: facts.Place) ?u32 {
        _ = self;
        for (state.choice_active.items) |entry|
            if (entry.storage.eql(storage)) return entry.variant_index;
        return null;
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

    fn validateIntegerLiteral(self: *SafetyChecker, source: primitives.SourceRef, maybe_ty: ?graph_mod.GlobalTypeId, value: i64) !void {
        const ty = maybe_ty orelse return;
        const builtin = switch (self.graph.resolvedSemanticType(ty) orelse return) {
            .builtin => |kind| kind,
            else => return,
        };
        const fits = switch (builtin) {
            .Int8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
            .Int16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
            .Int32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
            .Int64 => true,
            .UInt8 => value >= 0 and value <= std.math.maxInt(u8),
            .UInt16 => value >= 0 and value <= std.math.maxInt(u16),
            .UInt32 => value >= 0 and value <= std.math.maxInt(u32),
            .UInt64, .UIntNative => value >= 0,
            else => return,
        };
        if (fits) return;
        switch (builtin) {
            .Int8 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i8), std.math.maxInt(i8) }),
            .Int16 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i16), std.math.maxInt(i16) }),
            .Int32 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i32), std.math.maxInt(i32) }),
            .UInt8 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u8) }),
            .UInt16 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u16) }),
            .UInt32 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u32) }),
            .UInt64, .UIntNative => try self.report(source, "integer literal {d} does not fit in '{s}' (minimum 0)", .{ value, @tagName(builtin) }),
            else => unreachable,
        }
    }

    fn validateContextualIntegerLiteral(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId, expected: graph_mod.GlobalTypeId) !void {
        const node = self.graph.node(node_id);
        const value = switch (node.content) {
            .int_literal => |literal| literal,
            else => return,
        };
        try self.validateIntegerLiteral(node.source, expected, value);
    }

    fn location(self: *SafetyChecker, source: primitives.SourceRef) ?tok.Location {
        if (source.file_index >= self.graph.files.items.len) return null;
        const file = self.graph.files.items[source.file_index];
        const basename = self.graph.text(file.path);
        const module_dir = self.graph.text(self.graph.modules.items[@intFromEnum(file.module)].dir);

        var basename_match: ?@TypeOf(self.diagnostics.source_db.fileId(0)) = null;
        for (self.diagnostics.source_db.files, 0..) |candidate, index| {
            if (!std.mem.eql(u8, std.fs.path.basename(candidate.path), basename)) continue;
            const id = self.diagnostics.source_db.fileId(index);
            if (std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", module_dir))
                return .{ .file = id, .offset = source.offset };
            if (basename_match == null) basename_match = id else basename_match = null;
        }
        return if (basename_match) |id| .{ .file = id, .offset = source.offset } else null;
    }
};

fn appendDependencyFact(list: *std.array_list.Managed(facts.ValidityDependency), dependency: facts.ValidityDependency) !void {
    for (list.items) |existing| if (existing.root == dependency.root) return;
    try list.append(dependency);
}

fn appendRootFact(list: *std.array_list.Managed(facts.ValidityRootId), root: facts.ValidityRootId) !void {
    for (list.items) |existing| if (existing == root) return;
    try list.append(root);
}

fn appendCapabilityFact(list: *std.array_list.Managed(facts.StorageCapabilityId), capability: facts.StorageCapabilityId) !void {
    for (list.items) |existing| if (existing == capability) return;
    try list.append(capability);
}

fn appendPlaceFact(list: *std.array_list.Managed(facts.Place), storage: facts.Place) !void {
    for (list.items) |existing| if (existing.eql(storage)) return;
    try list.append(storage);
}

fn appendOpaqueProvenanceFact(list: *std.array_list.Managed(facts.OpaqueProvenance), provenance: facts.OpaqueProvenance) !void {
    for (list.items) |existing|
        if (existing.storage.eql(provenance.storage) and existing.generation == provenance.generation) return;
    try list.append(provenance);
}

fn containsRoot(roots: []const facts.ValidityRootId, root: facts.ValidityRootId) bool {
    for (roots) |existing| if (existing == root) return true;
    return false;
}

fn collectOwnedRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.ValidityRootId)) !void {
    for (value.owned_roots) |root| try appendRootFact(roots, root);
    for (value.fields) |field| try collectOwnedRoots(field.value.*, roots);
    for (value.variants) |variant| try collectOwnedRoots(variant.value.*, roots);
}

fn valueDependsOnRoot(value: facts.ValueFacts, root: facts.ValidityRootId) bool {
    for (value.dependencies) |dependency| if (dependency.root == root) return true;
    for (value.fields) |field| if (valueDependsOnRoot(field.value.*, root)) return true;
    for (value.variants) |variant| if (valueDependsOnRoot(variant.value.*, root)) return true;
    return false;
}

fn valueContainsOwnedRoot(value: facts.ValueFacts, root: facts.ValidityRootId) bool {
    if (containsRoot(value.owned_roots, root)) return true;
    for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) return true;
    for (value.variants) |variant| if (valueContainsOwnedRoot(variant.value.*, root)) return true;
    return false;
}

fn valueContainsOpaqueGeneration(value: facts.ValueFacts, storage: facts.Place, generation: facts.ValidityRootId) bool {
    for (value.opaque_provenance) |provenance|
        if (provenance.storage.eql(storage) and provenance.generation == generation) return true;
    for (value.fields) |field| if (valueContainsOpaqueGeneration(field.value.*, storage, generation)) return true;
    for (value.variants) |variant| if (valueContainsOpaqueGeneration(variant.value.*, storage, generation)) return true;
    return false;
}

fn valueHasDependency(value: facts.ValueFacts) bool {
    if (value.dependencies.len != 0) return true;
    for (value.fields) |field| if (valueHasDependency(field.value.*)) return true;
    for (value.variants) |variant| if (valueHasDependency(variant.value.*)) return true;
    return false;
}

fn hasExternalOpaqueDependency(value: facts.ValueFacts, owned: []const facts.ValidityRootId) bool {
    for (value.dependencies) |dependency| if (!containsRoot(owned, dependency.root)) return true;
    for (value.fields) |field| if (hasExternalOpaqueDependency(field.value.*, owned)) return true;
    for (value.variants) |variant| if (hasExternalOpaqueDependency(variant.value.*, owned)) return true;
    return false;
}

fn loopRootPhiForStorage(context: *const SafetyChecker.LoopJoinContext, storage: facts.Place) ?facts.ValidityRootId {
    var result: ?SafetyChecker.LoopRootPhi = null;
    for (context.roots.items) |entry| {
        if (!entry.storage.isPrefixOf(storage)) continue;
        if (result == null or entry.storage.projections.len > result.?.storage.projections.len) result = entry;
    }
    return if (result) |entry| entry.root else null;
}

fn loopRootPhiStorage(context: *const SafetyChecker.LoopJoinContext, root: facts.ValidityRootId) ?facts.Place {
    for (context.roots.items) |entry| if (entry.root == root) return entry.storage;
    return null;
}

fn collectDependencyRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.ValidityRootId)) !void {
    for (value.dependencies) |dependency| try appendRootFact(roots, dependency.root);
    for (value.fields) |field| try collectDependencyRoots(field.value.*, roots);
    for (value.variants) |variant| try collectDependencyRoots(variant.value.*, roots);
}

fn valueDependsOnDeadRoot(value: facts.ValueFacts, state: *const SafetyChecker.FunctionState) bool {
    return valueDependsOnDeadRootWithOwners(value, value, state);
}

fn valueDependsOnDeadRootWithOwners(
    value: facts.ValueFacts,
    owners: facts.ValueFacts,
    state: *const SafetyChecker.FunctionState,
) bool {
    for (value.dependencies) |dependency| {
        const root = state.tracker.roots.items[@intFromEnum(dependency.root)];
        if (root.state == .alive) continue;
        // A resource that only exists on one choice branch can become
        // conditional/maybe-alive after joins. It is still safe to escape when
        // the escaping aggregate itself carries ownership of that exact root.
        // Keeping the ownership envelope from the outer value is important:
        // nested fields may depend on a root whose owned_roots fact is stored
        // on an ancestor aggregate. Borrowed dependencies have no such proof.
        if ((root.state == .conditional or root.state == .maybe_alive) and
            root.owned_resource and valueContainsOwnedRoot(owners, dependency.root)) continue;
        return true;
    }
    for (value.fields) |field|
        if (valueDependsOnDeadRootWithOwners(field.value.*, owners, state)) return true;
    for (value.variants) |variant|
        if (valueDependsOnDeadRootWithOwners(variant.value.*, owners, state)) return true;
    return false;
}

fn rootIsStructurallyReferenced(state: *const SafetyChecker.FunctionState, root: facts.ValidityRootId) bool {
    for (state.places.items) |stored|
        if (valueContainsOwnedRoot(stored.value, root) or valueDependsOnRoot(stored.value, root)) return true;
    for (state.storage_generations.items) |storage_generation|
        if (storage_generation.generation == root) return true;
    for (state.opaque_storages.items) |opaque_storage|
        if (containsRoot(opaque_storage.hidden_dependencies, root)) return true;
    for (state.ownership_edges.items) |edge|
        if (edge.owner == root or edge.owned == root) return true;
    return false;
}

fn statesEqual(left: *const SafetyChecker.FunctionState, right: *const SafetyChecker.FunctionState) bool {
    if (left.reachable != right.reachable or
        left.tracker.roots.items.len != right.tracker.roots.items.len or
        left.storage_capabilities.items.len != right.storage_capabilities.items.len or
        left.lexical_storage_generations.items.len != right.lexical_storage_generations.items.len or
        left.places.items.len != right.places.items.len or
        left.ownership_edges.items.len != right.ownership_edges.items.len or
        left.storage_generations.items.len != right.storage_generations.items.len or
        left.opaque_storages.items.len != right.opaque_storages.items.len or
        left.choice_active.items.len != right.choice_active.items.len or
        left.choice_rejected.items.len != right.choice_rejected.items.len or
        left.choice_temporary_active.items.len != right.choice_temporary_active.items.len) return false;

    for (left.tracker.roots.items, right.tracker.roots.items) |a, b|
        if (a.state != b.state or a.owned_resource != b.owned_resource) return false;
    for (left.storage_capabilities.items, right.storage_capabilities.items) |a, b|
        if (a != b) return false;
    for (left.lexical_storage_generations.items) |root|
        if (!containsRoot(right.lexical_storage_generations.items, root)) return false;
    for (left.places.items) |left_place| {
        const right_place = findPlaceConst(right, left_place.storage) orelse return false;
        if (left_place.initializedness != right_place.initializedness or !valueFactsEqual(left_place.value, right_place.value)) return false;
    }
    for (left.ownership_edges.items) |edge| {
        var found = false;
        for (right.ownership_edges.items) |other| if (edge.owner == other.owner and edge.owned == other.owned) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    for (left.storage_generations.items) |entry| {
        var found = false;
        for (right.storage_generations.items) |other| if (entry.storage.eql(other.storage) and entry.generation == other.generation) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    for (left.opaque_storages.items) |opaque_storage| {
        var matching: ?SafetyChecker.OpaqueStorage = null;
        for (right.opaque_storages.items) |other| if (opaque_storage.storage.eql(other.storage)) {
            matching = other;
            break;
        };
        const other = matching orelse return false;
        if (opaque_storage.hidden_dependencies.len != other.hidden_dependencies.len) return false;
        for (opaque_storage.hidden_dependencies) |dependency|
            if (!containsRoot(other.hidden_dependencies, dependency)) return false;
    }
    for (left.choice_active.items) |candidate| {
        var found = false;
        for (right.choice_active.items) |other| if (candidate.storage.eql(other.storage) and candidate.variant_index == other.variant_index) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    for (left.choice_rejected.items) |candidate| {
        var found = false;
        for (right.choice_rejected.items) |other| if (candidate.storage.eql(other.storage) and candidate.variant_index == other.variant_index) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    for (left.choice_temporary_active.items) |candidate| {
        var found = false;
        for (right.choice_temporary_active.items) |other| if (candidate.expression == other.expression and candidate.variant_index == other.variant_index) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn valueFactsEqual(left: facts.ValueFacts, right: facts.ValueFacts) bool {
    if (left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        left.known_choice_variant != right.known_choice_variant or
        !std.mem.eql(facts.StorageCapabilityId, left.storage_capabilities, right.storage_capabilities) or
        !std.mem.eql(graph_mod.GlobalFunctionId, left.virtual_methods, right.virtual_methods) or
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len or
        left.variants.len != right.variants.len or
        left.opaque_provenance.len != right.opaque_provenance.len) return false;
    for (left.dependencies, right.dependencies) |a, b| if (a.root != b.root) return false;
    for (left.owned_roots, right.owned_roots) |a, b| if (a != b) return false;
    if ((left.referenced_place == null) != (right.referenced_place == null)) return false;
    if (left.referenced_place) |left_place| if (!left_place.eql(right.referenced_place.?)) return false;
    for (left.opaque_provenance, right.opaque_provenance) |a, b|
        if (!a.storage.eql(b.storage) or a.generation != b.generation) return false;
    for (left.fields, right.fields) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    for (left.variants, right.variants) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    return true;
}

fn joinInitializedness(left: value_state.Initializedness, right: value_state.Initializedness) value_state.Initializedness {
    if (left == right) return left;
    return .maybe_initialized;
}

fn findPlaceConst(state: *const SafetyChecker.FunctionState, storage: facts.Place) ?*const facts.PlaceFacts {
    for (state.places.items) |*entry| if (entry.storage.eql(storage)) return entry;
    return null;
}

fn isPointer(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .pointer => true,
        else => false,
    };
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

test "opaque summary runtime recovers hidden external dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const binding: graph_mod.GlobalBindingId = @enumFromInt(0);
    const storage = facts.Place{ .root = binding };
    const backing = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(backing)].owned_resource = true;
    const generation = try checker.storageGeneration(&state, storage);
    const external = try state.tracker.establish(.fresh);
    try checker.setPlace(&state, storage, .initialized, .{ .owned_roots = &.{backing} });
    try checker.mergeOpaqueStorage(&state, storage, &.{ backing, generation, external });

    const moved_out = try checker.instantiateOutput(.{
        .opaque_storage_dependencies = &.{.{ .input_index = 0 }},
        .fresh_owned_roots = &.{91},
    }, &.{.{ .referenced_place = storage }}, &state);
    try std.testing.expect(valueDependsOnRoot(moved_out, external));
    try std.testing.expect(!valueDependsOnRoot(moved_out, backing));
    try std.testing.expect(!valueDependsOnRoot(moved_out, generation));
    try std.testing.expectEqual(@as(usize, 1), moved_out.owned_roots.len);

    checker.markOpaqueStorageEmpty(&state, storage);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
}

test "opaque primitives move ownership through domain state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const storage_binding: graph_mod.GlobalBindingId = @enumFromInt(0);
    const storage = facts.Place{ .root = storage_binding };
    const owned = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(owned)].owned_resource = true;
    const external = try state.tracker.establish(.fresh);
    const moved = facts.ValueFacts{
        .dependencies = &.{.{ .root = external }},
        .owned_roots = &.{owned},
    };

    try checker.applyOpaqueMovePrimitive(
        @enumFromInt(0),
        .{ .file_index = 0, .offset = 0 },
        &.{},
        &.{ .{ .referenced_place = storage }, .{}, moved },
        &state,
    );
    try std.testing.expect(!state.tracker.isAlive(owned));
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items.len);
    try std.testing.expect(containsRoot(state.opaque_storages.items[0].hidden_dependencies, external));

    const moved_out = try checker.opaqueMoveOutPrimitive(
        &.{},
        &.{.{ .referenced_place = storage }},
        &state,
    );
    try std.testing.expect(valueDependsOnRoot(moved_out, external));
    try std.testing.expectEqual(@as(usize, 1), moved_out.owned_roots.len);
    try std.testing.expect(state.tracker.isAlive(moved_out.owned_roots[0]));

    checker.markOpaqueStorageEmpty(&state, storage);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
}

test "relocate primitive preserves owned root identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const source_storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const destination = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(1)) };
    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
    try checker.setPlace(&state, source_storage, .initialized, .{ .owned_roots = &.{root} });
    try checker.setPlace(&state, destination, .moved, .{});

    _ = try checker.relocatePrimitive(
        .{ .file_index = 0, .offset = 0 },
        &.{ .{ .referenced_place = source_storage }, .{ .referenced_place = destination } },
        &state,
    );
    try std.testing.expect(state.tracker.isAlive(root));
    try std.testing.expectEqual(value_state.Initializedness.moved, checker.getPlace(&state, source_storage).?.initializedness);
    const destination_value = checker.getPlace(&state, destination).?.value;
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{root}, destination_value.owned_roots);
}

test "choice variant projection retains nested reference dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();

    const root: facts.ValidityRootId = @enumFromInt(1);
    const reference = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    const payload = facts.ValueFacts{ .fields = &.{.{ .index = 0, .value = &reference }} };
    const choice = facts.ValueFacts{ .variants = &.{.{ .index = 1, .value = &payload }} };
    const projected = try checker.projectValueFacts(choice, &.{ .{ .variant = 1 }, .{ .field = 0 } });
    try std.testing.expectEqual(root, projected.dependencies[0].root);
}

test "opaque read envelopes distinguish scalar and reference values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .pointer = .{
        .child = @as(graph_mod.GlobalTypeId, @enumFromInt(0)),
        .mutability = .read_only,
    } });
    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();

    const storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const generation: facts.ValidityRootId = @enumFromInt(7);
    const unrelated: facts.ValidityRootId = @enumFromInt(8);
    const provenance = [_]facts.OpaqueProvenance{.{ .storage = storage, .generation = generation }};

    const scalar = try checker.addOpaqueReadEnvelope(
        .{ .dependencies = &.{.{ .root = unrelated }} },
        @as(graph_mod.GlobalTypeId, @enumFromInt(0)),
        &provenance,
    );
    try std.testing.expectEqual(@as(usize, 0), scalar.dependencies.len);

    const reference = try checker.addOpaqueReadEnvelope(
        .{},
        @as(graph_mod.GlobalTypeId, @enumFromInt(1)),
        &provenance,
    );
    try std.testing.expect(valueDependsOnRoot(reference, generation));
    const projected = try checker.addOpaqueReadEnvelope(
        .{ .dependencies = &.{.{ .root = unrelated }}, .owned_roots = &.{unrelated} },
        @as(graph_mod.GlobalTypeId, @enumFromInt(1)),
        &.{},
    );
    try std.testing.expect(valueDependsOnRoot(projected, unrelated));
    try std.testing.expectEqual(@as(usize, 0), projected.owned_roots.len);
}

test "structural auto deinit marks nested fields and parent dead" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .mutability = .variable,
    });
    try graph.auto_deinit_fields.append(allocator, .{
        .field_index = 0,
        .deinit_fn = null,
    });
    try graph.auto_deinits.append(allocator, .{
        .binding = @enumFromInt(0),
        .deinit_fn = null,
        .fields = .{ .start = 0, .len = 1 },
    });

    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const child = try checker.project(root, .{ .field = 0 });
    try checker.setPlace(&state, root, .initialized, .{});
    try checker.setPlace(&state, child, .initialized, .{});

    try checker.applyAutoDeinit(@enumFromInt(0), @enumFromInt(0), &state);
    try std.testing.expectEqual(value_state.Initializedness.deinitialized, checker.initializednessAtPlace(&state, child));
    try std.testing.expectEqual(value_state.Initializedness.deinitialized, checker.initializednessAtPlace(&state, root));
}

test "rich safety join preserves all compact state dimensions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();

    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    var right = SafetyChecker.FunctionState.init(allocator);
    defer right.deinit();
    var joined = SafetyChecker.FunctionState.init(allocator);
    defer joined.deinit();

    const changing = try left.tracker.establish(.fresh);
    const left_dependency = try left.tracker.establish(.fresh);
    const right_dependency = try left.tracker.establish(.fresh);
    _ = try right.tracker.establish(.fresh);
    _ = try right.tracker.establish(.fresh);
    _ = try right.tracker.establish(.fresh);
    right.tracker.end(changing);

    try left.storage_capabilities.append(.available);
    try right.storage_capabilities.append(.consumed);

    const storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    try left.places.append(.{
        .storage = storage,
        .initializedness = .initialized,
        .value = .{ .dependencies = &.{.{ .root = left_dependency }} },
    });
    try right.places.append(.{
        .storage = storage,
        .initializedness = .initialized,
        .value = .{ .dependencies = &.{.{ .root = right_dependency }} },
    });

    try left.ownership_edges.append(.{ .owner = changing, .owned = left_dependency });
    try right.ownership_edges.append(.{ .owner = changing, .owned = right_dependency });
    try left.storage_generations.append(.{ .storage = storage, .generation = left_dependency });
    try right.storage_generations.append(.{ .storage = storage, .generation = right_dependency });
    try left.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{left_dependency} });
    try right.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{right_dependency} });
    try left.choice_active.append(.{ .storage = storage, .variant_index = 2 });
    try right.choice_active.append(.{ .storage = storage, .variant_index = 2 });
    try left.choice_rejected.append(.{ .storage = storage, .variant_index = 1 });
    try right.choice_rejected.append(.{ .storage = storage, .variant_index = 1 });

    try checker.joinState(&joined, &left, &right);

    try std.testing.expectEqual(.maybe_alive, joined.tracker.roots.items[@intFromEnum(changing)].state);
    try std.testing.expectEqual(SafetyChecker.StorageCapabilityState.maybe_consumed, joined.storage_capabilities.items[0]);
    const joined_value = checker.valueAtPlace(&joined, storage).?;
    try std.testing.expect(valueDependsOnRoot(joined_value, left_dependency));
    try std.testing.expect(valueDependsOnRoot(joined_value, right_dependency));
    try std.testing.expectEqual(@as(usize, 2), joined.ownership_edges.items.len);
    try std.testing.expectEqual(@as(usize, 1), joined.storage_generations.items.len);
    try std.testing.expectEqual(@as(usize, 1), joined.opaque_storages.items.len);
    try std.testing.expect(containsRoot(joined.opaque_storages.items[0].hidden_dependencies, left_dependency));
    try std.testing.expect(containsRoot(joined.opaque_storages.items[0].hidden_dependencies, right_dependency));
    try std.testing.expectEqual(@as(usize, 1), joined.choice_active.items.len);
    try std.testing.expectEqual(@as(usize, 1), joined.choice_rejected.items.len);
}

test "loop transfer joins retain branch state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();

    var first = SafetyChecker.FunctionState.init(allocator);
    defer first.deinit();
    var second = SafetyChecker.FunctionState.init(allocator);
    defer second.deinit();
    const storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const first_root = try first.tracker.establish(.fresh);
    const second_root = try first.tracker.establish(.fresh);
    _ = try second.tracker.establish(.fresh);
    _ = try second.tracker.establish(.fresh);
    try first.places.append(.{ .storage = storage, .value = .{ .dependencies = &.{.{ .root = first_root }} } });
    try second.places.append(.{ .storage = storage, .value = .{ .dependencies = &.{.{ .root = second_root }} } });

    var transfer: ?SafetyChecker.FunctionState = null;
    defer if (transfer) |*state| state.deinit();
    try checker.mergeLoopTransfer(&transfer, &first);
    try checker.mergeLoopTransfer(&transfer, &second);
    const value = checker.valueAtPlace(&transfer.?, storage).?;
    try std.testing.expect(valueDependsOnRoot(value, first_root));
    try std.testing.expect(valueDependsOnRoot(value, second_root));
}

test "state equality observes capability and storage generation changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    var right = SafetyChecker.FunctionState.init(allocator);
    defer right.deinit();
    try left.storage_capabilities.append(.available);
    try right.storage_capabilities.append(.consumed);
    try std.testing.expect(!statesEqual(&left, &right));
}

test "loop root widening is stable and preserves historical aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();

    const binding: graph_mod.GlobalBindingId = @enumFromInt(0);
    const owner = facts.Place{ .root = binding, .projections = &.{.{ .field = 0 }} };
    const alias = facts.Place{ .root = binding, .projections = &.{.{ .field = 1 }} };

    var entry = SafetyChecker.FunctionState.init(allocator);
    defer entry.deinit();
    const old = try entry.tracker.establish(.fresh);
    entry.tracker.roots.items[@intFromEnum(old)].owned_resource = true;
    const child = try entry.tracker.establish(.fresh);
    entry.tracker.roots.items[@intFromEnum(child)].owned_resource = true;
    try entry.ownership_edges.append(.{ .owner = old, .owned = child });
    try entry.places.append(.{ .storage = owner, .initializedness = .initialized, .value = .{
        .dependencies = &.{.{ .root = old }},
        .owned_roots = &.{old},
    } });
    try entry.places.append(.{ .storage = alias, .initializedness = .initialized, .value = .{
        .dependencies = &.{.{ .root = old }},
    } });

    var iteration = try entry.clone(allocator, null);
    defer iteration.deinit();
    iteration.tracker.end(old);
    const replacement = try iteration.tracker.establish(.fresh);
    iteration.tracker.roots.items[@intFromEnum(replacement)].owned_resource = true;
    try iteration.ownership_edges.append(.{ .owner = replacement, .owned = child });
    checker.getPlace(&iteration, owner).?.value = .{
        .dependencies = &.{.{ .root = replacement }},
        .owned_roots = &.{replacement},
    };

    var context = SafetyChecker.LoopJoinContext.init(allocator);
    defer context.deinit();
    var joined = try entry.clone(allocator, null);
    defer joined.deinit();
    try checker.joinState(&joined, &entry, &iteration);
    try checker.widenLoopOwnedRoots(&context, &joined, &entry, &iteration);
    try std.testing.expectEqual(@as(usize, 1), context.roots.items.len);
    const phi = context.roots.items[0].root;
    const widened_owner = checker.getPlace(&joined, owner).?.value;
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{phi}, widened_owner.owned_roots);
    try std.testing.expect(joined.tracker.dependenciesAreAlive(widened_owner));
    try std.testing.expect(!joined.tracker.dependenciesAreAlive(checker.getPlace(&joined, alias).?.value));
    try std.testing.expectEqual(@as(usize, 1), joined.ownership_edges.items.len);
    try std.testing.expectEqual(phi, joined.ownership_edges.items[0].owner);
    try std.testing.expectEqual(child, joined.ownership_edges.items[0].owned);
    const stable_root_count = joined.tracker.roots.items.len;

    var second_iteration = try joined.clone(allocator, null);
    defer second_iteration.deinit();
    second_iteration.tracker.end(phi);
    const second_replacement = try second_iteration.tracker.establish(.fresh);
    second_iteration.tracker.roots.items[@intFromEnum(second_replacement)].owned_resource = true;
    try second_iteration.ownership_edges.append(.{ .owner = second_replacement, .owned = child });
    checker.getPlace(&second_iteration, owner).?.value = .{
        .dependencies = &.{.{ .root = second_replacement }},
        .owned_roots = &.{second_replacement},
    };

    var fixed_point = try entry.clone(allocator, null);
    defer fixed_point.deinit();
    try checker.joinState(&fixed_point, &entry, &second_iteration);
    try checker.widenLoopOwnedRoots(&context, &fixed_point, &entry, &second_iteration);
    try std.testing.expectEqual(phi, checker.getPlace(&fixed_point, owner).?.value.owned_roots[0]);
    try std.testing.expectEqual(stable_root_count, fixed_point.tracker.roots.items.len);
    try std.testing.expectEqual(@as(usize, 1), fixed_point.ownership_edges.items.len);
    try std.testing.expectEqual(phi, fixed_point.ownership_edges.items[0].owner);
}

test "loop root widening does not hide crossed stale dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();

    const storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    const first = try left.tracker.establish(.fresh);
    const second = try left.tracker.establish(.fresh);
    left.tracker.roots.items[@intFromEnum(first)].owned_resource = true;
    left.tracker.roots.items[@intFromEnum(second)].owned_resource = true;
    left.tracker.end(second);
    try left.places.append(.{ .storage = storage, .value = .{
        .dependencies = &.{ .{ .root = first }, .{ .root = second } },
        .owned_roots = &.{first},
    } });
    var right = try left.clone(allocator, null);
    defer right.deinit();
    right.tracker.roots.items[@intFromEnum(first)].state = .dead;
    right.tracker.roots.items[@intFromEnum(second)].state = .alive;
    checker.getPlace(&right, storage).?.value = .{
        .dependencies = &.{ .{ .root = first }, .{ .root = second } },
        .owned_roots = &.{second},
    };

    var joined = try left.clone(allocator, null);
    defer joined.deinit();
    try checker.joinState(&joined, &left, &right);
    var context = SafetyChecker.LoopJoinContext.init(allocator);
    defer context.deinit();
    try checker.widenLoopOwnedRoots(&context, &joined, &left, &right);
    try std.testing.expectEqual(@as(usize, 0), context.roots.items.len);
    try std.testing.expect(!joined.tracker.dependenciesAreAlive(checker.getPlace(&joined, storage).?.value));
}

test "local storage generations survive scope cleanup for escape checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const input_binding: graph_mod.GlobalBindingId = @enumFromInt(0);
    const local_binding: graph_mod.GlobalBindingId = @enumFromInt(1);
    try graph.binding_refs.append(allocator, input_binding);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .input_bindings = .{ .start = 0, .len = 1 },
    });

    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const input_root = try state.tracker.establish(.fresh);
    const local_root = try state.tracker.establish(.fresh);
    try state.storage_generations.append(.{ .storage = .{ .root = input_binding }, .generation = input_root });
    try state.storage_generations.append(.{ .storage = .{ .root = local_binding }, .generation = local_root });

    try std.testing.expect(!checker.isLocalStorageGeneration(@enumFromInt(0), &state, input_root));
    try std.testing.expect(checker.isLocalStorageGeneration(@enumFromInt(0), &state, local_root));

    try state.lexical_storage_generations.append(local_root);
    _ = state.storage_generations.pop();
    try std.testing.expect(checker.isLocalStorageGeneration(@enumFromInt(0), &state, local_root));

    const nested = facts.ValueFacts{ .dependencies = &.{.{ .root = local_root }} };
    const aggregate = facts.ValueFacts{ .fields = &.{.{ .index = 0, .value = &nested }} };
    try std.testing.expect(checker.valueDependsOnLocalStorage(@enumFromInt(0), aggregate, &state));
}

test "dead root output detection traverses choice payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    state.tracker.end(root);
    const payload = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    const value = facts.ValueFacts{ .variants = &.{.{ .index = 0, .value = &payload }} };
    try std.testing.expect(valueDependsOnDeadRoot(value, &state));
}

test "opaque writes repopulate only accessed domains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const domain = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const other = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(1)) };
    const root = try state.tracker.establish(.fresh);
    try checker.mergeOpaqueStorage(&state, domain, &.{});
    try checker.mergeOpaqueStorage(&state, other, &.{});
    try checker.recordOpaqueWrite(&state, .{ .opaque_provenance = &.{.{ .storage = domain, .generation = root }} }, .{ .dependencies = &.{.{ .root = root }} });
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{root}, state.opaque_storages.items[0].hidden_dependencies);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[1].hidden_dependencies.len);
}

test "payload transfer removes residual ownership without reviving ended roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].state = .conditional;
    const payload = facts.ValueFacts{ .owned_roots = &.{root}, .dependencies = &.{.{ .root = root }} };
    const aggregate = facts.ValueFacts{ .variants = &.{.{ .index = 0, .value = &payload }} };
    const residual = try checker.withoutOwnedRoots(aggregate, &.{root});
    try std.testing.expect(!valueContainsOwnedRoot(residual, root));
    try std.testing.expect(!valueDependsOnRoot(residual, root));
    try std.testing.expect(valueContainsOwnedRoot(payload, root));
    try checker.activateConditionalOwnedRoots(&state, payload);
    try std.testing.expect(state.tracker.isAlive(root));
    state.tracker.end(root);
    try checker.activateConditionalOwnedRoots(&state, payload);
    try std.testing.expect(!state.tracker.isAlive(root));
}

test "temporary choice refinement tracks non-addressable expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.variants.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .value = 0,
    });
    try graph.variants.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .value = 1,
    });
    try graph.types.append(allocator, .{ .structural_choice = .{
        .variants = .{ .start = 0, .len = 2 },
    } });
    try graph.nodes.append(allocator, .{
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .content = .{ .int_literal = 0 },
    });

    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    var right = SafetyChecker.FunctionState.init(allocator);
    defer right.deinit();
    var empty = SafetyChecker.FunctionState.init(allocator);
    defer empty.deinit();
    var joined = SafetyChecker.FunctionState.init(allocator);
    defer joined.deinit();

    const expression: graph_mod.GlobalNodeId = @enumFromInt(0);
    const variant: graph_mod.GlobalVariantId = @enumFromInt(1);
    try checker.refineChoice(&left, expression, variant, true);
    try checker.refineChoice(&right, expression, variant, true);
    try std.testing.expect(checker.temporaryVariantActive(&left, expression, 1));

    var cloned = try left.clone(allocator, null);
    defer cloned.deinit();
    try std.testing.expect(statesEqual(&left, &cloned));
    try std.testing.expect(!statesEqual(&left, &empty));

    try checker.joinState(&joined, &left, &right);
    try std.testing.expect(checker.temporaryVariantActive(&joined, expression, 1));

    try checker.joinState(&joined, &left, &empty);
    try std.testing.expectEqual(@as(usize, 0), joined.choice_temporary_active.items.len);
}

test "recursive summary helper instantiates converged outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var engine = summary_engine.Engine.init(allocator);
    defer engine.deinit();

    const function: graph_mod.GlobalFunctionId = @enumFromInt(0);
    try engine.ensureEmpty(function);
    _ = try engine.updateSummary(function, .{
        .outputs = &.{.{ .integer_address = true }},
    });
    checker.active_summaries = &engine;

    const result = (try checker.applyFunctionSummary(
        .{ .file_index = 0, .offset = 0 },
        null,
        function,
        &.{},
        &.{},
        &state,
    )).?;
    try std.testing.expect(result.integer_address);
}

test "direct call summaries annotate auto deinit transitions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const binding: graph_mod.GlobalBindingId = @enumFromInt(0);
    const binding_use: graph_mod.GlobalNodeId = @enumFromInt(0);
    const address: graph_mod.GlobalNodeId = @enumFromInt(1);
    const initializes_call: graph_mod.GlobalNodeId = @enumFromInt(2);
    const consumes_call: graph_mod.GlobalNodeId = @enumFromInt(3);
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .binding_use = binding } });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .address_of = binding_use } });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = binding_use } } });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = binding_use } } });
    try graph.value_fields.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = address });

    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    checker.recordFunctionCallAutoDeinit(initializes_call, .{ .input_post_states = &.{.{
        .target = .{ .input_index = 0 },
        .initializedness = .initialized,
        .requires_available_destination = true,
    }} }, &.{@as(graph_mod.GlobalValueFieldId, @enumFromInt(0))});
    checker.recordFunctionCallAutoDeinit(consumes_call, .{ .input_post_states = &.{.{
        .target = .{ .input_index = 0 },
        .initializedness = .deinitialized,
    }} }, &.{@as(graph_mod.GlobalValueFieldId, @enumFromInt(0))});

    try std.testing.expectEqual(address, graph.nodes.items[@intFromEnum(initializes_call)].content.function_call.initializes_auto_deinit.?);
    try std.testing.expectEqual(address, graph.nodes.items[@intFromEnum(consumes_call)].content.function_call.consumes_auto_deinit.?);
}

test "conditional owned roots may escape through nested aggregate fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].state = .maybe_alive;
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
    const child = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    const value = facts.ValueFacts{
        .owned_roots = &.{root},
        .fields = &.{.{ .index = 0, .value = &child }},
    };
    try std.testing.expect(!valueDependsOnDeadRoot(value, &state));
}

test "conditional borrowed roots still cannot escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].state = .maybe_alive;
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
    const child = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    const value = facts.ValueFacts{ .fields = &.{.{ .index = 0, .value = &child }} };
    try std.testing.expect(valueDependsOnDeadRoot(value, &state));
}

test "dead owned roots still cannot escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].state = .dead;
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
    const value = facts.ValueFacts{
        .dependencies = &.{.{ .root = root }},
        .owned_roots = &.{root},
    };
    try std.testing.expect(valueDependsOnDeadRoot(value, &state));
}
