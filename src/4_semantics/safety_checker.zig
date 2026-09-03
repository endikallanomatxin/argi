const std = @import("std");
const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");
const facts = @import("safety_facts.zig");
const place = @import("place.zig");
const value_state = @import("value_state.zig");

/// Infers temporal effects from semantized bodies. Summaries are deliberately
/// compiler-owned: ordinary functions have no source contract to maintain.
pub const SafetyChecker = struct {
    allocator: *const std.mem.Allocator,
    diagnostics: *diagnostics.Diagnostics,
    summaries: std.AutoHashMap(*const sg.FunctionDeclaration, facts.SafetySummary),
    virtual_summaries: std.AutoHashMap(*const sg.VirtualMethodRegistry, facts.SafetySummary),
    invalid_virtual_summaries: std.AutoHashMap(*const sg.VirtualMethodRegistry, void),
    inference_bindings: ?*std.AutoHashMap(*const sg.BindingDeclaration, facts.ValueEffect),
    inference_place_bindings: ?*std.AutoHashMap(*const sg.BindingDeclaration, []const facts.InputPath),
    // Choice construction retains invalid-address provenance in nested
    // default values and diagnoses it when that pointer is actually used.
    choice_payload_depth: usize,

    pub fn init(allocator: *const std.mem.Allocator, diags: *diagnostics.Diagnostics) SafetyChecker {
        return .{
            .allocator = allocator,
            .diagnostics = diags,
            .summaries = std.AutoHashMap(*const sg.FunctionDeclaration, facts.SafetySummary).init(allocator.*),
            .virtual_summaries = std.AutoHashMap(*const sg.VirtualMethodRegistry, facts.SafetySummary).init(allocator.*),
            .invalid_virtual_summaries = std.AutoHashMap(*const sg.VirtualMethodRegistry, void).init(allocator.*),
            .inference_bindings = null,
            .inference_place_bindings = null,
            .choice_payload_depth = 0,
        };
    }

    pub fn deinit(self: *SafetyChecker) void {
        self.summaries.deinit();
        self.virtual_summaries.deinit();
        self.invalid_virtual_summaries.deinit();
    }

    pub fn analyze(self: *SafetyChecker, nodes: []const *sg.SGNode) !void {
        const diagnostic_count = self.diagnostics.list.items.len;
        var functions = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*);
        defer functions.deinit();
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try functions.append(function),
            .test_declaration => |test_decl| try functions.append(test_decl.function),
            else => {},
        };

        for (functions.items) |function| try self.ensureEmptySummary(function);
        const limit = @max(functions.items.len + 1, 1);
        for (0..limit) |_| {
            self.virtual_summaries.clearRetainingCapacity();
            self.invalid_virtual_summaries.clearRetainingCapacity();
            var changed = false;
            for (functions.items) |function| changed = (try self.infer(function)) or changed;
            if (!changed) break;
        }
        self.virtual_summaries.clearRetainingCapacity();
        self.invalid_virtual_summaries.clearRetainingCapacity();
        for (functions.items) |function| try self.validateFunction(function);
        if (self.diagnostics.list.items.len != diagnostic_count) return error.Reported;
    }

    const FunctionState = struct {
        const OwnershipEdge = struct { owner: facts.ValidityRootId, owned: facts.ValidityRootId };
        const StorageGeneration = struct { storage: place.Place, generation: facts.ValidityRootId };
        const OpaqueStorage = struct { storage: place.Place, hidden_dependencies: []const facts.ValidityRootId };
        const ChoiceActive = struct { storage: place.Place, variant_index: u32 };
        const ChoiceRejected = struct { storage: place.Place, variant_index: u32 };
        const ChoiceTemporaryActive = struct { expression: *const sg.SGNode, variant_index: u32 };
        const StorageCapabilityState = enum { available, conditional, maybe_consumed, consumed };
        tracker: facts.Tracker,
        storage_capabilities: std.array_list.Managed(StorageCapabilityState),
        places: std.array_list.Managed(facts.PlaceFacts),
        ownership_edges: std.array_list.Managed(OwnershipEdge),
        storage_generations: std.array_list.Managed(StorageGeneration),
        lexical_storage_generations: std.array_list.Managed(facts.ValidityRootId),
        opaque_storages: std.array_list.Managed(OpaqueStorage),
        choice_active: std.array_list.Managed(ChoiceActive),
        choice_rejected: std.array_list.Managed(ChoiceRejected),
        choice_temporary_active: std.array_list.Managed(ChoiceTemporaryActive),
        reachable: bool = true,
        ownership_conflict_reported: bool = false,

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .storage_capabilities = std.array_list.Managed(StorageCapabilityState).init(allocator),
                .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
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
            self.storage_capabilities.deinit();
            self.places.deinit();
            self.ownership_edges.deinit();
            self.storage_generations.deinit();
            self.lexical_storage_generations.deinit();
            self.opaque_storages.deinit();
            self.choice_active.deinit();
            self.choice_rejected.deinit();
            self.choice_temporary_active.deinit();
        }

        fn clone(self: *const FunctionState, allocator: std.mem.Allocator) !FunctionState {
            var result = FunctionState.init(allocator);
            errdefer result.deinit();
            try result.tracker.roots.appendSlice(self.tracker.roots.items);
            try result.storage_capabilities.appendSlice(self.storage_capabilities.items);
            try result.places.appendSlice(self.places.items);
            try result.ownership_edges.appendSlice(self.ownership_edges.items);
            try result.storage_generations.appendSlice(self.storage_generations.items);
            try result.lexical_storage_generations.appendSlice(self.lexical_storage_generations.items);
            try result.opaque_storages.appendSlice(self.opaque_storages.items);
            try result.choice_active.appendSlice(self.choice_active.items);
            try result.choice_rejected.appendSlice(self.choice_rejected.items);
            try result.choice_temporary_active.appendSlice(self.choice_temporary_active.items);
            result.reachable = self.reachable;
            result.ownership_conflict_reported = self.ownership_conflict_reported;
            return result;
        }
    };

    /// Domains proven empty on every path reaching the current program point.
    /// Explicit returns are accumulated separately so unreachable fallthrough
    /// never makes a later lexical empty look definite.
    const OpaqueEmptyState = struct {
        emptied: std.array_list.Managed(facts.InputPath),
        reachable: bool = true,

        fn init(allocator: std.mem.Allocator) OpaqueEmptyState {
            return .{ .emptied = std.array_list.Managed(facts.InputPath).init(allocator) };
        }

        fn deinit(self: *OpaqueEmptyState) void {
            self.emptied.deinit();
        }

        fn clone(self: *const OpaqueEmptyState, allocator: std.mem.Allocator) !OpaqueEmptyState {
            var result = OpaqueEmptyState.init(allocator);
            errdefer result.deinit();
            try result.emptied.appendSlice(self.emptied.items);
            result.reachable = self.reachable;
            return result;
        }
    };

    const InputPostStateFlow = struct {
        states: std.array_list.Managed(facts.PlacePostState),
        reachable: bool = true,

        fn init(allocator: std.mem.Allocator) InputPostStateFlow {
            return .{ .states = std.array_list.Managed(facts.PlacePostState).init(allocator) };
        }

        fn deinit(self: *InputPostStateFlow) void {
            self.states.deinit();
        }

        fn clone(self: *const InputPostStateFlow, allocator: std.mem.Allocator) !InputPostStateFlow {
            return .{
                .states = try cloneInputPostStates(&self.states, allocator),
                .reachable = self.reachable,
            };
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
        storage: place.Place,
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

    const SymbolicInputOverride = struct {
        input_index: u32,
        effect: facts.ValueEffect,
    };

    fn validateFunction(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        const body = function.body orelse return;
        if (function.safety_primitive != .none) return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        // Argi pointer parameters may alias. Until a call-site proof can
        // partition them, one shared root conservatively represents any
        // temporal invalidation observable through compatible inputs.
        var pointer_input_root: ?facts.ValidityRootId = null;
        for (function.input_bindings) |binding| {
            if (binding.ty == .pointer_type) {
                const root = pointer_input_root orelse blk: {
                    const established = try state.tracker.establish(.fresh);
                    pointer_input_root = established;
                    break :blk established;
                };
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{ .dependencies = try self.oneDependency(root) });
            } else {
                try self.setPlace(&state, .{ .root = binding }, .initialized, .{});
            }
        }
        try self.validateBlock(function, body, &state, null);
        if (state.reachable) try self.rejectEscapingLocalRoots(function, &state);
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
        loop_transfers: ?*LoopTransfers,
    ) anyerror!void {
        for (block.nodes) |node| {
            switch (node.content) {
                .binding_declaration => |binding| {
                    const value = if (binding.initialization) |initialization|
                        try self.evaluate(function, initialization, state)
                    else
                        facts.ValueFacts{};
                    const storage = place.Place{ .root = binding };
                    // A declaration inside a repeated block starts a new
                    // lifetime after the previous iteration's cleanup.
                    if (self.initializednessAtPlace(state, storage) == .deinitialized)
                        try self.refreshStorageGeneration(function, state, storage);
                    try self.setPlace(state, storage, .initialized, value);
                },
                .binding_assignment => |assignment| {
                    const value = try self.evaluate(function, assignment.value, state);
                    const storage = place.Place{ .root = assignment.sym_id };
                    if (self.initializednessAtPlace(state, storage) == .deinitialized)
                        try self.refreshStorageGeneration(function, state, storage);
                    try self.setPlace(state, storage, .initialized, value);
                },
                .auto_deinit_binding => |cleanup| {
                    const storage = place.Place{ .root = cleanup.binding };
                    switch (self.initializednessAtPlace(state, storage)) {
                        .initialized => if (cleanup.deinit_fn != null) {
                            try self.evaluateResolvedAutoDeinit(function, cleanup, storage, state);
                        } else if (cleanup.fields.len == 0) {
                            if (self.getPlace(state, storage)) |owned_value| {
                                if (!try self.endRoots(function, state, owned_value.value.owned_roots)) continue;
                            }
                            try self.setPlace(state, storage, .deinitialized, .{});
                        } else {
                            const diagnostic_count = self.diagnostics.list.items.len;
                            try self.evaluateStructuralAutoDeinit(function, cleanup.fields, storage, state);
                            if (self.diagnostics.list.items.len == diagnostic_count)
                                try self.setPlace(state, storage, .deinitialized, .{});
                        },
                        // The drop flag correlates initializedness with the
                        // path-specific roots that are unavailable after a
                        // state join. No deinit effect is definite here.
                        .maybe_initialized => {},
                        .moved, .deinitialized => {},
                    }
                },
                .struct_field_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, pointerUseOperand(node).?, state) orelse continue;
                    const target = if (try self.resolvePlace(store.struct_ptr, state)) |base|
                        try self.projectedPlace(base, .{ .field = store.field_index })
                    else
                        null;
                    const value = try self.evaluateStoredValue(function, store.value, state, pointer);
                    try self.addStoredOwnershipEdges(function, state, pointer, value);
                    try self.hideOpaqueMutationDependencies(state, pointer, value);
                    if (target) |storage| try self.setPlace(state, storage, .initialized, value);
                },
                .array_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, pointerUseOperand(node).?, state) orelse continue;
                    const projection: place.Projection = if (staticIndex(store.index)) |index|
                        .{ .static_index = index }
                    else
                        .dynamic_index;
                    const target = if (try self.resolvePlace(store.array_ptr, state)) |base|
                        try self.projectedPlace(base, projection)
                    else
                        null;
                    const value = try self.evaluateStoredValue(function, store.value, state, pointer);
                    try self.addStoredOwnershipEdges(function, state, pointer, value);
                    try self.hideOpaqueMutationDependencies(state, pointer, value);
                    if (target) |storage| try self.setPlace(state, storage, .initialized, value);
                },
                .pointer_assignment => |assignment| {
                    var pointer = try self.evaluate(function, assignment.pointer, state);
                    const reinitializes_dead_place = if (pointer.referenced_place) |target|
                        if (self.getPlace(state, target)) |target_facts|
                            target_facts.initializedness == .deinitialized
                        else
                            false
                    else
                        false;
                    if (!state.tracker.dependenciesAreAlive(pointer) and !reinitializes_dead_place)
                        try self.diagnostics.add(function.location, .semantic, "reference depends on a root that has ended", .{});
                    if (reinitializes_dead_place) {
                        const target = pointer.referenced_place.?;
                        const pointer_storage = try self.resolvePlace(assignment.pointer, state);
                        pointer = try self.refreshStorageGenerationThroughPointer(function, state, target, pointer_storage, pointer);
                    }
                    const value = try self.evaluateStoredValue(function, assignment.value, state, pointer);
                    try self.addStoredOwnershipEdges(function, state, pointer, value);
                    try self.hideOpaqueMutationDependencies(state, pointer, value);
                    if (pointer.referenced_place) |target| try self.setPlace(state, target, .initialized, value);
                },
                .function_call, .virtual_call, .dereference, .explicit_cast, .struct_field_access, .array_index => _ = try self.evaluate(function, node, state),
                .if_statement => |statement| {
                    _ = try self.evaluate(function, statement.condition, state);
                    var then_state = try state.clone(self.allocator.*);
                    defer then_state.deinit();
                    if (statement.choice_test) |tag_test|
                        try self.refineChoiceTest(function, tag_test, &then_state, tag_test.then_has_variant);
                    try self.validateBlock(function, statement.then_block, &then_state, loop_transfers);
                    var else_state = try state.clone(self.allocator.*);
                    defer else_state.deinit();
                    if (statement.choice_test) |tag_test|
                        try self.refineChoiceTest(function, tag_test, &else_state, !tag_test.then_has_variant);
                    if (statement.else_block) |else_block| try self.validateBlock(function, else_block, &else_state, loop_transfers);
                    try self.joinStates(function, state, &then_state, &else_state);
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
                .return_statement => |statement| {
                    if (statement.expression) |expression| {
                        const output = try self.evaluate(function, expression, state);
                        if (expression.sem_type) |ty| if (typeContainsPointer(ty))
                            try self.rejectEscapingValue(function, output, state);
                    }
                    try self.rejectEscapingLocalRoots(function, state);
                    state.reachable = false;
                },
                .switch_statement => |statement| {
                    const choice = try self.evaluate(function, statement.expression, state);
                    var joined: ?FunctionState = null;
                    defer if (joined) |*joined_state| joined_state.deinit();
                    for (statement.cases) |case| {
                        var branch = try state.clone(self.allocator.*);
                        defer branch.deinit();
                        const variant_count = if (statement.expression.sem_type) |ty|
                            if (ty == .choice_type) ty.choice_type.variants.len else null
                        else
                            null;
                        try self.refineChoiceVariant(
                            try self.resolvePlace(statement.expression, &branch),
                            statement.expression,
                            choice,
                            variant_count,
                            case.variant_index,
                            true,
                            &branch,
                        );
                        try self.validateBlock(function, case.body, &branch, loop_transfers);
                        if (joined) |*joined_state| {
                            var combined = try state.clone(self.allocator.*);
                            try self.joinStates(function, &combined, joined_state, &branch);
                            joined_state.deinit();
                            joined_state.* = combined;
                        } else joined = try branch.clone(self.allocator.*);
                    }
                    if (statement.default_case) |default_case| {
                        var branch = try state.clone(self.allocator.*);
                        defer branch.deinit();
                        try self.validateBlock(function, default_case, &branch, loop_transfers);
                        if (joined) |*joined_state| {
                            var combined = try state.clone(self.allocator.*);
                            try self.joinStates(function, &combined, joined_state, &branch);
                            joined_state.deinit();
                            joined_state.* = combined;
                        } else joined = try branch.clone(self.allocator.*);
                    } else if (!statement.exhaustive) {
                        if (joined) |*joined_state| {
                            var combined = try state.clone(self.allocator.*);
                            try self.joinStates(function, &combined, joined_state, state);
                            joined_state.deinit();
                            joined_state.* = combined;
                        }
                    }
                    if (joined) |*joined_state| try self.copyState(state, joined_state);
                },
                .break_statement => {
                    if (loop_transfers) |transfers| try self.mergeLoopTransfer(function, &transfers.break_state, state);
                    state.reachable = false;
                },
                .continue_statement => {
                    if (loop_transfers) |transfers| try self.mergeLoopTransfer(function, &transfers.continue_state, state);
                    state.reachable = false;
                },
                else => {},
            }
            try self.validateUniqueOwnership(function, state);
            if (!state.reachable) {
                try self.endBlockLocalStorage(function, block, state);
                if (loop_transfers) |transfers| {
                    if (transfers.break_state) |*break_state|
                        try self.endBlockLocalStorage(function, block, break_state);
                    if (transfers.continue_state) |*continue_state|
                        try self.endBlockLocalStorage(function, block, continue_state);
                }
                return;
            }
        }
        try self.endBlockLocalStorage(function, block, state);
    }

    /// Value cleanup is represented explicitly in the semantic graph and has
    /// already run when control reaches a block boundary. What remains is the
    /// lexical lifetime of addressable local storage: end its temporal roots,
    /// remove its structural facts, and retain only dead ValidityRootIds still
    /// observable through values that escaped into an outer Place.
    fn endBlockLocalStorage(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
    ) !void {
        for (block.nodes) |node| {
            const binding = switch (node.content) {
                .binding_declaration => |declared| declared,
                else => continue,
            };
            var storage_index: usize = 0;
            while (storage_index < state.storage_generations.items.len) {
                const mapping = state.storage_generations.items[storage_index];
                if (mapping.storage.root != binding) {
                    storage_index += 1;
                    continue;
                }
                try appendOwnedRoot(&state.lexical_storage_generations, mapping.generation);
                _ = try self.endRoot(function, state, mapping.generation);
                _ = state.storage_generations.orderedRemove(storage_index);
            }
            var place_index: usize = 0;
            while (place_index < state.places.items.len) {
                if (state.places.items[place_index].storage.root == binding) {
                    _ = state.places.orderedRemove(place_index);
                } else place_index += 1;
            }
            var opaque_index: usize = 0;
            while (opaque_index < state.opaque_storages.items.len) {
                if (state.opaque_storages.items[opaque_index].storage.root == binding) {
                    _ = state.opaque_storages.orderedRemove(opaque_index);
                } else opaque_index += 1;
            }
            self.clearChoiceRefinementsUnder(state, .{ .root = binding });
        }
        self.trimUnreferencedRoots(state);
    }

    fn evaluate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        return switch (node.content) {
            .binding_use => |binding| blk: {
                const storage = place.Place{ .root = binding };
                if (self.getPlace(state, storage)) |place_facts| {
                    try self.requireInitialized(function, place_facts);
                    break :blk place_facts.value;
                }
                break :blk .{};
            },
            .move_value => |value| blk: {
                const value_type = value.sem_type orelse if (value.content == .binding_use) value.content.binding_use.ty else null;
                const moving_choice = value_type != null and value_type.? == .choice_type;
                const resolved = if (moving_choice) try self.resolvePlace(value, state) else null;
                if (resolved) |source| {
                    if (!try self.validateAddressablePath(function, value, state)) break :blk .{};
                    const result = self.valueAtPlace(state, source) orelse facts.ValueFacts{};
                    try self.setPlace(state, source, .moved, result);
                    break :blk result;
                }
                const result = try self.evaluate(function, value, state);
                if (try self.resolvePlace(value, state)) |source|
                    try self.setPlace(state, source, .moved, if (moving_choice) result else .{});
                break :blk result;
            },
            .address_of => |value| blk: {
                if (!try self.validateAddressablePath(function, value, state)) break :blk .{};
                const target = try self.resolvePlace(value, state);
                const opaque_provenance = try self.opaqueProvenanceForAccess(value, state);
                var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
                if (opaque_provenance.len == 0) {
                    try appendDependency(&dependencies, .{ .root = try self.storageGeneration(value, state) });
                } else {
                    for (opaque_provenance) |provenance|
                        try appendDependency(&dependencies, .{ .root = provenance.generation });
                }
                break :blk .{
                    .dependencies = try dependencies.toOwnedSlice(),
                    .referenced_place = target,
                    .opaque_provenance = opaque_provenance,
                };
            },
            .dereference => blk: {
                const pointer = try self.evaluatePointerUse(function, pointerUseOperand(node).?, state) orelse break :blk .{};
                if (pointer.referenced_place) |target| {
                    if (self.getPlace(state, target)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk try self.envelopeOpaqueRead(state, place_facts.value, node.sem_type, pointer);
                    }
                }
                break :blk try self.envelopeOpaqueRead(state, .{}, node.sem_type, pointer);
            },
            .struct_value_literal => |literal| try self.aggregate(function, literal.fields, state),
            .choice_literal => |literal| try self.evaluateChoiceLiteral(function, literal, state),
            .struct_field_access => |access| blk: {
                if (try self.resolvePlace(node, state)) |storage| {
                    if (!try self.validateAddressablePath(function, access.struct_value, state)) break :blk .{};
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        const provenance = try self.opaqueProvenanceCarriedByAccess(access.struct_value, state);
                        break :blk try self.addOpaqueReadEnvelope(place_facts.value, node.sem_type, provenance);
                    }
                }
                const aggregate_value = try self.evaluate(function, access.struct_value, state);
                for (aggregate_value.fields) |field| {
                    if (field.index == access.field_index) break :blk field.value.*;
                }
                break :blk aggregate_value;
            },
            .choice_payload_access => |access| blk: {
                // A moving match first consumes the choice container and then
                // extracts the active payload. Preserve the stored facts for
                // that compiler-generated extraction even though the
                // container Place has already transitioned to moved.
                const resolved = try self.resolvePlace(access.choice_value, state);
                if (resolved != null and !try self.validateAddressablePath(function, access.choice_value, state)) break :blk .{};
                const choice = if (resolved) |storage| stored_blk: {
                    const stored = self.valueAtPlace(state, storage) orelse facts.ValueFacts{};
                    const provenance = try self.opaqueProvenanceCarriedByAccess(access.choice_value, state);
                    break :stored_blk try self.addOpaqueReadEnvelope(stored, access.choice_value.sem_type, provenance);
                } else try self.evaluate(function, access.choice_value, state);
                if (resolved) |storage| {
                    if (!self.choiceVariantIsActive(state, storage, access.variant_index)) {
                        if (self.activeChoiceVariant(state, storage) != null) {
                            try self.diagnostics.add(function.location, .semantic, "choice payload '..{d}' is not active", .{access.variant_index});
                        } else {
                            try self.diagnostics.add(function.location, .semantic, "choice payload '..{d}' requires its variant to be proven active", .{access.variant_index});
                        }
                        break :blk .{};
                    }
                } else if (!self.choiceTemporaryVariantIsActive(state, access.choice_value, access.variant_index)) {
                    try self.diagnostics.add(function.location, .semantic, "choice payload access requires a choice Place with a proven active variant", .{});
                    break :blk .{};
                }
                for (choice.variants) |variant| {
                    if (variant.index == access.variant_index) break :blk variant.value.*;
                }
                break :blk .{};
            },
            .array_index => blk: {
                const pointer = try self.evaluatePointerUse(function, pointerUseOperand(node).?, state) orelse break :blk .{};
                if (try self.resolvePlace(node, state)) |storage| {
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk try self.envelopeOpaqueRead(state, place_facts.value, node.sem_type, pointer);
                    }
                }
                break :blk try self.envelopeOpaqueRead(state, .{}, node.sem_type, pointer);
            },
            .explicit_cast => |cast| blk: {
                const value = try self.evaluate(function, cast.value, state);
                const target_is_integer = cast.target_type == .builtin and cast.target_type.builtin == .UIntNative;
                const target_is_reference = cast.target_type == .pointer_type;
                const source_is_reference = cast.value.sem_type != null and cast.value.sem_type.? == .pointer_type;
                const source_is_integer = cast.value.sem_type != null and
                    cast.value.sem_type.? == .builtin and
                    switch (cast.value.sem_type.?.builtin) {
                        .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
                        else => false,
                    };
                if (target_is_integer and (source_is_reference or value.foreign_storage))
                    break :blk facts.ValueFacts{
                        .integer_address = true,
                        .foreign_storage = value.foreign_storage or value.dependencies.len == 0,
                        .storage_capabilities = value.storage_capabilities,
                    };
                if (target_is_reference and (source_is_integer or value.integer_address)) {
                    if (self.choice_payload_depth == 0)
                        try self.diagnostics.add(function.location, .semantic, "an integer address cannot establish a safe reference; use RawPointer and explicit root establishment", .{});
                    break :blk facts.ValueFacts{
                        .integer_address = true,
                        .foreign_storage = value.foreign_storage,
                        .storage_capabilities = value.storage_capabilities,
                    };
                }
                break :blk .{};
            },
            .function_call => |call| try self.evaluateCall(function, call, state),
            .virtualize => |virtualize| try self.evaluateVirtualize(function, virtualize, state),
            .virtual_call => |call| try self.evaluateVirtualCall(function, call, state),
            .binary_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                _ = try self.evaluate(function, operation.right, state);
                break :blk .{};
            },
            .comparison => |comparison| blk: {
                _ = try self.evaluate(function, comparison.left, state);
                _ = try self.evaluate(function, comparison.right, state);
                break :blk .{};
            },
            .logical_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                var right_state = try state.clone(self.allocator.*);
                defer right_state.deinit();
                if (self.choiceTagTestFromCondition(operation.left)) |tag_test| {
                    const left_has_variant = operation.operator == .and_;
                    try self.refineChoiceTest(function, tag_test, &right_state, left_has_variant == tag_test.then_has_variant);
                }
                _ = try self.evaluate(function, operation.right, &right_state);
                break :blk .{};
            },
            else => .{},
        };
    }

    fn evaluateChoiceLiteral(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        literal: *const sg.ChoiceLiteral,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        const payload = literal.payload orelse return self.choiceValue(literal.variant_index, .{});
        self.choice_payload_depth += 1;
        defer self.choice_payload_depth -= 1;
        return self.choiceValue(literal.variant_index, try self.evaluate(function, payload, state));
    }

    fn evaluateCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        // Argument evaluation can move values before a summary discovers that
        // one of its effects is invalid. Evaluate the complete call against a
        // speculative state so a rejected call cannot consume inputs or leave
        // any other temporal fact partly committed.
        var candidate = try state.clone(self.allocator.*);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        const result = try self.evaluateCallCandidate(function, call, &candidate);
        if (self.diagnostics.list.items.len != diagnostic_count) return .{};
        const previous = state.*;
        state.* = candidate;
        candidate = previous;
        return result;
    }

    fn evaluateCallCandidate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var arguments: []const sg.StructValueLiteralField = &.{};
        if (call.input.content == .struct_value_literal) arguments = call.input.content.struct_value_literal.fields;
        const argument_values = try self.allocator.alloc(facts.ValueFacts, arguments.len);
        for (arguments, 0..) |argument, index| argument_values[index] = try self.evaluate(function, argument.value, state);
        if (call.callee.safety_primitive == .relocate)
            return self.relocatePlaces(function, arguments, argument_values, state);
        if (call.callee.safety_primitive == .trusted_opaque_move or
            call.callee.safety_primitive == .trusted_opaque_move_in)
        {
            if (argument_values.len == 3) {
                try self.closeOpaqueOwnedRoots(function, argument_values[2], state, null);
                if (argument_values[0].referenced_place) |storage| {
                    try self.markOpaqueAccess(arguments[1].value, state, storage);
                    try self.hideOpaqueDependencies(state, storage, argument_values[2]);
                } else if (rootBinding(arguments[0].value)) |binding| {
                    // Pointer inputs name caller storage symbolically. The
                    // SafetySummary carries this obligation to the caller,
                    // where the concrete storage Place is available.
                    if (inputIndex(function, binding) == null and valueHasDependency(argument_values[2])) {
                        try self.diagnostics.add(function.location, .semantic, "opaque ownership storage requires an identifiable storage domain place", .{});
                        return .{};
                    }
                } else if (valueHasDependency(argument_values[2])) {
                    try self.diagnostics.add(function.location, .semantic, "opaque ownership storage requires an identifiable storage domain place", .{});
                    return .{};
                }
            } else if (argument_values.len == 2) {
                if (hasExternalOpaqueDependency(argument_values[1], argument_values[1].owned_roots)) {
                    try self.diagnostics.add(function.location, .semantic, "opaque ownership storage cannot hide dependencies on external roots", .{});
                    return .{};
                }
                try self.closeOpaqueOwnedRoots(function, argument_values[1], state, null);
                if (try self.inferOpaqueDomain(state, argument_values[0])) |storage| {
                    try self.markOpaqueAccess(arguments[0].value, state, storage);
                    try self.hideOpaqueDependencies(state, storage, argument_values[1]);
                }
            }
            return .{};
        }
        if (call.callee.safety_primitive == .trusted_opaque_move_out) {
            const source: facts.FreshEffectSource = @intFromPtr(call);
            return self.instantiateOutput(try self.primitiveValueEffect(.trusted_opaque_move_out, source), argument_values, state);
        }
        // Opaque-slot occupancy and contents deliberately have no precise
        // checker representation. Relocation only consults domain-level
        // dependencies; its source-live/destination-empty contract remains
        // the caller's responsibility.
        if (call.callee.safety_primitive == .trusted_opaque_relocate) {
            if (argument_values.len != 0) try self.rejectOpaqueRelocation(function, state, argument_values[0]);
            return .{};
        }
        if (call.callee.safety_primitive == .trusted_opaque_mark_empty) {
            if (argument_values.len == 1) {
                const storage = argument_values[0].referenced_place orelse
                    try self.resolvePlace(arguments[0].value, state) orelse return .{};
                self.markOpaqueStorageEmpty(state, storage);
            }
            return .{};
        }
        if (call.callee.safety_primitive == .raw_allocated_storage) {
            const capability: facts.StorageCapabilityId = @enumFromInt(state.storage_capabilities.items.len);
            try state.storage_capabilities.append(.available);
            return .{ .foreign_storage = true, .storage_capabilities = try self.oneStorageCapability(capability) };
        }
        if (call.callee.safety_primitive == .establish_fresh_reference)
            try self.diagnostics.add(function.location, .semantic, "fresh raw-to-safe reference establishment is restricted to compiler-owned storage boundaries", .{});
        if (call.callee.safety_primitive == .establish_allocation or
            call.callee.safety_primitive == .establish_inherited_reference or
            call.callee.safety_primitive == .establish_inherited_storage)
        {
            const requires_capability = call.callee.safety_primitive == .establish_allocation or
                call.callee.safety_primitive == .establish_inherited_storage;
            if (requires_capability and (argument_values.len == 0 or argument_values[0].storage_capabilities.len == 0)) {
                try self.diagnostics.add(function.location, .semantic, "allocation root establishment requires storage returned by an authorized allocator boundary", .{});
            } else if (argument_values.len != 0) {
                for (argument_values[0].storage_capabilities) |capability| {
                    const index = @intFromEnum(capability);
                    if (index >= state.storage_capabilities.items.len or state.storage_capabilities.items[index] != .available) {
                        try self.diagnostics.add(function.location, .semantic, "physical storage capability has already been consumed", .{});
                    } else {
                        state.storage_capabilities.items[index] = .consumed;
                    }
                }
            }
        }
        if (call.callee.body == null and call.callee.output.fields.len == 1 and
            call.callee.output.fields[0].ty == .pointer_type)
            return .{ .foreign_storage = true };
        const summary = self.summaries.get(call.callee) orelse return .{};
        if (!try self.validateRequiredLiveInputs(function, summary, argument_values, state)) return .{};
        for (summary.input_post_states) |post_state| {
            const index = post_state.target.input_index;
            if (post_state.requires_available_destination and post_state.target.projections.len == 0 and index < arguments.len and
                arguments[index].value.content == .address_of and rootBinding(arguments[index].value.content.address_of) != null)
            {
                @constCast(call).initializes_auto_deinit = arguments[index].value.content.address_of;
            }
            if ((post_state.initializedness != .deinitialized and post_state.initializedness != .moved) or
                post_state.target.projections.len != 0 or index >= arguments.len) continue;
            if (arguments[index].value.content == .address_of and rootBinding(arguments[index].value.content.address_of) != null) {
                @constCast(call).consumes_auto_deinit = arguments[index].value.content.address_of;
            }
        }
        try self.applySafetySummaryEffects(function, summary, arguments, argument_values, state);
        if (summary.outputs.len != 1) return .{};
        return self.instantiateOutput(summary.outputs[0], argument_values, state);
    }

    fn evaluateResolvedAutoDeinit(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        cleanup: *const sg.AutoDeinitBinding,
        storage: place.Place,
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
        function: *const sg.FunctionDeclaration,
        fields: []const sg.AutoDeinitField,
        storage: place.Place,
        state: *FunctionState,
    ) !void {
        for (fields) |field| {
            const field_storage = try self.projectedPlace(storage, .{ .field = field.field_index });
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
        function: *const sg.FunctionDeclaration,
        deinit_fn: *const sg.FunctionDeclaration,
        input: *const sg.SGNode,
        self_field_index: u32,
        storage: place.Place,
        state: *FunctionState,
    ) !void {
        if (input.content != .struct_value_literal) return;
        const summary = self.summaries.get(deinit_fn) orelse return;
        const arguments = input.content.struct_value_literal.fields;

        var candidate = try state.clone(self.allocator.*);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        const argument_values = try self.allocator.alloc(facts.ValueFacts, arguments.len);
        for (arguments, 0..) |argument, index| {
            argument_values[index] = if (index == self_field_index)
                .{
                    .dependencies = try self.oneDependency(try self.storageGenerationForPlace(storage, &candidate)),
                    .referenced_place = storage,
                }
            else
                try self.evaluate(function, argument.value, &candidate);
        }
        if (!try self.validateRequiredLiveInputs(function, summary, argument_values, &candidate)) return;
        try self.applySafetySummaryEffects(function, summary, arguments, argument_values, &candidate);
        if (self.diagnostics.list.items.len != diagnostic_count) return;
        const previous = state.*;
        state.* = candidate;
        candidate = previous;
    }

    fn applySafetySummaryEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.SafetySummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        // An empty-domain effect recorded in a summary is guaranteed on every exit and is
        // removed during inference if the domain is subsequently repopulated.
        // Clear it before input post-states so a wrapper can empty a domain
        // before deinitializing its storage, then reaffirm it after opaque
        // consumption effects have been instantiated.
        try self.applyOpaqueStorageEmpties(summary, arguments, argument_values, state);
        try self.applyInputEffects(function, summary, arguments, argument_values, state);
        try self.applyOpaqueStorageEmpties(summary, arguments, argument_values, state);
        try self.applyOpaqueStorageEffects(summary, arguments, argument_values, state);
    }

    /// Relocation transfers one existing value representation between distinct
    /// Places. It deliberately leaves structural Storage Generations alone: aliases
    /// into the source storage keep their old provenance and are not rebound.
    fn relocatePlaces(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        if (arguments.len != 2 or argument_values.len != 2) return .{};
        // Pointer inputs of an interprocedural body do not name a caller
        // Place locally. Their relocation effect is carried by the summary.
        const source = argument_values[0].referenced_place orelse return .{};
        const destination = argument_values[1].referenced_place orelse return .{};
        if (source.eql(destination)) {
            try self.diagnostics.add(function.location, .semantic, "relocate requires distinct source and destination places", .{});
            return .{};
        }
        if (self.initializednessAtPlace(state, source) != .initialized) {
            const initializedness = self.initializednessAtPlace(state, source);
            try self.diagnostics.add(function.location, .semantic, "place rooted at '{s}' is {s} and cannot be used", .{
                source.root.name,
                @tagName(initializedness),
            });
            return .{};
        }
        if (!try self.prepareRelocationDestination(function, state, destination)) return .{};
        const value = self.valueAtPlace(state, source) orelse return .{};
        try self.setPlace(state, destination, .initialized, value);
        try self.setPlace(state, source, .moved, .{});
        return .{};
    }

    fn closeOpaqueOwnedRoots(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        value: facts.ValueFacts,
        state: *FunctionState,
        consumed_source: ?place.Place,
    ) !void {
        var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        defer roots.deinit();
        try collectOwnedRoots(value, &roots);
        // Validate the complete boundary before changing root liveness. A
        // rejected call must not leave analysis state partly committed.
        for (roots.items) |root| {
            for (state.places.items) |candidate| {
                // The consumed Place owns the value being transferred; only
                // other live Places are external aliases to that ownership.
                if (consumed_source) |source| if (source.isPrefixOf(candidate.storage)) continue;
                if (candidate.initializedness != .initialized or !valueDependsOnRoot(candidate.value, root)) continue;
                try self.diagnostics.add(function.location, .semantic, "opaque ownership storage requires no live external aliases to the consumed root", .{});
                return;
            }
        }
        _ = try self.endRoots(function, state, roots.items);
    }

    fn hideOpaqueDependencies(self: *SafetyChecker, state: *FunctionState, storage: place.Place, value: facts.ValueFacts) !void {
        var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        defer hidden.deinit();
        try self.collectOpaqueHiddenDependencies(state, value, &hidden);
        try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
    }

    /// Opaque provenance are destination provenance when a pointer is used for
    /// access, but temporal value provenance when that pointer is stored as
    /// data. In the latter role each provenance depends on the domain's logical
    /// storage generation. Domain inference also covers aliases created before
    /// their backing storage was registered as opaque.
    fn collectOpaqueHiddenDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        hidden: *std.array_list.Managed(facts.ValidityRootId),
    ) !void {
        for (value.dependencies) |dependency| try appendOwnedRoot(hidden, dependency.root);

        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        defer provenances.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, value, &provenances);
        for (provenances.items) |provenance| try appendOwnedRoot(hidden, provenance.generation);

        for (value.fields) |field|
            try self.collectOpaqueHiddenDependencies(state, field.value.*, hidden);
        for (value.variants) |variant|
            try self.collectOpaqueHiddenDependencies(state, variant.value.*, hidden);
    }

    fn hideOpaqueMutationDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        value: facts.ValueFacts,
    ) !void {
        var storages = std.array_list.Managed(place.Place).init(self.allocator.*);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &storages);
        for (storages.items) |storage| try self.hideOpaqueDependencies(state, storage, value);
    }

    fn markOpaqueAccess(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState, storage: place.Place) !void {
        const pointer_place = try self.resolvePlace(node, state) orelse return;
        const pointer = self.getPlace(state, pointer_place) orelse return;
        try self.addOpaqueAccessProvenance(state, &pointer.value, storage);
    }

    fn addOpaqueAccessProvenance(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: *facts.ValueFacts,
        storage: place.Place,
    ) !void {
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        try provenances.appendSlice(pointer.opaque_provenance);
        for (provenances.items) |provenance| if (provenance.storage.eql(storage)) return;

        var inferred = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        defer inferred.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, pointer.*, &inferred);
        for (inferred.items) |provenance|
            if (provenance.storage.eql(storage)) try appendOpaqueProvenance(&provenances, provenance);

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
            // The first opaque move-in boundary establishes provenance for its
            // destination pointer now. Once the domain already exists, an
            // unproven old alias must never be rebound to its current root.
            if (!domain_already_opaque) try appendOpaqueProvenance(&provenances, .{
                .storage = storage,
                .generation = try self.storageGenerationForPlace(storage, state),
            });
        }
        pointer.opaque_provenance = try provenances.toOwnedSlice();
    }

    fn inferOpaqueDomain(self: *SafetyChecker, state: *FunctionState, pointer: facts.ValueFacts) !?place.Place {
        var storages = std.array_list.Managed(place.Place).init(self.allocator.*);
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

    fn collectOpaqueDomainsAccessedBy(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        result: *std.array_list.Managed(place.Place),
    ) !void {
        for (pointer.opaque_provenance) |provenance| try appendPlace(result, provenance.storage);
        for (state.opaque_storages.items) |opaque_storage| {
            if (self.valueAtPlace(state, opaque_storage.storage)) |storage_value| {
                for (pointer.dependencies) |dependency|
                    if (valueContainsOwnedRoot(storage_value, dependency.root)) try appendPlace(result, opaque_storage.storage);
            }
            for (state.storage_generations.items) |entry| {
                if (!opaque_storage.storage.isPrefixOf(entry.storage)) continue;
                for (pointer.dependencies) |dependency|
                    if (dependency.root == entry.generation) try appendPlace(result, opaque_storage.storage);
            }
        }
    }

    /// Recover generation-stable value provenance without resolving a domain
    /// Place against its current Storage Generation. Retrospective inference is only
    /// allowed when one of the pointer's existing dependency roots itself
    /// proves the association with the opaque domain.
    fn collectOpaqueProvenancesCarriedBy(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        result: *std.array_list.Managed(facts.OpaqueProvenance),
    ) !void {
        for (pointer.opaque_provenance) |provenance| try appendOpaqueProvenance(result, provenance);
        for (state.opaque_storages.items) |opaque_storage| {
            if (self.valueAtPlace(state, opaque_storage.storage)) |storage_value| {
                for (pointer.dependencies) |dependency|
                    if (valueContainsOwnedRoot(storage_value, dependency.root)) try appendOpaqueProvenance(result, .{
                        .storage = opaque_storage.storage,
                        .generation = dependency.root,
                    });
            }
            for (state.storage_generations.items) |entry| {
                if (!opaque_storage.storage.isPrefixOf(entry.storage)) continue;
                for (pointer.dependencies) |dependency|
                    if (dependency.root == entry.generation) try appendOpaqueProvenance(result, .{
                        .storage = opaque_storage.storage,
                        .generation = dependency.root,
                    });
            }
        }
    }

    /// Opaque contents have no per-slot facts. A reference-bearing value read
    /// through an opaque pointer therefore inherits the concrete generation
    /// carried by that pointer as its conservative temporal envelope.
    fn envelopeOpaqueRead(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        ty: ?sg.Type,
        pointer: facts.ValueFacts,
    ) !facts.ValueFacts {
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        defer provenances.deinit();
        try self.collectOpaqueProvenancesCarriedBy(state, pointer, &provenances);
        return self.addOpaqueReadEnvelope(value, ty, provenances.items);
    }

    fn opaqueProvenanceCarriedByAccess(
        self: *SafetyChecker,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) ![]const facts.OpaqueProvenance {
        return switch (node.content) {
            .move_value => |value| self.opaqueProvenanceCarriedByAccess(value, state),
            .struct_field_access => |access| self.opaqueProvenanceCarriedByAccess(access.struct_value, state),
            .choice_payload_access => |access| self.opaqueProvenanceCarriedByAccess(access.choice_value, state),
            .array_index => |index| self.opaqueProvenanceCarriedByPointerNode(index.array_ptr, state),
            .dereference => |dereference| self.opaqueProvenanceCarriedByPointerNode(dereference.pointer, state),
            else => &.{},
        };
    }

    fn opaqueProvenanceCarriedByPointerNode(
        self: *SafetyChecker,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) ![]const facts.OpaqueProvenance {
        const pointer_place = try self.resolvePlace(node, state) orelse return &.{};
        const pointer = self.getPlace(state, pointer_place) orelse return &.{};
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        try self.collectOpaqueProvenancesCarriedBy(state, pointer.value, &provenances);
        return provenances.toOwnedSlice();
    }

    fn addOpaqueReadEnvelope(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        ty: ?sg.Type,
        provenances: []const facts.OpaqueProvenance,
    ) !facts.ValueFacts {
        const value_type = ty orelse return value;
        if (!typeContainsPointer(value_type) or provenances.len == 0) return value;

        var result = value;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        try dependencies.appendSlice(value.dependencies);
        for (provenances) |provenance| try appendDependency(&dependencies, .{ .root = provenance.generation });
        result.dependencies = try dependencies.toOwnedSlice();

        if (value.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
            for (value.fields, 0..) |field, index| {
                const field_type: ?sg.Type = switch (value_type) {
                    .struct_type => |struct_type| if (field.index < struct_type.fields.len)
                        struct_type.fields[field.index].ty
                    else
                        null,
                    .array_type => |array_type| array_type.element_type.*,
                    else => null,
                };
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = try self.addOpaqueReadEnvelope(field.value.*, field_type, provenances);
                fields[index] = .{ .index = field.index, .value = stored };
            }
            result.fields = fields;
        }
        if (value.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
            for (value.variants, 0..) |variant, index| {
                const payload_type: ?sg.Type = switch (value_type) {
                    .choice_type => |choice| if (variant.index < choice.variants.len)
                        choice.variants[variant.index].payload_type
                    else
                        null,
                    else => null,
                };
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = try self.addOpaqueReadEnvelope(variant.value.*, payload_type, provenances);
                variants[index] = .{ .index = variant.index, .value = stored };
            }
            result.variants = variants;
        }
        return result;
    }

    fn opaqueProvenanceForAccess(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) ![]const facts.OpaqueProvenance {
        return switch (node.content) {
            .binding_use => |binding| blk: {
                const value = self.getPlace(state, .{ .root = binding }) orelse break :blk &.{};
                break :blk try self.currentOpaqueProvenancesForValue(state, value.value);
            },
            .move_value => |value| try self.opaqueProvenanceForAccess(value, state),
            .address_of => |value| try self.opaqueProvenanceForAccess(value, state),
            .struct_field_access => |access| try self.opaqueProvenanceForAccess(access.struct_value, state),
            .array_index => |index| try self.opaqueProvenanceForAccess(index.array_ptr, state),
            .dereference => |dereference| blk: {
                const pointer_place = try self.resolvePlace(dereference.pointer, state) orelse break :blk &.{};
                const pointer = self.getPlace(state, pointer_place) orelse break :blk &.{};
                break :blk try self.currentOpaqueProvenancesForValue(state, pointer.value);
            },
            else => &.{},
        };
    }

    /// A newly created reference observes the current generation of every
    /// opaque domain reached by its source expression. Existing values never
    /// pass through this normalization and retain their captured generations.
    fn currentOpaqueProvenancesForValue(self: *SafetyChecker, state: *FunctionState, value: facts.ValueFacts) ![]const facts.OpaqueProvenance {
        var storages = std.array_list.Managed(place.Place).init(self.allocator.*);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, value, &storages);
        var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        for (storages.items) |storage| try appendOpaqueProvenance(&provenances, .{
            .storage = storage,
            .generation = try self.storageGenerationForPlace(storage, state),
        });
        return provenances.toOwnedSlice();
    }

    fn rejectOpaqueRelocation(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
        source: facts.ValueFacts,
    ) !void {
        var storages = std.array_list.Managed(place.Place).init(self.allocator.*);
        defer storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, source, &storages);
        for (storages.items) |storage| {
            const storage_generation = try self.storageGenerationForPlace(storage, state);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                var invalidates_dependency = containsRoot(opaque_storage.hidden_dependencies, storage_generation);
                if (!invalidates_dependency) {
                    const storage_value = self.valueAtPlace(state, storage) orelse facts.ValueFacts{};
                    for (opaque_storage.hidden_dependencies) |dependency| {
                        if (!valueContainsOwnedRoot(storage_value, dependency)) continue;
                        invalidates_dependency = true;
                        break;
                    }
                }
                if (!invalidates_dependency) continue;
                try self.diagnostics.add(function.location, .semantic, "relocation would invalidate a hidden opaque dependency", .{});
                return;
            }
        }
    }

    fn applyOpaqueStorageEffects(
        self: *SafetyChecker,
        summary: facts.SafetySummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_effects) |effect| {
            if (effect.storage.input_index >= arguments.len) continue;
            var storage = argument_values[effect.storage.input_index].referenced_place orelse
                try self.resolvePlace(arguments[effect.storage.input_index].value, state) orelse continue;
            for (effect.storage.projections) |projection| storage = try self.projectedPlace(storage, projection);
            var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            defer hidden.deinit();
            var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator.*);
            defer fresh_roots.deinit();
            try self.instantiateOpaqueDependencies(effect.hidden_dependencies, argument_values, state, &fresh_roots, &hidden);
            var external = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            defer external.deinit();
            var hidden_value_owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            defer hidden_value_owned.deinit();
            for (effect.hidden_dependencies.input_dependencies) |dependency| {
                if (dependency.path.input_index >= argument_values.len) continue;
                const source = projectValueFacts(argument_values[dependency.path.input_index], dependency.path.projections);
                try collectOwnedRoots(source, &hidden_value_owned);
            }
            for (hidden.items) |dependency| {
                var internal_generation = false;
                for (argument_values) |argument| if (valueContainsOpaqueGeneration(argument, storage, dependency)) {
                    internal_generation = true;
                    break;
                };
                if (!internal_generation and !containsRoot(hidden_value_owned.items, dependency))
                    try appendOwnedRoot(&external, dependency);
            }
            try self.mergeLiveOpaqueDependencies(state, storage, external.items);
        }
    }

    fn applyOpaqueStorageEmpties(
        self: *SafetyChecker,
        summary: facts.SafetySummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_empties) |path| {
            if (path.input_index >= arguments.len) continue;
            var storage = argument_values[path.input_index].referenced_place orelse
                try self.resolvePlace(arguments[path.input_index].value, state) orelse continue;
            for (path.projections) |projection| storage = try self.projectedPlace(storage, projection);
            self.markOpaqueStorageEmpty(state, storage);
        }
    }

    fn mergeLiveOpaqueDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        dependencies: []const facts.ValidityRootId,
    ) !void {
        var live = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        defer live.deinit();
        for (dependencies) |dependency|
            if (state.tracker.isAlive(dependency)) try appendOwnedRoot(&live, dependency);
        try self.mergeOpaqueStorage(state, storage, live.items);
    }

    fn instantiateOpaqueDependencies(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
        hidden: *std.array_list.Managed(facts.ValidityRootId),
    ) !void {
        for (effect.fresh_dependencies) |source|
            try appendOwnedRoot(hidden, try self.instantiateFreshRoot(source, state, fresh_roots));
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            var target = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| target = try self.projectedPlace(target, projection);
            try appendOwnedRoot(hidden, try self.storageGenerationForPlace(target, state));
        }
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            const input = projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
            try self.collectOpaqueHiddenDependencies(state, input, hidden);
        }
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            const input = try self.instantiateInputPlaceValue(path, arguments, state);
            try self.collectOpaqueHiddenDependencies(state, input, hidden);
        }
        for (effect.opaque_generation_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            const input = projectValueFacts(arguments[path.input_index], path.projections);
            var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
            defer provenances.deinit();
            try self.collectOpaqueProvenancesRecursively(state, input, &provenances);
            for (provenances.items) |provenance| try appendOwnedRoot(hidden, provenance.generation);
        }
        for (effect.opaque_storage_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            var storage = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| storage = try self.projectedPlace(storage, projection);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency|
                    if (!self.opaqueDependencyIsInternalToStorage(state, storage, dependency))
                        try appendOwnedRoot(hidden, dependency);
            }
        }
        for (effect.fields) |field|
            try self.instantiateOpaqueDependencies(field.value.*, arguments, state, fresh_roots, hidden);
        for (effect.variants) |variant|
            try self.instantiateOpaqueDependencies(variant.value.*, arguments, state, fresh_roots, hidden);
    }

    fn evaluateVirtualCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.VirtualCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var candidate = try state.clone(self.allocator.*);
        defer candidate.deinit();
        const diagnostic_count = self.diagnostics.list.items.len;
        const result = try self.evaluateVirtualCallCandidate(function, call, &candidate);
        if (self.diagnostics.list.items.len != diagnostic_count) return .{};
        const previous = state.*;
        state.* = candidate;
        candidate = previous;
        return result;
    }

    fn evaluateVirtualCallCandidate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.VirtualCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        if (call.input.content != .struct_value_literal) return .{};
        const arguments = call.input.content.struct_value_literal.fields;
        const argument_values = try self.allocator.alloc(facts.ValueFacts, arguments.len);
        for (arguments, 0..) |argument, index| argument_values[index] = try self.evaluate(function, argument.value, state);
        // A virtual receiver is a pointer value stored in the Virtual wrapper.
        // Safety summaries describe the concrete Self Place behind that value,
        // not the wrapper binding used to issue the dispatch.
        const self_input_index: usize = call.self_input_index;
        if (self_input_index < argument_values.len) {
            if (argument_values[self_input_index].referenced_place) |wrapper| {
                if (self.valueAtPlace(state, wrapper)) |concrete| {
                    if (concrete.referenced_place != null) argument_values[self_input_index] = concrete;
                }
            }
        }
        const summary = try self.virtualSummary(call.safety_methods) orelse {
            if (self.invalid_virtual_summaries.contains(call.safety_methods))
                try self.diagnostics.add(call.input.location, .semantic, "virtual method '{s}' has incompatible safety effects across implementations", .{call.method_name});
            return .{};
        };
        if (!try self.validateRequiredLiveInputs(function, summary, argument_values, state)) return .{};
        for (summary.input_post_states) |post_state| {
            const index = post_state.target.input_index;
            if ((post_state.initializedness != .deinitialized and post_state.initializedness != .moved) or
                post_state.target.projections.len != 0 or index >= arguments.len) continue;
            if (arguments[index].value.content == .address_of and rootBinding(arguments[index].value.content.address_of) != null) {
                @constCast(call).consumes_auto_deinit = arguments[index].value.content.address_of;
            }
        }
        try self.applySafetySummaryEffects(function, summary, arguments, argument_values, state);
        if (summary.outputs.len != 1) return .{};
        return self.instantiateOutput(summary.outputs[0], argument_values, state);
    }

    fn evaluateVirtualize(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        virtualize: *const sg.Virtualize,
        state: *FunctionState,
    ) !facts.ValueFacts {
        for (virtualize.safety_methods) |registry| {
            _ = try self.virtualSummary(registry);
            if (self.invalid_virtual_summaries.contains(registry)) {
                try self.diagnostics.add(
                    virtualize.location,
                    .semantic,
                    "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
                    .{},
                );
                break;
            }
        }
        return self.evaluate(function, virtualize.value, state);
    }

    fn validateRequiredLiveInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.SafetySummary,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !bool {
        for (summary.required_live_inputs) |path| {
            if (path.input_index >= arguments.len) continue;
            var value = arguments[path.input_index];
            if (path.projections.len != 0) {
                if (value.referenced_place) |argument_place| {
                    var target = argument_place;
                    for (path.projections) |projection| target = try self.projectedPlace(target, projection);
                    value = self.valueAtPlace(state, target) orelse projectValueFacts(value, path.projections);
                } else value = projectValueFacts(value, path.projections);
            }
            if (!try self.validateLiveValueUse(function, value, state)) return false;
        }
        return true;
    }

    fn applyInputEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.SafetySummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator.*);
        defer fresh_roots.deinit();
        var fresh_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator.*);
        defer fresh_capabilities.deinit();
        // A relocation summary is only valid when its two Places remain
        // distinct at the caller. Check this before applying either side so
        // an invalid call cannot partially move its source.
        for (summary.input_post_states) |destination_state| {
            if (!destination_state.requires_available_destination) continue;
            const destination = try self.inputEffectTarget(destination_state, arguments, argument_values, state) orelse continue;
            for (summary.input_post_states) |source_state| {
                if (source_state.initializedness != .moved) continue;
                const source = try self.inputEffectTarget(source_state, arguments, argument_values, state) orelse continue;
                if (source.eql(destination)) {
                    try self.diagnostics.add(function.location, .semantic, "relocate requires distinct source and destination places", .{});
                    return;
                }
            }
            if (!try self.prepareRelocationDestination(function, state, destination)) return;
        }
        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            if (post_state.opaque_ownership == .none and post_state.initializedness == .initialized and
                post_state.may_repopulate_opaque_storage)
            {
                var opaque_storages = std.array_list.Managed(place.Place).init(self.allocator.*);
                defer opaque_storages.deinit();
                try self.collectOpaqueDomainsAccessedBy(state, argument_values[post_state.target.input_index], &opaque_storages);
                if (opaque_storages.items.len != 0) {
                    var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                    defer hidden.deinit();
                    try self.instantiateOpaqueDependencies(post_state.value, argument_values, state, &fresh_roots, &hidden);
                    for (opaque_storages.items) |storage|
                        try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
                }
            }
            if (post_state.opaque_ownership == .ambiguous) {
                try self.diagnostics.add(function.location, .semantic, "opaque ownership consumption has no single representable storage", .{});
                continue;
            }
            if (post_state.opaque_ownership == .definite or post_state.opaque_ownership == .conditional) {
                const source = try self.inputEffectTarget(post_state, arguments, argument_values, state);
                const argument_value = projectValueFacts(argument_values[post_state.target.input_index], post_state.target.projections);
                const value = if (source) |target|
                    if (self.initializednessAtPlace(state, target) == .initialized)
                        self.valueAtPlace(state, target) orelse argument_value
                    else
                        argument_value
                else
                    argument_value;
                const opaque_path = post_state.opaque_storage orelse {
                    if (hasExternalOpaqueDependency(value, value.owned_roots))
                        try self.diagnostics.add(function.location, .semantic, "opaque ownership storage cannot hide dependencies on external roots", .{});
                    try self.closeOpaqueOwnedRoots(function, value, state, source);
                    if (source) |target| try self.setPlace(state, target, .moved, .{});
                    continue;
                };
                if (opaque_path.input_index >= arguments.len) continue;
                var storage = argument_values[opaque_path.input_index].referenced_place orelse
                    try self.resolvePlace(arguments[opaque_path.input_index].value, state) orelse continue;
                for (opaque_path.projections) |projection| storage = try self.projectedPlace(storage, projection);
                // Match the primitive boundary: consuming the old ownership
                // is validated before the destination storage starts hiding
                // the transferred value's dependencies.
                try self.closeOpaqueOwnedRoots(function, value, state, source);
                if (source) |target| try self.setPlace(state, target, .moved, .{});
                try self.hideOpaqueDependencies(state, storage, value);
                continue;
            }
            const index = post_state.target.input_index;
            if (argument_values[index].referenced_place == null) {
                if (post_state.ends_previous_roots and post_state.target.projections.len == 0) {
                    for (argument_values[index].dependencies) |dependency| {
                        _ = try self.endRoot(function, state, dependency.root);
                    }
                }
                continue;
            }
            const target = try self.inputEffectTarget(post_state, arguments, argument_values, state) orelse continue;
            // A callee only describes its resulting Place state. The caller
            // decides whether that state begins a new storage generation.
            const reinitializes_dead_place = post_state.initializedness == .initialized and
                (if (self.getPlace(state, target)) |target_facts|
                    target_facts.initializedness == .deinitialized
                else
                    false);
            const previous_value = self.valueAtPlace(state, target);
            if (post_state.ends_previous_roots) {
                if (previous_value) |old| {
                    for (old.owned_roots) |root| _ = try self.endRoot(function, state, root);
                }
            }
            if (post_state.initializedness == .deinitialized) try self.endStorageGenerationsUnder(function, state, target);
            if (!post_state.requires_available_destination and (reinitializes_dead_place or post_state.refreshes_storage_generation)) {
                const pointer_storage = try self.resolvePlace(arguments[index].value, state);
                _ = try self.refreshStorageGenerationThroughPointer(
                    function,
                    state,
                    target,
                    pointer_storage,
                    argument_values[index],
                );
            }
            var value = if (post_state.initializedness == .initialized)
                try self.instantiateOutputWithFresh(post_state.value, argument_values, state, &fresh_roots, &fresh_capabilities)
            else
                facts.ValueFacts{};
            if (previous_value) |old|
                value = try self.collapseReplacedOwnedRoots(value, old, state);
            try self.setPlace(state, target, post_state.initializedness, value);
        }
    }

    /// A conditional replacement summary contains both the input generation
    /// and the fresh generation. Once the old generation has conservatively
    /// ended, the fresh identity is the caller-visible phi for the current
    /// owned resource. Rewriting only the target value preserves historical
    /// aliases to the ended generation.
    fn collapseReplacedOwnedRoots(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        previous: facts.ValueFacts,
        state: *const FunctionState,
    ) !facts.ValueFacts {
        var result = value;
        var old_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        defer old_roots.deinit();
        for (previous.owned_roots) |root| {
            const index = @intFromEnum(root);
            if (valueContainsOwnedRoot(value, root) and index < state.tracker.roots.items.len and !state.tracker.isAlive(root))
                try appendOwnedRoot(&old_roots, root);
        }
        var replacements = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        defer replacements.deinit();
        for (value.owned_roots) |root| {
            if (containsRoot(old_roots.items, root)) continue;
            const index = @intFromEnum(root);
            if (index < state.tracker.roots.items.len and state.tracker.isAlive(root))
                try appendOwnedRoot(&replacements, root);
        }
        if (old_roots.items.len != 0 and replacements.items.len == 1)
            result = try self.replaceValueRoots(result, old_roots.items, replacements.items[0]);

        if (result.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, result.fields.len);
            for (result.fields, 0..) |field, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                const old_field = findField(previous.fields, field.index);
                stored.* = if (old_field) |prior|
                    try self.collapseReplacedOwnedRoots(field.value.*, prior.value.*, state)
                else
                    field.value.*;
                fields[index] = .{ .index = field.index, .value = stored };
            }
            result.fields = fields;
        }
        if (result.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, result.variants.len);
            for (result.variants, 0..) |variant, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                const old_variant = findVariant(previous.variants, variant.index);
                stored.* = if (old_variant) |prior|
                    try self.collapseReplacedOwnedRoots(variant.value.*, prior.value.*, state)
                else
                    variant.value.*;
                variants[index] = .{ .index = variant.index, .value = stored };
            }
            result.variants = variants;
        }
        return result;
    }

    fn inputEffectTarget(
        self: *SafetyChecker,
        post_state: facts.PlacePostState,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?place.Place {
        const index = post_state.target.input_index;
        if (index >= arguments.len) return null;
        var target = argument_values[index].referenced_place orelse try self.resolvePlace(arguments[index].value, state) orelse return null;
        for (post_state.target.projections) |projection|
            target = try self.projectedPlace(target, projection);
        return target;
    }

    fn refreshStorageGenerationThroughPointer(
        self: *SafetyChecker,
        function: ?*const sg.FunctionDeclaration,
        state: *FunctionState,
        target: place.Place,
        pointer_storage: ?place.Place,
        pointer: facts.ValueFacts,
    ) !facts.ValueFacts {
        const old_root = try self.storageGenerationForPlace(target, state);
        try self.refreshStorageGeneration(function, state, target);
        const fresh_root = try self.storageGenerationForPlace(target, state);
        const storage = pointer_storage orelse return pointer;
        if (storage.eql(target)) return pointer;

        var refreshed = pointer;
        const dependencies = try self.allocator.alloc(facts.ValidityDependency, pointer.dependencies.len);
        var retargeted = false;
        for (pointer.dependencies, 0..) |dependency, index| {
            dependencies[index] = .{ .root = if (dependency.root == old_root) blk: {
                retargeted = true;
                break :blk fresh_root;
            } else dependency.root };
        }
        if (!retargeted) return pointer;
        refreshed.dependencies = dependencies;
        // The precise pointer used as the reinitialization capability follows
        // the new generation. Other aliases retain the ended generation.
        try self.setPlace(state, storage, .initialized, refreshed);
        return refreshed;
    }

    /// Relocation receives storage; it never destroys the representation that
    /// happens to be there. A deinitialized Place starts a new structural
    /// generation, while a moved Place follows ordinary Place reuse rules.
    fn prepareRelocationDestination(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
        destination: place.Place,
    ) !bool {
        switch (self.initializednessAtPlace(state, destination)) {
            .initialized => {
                try self.diagnostics.add(function.location, .semantic, "relocate destination is initialized", .{});
                return false;
            },
            .maybe_initialized => {
                try self.diagnostics.add(function.location, .semantic, "relocate destination may be initialized", .{});
                return false;
            },
            .deinitialized => try self.refreshStorageGeneration(function, state, destination),
            .moved => {},
        }
        return true;
    }

    fn instantiateOutput(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator.*);
        defer fresh_roots.deinit();
        var fresh_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator.*);
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
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        for (effect.fresh_dependencies) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            try appendDependency(&dependencies, .{ .root = root });
        }
        for (effect.opaque_generation_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            const input = projectValueFacts(arguments[path.input_index], path.projections);
            var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
            defer provenances.deinit();
            try self.collectOpaqueProvenancesRecursively(state, input, &provenances);
            for (provenances.items) |provenance| try appendDependency(&dependencies, .{ .root = provenance.generation });
        }
        for (effect.opaque_storage_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            var storage = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| storage = try self.projectedPlace(storage, projection);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency|
                    if (!self.opaqueDependencyIsInternalToStorage(state, storage, dependency))
                        try appendDependency(&dependencies, .{ .root = dependency });
            }
        }
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        for (effect.fresh_owned_roots) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
            try appendOwnedRoot(&owned_roots, root);
        }
        result.owned_roots = try owned_roots.toOwnedSlice();
        var capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator.*);
        for (effect.fresh_storage_capabilities) |source|
            try appendStorageCapability(&capabilities, try self.instantiateFreshStorageCapability(source, state, fresh_capabilities));
        result.storage_capabilities = try capabilities.toOwnedSlice();
        // `input_places` names the provenance of the output. Apply it after
        // dependencies: an effect may intentionally combine a reference with
        // unrelated lifetime dependencies without changing where it points.
        var referenced_place: ?place.Place = null;
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            if (arguments[path.input_index].referenced_place) |argument_place| {
                var target = argument_place;
                for (path.projections) |projection| target = try self.projectedPlace(target, projection);
                try appendDependency(&dependencies, .{ .root = try self.storageGenerationForPlace(target, state) });
                referenced_place = target;
            }
        }
        result.dependencies = try dependencies.toOwnedSlice();
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            var input = arguments[dependency.path.input_index];
            input = projectValueFacts(input, dependency.path.projections);
            if (!dependency.transfers_ownership) input.owned_roots = &.{};
            result = try self.mergeValueFacts(result, input);
        }
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            const input = try self.instantiateInputPlaceValue(path, arguments, state);
            result = try self.mergeValueFacts(result, input);
        }
        if (effect.fields.len != 0) {
            const enclosing_variants = result.variants;
            const fields = try self.allocator.alloc(facts.FieldFacts, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(field.value.*, arguments, state, fresh_roots, fresh_capabilities);
                fields[index] = .{ .index = field.index, .value = value };
                result = try self.mergeValueFacts(result, value.*);
            }
            result.fields = fields;
            result.variants = enclosing_variants;
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

    fn instantiateInputPlaceValue(
        self: *SafetyChecker,
        path: facts.InputPath,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        const input = arguments[path.input_index];
        if (input.referenced_place) |argument_place| {
            var target = argument_place;
            for (path.projections) |projection| target = try self.projectedPlace(target, projection);
            return self.valueAtPlace(state, target) orelse projectValueFacts(input, path.projections);
        }
        // Some symbolic callers cannot name a concrete pointee Place. Their
        // argument facts are the only conservative value approximation
        // available; no synthetic storage identity is introduced here.
        return projectValueFacts(input, path.projections);
    }

    fn collectOpaqueProvenancesRecursively(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        provenance: *std.array_list.Managed(facts.OpaqueProvenance),
    ) !void {
        try self.collectOpaqueProvenancesCarriedBy(state, value, provenance);
        for (value.fields) |field| try self.collectOpaqueProvenancesRecursively(state, field.value.*, provenance);
        for (value.variants) |variant| try self.collectOpaqueProvenancesRecursively(state, variant.value.*, provenance);
    }

    fn activateChoiceVariant(self: *SafetyChecker, choice: facts.ValueFacts, variant_index: u32, state: *FunctionState) void {
        _ = self;
        for (choice.variants) |variant| {
            if (variant.index == variant_index)
                activateConditionalFacts(variant.value.*, state)
            else
                rejectConditionalFacts(variant.value.*, state);
        }
    }

    fn refineChoiceTest(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        tag_test: sg.ChoiceTagTest,
        state: *FunctionState,
        has_variant: bool,
    ) !void {
        const choice = try self.evaluate(function, tag_test.choice_value, state);
        try self.refineChoiceVariant(
            try self.resolvePlace(tag_test.choice_value, state),
            tag_test.choice_value,
            choice,
            tag_test.choice_type.variants.len,
            tag_test.variant_index,
            has_variant,
            state,
        );
    }

    fn choiceTagTestFromCondition(self: *SafetyChecker, condition: *const sg.SGNode) ?sg.ChoiceTagTest {
        _ = self;
        const comparison = switch (condition.content) {
            .comparison => |value| value,
            else => return null,
        };
        const then_has_variant = switch (comparison.operator) {
            .equal => true,
            .not_equal => false,
            else => return null,
        };
        const left_literal = switch (comparison.left.content) {
            .choice_literal => |value| value,
            else => null,
        };
        const right_literal = switch (comparison.right.content) {
            .choice_literal => |value| value,
            else => null,
        };
        const choice_value = if (left_literal != null)
            comparison.right
        else if (right_literal != null)
            comparison.left
        else
            return null;
        const literal = left_literal orelse right_literal.?;
        if (literal.payload != null or choice_value.sem_type == null or choice_value.sem_type.? != .choice_type) return null;
        return .{
            .choice_value = choice_value,
            .choice_type = choice_value.sem_type.?.choice_type,
            .variant_index = literal.variant_index,
            .then_has_variant = then_has_variant,
        };
    }

    fn refineChoiceVariant(
        self: *SafetyChecker,
        storage: ?place.Place,
        expression: ?*const sg.SGNode,
        choice: facts.ValueFacts,
        variant_count: ?usize,
        variant_index: u32,
        has_variant: bool,
        state: *FunctionState,
    ) !void {
        if (has_variant) {
            self.activateChoiceVariant(choice, variant_index, state);
            if (storage) |target|
                try self.setChoiceActive(state, target, variant_index)
            else if (expression) |temporary|
                try self.setChoiceTemporaryActive(state, temporary, variant_index);
            return;
        }

        for (choice.variants) |variant| if (variant.index == variant_index) {
            rejectConditionalFacts(variant.value.*, state);
            break;
        };
        const target = storage orelse return;
        try self.setChoiceRejected(state, target, variant_index);
        const count = variant_count orelse return;
        var remaining: ?u32 = null;
        for (0..count) |index| {
            const candidate: u32 = @intCast(index);
            if (self.choiceVariantIsRejected(state, target, candidate)) continue;
            if (remaining != null) return;
            remaining = candidate;
        }
        if (remaining) |active| {
            self.activateChoiceVariant(choice, active, state);
            try self.setChoiceActive(state, target, active);
        }
    }

    fn setChoiceActive(self: *SafetyChecker, state: *FunctionState, storage: place.Place, variant_index: u32) !void {
        _ = self;
        var index: usize = 0;
        while (index < state.choice_active.items.len) {
            if (state.choice_active.items[index].storage.eql(storage)) {
                _ = state.choice_active.orderedRemove(index);
            } else index += 1;
        }
        try state.choice_active.append(.{ .storage = storage, .variant_index = variant_index });
    }

    fn setChoiceTemporaryActive(self: *SafetyChecker, state: *FunctionState, expression: *const sg.SGNode, variant_index: u32) !void {
        _ = self;
        for (state.choice_temporary_active.items) |*active| {
            if (active.expression != expression) continue;
            active.variant_index = variant_index;
            return;
        }
        try state.choice_temporary_active.append(.{ .expression = expression, .variant_index = variant_index });
    }

    fn setChoiceRejected(self: *SafetyChecker, state: *FunctionState, storage: place.Place, variant_index: u32) !void {
        if (self.choiceVariantIsRejected(state, storage, variant_index)) return;
        try state.choice_rejected.append(.{ .storage = storage, .variant_index = variant_index });
    }

    fn choiceVariantIsActive(self: *SafetyChecker, state: *const FunctionState, storage: place.Place, variant_index: u32) bool {
        return if (self.activeChoiceVariant(state, storage)) |active| active == variant_index else false;
    }

    fn activeChoiceVariant(self: *SafetyChecker, state: *const FunctionState, storage: place.Place) ?u32 {
        _ = self;
        for (state.choice_active.items) |active|
            if (active.storage.eql(storage)) return active.variant_index;
        return null;
    }

    fn choiceTemporaryVariantIsActive(self: *SafetyChecker, state: *const FunctionState, expression: *const sg.SGNode, variant_index: u32) bool {
        _ = self;
        for (state.choice_temporary_active.items) |active|
            if (active.expression == expression) return active.variant_index == variant_index;
        return false;
    }

    fn choiceVariantIsRejected(self: *SafetyChecker, state: *const FunctionState, storage: place.Place, variant_index: u32) bool {
        _ = self;
        for (state.choice_rejected.items) |rejected|
            if (rejected.storage.eql(storage) and rejected.variant_index == variant_index) return true;
        return false;
    }

    fn instantiateFreshStorageCapability(self: *SafetyChecker, source: facts.FreshEffectSource, state: *FunctionState, fresh: *std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId)) !facts.StorageCapabilityId {
        _ = self;
        if (fresh.get(source)) |capability| return capability;
        const capability: facts.StorageCapabilityId = @enumFromInt(state.storage_capabilities.items.len);
        try state.storage_capabilities.append(.available);
        try fresh.put(source, capability);
        return capability;
    }

    fn instantiateFreshRoot(
        self: *SafetyChecker,
        source: facts.FreshEffectSource,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
    ) !facts.ValidityRootId {
        _ = self;
        if (fresh_roots.get(source)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try fresh_roots.put(source, root);
        return root;
    }

    fn mergeValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        for (left.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        for (right.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        for (left.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        for (right.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        var capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator.*);
        for (left.storage_capabilities) |capability| try appendStorageCapability(&capabilities, capability);
        for (right.storage_capabilities) |capability| try appendStorageCapability(&capabilities, capability);
        var opaque_provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        for (left.opaque_provenance) |provenance| try appendOpaqueProvenance(&opaque_provenances, provenance);
        for (right.opaque_provenance) |provenance| try appendOpaqueProvenance(&opaque_provenances, provenance);
        var fields = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
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
        var variants = std.array_list.Managed(facts.VariantFacts).init(self.allocator.*);
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
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .variants = try variants.toOwnedSlice(),
            .known_choice_variant = if (left.known_choice_variant != null and left.known_choice_variant == right.known_choice_variant)
                left.known_choice_variant
            else
                null,
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .storage_capabilities = try capabilities.toOwnedSlice(),
            .referenced_place = if (left.referenced_place != null and right.referenced_place != null and left.referenced_place.?.eql(right.referenced_place.?))
                left.referenced_place
            else
                null,
            .opaque_provenance = try opaque_provenances.toOwnedSlice(),
        };
    }

    /// Dependencies and cleanup obligations both widen at an ordinary join.
    /// Initializedness handles a value that exists on only some paths. When an
    /// initialized value instead owns different current generations on two
    /// loop paths, validateLoop subsequently folds those alternatives into a
    /// stable root phi; unioning them here alone would make both roots merely
    /// maybe-alive and incorrectly reject the owner.
    fn joinValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var result = try self.mergeValueFacts(left, right);

        const fields = try self.allocator.alloc(facts.FieldFacts, result.fields.len);
        for (result.fields, 0..) |field, index| {
            const stored = try self.allocator.create(facts.ValueFacts);
            const left_field = findField(left.fields, field.index);
            const right_field = findField(right.fields, field.index);
            if (left_field != null and right_field != null) {
                stored.* = try self.joinValueFacts(left_field.?.value.*, right_field.?.value.*);
            } else {
                stored.* = field.value.*;
            }
            fields[index] = .{ .index = field.index, .value = stored };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.VariantFacts, result.variants.len);
        for (result.variants, 0..) |variant, index| {
            const stored = try self.allocator.create(facts.ValueFacts);
            const left_variant = findVariant(left.variants, variant.index);
            const right_variant = findVariant(right.variants, variant.index);
            stored.* = if (left_variant != null and right_variant != null)
                try self.joinValueFacts(left_variant.?.value.*, right_variant.?.value.*)
            else
                variant.value.*;
            variants[index] = .{ .index = variant.index, .value = stored };
        }
        result.variants = variants;
        return result;
    }

    fn copyState(self: *SafetyChecker, destination: *FunctionState, source: *const FunctionState) !void {
        const replacement = try source.clone(self.allocator.*);
        destination.deinit();
        destination.* = replacement;
    }

    fn joinStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        destination: *FunctionState,
        left: *const FunctionState,
        right: *const FunctionState,
    ) !void {
        _ = function;
        if (!left.reachable) return self.copyState(destination, right);
        if (!right.reachable) return self.copyState(destination, left);
        var joined = FunctionState.init(self.allocator.*);
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
            const root_state: @TypeOf(left_state) = if (left_state == right_state)
                left_state
            else
                .maybe_alive;
            const left_owned = index < left.tracker.roots.items.len and left.tracker.roots.items[index].owned_resource;
            const right_owned = index < right.tracker.roots.items.len and right.tracker.roots.items[index].owned_resource;
            try joined.tracker.roots.append(.{ .id = id, .state = root_state, .owned_resource = left_owned or right_owned });
        }
        const capability_count = @max(left.storage_capabilities.items.len, right.storage_capabilities.items.len);
        for (0..capability_count) |index| {
            const left_state: FunctionState.StorageCapabilityState = if (index < left.storage_capabilities.items.len) left.storage_capabilities.items[index] else .consumed;
            const right_state: FunctionState.StorageCapabilityState = if (index < right.storage_capabilities.items.len) right.storage_capabilities.items[index] else .consumed;
            try joined.storage_capabilities.append(if (left_state == right_state) left_state else .maybe_consumed);
        }
        for (left.places.items) |left_place| {
            var merged = left_place;
            if (findPlace(right.places.items, left_place.storage)) |right_place| {
                merged.initializedness = joinInitializedness(left_place.initializedness, right_place.initializedness);
                merged.value = try self.joinValueFacts(left_place.value, right_place.value);
            }
            try joined.places.append(merged);
        }
        for (right.places.items) |right_place| {
            if (findPlace(left.places.items, right_place.storage) == null) try joined.places.append(right_place);
        }
        for (left.ownership_edges.items) |edge| try appendOwnershipEdge(&joined.ownership_edges, edge);
        for (right.ownership_edges.items) |edge| try appendOwnershipEdge(&joined.ownership_edges, edge);
        try joined.storage_generations.appendSlice(left.storage_generations.items);
        for (right.storage_generations.items) |candidate| {
            var found = false;
            for (joined.storage_generations.items) |existing| if (existing.storage.eql(candidate.storage)) {
                found = true;
                break;
            };
            if (!found) try joined.storage_generations.append(candidate);
        }
        for (left.lexical_storage_generations.items) |root| try appendOwnedRoot(&joined.lexical_storage_generations, root);
        for (right.lexical_storage_generations.items) |root| try appendOwnedRoot(&joined.lexical_storage_generations, root);
        for (left.opaque_storages.items) |opaque_storage| try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);
        for (right.opaque_storages.items) |opaque_storage| try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);
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
        joined.ownership_conflict_reported = left.ownership_conflict_reported or right.ownership_conflict_reported;
        destination.deinit();
        destination.* = joined;
    }

    /// Storage Generations are compiler facts created lazily when a Place first has
    /// its address taken. If only one branch needed that fact, the other branch
    /// still preserves the same generation when the Place existed there.
    fn storageGenerationWasOnlyMaterializedIn(
        self: *SafetyChecker,
        root: facts.ValidityRootId,
        materialized: *const FunctionState,
        other: *const FunctionState,
    ) bool {
        _ = self;
        var storage: ?place.Place = null;
        for (materialized.storage_generations.items) |entry| if (entry.generation == root) {
            storage = entry.storage;
            break;
        };
        const target = storage orelse return false;
        for (other.storage_generations.items) |entry| if (entry.storage.eql(target)) return false;

        var projection_count = target.projections.len;
        while (true) {
            const prefix = place.Place{ .root = target.root, .projections = target.projections[0..projection_count] };
            if (findPlace(other.places.items, prefix)) |stored|
                return stored.initializedness == .initialized;
            if (projection_count == 0) return false;
            projection_count -= 1;
        }
    }

    fn validateLoop(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        body: *const sg.CodeBlock,
        state: *FunctionState,
        increment: ?*const sg.SGNode,
    ) !void {
        // Structural storage exists before control enters the loop. Materialize
        // its roots before cloning the entry state so lazy first address-taking
        // inside the body cannot look like a conditionally created lifetime at
        // the CFG join.
        const existing_places = try self.allocator.dupe(facts.PlaceFacts, state.places.items);
        for (existing_places) |place_facts| _ = try self.storageGenerationForPlace(place_facts.storage, state);
        var entry = try state.clone(self.allocator.*);
        defer entry.deinit();
        var current = try state.clone(self.allocator.*);
        defer current.deinit();
        var last_break: ?FunctionState = null;
        defer if (last_break) |*break_state| break_state.deinit();
        var join_context = LoopJoinContext.init(self.allocator.*);
        defer join_context.deinit();
        for (0..8) |_| {
            var iteration = try current.clone(self.allocator.*);
            defer iteration.deinit();
            var transfers: LoopTransfers = .{};
            defer transfers.deinit();
            try self.validateBlock(function, body, &iteration, &transfers);
            if (transfers.continue_state) |*continue_state|
                try self.mergeLoopTransfer(function, &iteration, continue_state);
            if (iteration.reachable) {
                if (increment) |node| _ = try self.evaluate(function, node, &iteration);
            }
            if (last_break) |*break_state| break_state.deinit();
            last_break = if (transfers.break_state) |*break_state| try break_state.clone(self.allocator.*) else null;
            var next = try entry.clone(self.allocator.*);
            try self.joinStates(function, &next, &entry, &iteration);
            try self.widenLoopOwnedRoots(&join_context, &next, &entry, &iteration);
            if (statesEqual(&current, &next)) {
                if (last_break) |*break_state| try self.mergeLoopTransfer(function, &next, break_state);
                try self.copyState(state, &next);
                next.deinit();
                return;
            }
            current.deinit();
            current = next;
        }
        if (last_break) |*break_state| try self.mergeLoopTransfer(function, &current, break_state);
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
            var left_only = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            defer left_only.deinit();
            for (left_value.owned_roots) |root|
                if ((existing_phi == null or root != existing_phi.?) and !containsRoot(right_value.owned_roots, root)) try appendOwnedRoot(&left_only, root);
            var right_only = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            defer right_only.deinit();
            for (right_value.owned_roots) |root|
                if ((existing_phi == null or root != existing_phi.?) and !containsRoot(left_value.owned_roots, root)) try appendOwnedRoot(&right_only, root);
            for (left_value.owned_roots) |root| {
                if (existing_phi != null and root == existing_phi.?) continue;
                if (!containsRoot(right_value.owned_roots, root)) continue;
                const index = @intFromEnum(root);
                const left_alive = index < left.tracker.roots.items.len and left.tracker.isAlive(root);
                const right_alive = index < right.tracker.roots.items.len and right.tracker.isAlive(root);
                if (left_alive and !right_alive) try appendOwnedRoot(&left_only, root);
                if (right_alive and !left_alive) try appendOwnedRoot(&right_only, root);
            }
            var stale_alternative: ?facts.ValidityRootId = null;
            if (left_only.items.len == 0 and right_only.items.len == 1) {
                for (right_value.owned_roots) |root| {
                    if (!containsRoot(left_value.owned_roots, root)) continue;
                    const index = @intFromEnum(root);
                    const left_alive = index < left.tracker.roots.items.len and left.tracker.isAlive(root);
                    const right_alive = index < right.tracker.roots.items.len and right.tracker.isAlive(root);
                    if (left_alive or right_alive) continue;
                    try appendOwnedRoot(&left_only, root);
                    stale_alternative = root;
                    break;
                }
                var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                defer left_dependencies.deinit();
                try collectDependencyRoots(left_value, &left_dependencies);
                for (left_dependencies.items) |root| {
                    if (stale_alternative != null) break;
                    const index = @intFromEnum(root);
                    if (!valueDependsOnRoot(right_value, root) or containsRoot(left_value.owned_roots, root) or
                        containsRoot(right_value.owned_roots, root) or index >= left.tracker.roots.items.len or
                        index >= right.tracker.roots.items.len or !left.tracker.roots.items[index].owned_resource or
                        !left.tracker.isAlive(root) or right.tracker.isAlive(root)) continue;
                    try appendOwnedRoot(&left_only, root);
                    stale_alternative = root;
                    break;
                }
                if (stale_alternative == null) {
                    var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                    defer right_dependencies.deinit();
                    try collectDependencyRoots(right_value, &right_dependencies);
                    for (right_dependencies.items) |root| {
                        const index = @intFromEnum(root);
                        if (valueDependsOnRoot(left_value, root) or containsRoot(right_value.owned_roots, root) or
                            index >= right.tracker.roots.items.len or !right.tracker.roots.items[index].owned_resource or
                            right.tracker.isAlive(root)) continue;
                        try appendOwnedRoot(&left_only, root);
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
                    try appendOwnedRoot(&right_only, root);
                    stale_alternative = root;
                    break;
                }
                var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                defer right_dependencies.deinit();
                try collectDependencyRoots(right_value, &right_dependencies);
                for (right_dependencies.items) |root| {
                    if (stale_alternative != null) break;
                    const index = @intFromEnum(root);
                    if (!valueDependsOnRoot(left_value, root) or containsRoot(left_value.owned_roots, root) or
                        containsRoot(right_value.owned_roots, root) or index >= left.tracker.roots.items.len or
                        index >= right.tracker.roots.items.len or !right.tracker.roots.items[index].owned_resource or
                        !right.tracker.isAlive(root) or left.tracker.isAlive(root)) continue;
                    try appendOwnedRoot(&right_only, root);
                    stale_alternative = root;
                    break;
                }
                if (stale_alternative == null) {
                    var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                    defer left_dependencies.deinit();
                    try collectDependencyRoots(left_value, &left_dependencies);
                    for (left_dependencies.items) |root| {
                        const index = @intFromEnum(root);
                        if (valueDependsOnRoot(right_value, root) or containsRoot(left_value.owned_roots, root) or
                            index >= left.tracker.roots.items.len or !left.tracker.roots.items[index].owned_resource or
                            left.tracker.isAlive(root)) continue;
                        try appendOwnedRoot(&right_only, root);
                        stale_alternative = root;
                        break;
                    }
                }
            }
            if (left_only.items.len == 0 and right_only.items.len == 0) {
                var left_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                defer left_dependencies.deinit();
                try collectDependencyRoots(left_value, &left_dependencies);
                var right_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
                defer right_dependencies.deinit();
                try collectDependencyRoots(right_value, &right_dependencies);
                for (left_dependencies.items) |root| {
                    const index = @intFromEnum(root);
                    if ((existing_phi == null or root != existing_phi.?) and
                        !containsRoot(right_dependencies.items, root) and index < left.tracker.roots.items.len and
                        left.tracker.roots.items[index].owned_resource and left.tracker.isAlive(root))
                        try appendOwnedRoot(&left_only, root);
                }
                for (right_dependencies.items) |root| {
                    const index = @intFromEnum(root);
                    if ((existing_phi == null or root != existing_phi.?) and
                        !containsRoot(left_dependencies.items, root) and index < right.tracker.roots.items.len and
                        right.tracker.roots.items[index].owned_resource and right.tracker.isAlive(root))
                        try appendOwnedRoot(&right_only, root);
                }
            }
            if (left_only.items.len == 0 and right_only.items.len == 0) continue;
            // Two roots on one side are one representable generation slot
            // only when a summary retained the ended predecessor alongside
            // its live replacement. Two simultaneous live roots still need
            // explicit slot correspondence and remain conservative.
            if (left_only.items.len + right_only.items.len > 2) continue;
            if (left_only.items.len > 1) {
                var alive: usize = 0;
                for (left_only.items) |root| if (left.tracker.isAlive(root)) {
                    alive += 1;
                };
                if (right_only.items.len != 0 or alive != 1) continue;
            }
            if (right_only.items.len > 1) {
                var alive: usize = 0;
                for (right_only.items) |root| if (right.tracker.isAlive(root)) {
                    alive += 1;
                };
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
            _ = state.tracker.roots.pop();
        }
        _ = self;
    }

    fn trimUnreferencedRoots(self: *SafetyChecker, state: *FunctionState) void {
        while (state.tracker.roots.items.len != 0) {
            const root: facts.ValidityRootId = @enumFromInt(state.tracker.roots.items.len - 1);
            if (rootIsStructurallyReferenced(state, root)) return;
            var lexical_index: usize = 0;
            while (lexical_index < state.lexical_storage_generations.items.len) {
                if (state.lexical_storage_generations.items[lexical_index] == root) {
                    _ = state.lexical_storage_generations.orderedRemove(lexical_index);
                } else lexical_index += 1;
            }
            _ = state.tracker.roots.pop();
        }
        _ = self;
    }

    fn loopPhiOwnerStorage(
        self: *SafetyChecker,
        state: *const FunctionState,
        fallback: place.Place,
        roots: []const facts.ValidityRootId,
    ) place.Place {
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
            const rewritten = FunctionState.OwnershipEdge{
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
        storage: place.Place,
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

    fn loopRootPhiForStorage(context: *const LoopJoinContext, storage: place.Place) ?facts.ValidityRootId {
        var result: ?LoopRootPhi = null;
        for (context.roots.items) |entry| {
            if (!entry.storage.isPrefixOf(storage)) continue;
            if (result == null or entry.storage.projections.len > result.?.storage.projections.len) result = entry;
        }
        return if (result) |entry| entry.root else null;
    }

    fn loopRootPhiStorage(context: *const LoopJoinContext, root: facts.ValidityRootId) ?place.Place {
        for (context.roots.items) |entry| if (entry.root == root) return entry.storage;
        return null;
    }

    fn replaceValueRoots(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        sources: []const facts.ValidityRootId,
        replacement: facts.ValidityRootId,
    ) !facts.ValueFacts {
        var result = value;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        for (value.dependencies) |dependency|
            try appendDependency(&dependencies, .{ .root = if (containsRoot(sources, dependency.root)) replacement else dependency.root });
        result.dependencies = try dependencies.toOwnedSlice();
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        for (value.owned_roots) |root|
            try appendOwnedRoot(&owned_roots, if (containsRoot(sources, root)) replacement else root);
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

    fn mergeLoopTransfer(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        destination: anytype,
        source: *const FunctionState,
    ) !void {
        const Destination = @TypeOf(destination.*);
        if (comptime Destination == ?FunctionState) {
            if (destination.*) |*current| {
                var joined = try current.clone(self.allocator.*);
                try self.joinStates(function, &joined, current, source);
                current.deinit();
                current.* = joined;
            } else destination.* = try source.clone(self.allocator.*);
        } else {
            if (!destination.*.reachable) {
                try self.copyState(destination, source);
            } else {
                var joined = try destination.*.clone(self.allocator.*);
                try self.joinStates(function, &joined, destination, source);
                destination.deinit();
                destination.* = joined;
            }
        }
    }

    fn aggregate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var contains_integer_address = false;
        var contains_foreign_storage = false;
        var storage_capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator.*);
        for (fields, 0..) |field, index| {
            const value = try self.evaluate(function, field.value, state);
            try dependencies.appendSlice(value.dependencies);
            try owned_roots.appendSlice(value.owned_roots);
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = value;
            try field_facts.append(.{ .index = @intCast(index), .value = stored });
            contains_integer_address = contains_integer_address or value.integer_address;
            contains_foreign_storage = contains_foreign_storage or value.foreign_storage;
            for (value.storage_capabilities) |capability| try appendStorageCapability(&storage_capabilities, capability);
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try field_facts.toOwnedSlice(),
            .integer_address = contains_integer_address,
            .foreign_storage = contains_foreign_storage,
            .storage_capabilities = try storage_capabilities.toOwnedSlice(),
        };
    }

    fn evaluateStoredValue(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
        pointer: facts.ValueFacts,
    ) anyerror!facts.ValueFacts {
        var opaque_storages = std.array_list.Managed(place.Place).init(self.allocator.*);
        defer opaque_storages.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &opaque_storages);
        if (opaque_storages.items.len == 0) return self.evaluate(function, node, state);
        return self.evaluateOpaqueMutationValue(function, node, state);
    }

    fn evaluateOpaqueMutationValue(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        return switch (node.content) {
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.choiceValue(literal.variant_index, try self.evaluateOpaqueMutationValue(function, payload, state))
            else
                try self.choiceValue(literal.variant_index, .{}),
            .struct_value_literal => |literal| try self.aggregateOpaqueMutation(function, literal.fields, state),
            .list_literal => |literal| try self.aggregateOpaqueMutationElements(function, literal.elements, state),
            .array_literal => |literal| try self.aggregateOpaqueMutationElements(function, literal.elements, state),
            .explicit_cast => |cast| try self.evaluateOpaqueMutationValue(function, cast.value, state),
            else => try self.evaluate(function, node, state),
        };
    }

    fn aggregateOpaqueMutation(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        var owned_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var storage_capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator.*);
        var opaque_provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator.*);
        var contains_integer_address = false;
        var contains_foreign_storage = false;
        for (fields, 0..) |field, index| {
            const value = try self.evaluateOpaqueMutationValue(function, field.value, state);
            for (value.dependencies) |dependency| try appendDependency(&dependencies, dependency);
            for (value.owned_roots) |root| try appendOwnedRoot(&owned_roots, root);
            for (value.storage_capabilities) |capability| try appendStorageCapability(&storage_capabilities, capability);
            for (value.opaque_provenance) |provenance| try appendOpaqueProvenance(&opaque_provenances, provenance);
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = value;
            try field_facts.append(.{ .index = @intCast(index), .value = stored });
            contains_integer_address = contains_integer_address or value.integer_address;
            contains_foreign_storage = contains_foreign_storage or value.foreign_storage;
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try field_facts.toOwnedSlice(),
            .integer_address = contains_integer_address,
            .foreign_storage = contains_foreign_storage,
            .storage_capabilities = try storage_capabilities.toOwnedSlice(),
            .opaque_provenance = try opaque_provenances.toOwnedSlice(),
        };
    }

    fn aggregateOpaqueMutationElements(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        elements: []const *const sg.SGNode,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var result: facts.ValueFacts = .{};
        const fields = try self.allocator.alloc(facts.FieldFacts, elements.len);
        for (elements, 0..) |element, index| {
            const value = try self.allocator.create(facts.ValueFacts);
            value.* = try self.evaluateOpaqueMutationValue(function, element, state);
            result = try self.mergeValueFacts(result, value.*);
            fields[index] = .{ .index = @intCast(index), .value = value };
        }
        result.fields = fields;
        return result;
    }

    fn storageGeneration(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !facts.ValidityRootId {
        const storage = try self.resolvePlace(node, state) orelse return state.tracker.establish(.fresh);
        return self.storageGenerationForPlace(storage, state);
    }

    fn storageGenerationForPlace(self: *SafetyChecker, storage: place.Place, state: *FunctionState) !facts.ValidityRootId {
        _ = self;
        for (state.storage_generations.items) |entry| if (entry.storage.eql(storage)) return entry.generation;
        const root = try state.tracker.establish(.fresh);
        try state.storage_generations.append(.{ .storage = storage, .generation = root });
        return root;
    }

    fn mergeOpaqueStorage(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        dependencies: []const facts.ValidityRootId,
    ) !void {
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            var merged = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
            try merged.appendSlice(opaque_storage.hidden_dependencies);
            for (dependencies) |dependency| try appendOwnedRoot(&merged, dependency);
            opaque_storage.hidden_dependencies = try merged.toOwnedSlice();
            return;
        }
        var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        for (dependencies) |dependency| try appendOwnedRoot(&hidden, dependency);
        try state.opaque_storages.append(.{
            .storage = storage,
            .hidden_dependencies = try hidden.toOwnedSlice(),
        });
    }

    /// The trusted caller proved every opaque runtime value in this exact
    /// structural domain is gone. Generations and extracted provenance remain.
    fn markOpaqueStorageEmpty(self: *SafetyChecker, state: *FunctionState, storage: place.Place) void {
        _ = self;
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            opaque_storage.hidden_dependencies = &.{};
            return;
        }
    }

    fn rootIsHidden(state: *const FunctionState, root: facts.ValidityRootId) bool {
        for (state.opaque_storages.items) |opaque_storage|
            if (containsRoot(opaque_storage.hidden_dependencies, root)) return true;
        return false;
    }

    fn opaqueDependencyIsInternalToStorage(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
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
        function: ?*const sg.FunctionDeclaration,
        state: *FunctionState,
        root: facts.ValidityRootId,
    ) !bool {
        return self.endRoots(function, state, &.{root});
    }

    fn endRoots(
        self: *SafetyChecker,
        function: ?*const sg.FunctionDeclaration,
        state: *FunctionState,
        roots: []const facts.ValidityRootId,
    ) !bool {
        // Validity Root termination is a transaction: opaque barriers are checked for
        // the complete batch before any liveness fact changes.
        for (roots) |root| {
            var externally_hidden = false;
            for (state.opaque_storages.items) |opaque_storage| {
                if (!containsRoot(opaque_storage.hidden_dependencies, root)) continue;
                if (self.opaqueDependencyIsInternalToStorage(state, opaque_storage.storage, root)) continue;
                externally_hidden = true;
                break;
            }
            if (!externally_hidden) continue;
            if (function) |current|
                try self.diagnostics.add(current.location, .semantic, "cannot end a root while opaque storage hides a dependency on it", .{});
            return false;
        }
        for (roots) |root| state.tracker.end(root);
        return true;
    }

    fn refreshStorageGeneration(self: *SafetyChecker, function: ?*const sg.FunctionDeclaration, state: *FunctionState, storage: place.Place) !void {
        for (state.storage_generations.items) |entry| {
            if (storage.isPrefixOf(entry.storage) and rootIsHidden(state, entry.generation)) {
                _ = try self.endRoot(function, state, entry.generation);
                return;
            }
        }
        var refreshed = false;
        var index: usize = 0;
        while (index < state.storage_generations.items.len) {
            const entry = state.storage_generations.items[index];
            if (!storage.isPrefixOf(entry.storage)) {
                index += 1;
                continue;
            }
            _ = try self.endRoot(function, state, entry.generation);
            if (entry.storage.eql(storage)) {
                state.storage_generations.items[index].generation = try state.tracker.establish(.fresh);
                refreshed = true;
                index += 1;
            } else {
                // Descendant mappings name storage from the old generation.
                // Drop them so a later address-of establishes each new root
                // lazily, without reviving aliases to the old roots.
                _ = state.storage_generations.orderedRemove(index);
            }
        }
        if (!refreshed)
            try state.storage_generations.append(.{ .storage = storage, .generation = try state.tracker.establish(.fresh) });
    }

    fn endStorageGenerationsUnder(self: *SafetyChecker, function: ?*const sg.FunctionDeclaration, state: *FunctionState, storage: place.Place) !void {
        for (state.storage_generations.items) |entry| {
            if (storage.isPrefixOf(entry.storage) and rootIsHidden(state, entry.generation)) {
                _ = try self.endRoot(function, state, entry.generation);
                return;
            }
        }
        for (state.storage_generations.items) |entry| {
            if (storage.isPrefixOf(entry.storage)) _ = try self.endRoot(function, state, entry.generation);
        }
    }

    fn getPlace(self: *SafetyChecker, state: *FunctionState, storage: place.Place) ?*facts.PlaceFacts {
        _ = self;
        var index = state.places.items.len;
        while (index > 0) {
            index -= 1;
            if (state.places.items[index].storage.eql(storage)) return &state.places.items[index];
        }
        return null;
    }

    fn initializednessAtPlace(self: *SafetyChecker, state: *FunctionState, storage: place.Place) value_state.Initializedness {
        var projection_count = storage.projections.len;
        while (true) {
            const prefix = place.Place{ .root = storage.root, .projections = storage.projections[0..projection_count] };
            if (self.getPlace(state, prefix)) |facts_at_prefix| return facts_at_prefix.initializedness;
            if (projection_count == 0) return .initialized;
            projection_count -= 1;
        }
    }

    fn valueAtPlace(self: *SafetyChecker, state: *FunctionState, storage: place.Place) ?facts.ValueFacts {
        if (self.getPlace(state, storage)) |exact| return exact.value;
        var projection_count = storage.projections.len;
        while (true) {
            const prefix = place.Place{ .root = storage.root, .projections = storage.projections[0..projection_count] };
            if (self.getPlace(state, prefix)) |ancestor|
                return projectValueFacts(ancestor.value, storage.projections[projection_count..]);
            if (projection_count == 0) return null;
            projection_count -= 1;
        }
    }

    fn setPlace(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        initializedness: value_state.Initializedness,
        value: facts.ValueFacts,
    ) !void {
        self.clearChoiceRefinementsUnder(state, storage);
        if (storage.projections.len != 0) {
            const root_storage = place.Place{ .root = storage.root };
            if (self.getPlace(state, root_storage)) |root_place| {
                root_place.value = try self.replaceProjectedValue(
                    root_place.value,
                    storage.projections,
                    if (initializedness == .initialized) value else .{},
                );
            }
        }
        if (self.getPlace(state, storage)) |existing| {
            existing.initializedness = initializedness;
            existing.value = value;
        } else {
            try state.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
        }
        if (initializedness == .initialized) {
            var index = state.places.items.len;
            while (index > 0) {
                index -= 1;
                const candidate = &state.places.items[index];
                if (storage.eql(candidate.storage)) continue;
                if (storage.isPrefixOf(candidate.storage)) {
                    candidate.initializedness = .initialized;
                    candidate.value = projectValueFacts(value, candidate.storage.projections[storage.projections.len..]);
                }
            }
            try self.recordKnownChoiceVariants(state, storage, value);
        }
    }

    fn recordKnownChoiceVariants(self: *SafetyChecker, state: *FunctionState, storage: place.Place, value: facts.ValueFacts) !void {
        if (value.known_choice_variant) |variant_index| {
            self.activateChoiceVariant(value, variant_index, state);
            try self.setChoiceActive(state, storage, variant_index);
        }
        for (value.fields) |field|
            try self.recordKnownChoiceVariants(
                state,
                try self.projectedPlace(storage, .{ .field = field.index }),
                field.value.*,
            );
        if (value.known_choice_variant) |active| for (value.variants) |variant| {
            if (variant.index != active) continue;
            try self.recordKnownChoiceVariants(
                state,
                try self.projectedPlace(storage, .{ .field = active }),
                variant.value.*,
            );
        };
    }

    fn clearChoiceRefinementsUnder(self: *SafetyChecker, state: *FunctionState, storage: place.Place) void {
        _ = self;
        var index: usize = 0;
        while (index < state.choice_active.items.len) {
            const refined = state.choice_active.items[index].storage;
            if (storage.isPrefixOf(refined)) {
                _ = state.choice_active.orderedRemove(index);
            } else index += 1;
        }
        index = 0;
        while (index < state.choice_rejected.items.len) {
            const refined = state.choice_rejected.items[index].storage;
            if (storage.isPrefixOf(refined)) {
                _ = state.choice_rejected.orderedRemove(index);
            } else index += 1;
        }
    }

    fn replaceProjectedValue(
        self: *SafetyChecker,
        container: facts.ValueFacts,
        projections: []const place.Projection,
        replacement: facts.ValueFacts,
    ) !facts.ValueFacts {
        if (projections.len == 0) return replacement;
        const field_index = switch (projections[0]) {
            .field => |index| index,
            else => return container,
        };
        const old_field = findField(container.fields, field_index) orelse return container;

        var direct_roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator.*);
        for (container.owned_roots) |root| {
            var belongs_to_field = false;
            for (container.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) {
                belongs_to_field = true;
                break;
            };
            if (!belongs_to_field) try appendOwnedRoot(&direct_roots, root);
        }
        var direct_dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator.*);
        for (container.dependencies) |dependency| {
            var belongs_to_field = false;
            for (container.fields) |field| if (valueDependsOnRoot(field.value.*, dependency.root)) {
                belongs_to_field = true;
                break;
            };
            if (!belongs_to_field) try appendDependency(&direct_dependencies, dependency);
        }

        const fields = try self.allocator.alloc(facts.FieldFacts, container.fields.len);
        for (container.fields, 0..) |field, index| {
            if (field.index != field_index) {
                fields[index] = field;
                continue;
            }
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = try self.replaceProjectedValue(old_field.value.*, projections[1..], replacement);
            fields[index] = .{ .index = field.index, .value = stored };
        }
        for (fields) |field| {
            for (field.value.owned_roots) |root| try appendOwnedRoot(&direct_roots, root);
            for (field.value.dependencies) |dependency| try appendDependency(&direct_dependencies, dependency);
        }
        var result = container;
        result.fields = fields;
        result.owned_roots = try direct_roots.toOwnedSlice();
        result.dependencies = try direct_dependencies.toOwnedSlice();
        return result;
    }

    fn requireInitialized(self: *SafetyChecker, function: *const sg.FunctionDeclaration, place_facts: *const facts.PlaceFacts) !void {
        if (place_facts.initializedness == .initialized) return;
        try self.diagnostics.add(function.location, .semantic, "place rooted at '{s}' is {s} and cannot be used", .{
            place_facts.storage.root.name,
            @tagName(place_facts.initializedness),
        });
    }

    const OwnerLocation = struct {
        root: facts.ValidityRootId,
        storage: place.Place,
    };

    fn validateUniqueOwnership(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
    ) !void {
        if (state.ownership_conflict_reported) return;
        var owners = std.array_list.Managed(OwnerLocation).init(self.allocator.*);
        defer owners.deinit();
        for (state.places.items) |place_facts| {
            if (place_facts.initializedness != .initialized) continue;
            try self.collectOwnerLocations(place_facts.storage, place_facts.value, &owners);
        }
        for (owners.items, 0..) |owner, index| {
            for (owners.items[index + 1 ..]) |other| {
                if (owner.root != other.root or owner.storage.eql(other.storage) or
                    owner.storage.isPrefixOf(other.storage) or other.storage.isPrefixOf(owner.storage)) continue;
                state.ownership_conflict_reported = true;
                try self.diagnostics.add(function.location, .semantic, "root ownership was duplicated across structural places", .{});
                return;
            }
        }
    }

    fn addStoredOwnershipEdges(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *FunctionState,
        destination: facts.ValueFacts,
        stored: facts.ValueFacts,
    ) !void {
        for (destination.dependencies) |dependency| {
            const owner_index = @intFromEnum(dependency.root);
            if (owner_index >= state.tracker.roots.items.len or
                !state.tracker.roots.items[owner_index].owned_resource) continue;
            for (stored.owned_roots) |owned_root| {
                if (dependency.root == owned_root or self.ownershipPathExists(state, owned_root, dependency.root)) {
                    try self.diagnostics.add(function.location, .semantic, "root ownership must be acyclic", .{});
                    continue;
                }
                try appendOwnershipEdge(&state.ownership_edges, .{ .owner = dependency.root, .owned = owned_root });
            }
        }
    }

    fn ownershipPathExists(
        self: *SafetyChecker,
        state: *const FunctionState,
        from: facts.ValidityRootId,
        target: facts.ValidityRootId,
    ) bool {
        _ = self;
        return ownershipPathExistsFrom(state, from, target, state.tracker.roots.items.len);
    }

    fn rejectEscapingLocalRoots(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        state: *const FunctionState,
    ) !void {
        for (function.output_bindings) |binding| {
            if (!typeContainsPointer(binding.ty)) continue;
            const output = findPlace(state.places.items, .{ .root = binding }) orelse continue;
            if (output.initializedness == .initialized)
                try self.rejectEscapingValue(function, output.value, state);
        }
    }

    fn rejectEscapingValue(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        value: facts.ValueFacts,
        state: *const FunctionState,
    ) !void {
        for (value.dependencies) |dependency| {
            if (!isLocalStorageGeneration(function, state, dependency.root)) continue;
            try self.diagnostics.add(function.location, .semantic, "function output cannot depend on a local storage generation that ends before return", .{});
            return;
        }
        // Aggregate outputs, including choice payloads such as
        // Errable<Allocation>, retain the temporal facts of their fields.
        // Escapes must therefore be checked recursively rather than only on
        // the aggregate's direct facts.
        for (value.fields) |field| {
            try self.rejectEscapingValue(function, field.value.*, state);
        }
        for (value.variants) |variant| {
            try self.rejectEscapingValue(function, variant.value.*, state);
        }
    }

    fn collectOwnerLocations(
        self: *SafetyChecker,
        storage: place.Place,
        value: facts.ValueFacts,
        result: *std.array_list.Managed(OwnerLocation),
    ) !void {
        for (value.owned_roots) |root| {
            var owned_by_field = false;
            for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) {
                owned_by_field = true;
                break;
            };
            if (!owned_by_field) try result.append(.{ .root = root, .storage = storage });
        }
        for (value.fields) |field| {
            try self.collectOwnerLocations(
                try self.projectedPlace(storage, .{ .field = field.index }),
                field.value.*,
                result,
            );
        }
    }

    fn projectedPlace(self: *SafetyChecker, base: place.Place, projection: place.Projection) !place.Place {
        const projections = try self.allocator.alloc(place.Projection, base.projections.len + 1);
        @memcpy(projections[0..base.projections.len], base.projections);
        projections[base.projections.len] = projection;
        return .{ .root = base.root, .projections = projections };
    }

    fn resolvePlace(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !?place.Place {
        return switch (node.content) {
            .binding_use => |binding| .{ .root = binding },
            .move_value => |value| try self.resolvePlace(value, state),
            .address_of => |value| try self.resolvePlace(value, state),
            .struct_field_access => |access| if (try self.resolvePlace(access.struct_value, state)) |base|
                try self.projectedPlace(base, .{ .field = access.field_index })
            else
                null,
            .choice_payload_access => |access| if (try self.resolvePlace(access.choice_value, state)) |base|
                try self.projectedPlace(base, .{ .field = access.variant_index })
            else
                null,
            .array_index => |index| if (try self.resolvePlace(index.array_ptr, state)) |base|
                try self.projectedPlace(base, if (staticIndex(index.index)) |static_index|
                    .{ .static_index = static_index }
                else
                    .dynamic_index)
            else
                null,
            .dereference => |dereference| blk: {
                if (dereference.pointer.content == .address_of)
                    break :blk try self.resolvePlace(dereference.pointer.content.address_of, state);
                const pointer_storage = try self.resolvePlace(dereference.pointer, state) orelse break :blk null;
                const pointer_facts = self.getPlace(state, pointer_storage) orelse break :blk null;
                break :blk pointer_facts.value.referenced_place;
            },
            else => null,
        };
    }

    /// Validate only the pointer traversals needed to reach an addressable
    /// Place. Structural resolution intentionally remains liveness-agnostic;
    /// taking an address is the semantic operation that must prove each
    /// intermediate pointer usable. Bindings and projections are not read.
    fn validateAddressablePath(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) !bool {
        return switch (node.content) {
            .binding_use => true,
            .move_value => |value| self.validateAddressablePath(function, value, state),
            .address_of => |value| self.validateAddressablePath(function, value, state),
            .struct_field_access => |access| self.validateAddressablePath(function, access.struct_value, state),
            .choice_payload_access => |access| self.validateAddressablePath(function, access.choice_value, state),
            .array_index => |index| (try self.evaluatePointerUse(function, index.array_ptr, state)) != null,
            .dereference => |dereference| blk: {
                break :blk (try self.evaluatePointerUse(function, dereference.pointer, state)) != null;
            },
            else => true,
        };
    }

    /// Evaluate one pointer expression exactly once, then validate the
    /// generation carried by that resulting pointer value.
    fn evaluatePointerUse(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        pointer_node: *const sg.SGNode,
        state: *FunctionState,
    ) !?facts.ValueFacts {
        const diagnostic_count = self.diagnostics.list.items.len;
        const pointer = try self.evaluate(function, pointer_node, state);
        if (self.diagnostics.list.items.len != diagnostic_count) return null;
        return if (try self.validateLiveValueUse(function, pointer, state)) pointer else null;
    }

    fn validateLiveValueUse(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        value: facts.ValueFacts,
        state: *const FunctionState,
    ) !bool {
        if (value.integer_address) {
            try self.diagnostics.add(function.location, .semantic, "an integer address cannot establish a safe reference; use RawPointer and explicit root establishment", .{});
            return false;
        }
        if (state.tracker.dependenciesAreAlive(value)) return true;
        try self.diagnostics.add(function.location, .semantic, "reference depends on a root that has ended", .{});
        return false;
    }

    fn oneDependency(self: *SafetyChecker, root: facts.ValidityRootId) ![]const facts.ValidityDependency {
        const result = try self.allocator.alloc(facts.ValidityDependency, 1);
        result[0] = .{ .root = root };
        return result;
    }

    fn oneFreshSource(self: *SafetyChecker, source: facts.FreshEffectSource) ![]const facts.FreshEffectSource {
        const result = try self.allocator.alloc(facts.FreshEffectSource, 1);
        result[0] = source;
        return result;
    }

    fn mergeFreshSources(
        self: *SafetyChecker,
        left: []const facts.FreshEffectSource,
        right: []const facts.FreshEffectSource,
    ) ![]const facts.FreshEffectSource {
        var result = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator.*);
        for (left) |source| try appendFreshSource(&result, source);
        for (right) |source| try appendFreshSource(&result, source);
        return result.toOwnedSlice();
    }

    fn oneOwnedRoot(self: *SafetyChecker, root: facts.ValidityRootId) ![]const facts.ValidityRootId {
        const result = try self.allocator.alloc(facts.ValidityRootId, 1);
        result[0] = root;
        return result;
    }

    fn oneStorageCapability(self: *SafetyChecker, capability: facts.StorageCapabilityId) ![]const facts.StorageCapabilityId {
        const result = try self.allocator.alloc(facts.StorageCapabilityId, 1);
        result[0] = capability;
        return result;
    }

    fn ensureEmptySummary(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        if (self.summaries.contains(function)) return;
        const outputs = try self.allocator.alloc(facts.ValueEffect, function.output.fields.len);
        @memset(outputs, .{});
        try self.summaries.put(function, .{ .outputs = outputs });
    }

    fn virtualSummary(self: *SafetyChecker, registry: *const sg.VirtualMethodRegistry) !?facts.SafetySummary {
        if (self.invalid_virtual_summaries.contains(registry)) return null;
        if (self.virtual_summaries.get(registry)) |summary| return summary;
        if (registry.implementations.items.len == 0) return null;

        var merged = self.summaries.get(registry.implementations.items[0]) orelse return null;
        if (!virtualInputPostStatesRuntimeRepresentable(merged.input_post_states)) {
            try self.invalid_virtual_summaries.put(registry, {});
            return null;
        }
        for (registry.implementations.items[1..]) |implementation| {
            const next = self.summaries.get(implementation) orelse return null;
            if (!virtualInputPostStatesRuntimeRepresentable(next.input_post_states)) {
                try self.invalid_virtual_summaries.put(registry, {});
                return null;
            }
            merged = (try self.mergeVirtualSafetySummary(merged, next)) orelse {
                try self.invalid_virtual_summaries.put(registry, {});
                return null;
            };
        }
        try self.virtual_summaries.put(registry, merged);
        return merged;
    }

    fn mergeVirtualSafetySummary(
        self: *SafetyChecker,
        left: facts.SafetySummary,
        right: facts.SafetySummary,
    ) !?facts.SafetySummary {
        if (left.outputs.len != right.outputs.len) return null;
        if (!virtualInputPostStatesRuntimeRepresentable(left.input_post_states) or
            !virtualInputPostStatesRuntimeRepresentable(right.input_post_states)) return null;

        const input_post_states = (try self.mergeVirtualInputPostStates(
            left.input_post_states,
            right.input_post_states,
        )) orelse return null;

        var fresh_map = std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource).init(self.allocator.*);
        defer fresh_map.deinit();
        const outputs = try self.allocator.alloc(facts.ValueEffect, left.outputs.len);
        for (left.outputs, right.outputs, 0..) |left_output, right_output, index| {
            outputs[index] = (try self.mergeVirtualValueEffect(left_output, right_output, &fresh_map)) orelse return null;
        }
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator.*);
        for (left.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);
        for (right.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);
        const empty_intersection = try self.intersectInputPaths(left.opaque_storage_empties, right.opaque_storage_empties);
        var opaque_storage_empties = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (empty_intersection) |empty| {
            var repopulated = false;
            for (opaque_storage_effects.items) |effect| if (inputPlaceTargetEqual(empty, effect.storage)) {
                repopulated = true;
                break;
            };
            if (!repopulated) try appendInputPath(&opaque_storage_empties, empty);
        }
        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.required_live_inputs) |path| try appendInputPath(&required_live_inputs, path);
        for (right.required_live_inputs) |path| try appendInputPath(&required_live_inputs, path);
        return .{
            .outputs = outputs,
            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .input_post_states = input_post_states,
            .opaque_storage_effects = try opaque_storage_effects.toOwnedSlice(),
            .opaque_storage_empties = try opaque_storage_empties.toOwnedSlice(),
        };
    }

    /// Virtual dispatch merges alternatives selected after the caller has
    /// satisfied the contract. Preconditions therefore accumulate, while
    /// caller-visible post-states retain every representable possibility.
    fn mergeVirtualInputPostStates(
        self: *SafetyChecker,
        left: []const facts.PlacePostState,
        right: []const facts.PlacePostState,
    ) !?[]const facts.PlacePostState {
        var merged = std.array_list.Managed(facts.PlacePostState).init(self.allocator.*);
        for (left) |left_state| {
            const right_state = findInputPostState(right, left_state.target) orelse facts.PlacePostState{
                .target = left_state.target,
                .initializedness = .initialized,
                .value = try self.inputPlaceValueEffect(left_state.target),
            };
            try merged.append((try self.mergeVirtualPlacePostState(left_state, right_state)) orelse return null);
        }
        for (right) |right_state| if (findInputPostState(left, right_state.target) == null) {
            const unchanged = facts.PlacePostState{
                .target = right_state.target,
                .initializedness = .initialized,
                .value = try self.inputPlaceValueEffect(right_state.target),
            };
            try merged.append((try self.mergeVirtualPlacePostState(unchanged, right_state)) orelse return null);
        };
        const result: []const facts.PlacePostState = try merged.toOwnedSlice();
        return result;
    }

    fn mergeVirtualPlacePostState(
        self: *SafetyChecker,
        left: facts.PlacePostState,
        right: facts.PlacePostState,
    ) !?facts.PlacePostState {
        if (!inputPlaceTargetEqual(left.target, right.target)) return null;
        // The runtime drop state is attached to the caller's backing binding,
        // while virtual dispatch only carries an erased data pointer. Until
        // those identities can be correlated, a virtual contract cannot
        // safely consume or conditionally destroy an input. Ordinary rewrites
        // remain mergeable because they do not change cleanup responsibility.
        if (!virtualInputPostStateRuntimeRepresentable(left) or
            !virtualInputPostStateRuntimeRepresentable(right)) return null;
        const value = if (outputEffectEqual(left.value, right.value))
            left.value
        else blk: {
            // Fresh roles and ordinary ownership transfers require correlation
            // that PlacePostState cannot currently express across variants.
            if (outputEffectHasFreshRole(left.value) or outputEffectHasFreshRole(right.value) or
                outputEffectTransfersOwnership(left.value) or outputEffectTransfersOwnership(right.value)) return null;
            break :blk try self.mergeValueEffects(left.value, right.value);
        };
        var result = facts.PlacePostState{
            .target = left.target,
            .initializedness = joinInitializedness(left.initializedness, right.initializedness),
            .value = value,
            .ends_previous_roots = left.ends_previous_roots or right.ends_previous_roots,
            .refreshes_storage_generation = left.refreshes_storage_generation or right.refreshes_storage_generation,
            .requires_available_destination = left.requires_available_destination or right.requires_available_destination,
            .may_repopulate_opaque_storage = left.may_repopulate_opaque_storage or right.may_repopulate_opaque_storage,
        };
        if (!mergeVirtualOpaqueOwnershipEffect(&result, left, right)) return null;
        return result;
    }

    fn virtualInputPostStatesRuntimeRepresentable(states: []const facts.PlacePostState) bool {
        for (states) |state| if (!virtualInputPostStateRuntimeRepresentable(state)) return false;
        return true;
    }

    fn virtualInputPostStateRuntimeRepresentable(state: facts.PlacePostState) bool {
        return state.initializedness == .initialized and state.opaque_ownership == .none;
    }

    /// A virtual call may discharge a domain only when every implementation
    /// guarantees empty of the same input path.
    fn intersectInputPaths(
        self: *SafetyChecker,
        left: []const facts.InputPath,
        right: []const facts.InputPath,
    ) ![]const facts.InputPath {
        var result = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left) |path| for (right) |other| {
            if (!inputPlaceTargetEqual(path, other)) continue;
            try appendInputPath(&result, path);
            break;
        };
        return result.toOwnedSlice();
    }

    fn mergeVirtualValueEffect(
        self: *SafetyChecker,
        left: facts.ValueEffect,
        right: facts.ValueEffect,
        fresh_map: *std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource),
    ) !?facts.ValueEffect {
        if (left.integer_address != right.integer_address or
            left.foreign_storage != right.foreign_storage or
            left.fresh_dependencies.len != right.fresh_dependencies.len or
            left.fresh_owned_roots.len != right.fresh_owned_roots.len or
            left.fresh_storage_capabilities.len != right.fresh_storage_capabilities.len or
            left.fields.len != right.fields.len or
            left.variants.len != right.variants.len) return null;

        if (!try alignFreshSources(left.fresh_dependencies, right.fresh_dependencies, fresh_map) or
            !try alignFreshSources(left.fresh_owned_roots, right.fresh_owned_roots, fresh_map) or
            !try alignFreshSources(left.fresh_storage_capabilities, right.fresh_storage_capabilities, fresh_map)) return null;

        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator.*);
        for (left.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        for (right.input_dependencies) |dependency| {
            if (dependency.transfers_ownership and !containsInputDependency(left.input_dependencies, dependency)) return null;
            try appendInputDependency(&dependencies, dependency);
        }
        for (left.input_dependencies) |dependency| {
            if (dependency.transfers_ownership and !containsInputDependency(right.input_dependencies, dependency)) return null;
        }
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.input_places) |path| try appendInputPath(&input_places, path);
        for (right.input_places) |path| try appendInputPath(&input_places, path);
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.input_place_values) |path| try appendInputPath(&input_place_values, path);
        for (right.input_place_values) |path| try appendInputPath(&input_place_values, path);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.opaque_generation_dependencies) |path| try appendInputPath(&opaque_generations, path);
        for (right.opaque_generation_dependencies) |path| try appendInputPath(&opaque_generations, path);
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.opaque_storage_dependencies) |path| try appendInputPath(&opaque_storages, path);
        for (right.opaque_storage_dependencies) |path| try appendInputPath(&opaque_storages, path);

        const fields = try self.allocator.alloc(facts.OutputFieldEffect, left.fields.len);
        for (left.fields, right.fields, 0..) |left_field, right_field, index| {
            if (left_field.index != right_field.index) return null;
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = (try self.mergeVirtualValueEffect(left_field.value.*, right_field.value.*, fresh_map)) orelse return null;
            fields[index] = .{ .index = left_field.index, .value = value };
        }
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, left.variants.len);
        for (left.variants, right.variants, 0..) |left_variant, right_variant, index| {
            if (left_variant.index != right_variant.index) return null;
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = (try self.mergeVirtualValueEffect(left_variant.value.*, right_variant.value.*, fresh_map)) orelse return null;
            variants[index] = .{ .index = left_variant.index, .value = value };
        }
        return .{
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_places = try input_places.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .opaque_generation_dependencies = try opaque_generations.toOwnedSlice(),
            .opaque_storage_dependencies = try opaque_storages.toOwnedSlice(),
            .fields = fields,
            .variants = variants,
            .known_choice_variant = if (left.known_choice_variant == right.known_choice_variant)
                left.known_choice_variant
            else
                null,
            .fresh_dependencies = left.fresh_dependencies,
            .fresh_owned_roots = left.fresh_owned_roots,
            .fresh_storage_capabilities = left.fresh_storage_capabilities,
            .integer_address = left.integer_address,
            .foreign_storage = left.foreign_storage,
        };
    }

    fn infer(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !bool {
        if (function.safety_primitive != .none)
            return self.replaceSingleOutput(function, try self.primitiveValueEffect(function.safety_primitive, @intFromPtr(function)));
        const body = function.body orelse return false;
        const previous = self.summaries.get(function).?;
        const outputs = try self.allocator.dupe(facts.ValueEffect, previous.outputs);
        var bindings = std.AutoHashMap(*const sg.BindingDeclaration, facts.ValueEffect).init(self.allocator.*);
        defer bindings.deinit();
        var place_bindings = std.AutoHashMap(*const sg.BindingDeclaration, []const facts.InputPath).init(self.allocator.*);
        defer place_bindings.deinit();
        self.inference_bindings = &bindings;
        defer self.inference_bindings = null;
        self.inference_place_bindings = &place_bindings;
        defer self.inference_place_bindings = null;
        try self.inferBlock(function, body, outputs);
        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        try self.inferRequiredLiveInputsBlock(function, body, &required_live_inputs);
        var post_flow = InputPostStateFlow.init(self.allocator.*);
        defer post_flow.deinit();
        var post_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
        defer if (post_exits) |*exits| exits.deinit();
        try self.inferInputPostStates(function, body, &post_flow, &post_exits);
        if (post_flow.reachable) try self.recordInputPostStateExit(&post_exits, &post_flow.states);
        var post_states = if (post_exits) |exits|
            try cloneInputPostStates(&exits, self.allocator.*)
        else
            std.array_list.Managed(facts.PlacePostState).init(self.allocator.*);
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator.*);
        const opaque_storage_empties = try self.inferOpaqueStorageEffects(function, body, &opaque_storage_effects);
        if (function.is_deinit) {
            for (function.input.fields, 0..) |input_field, index| {
                if (!std.mem.eql(u8, input_field.name, "self") or input_field.ty != .pointer_type or
                    input_field.ty.pointer_type.mutability != .read_write) continue;
                try self.recordInputPostState(&post_states, try self.oneInputPath(@intCast(index), &.{}), .deinitialized, .{}, true, false, false, false);
                break;
            }
        }
        const post_state_slice = try post_states.toOwnedSlice();
        const opaque_storage_effect_slice = try opaque_storage_effects.toOwnedSlice();
        const opaque_storage_empty_slice = opaque_storage_empties;
        if (effectsEqual(previous.outputs, outputs) and
            inputPathsEqual(previous.required_live_inputs, required_live_inputs.items) and
            inputPostStatesEqual(previous.input_post_states, post_state_slice) and
            opaqueStorageEffectsEqual(previous.opaque_storage_effects, opaque_storage_effect_slice) and
            inputPathsEqual(previous.opaque_storage_empties, opaque_storage_empty_slice)) return false;
        try self.summaries.put(function, .{
            .outputs = outputs,
            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .input_post_states = post_state_slice,
            .opaque_storage_effects = opaque_storage_effect_slice,
            .opaque_storage_empties = opaque_storage_empty_slice,
        });
        return true;
    }

    fn inferInputPostStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) !void {
        for (block.nodes) |node| {
            if (!flow.reachable) break;
            try self.inferInputPostStatesNode(function, node, flow, exits);
        }
        if (flow.reachable) if (block.ret_val) |value|
            try self.inferInputPostStatesExpression(function, value, &flow.states, exits);
    }

    fn inferInputPostStatesNode(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const states = &flow.states;
        switch (node.content) {
            .binding_declaration => |binding| if (binding.initialization) |initialization|
                try self.inferInputPostStatesExpression(function, initialization, states, exits),
            .binding_assignment => |assignment| try self.inferInputPostStatesExpression(function, assignment.value, states, exits),
            .function_call, .virtual_call => try self.inferInputPostStatesExpression(function, node, states, exits),
            .pointer_assignment => |assignment| {
                try self.inferInputPostStatesExpression(function, assignment.pointer, states, exits);
                try self.inferInputPostStatesExpression(function, assignment.value, states, exits);
                try self.recordInputPostState(states, try self.inferInputPaths(function, assignment.pointer), .initialized, try self.inferExpression(function, assignment.value), false, false, false, true);
            },
            .struct_field_store => |store| {
                try self.inferInputPostStatesExpression(function, store.struct_ptr, states, exits);
                try self.inferInputPostStatesExpression(function, store.value, states, exits);
                const targets = try self.projectInputPaths(try self.inferInputPaths(function, store.struct_ptr), .{ .field = store.field_index });
                try self.recordInputPostState(states, targets, .initialized, try self.inferExpression(function, store.value), false, false, false, true);
            },
            .array_store => |store| {
                try self.inferInputPostStatesExpression(function, store.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function, store.index, states, exits);
                try self.inferInputPostStatesExpression(function, store.value, states, exits);
                const projection: place.Projection = if (staticIndex(store.index)) |index| .{ .static_index = index } else .dynamic_index;
                const targets = try self.projectInputPaths(try self.inferInputPaths(function, store.array_ptr), projection);
                try self.recordInputPostState(states, targets, .initialized, try self.inferExpression(function, store.value), false, false, false, true);
            },
            .if_statement => |statement| {
                try self.inferInputPostStatesExpression(function, statement.condition, states, exits);
                var then_flow = try flow.clone(self.allocator.*);
                defer then_flow.deinit();
                try self.inferInputPostStates(function, statement.then_block, &then_flow, exits);
                var else_flow = try flow.clone(self.allocator.*);
                defer else_flow.deinit();
                if (statement.else_block) |else_block| try self.inferInputPostStates(function, else_block, &else_flow, exits);
                try self.joinInputPostStateFallthrough(flow, &then_flow, &else_flow);
            },
            .while_statement => |statement| {
                try self.inferInputPostStatesExpression(function, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator.*);
                defer body_flow.deinit();
                try self.inferInputPostStates(function, statement.body, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| try self.inferInputPostStatesNode(function, initialization, flow, exits);
                if (!flow.reachable) return;
                try self.inferInputPostStatesExpression(function, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator.*);
                defer body_flow.deinit();
                try self.inferInputPostStates(function, statement.body, &body_flow, exits);
                if (body_flow.reachable) if (statement.increment) |increment| try self.inferInputPostStatesNode(function, increment, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .switch_statement => |statement| {
                try self.inferInputPostStatesExpression(function, statement.expression, states, exits);
                var joined: ?InputPostStateFlow = null;
                defer if (joined) |*joined_flow| joined_flow.deinit();

                for (statement.cases) |case| {
                    var branch = try flow.clone(self.allocator.*);
                    defer branch.deinit();
                    try self.inferInputPostStates(function, case.body, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                }
                if (statement.default_case) |default_case| {
                    var branch = try flow.clone(self.allocator.*);
                    defer branch.deinit();
                    try self.inferInputPostStates(function, default_case, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinInputPostStateFlowBranch(&joined, flow);
                }
                if (joined) |*joined_flow| try self.copyInputPostStateFlow(flow, joined_flow) else flow.reachable = false;
            },
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.inferInputPostStatesExpression(function, expression, states, exits);
                for (statement.cleanup_nodes) |cleanup| try self.inferInputPostStatesNode(function, cleanup, flow, exits);
                try self.recordInputPostStateExit(exits, states);
                flow.reachable = false;
            },
            .code_block => |nested| try self.inferInputPostStates(function, nested, flow, exits),
            .break_statement, .continue_statement => flow.reachable = false,
            .auto_deinit_binding => |cleanup| try self.applyAutoDeinitInputPostStates(function, cleanup, states),
            else => try self.inferInputPostStatesExpression(function, node, states, exits),
        }
    }

    fn inferInputPostStatesExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        switch (node.content) {
            .move_value, .address_of => |value| try self.inferInputPostStatesExpression(function, value, states, exits),
            .dereference => |dereference| try self.inferInputPostStatesExpression(function, dereference.pointer, states, exits),
            .struct_value_literal => |literal| for (literal.fields) |field|
                try self.inferInputPostStatesExpression(function, field.value, states, exits),
            .list_literal => |literal| for (literal.elements) |element|
                try self.inferInputPostStatesExpression(function, element, states, exits),
            .array_literal => |literal| for (literal.elements) |element|
                try self.inferInputPostStatesExpression(function, element, states, exits),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.inferInputPostStatesExpression(function, payload, states, exits),
            .struct_field_access => |access| try self.inferInputPostStatesExpression(function, access.struct_value, states, exits),
            .choice_payload_access => |access| try self.inferInputPostStatesExpression(function, access.choice_value, states, exits),
            .array_index => |index| {
                try self.inferInputPostStatesExpression(function, index.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function, index.index, states, exits);
            },
            .explicit_cast => |cast| try self.inferInputPostStatesExpression(function, cast.value, states, exits),
            .binary_operation => |operation| {
                try self.inferInputPostStatesExpression(function, operation.left, states, exits);
                try self.inferInputPostStatesExpression(function, operation.right, states, exits);
            },
            .comparison => |comparison| {
                try self.inferInputPostStatesExpression(function, comparison.left, states, exits);
                try self.inferInputPostStatesExpression(function, comparison.right, states, exits);
            },
            .logical_operation => |operation| {
                try self.inferInputPostStatesExpression(function, operation.left, states, exits);
                try self.inferConditionalInputPostStatesExpression(function, operation.right, states, exits);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.inferInputPostStatesExpression(function, unwrap.nullable_value, states, exits);
                try self.inferConditionalInputPostStatesExpression(function, unwrap.fallback_value, states, exits);
            },
            .testing_expect_error => |expectation| {
                try self.inferInputPostStatesExpression(function, expectation.expected_reason, states, exits);
                try self.inferInputPostStatesExpression(function, expectation.actual_result, states, exits);
            },
            .error_propagation => |propagation| {
                try self.inferInputPostStatesExpression(function, propagation.errable_value, states, exits);
                var error_flow = InputPostStateFlow{ .states = try cloneInputPostStates(states, self.allocator.*) };
                defer error_flow.deinit();
                for (propagation.cleanup_nodes) |cleanup| try self.inferInputPostStatesNode(function, cleanup, &error_flow, exits);
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .error_context => |context| {
                try self.inferInputPostStatesExpression(function, context.errable_value, states, exits);
                var error_flow = InputPostStateFlow{ .states = try cloneInputPostStates(states, self.allocator.*) };
                defer error_flow.deinit();
                try self.inferInputPostStatesExpression(function, context.context, &error_flow.states, exits);
                for (context.cleanup_nodes) |cleanup| try self.inferInputPostStatesNode(function, cleanup, &error_flow, exits);
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .function_call => |call| {
                try self.inferInputPostStatesExpression(function, call.input, states, exits);
                try self.applyInputPostStatesFromFunctionCall(function, call, states);
            },
            .virtual_call => |call| {
                try self.inferInputPostStatesExpression(function, call.handle, states, exits);
                try self.inferInputPostStatesExpression(function, call.input, states, exits);
                const summary = try self.virtualSummary(call.safety_methods) orelse return;
                try self.applyInputPostStatesFromSummary(function, summary, call.input, states, null);
            },
            .virtualize => |virtualize| try self.inferInputPostStatesExpression(function, virtualize.value, states, exits),
            .type_initializer => |initializer| try self.inferInputPostStatesExpression(function, initializer.args, states, exits),
            else => {},
        }
    }

    fn inferConditionalInputPostStatesExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) !void {
        var executed = try cloneInputPostStates(states, self.allocator.*);
        defer executed.deinit();
        try self.inferInputPostStatesExpression(function, node, &executed, exits);
        var skipped = try cloneInputPostStates(states, self.allocator.*);
        defer skipped.deinit();
        try self.joinInputPostStates(states, &executed, &skipped);
    }

    fn applyInputPostStatesFromFunctionCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (call.input.content != .struct_value_literal) return;
        const arguments = call.input.content.struct_value_literal.fields;
        if (call.callee.safety_primitive == .trusted_opaque_move or
            call.callee.safety_primitive == .trusted_opaque_move_in)
        {
            if (arguments.len >= 2) {
                const source_index: usize = if (arguments.len == 3) 2 else 1;
                const targets = try self.inferInputPaths(function, arguments[source_index].value);
                const storage = if (arguments.len == 3) blk: {
                    const storage_targets = try self.inferInputPaths(function, arguments[0].value);
                    break :blk if (storage_targets.len == 1) storage_targets[0] else null;
                } else null;
                try self.recordOpaqueOwnershipConsumption(states, targets, .definite, storage);
            }
            return;
        }
        if (call.callee.safety_primitive == .trusted_opaque_relocate) return;
        if (call.callee.safety_primitive == .relocate) {
            if (arguments.len != 2) return;
            const source_targets = try self.inferInputPaths(function, arguments[0].value);
            const destination_targets = try self.inferInputPaths(function, arguments[1].value);
            for (source_targets) |source| {
                try self.recordInputPostState(states, &.{source}, .moved, .{}, false, false, false, false);
                var transferred = try self.inputValueEffect(source.input_index, source.projections);
                transferred = self.withOwnershipTransfer(transferred);
                for (destination_targets) |destination|
                    try self.recordInputPostState(states, &.{destination}, .initialized, transferred, false, false, true, false);
            }
            return;
        }
        const summary = self.summaries.get(call.callee) orelse return;
        try self.applyInputPostStatesFromSummary(function, summary, call.input, states, null);
    }

    fn applyInputPostStatesFromSummary(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.SafetySummary,
        input: *const sg.SGNode,
        states: *std.array_list.Managed(facts.PlacePostState),
        symbolic_override: ?SymbolicInputOverride,
    ) !void {
        if (input.content != .struct_value_literal) return;
        const arguments = input.content.struct_value_literal.fields;
        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            const targets = try self.substituteInputPathWithOverride(function, post_state.target, arguments, symbolic_override);
            if (post_state.opaque_ownership != .none) {
                const storage = if (post_state.opaque_storage) |opaque_storage| blk: {
                    if (opaque_storage.input_index >= arguments.len) break :blk null;
                    const mapped = try self.substituteInputPathWithOverride(function, opaque_storage, arguments, symbolic_override);
                    break :blk if (mapped.len == 1) mapped[0] else null;
                } else null;
                try self.recordOpaqueOwnershipConsumption(states, targets, post_state.opaque_ownership, storage);
                continue;
            }
            const value = try self.substituteOutputWithOverride(function, post_state.value, arguments, symbolic_override);
            try self.recordInputPostState(states, targets, post_state.initializedness, value, post_state.ends_previous_roots, post_state.refreshes_storage_generation, post_state.requires_available_destination, post_state.may_repopulate_opaque_storage);
        }
    }

    fn applyAutoDeinitInputPostStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        cleanup: *const sg.AutoDeinitBinding,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        const binding_effect = if (self.inference_bindings) |bindings| bindings.get(cleanup.binding) else null;
        if (cleanup.deinit_fn) |deinit_fn| if (cleanup.input) |input| if (self.summaries.get(deinit_fn)) |summary|
            try self.applyInputPostStatesFromSummary(function, summary, input, states, if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null);
        if (binding_effect) |effect| try self.applyAutoDeinitFieldInputPostStates(function, cleanup.fields, states, effect);
    }

    fn applyAutoDeinitFieldInputPostStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.AutoDeinitField,
        states: *std.array_list.Managed(facts.PlacePostState),
        parent_effect: facts.ValueEffect,
    ) !void {
        for (fields) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.deinit_fn) |deinit_fn| if (field.input) |input| if (self.summaries.get(deinit_fn)) |summary|
                try self.applyInputPostStatesFromSummary(function, summary, input, states, .{ .input_index = field.self_field_index, .effect = field_effect });
            try self.applyAutoDeinitFieldInputPostStates(function, field.fields, states, field_effect);
        }
    }

    fn inferRequiredLiveInputsBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        for (block.nodes) |node| try self.inferRequiredLiveInputsNode(function, node, required);
        if (block.ret_val) |value| try self.inferRequiredLiveInputsNode(function, value, required);
    }

    fn inferRequiredLiveInputsNode(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        if (pointerUseOperand(node)) |pointer|
            try self.recordPointerUseRequirement(function, pointer, required);
        switch (node.content) {
            .binding_declaration => |binding| if (binding.initialization) |value|
                try self.inferRequiredLiveInputsNode(function, value, required),
            .binding_assignment => |assignment| try self.inferRequiredLiveInputsNode(function, assignment.value, required),
            .move_value, .address_of => |value| try self.inferRequiredLiveInputsNode(function, value, required),
            .dereference => |dereference| {
                try self.inferRequiredLiveInputsNode(function, dereference.pointer, required);
            },
            .array_index => |index| {
                try self.inferRequiredLiveInputsNode(function, index.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function, index.index, required);
            },
            .array_store => |store| {
                try self.inferRequiredLiveInputsNode(function, store.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function, store.index, required);
                try self.inferRequiredLiveInputsNode(function, store.value, required);
            },
            .pointer_assignment => |assignment| {
                try self.inferRequiredLiveInputsNode(function, assignment.pointer, required);
                try self.inferRequiredLiveInputsNode(function, assignment.value, required);
            },
            .struct_field_access => |access| try self.inferRequiredLiveInputsNode(function, access.struct_value, required),
            .choice_payload_access => |access| try self.inferRequiredLiveInputsNode(function, access.choice_value, required),
            .explicit_cast => |cast| try self.inferRequiredLiveInputsNode(function, cast.value, required),
            .struct_field_store => |store| {
                try self.inferRequiredLiveInputsNode(function, store.struct_ptr, required);
                try self.inferRequiredLiveInputsNode(function, store.value, required);
            },
            .struct_value_literal => |literal| for (literal.fields) |field|
                try self.inferRequiredLiveInputsNode(function, field.value, required),
            .list_literal => |literal| for (literal.elements) |element|
                try self.inferRequiredLiveInputsNode(function, element, required),
            .array_literal => |literal| for (literal.elements) |element|
                try self.inferRequiredLiveInputsNode(function, element, required),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.inferRequiredLiveInputsNode(function, payload, required),
            .function_call => |call| {
                try self.inferRequiredLiveInputsNode(function, call.input, required);
                if (self.summaries.get(call.callee)) |summary|
                    try self.substituteRequiredLiveInputs(function, summary.required_live_inputs, call.input, required);
            },
            .virtual_call => |call| {
                try self.inferRequiredLiveInputsNode(function, call.handle, required);
                try self.inferRequiredLiveInputsNode(function, call.input, required);
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.substituteRequiredLiveInputs(function, summary.required_live_inputs, call.input, required);
            },
            .virtualize => |virtualize| try self.inferRequiredLiveInputsNode(function, virtualize.value, required),
            .binary_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function, operation.left, required);
                try self.inferRequiredLiveInputsNode(function, operation.right, required);
            },
            .comparison => |operation| {
                try self.inferRequiredLiveInputsNode(function, operation.left, required);
                try self.inferRequiredLiveInputsNode(function, operation.right, required);
            },
            .logical_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function, operation.left, required);
                try self.inferRequiredLiveInputsNode(function, operation.right, required);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.inferRequiredLiveInputsNode(function, unwrap.nullable_value, required);
                try self.inferRequiredLiveInputsNode(function, unwrap.fallback_value, required);
            },
            .testing_expect_error => |expectation| {
                try self.inferRequiredLiveInputsNode(function, expectation.expected_reason, required);
                try self.inferRequiredLiveInputsNode(function, expectation.actual_result, required);
            },
            .error_propagation => |propagation| {
                try self.inferRequiredLiveInputsNode(function, propagation.errable_value, required);
                for (propagation.cleanup_nodes) |cleanup| try self.inferRequiredLiveInputsNode(function, cleanup, required);
            },
            .error_context => |context| {
                try self.inferRequiredLiveInputsNode(function, context.errable_value, required);
                try self.inferRequiredLiveInputsNode(function, context.context, required);
                for (context.cleanup_nodes) |cleanup| try self.inferRequiredLiveInputsNode(function, cleanup, required);
            },
            .if_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function, statement.then_block, required);
                if (statement.else_block) |else_block| try self.inferRequiredLiveInputsBlock(function, else_block, required);
            },
            .while_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function, statement.body, required);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| try self.inferRequiredLiveInputsNode(function, initialization, required);
                try self.inferRequiredLiveInputsNode(function, statement.condition, required);
                if (statement.increment) |increment| try self.inferRequiredLiveInputsNode(function, increment, required);
                try self.inferRequiredLiveInputsBlock(function, statement.body, required);
            },
            .switch_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function, statement.expression, required);
                for (statement.cases) |case| {
                    try self.inferRequiredLiveInputsNode(function, case.value, required);
                    try self.inferRequiredLiveInputsBlock(function, case.body, required);
                }
                if (statement.default_case) |default_case| try self.inferRequiredLiveInputsBlock(function, default_case, required);
            },
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.inferRequiredLiveInputsNode(function, expression, required);
                for (statement.cleanup_nodes) |cleanup| try self.inferRequiredLiveInputsNode(function, cleanup, required);
            },
            .code_block => |block| try self.inferRequiredLiveInputsBlock(function, block, required),
            .type_initializer => |initializer| try self.inferRequiredLiveInputsNode(function, initializer.args, required),
            .auto_deinit_binding => |cleanup| try self.inferAutoDeinitRequiredLiveInputs(function, cleanup, required),
            else => {},
        }
    }

    fn inferAutoDeinitRequiredLiveInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        cleanup: *const sg.AutoDeinitBinding,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const binding_effect = if (self.inference_bindings) |bindings| bindings.get(cleanup.binding) else null;
        if (cleanup.input) |input| {
            try self.inferRequiredLiveInputsNode(function, input, required);
            if (cleanup.deinit_fn) |deinit_fn| if (self.summaries.get(deinit_fn)) |summary|
                try self.substituteRequiredLiveInputsWithOverride(function, summary.required_live_inputs, input, required, if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null);
        }
        if (binding_effect) |effect| try self.inferAutoDeinitFieldRequiredLiveInputs(function, cleanup.fields, required, effect);
    }

    fn inferAutoDeinitFieldRequiredLiveInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.AutoDeinitField,
        required: *std.array_list.Managed(facts.InputPath),
        parent_effect: facts.ValueEffect,
    ) !void {
        for (fields) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.input) |input| {
                try self.inferRequiredLiveInputsNode(function, input, required);
                if (field.deinit_fn) |deinit_fn| if (self.summaries.get(deinit_fn)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(function, summary.required_live_inputs, input, required, .{ .input_index = field.self_field_index, .effect = field_effect });
            }
            try self.inferAutoDeinitFieldRequiredLiveInputs(function, field.fields, required, field_effect);
        }
    }

    fn recordPointerUseRequirement(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        pointer: *const sg.SGNode,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const effect = try self.inferExpression(function, pointer);
        for (try self.symbolicSourcePaths(function, pointer, effect)) |path|
            try appendInputPath(required, path);
    }

    fn substituteRequiredLiveInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        callee_required: []const facts.InputPath,
        input: *const sg.SGNode,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        try self.substituteRequiredLiveInputsWithOverride(function, callee_required, input, required, null);
    }

    fn substituteRequiredLiveInputsWithOverride(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        callee_required: []const facts.InputPath,
        input: *const sg.SGNode,
        required: *std.array_list.Managed(facts.InputPath),
        symbolic_override: ?SymbolicInputOverride,
    ) !void {
        if (input.content != .struct_value_literal) return;
        const arguments = input.content.struct_value_literal.fields;
        for (callee_required) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteInputPathWithOverride(function, path, arguments, symbolic_override);
            for (substituted) |candidate| try appendInputPath(required, candidate);
        }
    }

    fn inferOpaqueStorageEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
    ) ![]const facts.InputPath {
        var state = OpaqueEmptyState.init(self.allocator.*);
        defer state.deinit();
        var exits: ?std.array_list.Managed(facts.InputPath) = null;
        defer if (exits) |*emptied| emptied.deinit();
        try self.inferOpaqueEmptyBlock(function, block, effects, &state, &exits);
        if (state.reachable) try self.recordOpaqueEmptyExit(&exits, state.emptied.items);

        const emptied = if (exits) |emptied| try self.allocator.dupe(facts.InputPath, emptied.items) else &.{};
        for (emptied) |storage| self.removeOpaqueStorageEffects(effects, storage);
        return emptied;
    }

    fn inferOpaqueEmptyBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) !void {
        for (block.nodes) |node| {
            if (!state.reachable) break;
            try self.inferOpaqueEmptyNode(function, node, effects, state, exits);
        }
        if (state.reachable) if (block.ret_val) |value|
            try self.inferOpaqueEmptyExpression(function, value, effects, state, exits);
    }

    fn inferOpaqueEmptyNode(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        switch (node.content) {
            .binding_declaration => |binding| if (binding.initialization) |initialization|
                try self.inferOpaqueEmptyExpression(function, initialization, effects, state, exits),
            .binding_assignment => |assignment| try self.inferOpaqueEmptyExpression(function, assignment.value, effects, state, exits),
            .function_call, .virtual_call => try self.inferOpaqueEmptyExpression(function, node, effects, state, exits),
            .if_statement => |statement| {
                try self.inferOpaqueEmptyExpression(function, statement.condition, effects, state, exits);
                var then_state = try state.clone(self.allocator.*);
                defer then_state.deinit();
                try self.inferOpaqueEmptyBlock(function, statement.then_block, effects, &then_state, exits);
                var else_state = try state.clone(self.allocator.*);
                defer else_state.deinit();
                if (statement.else_block) |else_block|
                    try self.inferOpaqueEmptyBlock(function, else_block, effects, &else_state, exits);
                try self.joinOpaqueEmptyFallthrough(state, &then_state, &else_state);
            },
            .while_statement => |statement| {
                try self.inferOpaqueEmptyExpression(function, statement.condition, effects, state, exits);
                var body_state = try state.clone(self.allocator.*);
                defer body_state.deinit();
                try self.inferOpaqueEmptyBlock(function, statement.body, effects, &body_state, exits);
                // A loop may execute zero or more times; without loop proofs,
                // no domain is known empty on every fallthrough path.
                state.emptied.clearRetainingCapacity();
            },
            .for_statement => |statement| {
                if (statement.init) |initialization|
                    try self.inferOpaqueEmptyNode(function, initialization, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, statement.condition, effects, state, exits);
                var body_state = try state.clone(self.allocator.*);
                defer body_state.deinit();
                try self.inferOpaqueEmptyBlock(function, statement.body, effects, &body_state, exits);
                if (body_state.reachable) if (statement.increment) |increment|
                    try self.inferOpaqueEmptyNode(function, increment, effects, &body_state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .switch_statement => |statement| {
                try self.inferOpaqueEmptyExpression(function, statement.expression, effects, state, exits);
                var joined: ?OpaqueEmptyState = null;
                defer if (joined) |*joined_state| joined_state.deinit();
                for (statement.cases) |case| {
                    var branch = try state.clone(self.allocator.*);
                    defer branch.deinit();
                    try self.inferOpaqueEmptyBlock(function, case.body, effects, &branch, exits);
                    try self.joinOpaqueEmptyBranch(&joined, &branch);
                }
                if (statement.default_case) |default_case| {
                    var branch = try state.clone(self.allocator.*);
                    defer branch.deinit();
                    try self.inferOpaqueEmptyBlock(function, default_case, effects, &branch, exits);
                    try self.joinOpaqueEmptyBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinOpaqueEmptyBranch(&joined, state);
                }
                if (joined) |*joined_state| try self.copyOpaqueEmptyState(state, joined_state) else state.reachable = false;
            },
            .return_statement => |statement| {
                if (statement.expression) |expression|
                    try self.inferOpaqueEmptyExpression(function, expression, effects, state, exits);
                for (statement.cleanup_nodes) |cleanup|
                    try self.inferOpaqueEmptyNode(function, cleanup, effects, state, exits);
                try self.recordOpaqueEmptyExit(exits, state.emptied.items);
                state.reachable = false;
            },
            .struct_field_store => |store| {
                try self.inferOpaqueEmptyExpression(function, store.struct_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .array_store => |store| {
                try self.inferOpaqueEmptyExpression(function, store.array_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, store.index, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .pointer_assignment => |assignment| {
                try self.inferOpaqueEmptyExpression(function, assignment.pointer, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, assignment.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .code_block => |nested| try self.inferOpaqueEmptyBlock(function, nested, effects, state, exits),
            .break_statement, .continue_statement => state.reachable = false,
            .auto_deinit_binding => |cleanup| try self.applyAutoDeinitOpaqueEffects(function, cleanup, effects, state),
            else => try self.inferOpaqueEmptyExpression(function, node, effects, state, exits),
        }
    }

    fn applyAutoDeinitOpaqueEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        cleanup: *const sg.AutoDeinitBinding,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
    ) !void {
        const binding_effect = if (self.inference_bindings) |bindings| bindings.get(cleanup.binding) else null;
        if (cleanup.deinit_fn) |deinit_fn| if (cleanup.input) |input| if (self.summaries.get(deinit_fn)) |summary|
            try self.applyOpaqueEmptySummary(function, summary, input, effects, state, if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null);
        if (binding_effect) |effect| try self.applyAutoDeinitFieldOpaqueEffects(function, cleanup.fields, effects, state, effect);
    }

    fn applyAutoDeinitFieldOpaqueEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.AutoDeinitField,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        parent_effect: facts.ValueEffect,
    ) !void {
        for (fields) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.deinit_fn) |deinit_fn| if (field.input) |input| if (self.summaries.get(deinit_fn)) |summary|
                try self.applyOpaqueEmptySummary(function, summary, input, effects, state, .{ .input_index = field.self_field_index, .effect = field_effect });
            try self.applyAutoDeinitFieldOpaqueEffects(function, field.fields, effects, state, field_effect);
        }
    }

    /// Visits expression children in runtime evaluation order, then applies a
    /// call's net opaque state. Conditional children are joined with the path
    /// that skips them so they cannot manufacture a definite empty.
    fn inferOpaqueEmptyExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        switch (node.content) {
            .move_value, .address_of => |value| try self.inferOpaqueEmptyExpression(function, value, effects, state, exits),
            .dereference => |dereference| try self.inferOpaqueEmptyExpression(function, dereference.pointer, effects, state, exits),
            .struct_value_literal => |literal| for (literal.fields) |field|
                try self.inferOpaqueEmptyExpression(function, field.value, effects, state, exits),
            .list_literal => |literal| for (literal.elements) |element|
                try self.inferOpaqueEmptyExpression(function, element, effects, state, exits),
            .array_literal => |literal| for (literal.elements) |element|
                try self.inferOpaqueEmptyExpression(function, element, effects, state, exits),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.inferOpaqueEmptyExpression(function, payload, effects, state, exits),
            .struct_field_access => |access| try self.inferOpaqueEmptyExpression(function, access.struct_value, effects, state, exits),
            .choice_payload_access => |access| try self.inferOpaqueEmptyExpression(function, access.choice_value, effects, state, exits),
            .array_index => |index| {
                try self.inferOpaqueEmptyExpression(function, index.array_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, index.index, effects, state, exits);
            },
            .explicit_cast => |cast| try self.inferOpaqueEmptyExpression(function, cast.value, effects, state, exits),
            .binary_operation => |operation| {
                try self.inferOpaqueEmptyExpression(function, operation.left, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, operation.right, effects, state, exits);
            },
            .comparison => |comparison| {
                try self.inferOpaqueEmptyExpression(function, comparison.left, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, comparison.right, effects, state, exits);
            },
            .logical_operation => |operation| {
                try self.inferOpaqueEmptyExpression(function, operation.left, effects, state, exits);
                try self.inferConditionalOpaqueEmptyExpression(function, operation.right, effects, state, exits);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.inferOpaqueEmptyExpression(function, unwrap.nullable_value, effects, state, exits);
                try self.inferConditionalOpaqueEmptyExpression(function, unwrap.fallback_value, effects, state, exits);
            },
            .testing_expect_error => |expectation| {
                try self.inferOpaqueEmptyExpression(function, expectation.expected_reason, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, expectation.actual_result, effects, state, exits);
            },
            .error_propagation => |propagation| {
                try self.inferOpaqueEmptyExpression(function, propagation.errable_value, effects, state, exits);
                var error_state = try state.clone(self.allocator.*);
                defer error_state.deinit();
                for (propagation.cleanup_nodes) |cleanup|
                    try self.inferOpaqueEmptyNode(function, cleanup, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, error_state.emptied.items);
            },
            .error_context => |context| {
                try self.inferOpaqueEmptyExpression(function, context.errable_value, effects, state, exits);
                var error_state = try state.clone(self.allocator.*);
                defer error_state.deinit();
                try self.inferOpaqueEmptyExpression(function, context.context, effects, &error_state, exits);
                for (context.cleanup_nodes) |cleanup|
                    try self.inferOpaqueEmptyNode(function, cleanup, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, error_state.emptied.items);
            },
            .function_call => |call| {
                try self.inferOpaqueEmptyExpression(function, call.input, effects, state, exits);
                try self.applyOpaqueEmptyFunctionCall(function, call, effects, state);
            },
            .virtual_call => |call| {
                try self.inferOpaqueEmptyExpression(function, call.handle, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function, call.input, effects, state, exits);
                const summary = try self.virtualSummary(call.safety_methods) orelse return;
                try self.applyOpaqueEmptySummary(function, summary, call.input, effects, state, null);
            },
            .virtualize => |virtualize| try self.inferOpaqueEmptyExpression(function, virtualize.value, effects, state, exits),
            .type_initializer => |initializer| try self.inferOpaqueEmptyExpression(function, initializer.args, effects, state, exits),
            else => {},
        }
    }

    fn inferConditionalOpaqueEmptyExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) !void {
        var executed = try state.clone(self.allocator.*);
        defer executed.deinit();
        try self.inferOpaqueEmptyExpression(function, node, effects, &executed, exits);
        var skipped = try state.clone(self.allocator.*);
        defer skipped.deinit();
        try self.joinOpaqueEmptyFallthrough(state, &executed, &skipped);
    }

    fn applyOpaqueEmptyFunctionCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
    ) !void {
        if (call.input.content != .struct_value_literal) return;
        const arguments = call.input.content.struct_value_literal.fields;
        if (call.callee.safety_primitive == .trusted_opaque_move) {
            state.emptied.clearRetainingCapacity();
            return;
        }
        if (call.callee.safety_primitive == .trusted_opaque_move_in) {
            if (arguments.len != 3) return;
            const storages = try self.inferInputPaths(function, arguments[0].value);
            const hidden = try self.inferExpression(function, arguments[2].value);
            for (storages) |storage| {
                self.removeOpaqueStorageRelease(&state.emptied, storage);
                try self.recordOpaqueStorageEffect(effects, storage, hidden);
            }
            return;
        }
        if (call.callee.safety_primitive == .trusted_opaque_mark_empty) {
            if (arguments.len != 1) return;
            const storages = try self.inferInputPaths(function, arguments[0].value);
            for (storages) |storage| try self.recordOpaqueStorageRelease(&state.emptied, storage);
            return;
        }
        const summary = self.summaries.get(call.callee) orelse return;
        try self.applyOpaqueEmptySummary(function, summary, call.input, effects, state, null);
    }

    fn applyOpaqueEmptySummary(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.SafetySummary,
        input: *const sg.SGNode,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        symbolic_override: ?SymbolicInputOverride,
    ) !void {
        if (input.content != .struct_value_literal) return;
        const arguments = input.content.struct_value_literal.fields;
        // Projected post-states can become opaque mutations through runtime
        // provenance even when their symbolic target does not name the domain.
        if (summaryMayRepopulateOpaqueStorage(summary)) state.emptied.clearRetainingCapacity();
        for (summary.opaque_storage_effects) |effect| {
            if (effect.storage.input_index >= arguments.len) continue;
            const storages = try self.substituteInputPathWithOverride(function, effect.storage, arguments, symbolic_override);
            const hidden = try self.substituteOutputWithOverride(function, effect.hidden_dependencies, arguments, symbolic_override);
            for (storages) |storage| {
                self.removeOpaqueStorageRelease(&state.emptied, storage);
                try self.recordOpaqueStorageEffect(effects, storage, hidden);
            }
        }
        for (summary.opaque_storage_empties) |empty| {
            if (empty.input_index >= arguments.len) continue;
            const storages = try self.substituteInputPathWithOverride(function, empty, arguments, symbolic_override);
            for (storages) |storage| try self.recordOpaqueStorageRelease(&state.emptied, storage);
        }
    }

    fn joinOpaqueEmptyFallthrough(
        self: *SafetyChecker,
        destination: *OpaqueEmptyState,
        left: *const OpaqueEmptyState,
        right: *const OpaqueEmptyState,
    ) !void {
        if (!left.reachable and !right.reachable) {
            destination.emptied.clearRetainingCapacity();
            destination.reachable = false;
            return;
        }
        if (!left.reachable) return self.copyOpaqueEmptyState(destination, right);
        if (!right.reachable) return self.copyOpaqueEmptyState(destination, left);
        const joined = try self.intersectInputPaths(left.emptied.items, right.emptied.items);
        destination.emptied.clearRetainingCapacity();
        try destination.emptied.appendSlice(joined);
        destination.reachable = true;
    }

    fn joinOpaqueEmptyBranch(
        self: *SafetyChecker,
        joined: *?OpaqueEmptyState,
        branch: *const OpaqueEmptyState,
    ) !void {
        if (joined.*) |*current| {
            var combined = OpaqueEmptyState.init(self.allocator.*);
            try self.joinOpaqueEmptyFallthrough(&combined, current, branch);
            current.deinit();
            current.* = combined;
        } else joined.* = try branch.clone(self.allocator.*);
    }

    fn copyOpaqueEmptyState(
        self: *SafetyChecker,
        destination: *OpaqueEmptyState,
        source: *const OpaqueEmptyState,
    ) !void {
        _ = self;
        destination.emptied.clearRetainingCapacity();
        try destination.emptied.appendSlice(source.emptied.items);
        destination.reachable = source.reachable;
    }

    fn recordOpaqueEmptyExit(
        self: *SafetyChecker,
        exits: *?std.array_list.Managed(facts.InputPath),
        emptied: []const facts.InputPath,
    ) !void {
        if (exits.*) |*current| {
            const joined = try self.intersectInputPaths(current.items, emptied);
            current.clearRetainingCapacity();
            try current.appendSlice(joined);
        } else {
            var first = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
            try first.appendSlice(emptied);
            exits.* = first;
        }
    }

    fn removeOpaqueStorageRelease(
        self: *SafetyChecker,
        empties: *std.array_list.Managed(facts.InputPath),
        storage: facts.InputPath,
    ) void {
        _ = self;
        var index: usize = 0;
        while (index < empties.items.len) {
            if (inputPlaceTargetEqual(empties.items[index], storage)) {
                _ = empties.orderedRemove(index);
            } else index += 1;
        }
    }

    fn recordOpaqueStorageEffect(
        self: *SafetyChecker,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        storage: facts.InputPath,
        hidden: facts.ValueEffect,
    ) !void {
        const dependencies_only = try self.dependencyOnlyEffect(hidden);
        for (effects.items) |*existing| {
            if (!inputPlaceTargetEqual(existing.storage, storage)) continue;
            existing.hidden_dependencies = try self.mergeValueEffects(existing.hidden_dependencies, dependencies_only);
            return;
        }
        try effects.append(.{ .storage = storage, .hidden_dependencies = dependencies_only });
    }

    fn recordOpaqueStorageRelease(
        self: *SafetyChecker,
        empties: *std.array_list.Managed(facts.InputPath),
        storage: facts.InputPath,
    ) !void {
        _ = self;
        try appendInputPath(empties, storage);
    }

    fn removeOpaqueStorageEffects(
        self: *SafetyChecker,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        storage: facts.InputPath,
    ) void {
        _ = self;
        var index: usize = 0;
        while (index < effects.items.len) {
            if (inputPlaceTargetEqual(effects.items[index].storage, storage)) {
                _ = effects.orderedRemove(index);
            } else index += 1;
        }
    }

    fn dependencyOnlyEffect(self: *SafetyChecker, effect: facts.ValueEffect) !facts.ValueEffect {
        var owned_sources = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator.*);
        try self.collectFreshOwnedSources(effect, &owned_sources);
        return self.dependencyOnlyEffectExcludingOwned(effect, owned_sources.items);
    }

    fn collectFreshOwnedSources(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        sources: *std.array_list.Managed(facts.FreshEffectSource),
    ) !void {
        for (effect.fresh_owned_roots) |source| try appendFreshSource(sources, source);
        for (effect.fields) |field| try self.collectFreshOwnedSources(field.value.*, sources);
        for (effect.variants) |variant| try self.collectFreshOwnedSources(variant.value.*, sources);
    }

    fn dependencyOnlyEffectExcludingOwned(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        owned_sources: []const facts.FreshEffectSource,
    ) !facts.ValueEffect {
        const input_dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (input_dependencies) |*dependency| dependency.transfers_ownership = false;
        var fresh_dependencies = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator.*);
        for (effect.fresh_dependencies) |source| {
            var owned = false;
            for (owned_sources) |owned_source| if (owned_source == source) {
                owned = true;
                break;
            };
            if (!owned) try appendFreshSource(&fresh_dependencies, source);
        }
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.dependencyOnlyEffectExcludingOwned(field.value.*, owned_sources);
            fields[index] = .{ .index = field.index, .value = value };
        }
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, 0..) |variant, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.dependencyOnlyEffectExcludingOwned(variant.value.*, owned_sources);
            variants[index] = .{ .index = variant.index, .value = value };
        }
        return .{
            .input_dependencies = input_dependencies,
            .input_places = effect.input_places,
            .input_place_values = effect.input_place_values,
            .opaque_generation_dependencies = effect.opaque_generation_dependencies,
            .opaque_storage_dependencies = effect.opaque_storage_dependencies,
            .fields = fields,
            .variants = variants,
            .fresh_dependencies = try fresh_dependencies.toOwnedSlice(),
        };
    }

    fn joinInputPostStateBranch(
        self: *SafetyChecker,
        joined: *?std.array_list.Managed(facts.PlacePostState),
        branch: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (joined.*) |*previous| {
            var combined = std.array_list.Managed(facts.PlacePostState).init(self.allocator.*);
            try self.joinInputPostStates(&combined, previous, branch);
            previous.deinit();
            joined.* = combined;
        } else {
            joined.* = try cloneInputPostStates(branch, self.allocator.*);
        }
    }

    fn recordInputPostStateExit(
        self: *SafetyChecker,
        exits: *?std.array_list.Managed(facts.PlacePostState),
        states: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (exits.*) |*current| {
            var combined = std.array_list.Managed(facts.PlacePostState).init(self.allocator.*);
            try self.joinInputPostStates(&combined, current, states);
            current.deinit();
            current.* = combined;
        } else exits.* = try cloneInputPostStates(states, self.allocator.*);
    }

    fn copyInputPostStateFlow(
        self: *SafetyChecker,
        destination: *InputPostStateFlow,
        source: *const InputPostStateFlow,
    ) !void {
        _ = self;
        destination.states.clearRetainingCapacity();
        try destination.states.appendSlice(source.states.items);
        destination.reachable = source.reachable;
    }

    fn joinInputPostStateFallthrough(
        self: *SafetyChecker,
        destination: *InputPostStateFlow,
        left: *const InputPostStateFlow,
        right: *const InputPostStateFlow,
    ) !void {
        if (!left.reachable and !right.reachable) {
            destination.states.clearRetainingCapacity();
            destination.reachable = false;
        } else if (!left.reachable) {
            try self.copyInputPostStateFlow(destination, right);
        } else if (!right.reachable) {
            try self.copyInputPostStateFlow(destination, left);
        } else {
            try self.joinInputPostStates(&destination.states, &left.states, &right.states);
            destination.reachable = true;
        }
    }

    fn joinInputPostStateFlowBranch(
        self: *SafetyChecker,
        joined: *?InputPostStateFlow,
        branch: *const InputPostStateFlow,
    ) !void {
        if (joined.*) |*current| {
            var combined = InputPostStateFlow.init(self.allocator.*);
            try self.joinInputPostStateFallthrough(&combined, current, branch);
            current.deinit();
            current.* = combined;
        } else joined.* = try branch.clone(self.allocator.*);
    }

    fn recordInputPostState(self: *SafetyChecker, states: *std.array_list.Managed(facts.PlacePostState), targets: []const facts.InputPath, initializedness: value_state.Initializedness, value: facts.ValueEffect, ends_roots: bool, refreshes_storage_generation: bool, requires_available_destination: bool, may_repopulate_opaque_storage: bool) !void {
        _ = self;
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (inputPlaceTargetEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                const was_deinitialized = existing.initializedness != .initialized;
                existing.initializedness = initializedness;
                existing.value = value;
                existing.ends_previous_roots = existing.ends_previous_roots or ends_roots;
                existing.refreshes_storage_generation = existing.refreshes_storage_generation or refreshes_storage_generation or (was_deinitialized and initializedness == .initialized);
                existing.requires_available_destination = existing.requires_available_destination or requires_available_destination;
                existing.may_repopulate_opaque_storage = existing.may_repopulate_opaque_storage or may_repopulate_opaque_storage;
            } else try states.append(.{
                .target = target,
                .initializedness = initializedness,
                .value = value,
                .ends_previous_roots = ends_roots,
                .refreshes_storage_generation = refreshes_storage_generation,
                .requires_available_destination = requires_available_destination,
                .may_repopulate_opaque_storage = may_repopulate_opaque_storage,
            });
        }
    }

    fn recordOpaqueOwnershipConsumption(self: *SafetyChecker, states: *std.array_list.Managed(facts.PlacePostState), targets: []const facts.InputPath, consumption: facts.OpaqueOwnershipConsumption, storage: ?facts.InputPath) !void {
        _ = self;
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (inputPlaceTargetEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                // A later unconditional boundary dominates an earlier
                // conditional one on every path that reaches this point.
                existing.opaque_ownership = consumption;
                existing.opaque_storage = storage;
            } else {
                try states.append(.{
                    .target = target,
                    .initializedness = .initialized,
                    .opaque_ownership = consumption,
                    .opaque_storage = storage,
                });
            }
        }
    }

    fn joinInputPostStates(self: *SafetyChecker, destination: *std.array_list.Managed(facts.PlacePostState), left: *const std.array_list.Managed(facts.PlacePostState), right: *const std.array_list.Managed(facts.PlacePostState)) !void {
        var joined = std.array_list.Managed(facts.PlacePostState).init(self.allocator.*);
        for (left.items) |left_state| {
            var merged = left_state;
            if (findInputPostState(right.items, left_state.target)) |right_state| {
                merged.initializedness = joinInitializedness(left_state.initializedness, right_state.initializedness);
                merged.value = try self.mergeValueEffects(left_state.value, right_state.value);
                merged.ends_previous_roots = left_state.ends_previous_roots or right_state.ends_previous_roots;
                merged.refreshes_storage_generation = left_state.refreshes_storage_generation or right_state.refreshes_storage_generation;
                merged.requires_available_destination = left_state.requires_available_destination or right_state.requires_available_destination;
                merged.may_repopulate_opaque_storage = left_state.may_repopulate_opaque_storage or right_state.may_repopulate_opaque_storage;
                joinOpaqueOwnershipEffect(&merged, left_state, right_state);
            } else {
                if (left_state.initializedness != .initialized) {
                    merged.initializedness = .maybe_initialized;
                } else {
                    merged.value = try self.mergeValueEffects(left_state.value, try self.inputPlaceValueEffect(left_state.target));
                }
                const unchanged: facts.PlacePostState = .{ .target = left_state.target, .initializedness = .initialized };
                joinOpaqueOwnershipEffect(&merged, left_state, unchanged);
            }
            try joined.append(merged);
        }
        for (right.items) |right_state| if (findInputPostState(left.items, right_state.target) == null) {
            var merged = right_state;
            if (right_state.initializedness != .initialized) {
                merged.initializedness = .maybe_initialized;
            } else {
                merged.value = try self.mergeValueEffects(right_state.value, try self.inputPlaceValueEffect(right_state.target));
            }
            const unchanged: facts.PlacePostState = .{ .target = right_state.target, .initializedness = .initialized };
            joinOpaqueOwnershipEffect(&merged, unchanged, right_state);
            try joined.append(merged);
        };
        destination.clearRetainingCapacity();
        try destination.appendSlice(joined.items);
        joined.deinit();
    }

    fn replaceSingleOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.ValueEffect,
    ) !bool {
        const previous = self.summaries.get(function).?;
        if (previous.outputs.len != 1 or std.meta.eql(previous.outputs[0], effect)) return false;
        const outputs = try self.allocator.alloc(facts.ValueEffect, 1);
        outputs[0] = effect;
        try self.summaries.put(function, .{ .outputs = outputs });
        return true;
    }

    fn inferBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        outputs: []facts.ValueEffect,
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .binding_declaration => |binding| {
                const initialization = binding.initialization orelse continue;
                try self.inference_bindings.?.put(binding, try self.inferExpression(function, initialization));
                try self.inference_place_bindings.?.put(binding, try self.inferInputPaths(function, initialization));
            },
            .binding_assignment => |assignment| {
                const effect = try self.inferExpression(function, assignment.value);
                if (bindingIndex(function.output_bindings, assignment.sym_id)) |output_index| {
                    outputs[output_index] = if (outputs[output_index].variants.len != 0 or effect.variants.len != 0)
                        try self.mergeValueEffects(outputs[output_index], effect)
                    else
                        effect;
                } else {
                    try self.inference_bindings.?.put(assignment.sym_id, effect);
                    try self.inference_place_bindings.?.put(assignment.sym_id, try self.inferInputPaths(function, assignment.value));
                }
            },
            .if_statement => |statement| {
                try self.inferBlock(function, statement.then_block, outputs);
                if (statement.else_block) |else_block| try self.inferBlock(function, else_block, outputs);
            },
            .while_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .for_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .switch_statement => |statement| {
                for (statement.cases) |case| try self.inferBlock(function, case.body, outputs);
                if (statement.default_case) |default_case| try self.inferBlock(function, default_case, outputs);
            },
            else => {},
        };
    }

    fn inferExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
    ) anyerror!facts.ValueEffect {
        return switch (node.content) {
            .binding_use => |binding| if (inputIndex(function, binding)) |index|
                try self.inputValueEffect(@intCast(index), &.{})
            else if (self.inference_bindings) |bindings| bindings.get(binding) orelse .{} else .{},
            .move_value => |value| self.withOwnershipTransfer(try self.inferExpression(function, value)),
            .address_of => |value| .{ .input_places = try self.inferInputPaths(function, value) },
            .dereference => |value| try self.inferOpaqueRead(
                function,
                node,
                value.pointer,
                try self.inferExpression(function, value.pointer),
            ),
            .struct_value_literal => |literal| try self.inferAggregate(function, literal),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.choiceValueEffect(literal.variant_index, try self.inferExpression(function, payload))
            else
                try self.choiceValueEffect(literal.variant_index, .{}),
            .struct_field_access => |access| try self.inferOpaqueReadFromSyntax(
                function,
                node,
                try self.inferProjection(function, access.struct_value, .{ .field = access.field_index }),
            ),
            .choice_payload_access => |access| try self.inferOpaqueReadFromSyntax(
                function,
                node,
                try self.inferChoicePayload(function, access.choice_value, access.variant_index),
            ),
            .array_index => |index| try self.inferOpaqueRead(
                function,
                node,
                index.array_ptr,
                try self.inferProjection(function, index.array_ptr, if (staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index),
            ),
            .explicit_cast => |cast| try self.inferExpression(function, cast.value),
            .function_call => |call| try self.inferCall(function, call),
            .virtualize => |virtualize| try self.inferExpression(function, virtualize.value),
            .virtual_call => |call| try self.inferVirtualCall(function, call),
            else => .{},
        };
    }

    fn inferOpaqueRead(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        pointer: *const sg.SGNode,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = node.sem_type orelse return .{};
        // Loading a scalar produces a value independent of the Place that
        // contained it. In particular, an unresolved dynamic projection must
        // not substitute the owning facts of its container for the slot.
        if (!typeContainsPointer(ty)) return .{};
        const input_paths = try self.inferInputPaths(function, pointer);
        var pointee = effect;
        if (input_paths.len != 0) {
            pointee.input_dependencies = &.{};
            pointee.input_places = &.{};
            pointee.input_place_values = input_paths;
        }
        return self.withOpaqueReadGenerationDependencies(try self.symbolicSourcePaths(function, pointer, pointee), pointee);
    }

    fn withOpaqueReadGenerationDependencies(
        self: *SafetyChecker,
        accesses: []const facts.InputPath,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        var result = effect;
        var dependencies = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        try dependencies.appendSlice(effect.opaque_generation_dependencies);
        for (accesses) |path| try appendInputPath(&dependencies, path);
        result.opaque_generation_dependencies = try dependencies.toOwnedSlice();
        return result;
    }

    fn inferOpaqueReadFromSyntax(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = node.sem_type orelse return effect;
        if (!typeContainsPointer(ty)) return effect;
        return self.withOpaqueReadGenerationDependencies(try self.inferOpaqueReadInputPaths(function, node), effect);
    }

    fn inferOpaqueReadInputPaths(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
    ) ![]const facts.InputPath {
        return switch (node.content) {
            .move_value => |value| self.inferOpaqueReadInputPaths(function, value),
            .struct_field_access => |access| self.inferOpaqueReadInputPaths(function, access.struct_value),
            .choice_payload_access => |access| self.inferOpaqueReadInputPaths(function, access.choice_value),
            .dereference => |dereference| self.inferInputPaths(function, dereference.pointer),
            .array_index => |index| self.inferInputPaths(function, index.array_ptr),
            else => &.{},
        };
    }

    /// Pointer-producing summaries carry their source as an input Place when
    /// provenance is explicit, or as an input dependency for transparent
    /// wrappers such as identity functions. Turning those paths into opaque
    /// generation dependencies is deliberately deferred until a read occurs.
    fn opaqueGenerationSourcePaths(self: *SafetyChecker, effect: facts.ValueEffect) ![]const facts.InputPath {
        if (effect.input_places.len != 0) return effect.input_places;
        var paths = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (effect.input_dependencies) |dependency|
            try appendInputPath(&paths, dependency.path);
        return paths.toOwnedSlice();
    }

    fn symbolicSourcePaths(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        effect: facts.ValueEffect,
    ) ![]const facts.InputPath {
        const direct = try self.inferInputPaths(function, node);
        if (direct.len != 0) return direct;
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn inferInputPaths(self: *SafetyChecker, function: *const sg.FunctionDeclaration, node: *const sg.SGNode) anyerror![]const facts.InputPath {
        return switch (node.content) {
            .binding_use => |binding| if (inputIndex(function, binding)) |index|
                try self.oneInputPath(@intCast(index), &.{})
            else if (self.inference_place_bindings) |bindings| bindings.get(binding) orelse &.{} else &.{},
            .address_of => |value| try self.inferInputPaths(function, value),
            .dereference => |value| try self.inferInputPaths(function, value.pointer),
            .struct_field_access => |access| try self.projectInputPaths(try self.inferInputPaths(function, access.struct_value), .{ .field = access.field_index }),
            .array_index => |index| try self.projectInputPaths(try self.inferInputPaths(function, index.array_ptr), if (staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index),
            .explicit_cast => |cast| try self.inferInputPaths(function, cast.value),
            .move_value => |value| try self.inferInputPaths(function, value),
            else => &.{},
        };
    }

    fn projectInputPaths(self: *SafetyChecker, paths: []const facts.InputPath, projection: place.Projection) ![]const facts.InputPath {
        const result = try self.allocator.alloc(facts.InputPath, paths.len);
        for (paths, 0..) |path, index| {
            const projections = try self.allocator.alloc(place.Projection, path.projections.len + 1);
            @memcpy(projections[0..path.projections.len], path.projections);
            projections[path.projections.len] = projection;
            result[index] = .{ .input_index = path.input_index, .projections = projections };
        }
        return result;
    }

    fn substituteInputPath(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        path: facts.InputPath,
        arguments: []const sg.StructValueLiteralField,
    ) ![]const facts.InputPath {
        return self.substituteInputPathWithOverride(function, path, arguments, null);
    }

    fn substituteInputPathWithOverride(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        path: facts.InputPath,
        arguments: []const sg.StructValueLiteralField,
        symbolic_override: ?SymbolicInputOverride,
    ) ![]const facts.InputPath {
        if (path.input_index >= arguments.len) return &.{};
        if (symbolic_override) |override| if (override.input_index == path.input_index) {
            // The synthetic self denotes local storage. Only projections that
            // reach values stored inside it can escape through provenance.
            if (path.projections.len == 0) return &.{};
            var effect = override.effect;
            for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
            return self.opaqueGenerationSourcePaths(effect);
        };
        const argument = arguments[path.input_index].value;
        var direct = try self.inferInputPaths(function, argument);
        if (direct.len != 0) {
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            return direct;
        }
        var effect = try self.inferExpression(function, argument);
        for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn inferCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.FunctionCall) !facts.ValueEffect {
        if (call.callee.safety_primitive != .none) {
            const effect = try self.primitiveValueEffect(call.callee.safety_primitive, @intFromPtr(call));
            if (call.input.content != .struct_value_literal) return effect;
            return self.substituteOutput(function, effect, call.input.content.struct_value_literal.fields);
        }
        const callee_summary = self.summaries.get(call.callee) orelse return .{};
        if (callee_summary.outputs.len != 1 or call.input.content != .struct_value_literal) return .{};
        const substituted = try self.substituteOutput(function, callee_summary.outputs[0], call.input.content.struct_value_literal.fields);
        return self.rebaseFreshSources(substituted, @intFromPtr(call));
    }

    fn inferVirtualCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.VirtualCall) !facts.ValueEffect {
        const summary = try self.virtualSummary(call.safety_methods) orelse return .{};
        if (summary.outputs.len != 1 or call.input.content != .struct_value_literal) return .{};
        const substituted = try self.substituteOutput(function, summary.outputs[0], call.input.content.struct_value_literal.fields);
        return self.rebaseFreshSources(substituted, @intFromPtr(call));
    }

    fn rebaseFreshSources(self: *SafetyChecker, effect: facts.ValueEffect, call_site: usize) !facts.ValueEffect {
        const Context = struct { call_site: usize, source: facts.FreshEffectSource };
        var result = effect;
        const dependencies = try self.allocator.alloc(facts.FreshEffectSource, effect.fresh_dependencies.len);
        for (effect.fresh_dependencies, 0..) |source, index|
            dependencies[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_dependencies = dependencies;
        const owned_roots = try self.allocator.alloc(facts.FreshEffectSource, effect.fresh_owned_roots.len);
        for (effect.fresh_owned_roots, 0..) |source, index|
            owned_roots[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_owned_roots = owned_roots;
        const capabilities = try self.allocator.alloc(facts.FreshEffectSource, effect.fresh_storage_capabilities.len);
        for (effect.fresh_storage_capabilities, 0..) |source, index|
            capabilities[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_storage_capabilities = capabilities;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.rebaseFreshSources(field.value.*, call_site);
            fields[index] = .{ .index = field.index, .value = value };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, 0..) |variant, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.rebaseFreshSources(variant.value.*, call_site);
            variants[index] = .{ .index = variant.index, .value = value };
        }
        result.variants = variants;
        return result;
    }

    fn inputValueEffect(self: *SafetyChecker, input_index: u32, projections: []const place.Projection) !facts.ValueEffect {
        return .{ .input_dependencies = try self.oneInputDependency(input_index, projections) };
    }

    fn inputPlaceValueEffect(self: *SafetyChecker, target: facts.InputPath) !facts.ValueEffect {
        return .{ .input_place_values = try self.oneInputPath(target.input_index, target.projections) };
    }

    fn oneInputDependency(self: *SafetyChecker, input_index: u32, projections: []const place.Projection) ![]const facts.InputDependency {
        const dependencies = try self.allocator.alloc(facts.InputDependency, 1);
        dependencies[0] = .{ .path = .{ .input_index = input_index, .projections = projections } };
        return dependencies;
    }

    fn oneInputPath(self: *SafetyChecker, input_index: u32, projections: []const place.Projection) ![]const facts.InputPath {
        const paths = try self.allocator.alloc(facts.InputPath, 1);
        paths[0] = .{ .input_index = input_index, .projections = projections };
        return paths;
    }

    fn primitiveValueEffect(self: *SafetyChecker, primitive: sg.SafetyPrimitive, source: facts.FreshEffectSource) !facts.ValueEffect {
        return switch (primitive) {
            .none => .{},
            .relocate => .{},
            .establish_fresh_reference => .{ .fresh_dependencies = try self.oneFreshSource(source) },
            .establish_inherited_reference => self.inputValueEffect(1, &.{}),
            .establish_inherited_storage => self.inputValueEffect(1, &.{}),
            .establish_allocation => self.ownedAllocationEffect(source),
            .raw_allocated_storage => .{ .foreign_storage = true, .fresh_storage_capabilities = try self.oneFreshSource(source) },
            .reference_offset,
            .mutable_reference_offset,
            .reinterpret_reference,
            .mutable_reinterpret_reference,
            .read_reference,
            => self.inputValueEffect(0, &.{}),
            .restrict_reference => self.restrictReferenceEffect(),
            .trusted_opaque_move_out => .{
                .opaque_storage_dependencies = try self.oneInputPath(0, &.{}),
                .fresh_owned_roots = try self.oneFreshSource(source),
            },
            .trusted_opaque_move,
            .trusted_opaque_move_in,
            .trusted_opaque_relocate,
            .trusted_opaque_drop,
            .trusted_opaque_mark_empty,
            => .{},
        };
    }

    /// Restriction retains every fact of the input reference and appends the
    /// storage generation of the lifetime Place. `input_places` preserves the
    /// input reference's provenance; neither root ownership nor capability is
    /// transferred by either dependency.
    fn restrictReferenceEffect(self: *SafetyChecker) !facts.ValueEffect {
        var result = try self.inputValueEffect(0, &.{});
        result = try self.mergeValueEffects(result, try self.inputValueEffect(1, &.{}));
        result.input_places = try self.oneInputPath(0, &.{});
        return result;
    }

    fn ownedAllocationEffect(self: *SafetyChecker, source: facts.FreshEffectSource) !facts.ValueEffect {
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, 3);
        const data = try self.allocator.create(facts.ValueEffect);
        data.* = .{ .fresh_dependencies = try self.oneFreshSource(source) };
        const size = try self.allocator.create(facts.ValueEffect);
        size.* = .{};
        const allocator = try self.allocator.create(facts.ValueEffect);
        allocator.* = try self.inputValueEffect(2, &.{});
        fields[0] = .{ .index = 0, .value = data };
        fields[1] = .{ .index = 1, .value = size };
        fields[2] = .{ .index = 2, .value = allocator };
        return .{
            .fresh_owned_roots = try self.oneFreshSource(source),
            .fields = fields,
        };
    }

    fn withOwnershipTransfer(self: *SafetyChecker, effect: facts.ValueEffect) facts.ValueEffect {
        _ = self;
        for (effect.input_dependencies) |*dependency| @constCast(dependency).transfers_ownership = true;
        return effect;
    }

    fn withoutOwnershipTransfer(self: *SafetyChecker, effect: facts.ValueEffect) !facts.ValueEffect {
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = false;
        var result = effect;
        result.input_dependencies = dependencies;
        return result;
    }

    fn inferAggregate(self: *SafetyChecker, function: *const sg.FunctionDeclaration, literal: *const sg.StructValueLiteral) !facts.ValueEffect {
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, literal.fields.len);
        var result: facts.ValueEffect = .{};
        for (literal.fields, 0..) |field, position| {
            var field_index: ?u32 = null;
            for (literal.ty.struct_type.fields, 0..) |type_field, index| {
                if (!std.mem.eql(u8, field.name, type_field.name)) continue;
                field_index = @intCast(index);
                break;
            }
            // Struct literals have already been semantized against their
            // declared type. Keep facts keyed by that type's field index,
            // rather than by the incidental order in which the literal wrote
            // its named fields.
            const semantic_index = field_index orelse return error.InvalidType;
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.inferExpression(function, field.value);
            output_fields[position] = .{ .index = semantic_index, .value = value };
            result = try self.mergeValueEffects(result, value.*);
            // A struct contains the choice; it is not itself refined by the
            // tags of choice-valued fields.
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields;
        return result;
    }

    fn choiceValue(self: *SafetyChecker, variant_index: u32, payload: facts.ValueFacts) !facts.ValueFacts {
        const variants = try self.allocator.alloc(facts.VariantFacts, 1);
        const stored = try self.allocator.create(facts.ValueFacts);
        stored.* = payload;
        variants[0] = .{ .index = variant_index, .value = stored };
        return .{ .variants = variants, .known_choice_variant = variant_index };
    }

    fn choiceValueEffect(self: *SafetyChecker, variant_index: u32, payload: facts.ValueEffect) !facts.ValueEffect {
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, 1);
        const stored = try self.allocator.create(facts.ValueEffect);
        stored.* = payload;
        variants[0] = .{ .index = variant_index, .value = stored };
        return .{ .variants = variants, .known_choice_variant = variant_index };
    }

    fn inferProjection(self: *SafetyChecker, function: *const sg.FunctionDeclaration, base_node: *const sg.SGNode, projection: place.Projection) !facts.ValueEffect {
        return self.projectValueEffect(try self.inferExpression(function, base_node), projection);
    }

    fn inferChoicePayload(self: *SafetyChecker, function: *const sg.FunctionDeclaration, base_node: *const sg.SGNode, variant_index: u32) !facts.ValueEffect {
        const effect = try self.inferExpression(function, base_node);
        for (effect.variants) |variant| if (variant.index == variant_index) return variant.value.*;
        return .{};
    }

    fn projectValueEffect(self: *SafetyChecker, effect: facts.ValueEffect, projection: place.Projection) !facts.ValueEffect {
        if (projection == .field) {
            for (effect.fields) |field| if (field.index == projection.field) return field.value.*;
        }
        const dependencies = try self.allocator.alloc(facts.InputDependency, effect.input_dependencies.len);
        for (effect.input_dependencies, 0..) |dependency, index| {
            const projections = try self.allocator.alloc(place.Projection, dependency.path.projections.len + 1);
            @memcpy(projections[0..dependency.path.projections.len], dependency.path.projections);
            projections[dependency.path.projections.len] = projection;
            dependencies[index] = dependency;
            dependencies[index].path.projections = projections;
        }
        const input_places = try self.projectInputPaths(effect.input_places, projection);
        const input_place_values = try self.projectInputPaths(effect.input_place_values, projection);
        return .{
            .input_dependencies = dependencies,
            .input_places = input_places,
            .input_place_values = input_place_values,
            .opaque_generation_dependencies = effect.opaque_generation_dependencies,
            .opaque_storage_dependencies = effect.opaque_storage_dependencies,
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
    }

    fn substituteOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.ValueEffect,
        arguments: []const sg.StructValueLiteralField,
    ) !facts.ValueEffect {
        return self.substituteOutputWithOverride(function, effect, arguments, null);
    }

    fn substituteOutputWithOverride(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.ValueEffect,
        arguments: []const sg.StructValueLiteralField,
        symbolic_override: ?SymbolicInputOverride,
    ) !facts.ValueEffect {
        var result: facts.ValueEffect = .{
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteInputPathWithOverride(function, path, arguments, symbolic_override);
            for (substituted) |candidate| try appendInputPath(&input_places, candidate);
        }
        result.input_places = try input_places.toOwnedSlice();
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        var input_place_value_overrides: facts.ValueEffect = .{};
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            if (symbolic_override) |override| if (override.input_index == path.input_index) {
                var value = override.effect;
                for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
                input_place_value_overrides = try self.mergeValueEffects(input_place_value_overrides, value);
                continue;
            };
            const substituted = try self.substituteInputPathWithOverride(function, path, arguments, symbolic_override);
            for (substituted) |candidate| try appendInputPath(&input_place_values, candidate);
        }
        result.input_place_values = try input_place_values.toOwnedSlice();
        result = try self.mergeValueEffects(result, input_place_value_overrides);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (effect.opaque_generation_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteInputPathWithOverride(function, path, arguments, symbolic_override);
            for (substituted) |candidate| try appendInputPath(&opaque_generations, candidate);
        }
        result.opaque_generation_dependencies = try opaque_generations.toOwnedSlice();
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (effect.opaque_storage_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteInputPathWithOverride(function, path, arguments, symbolic_override);
            for (substituted) |candidate| try appendInputPath(&opaque_storages, candidate);
        }
        result.opaque_storage_dependencies = try opaque_storages.toOwnedSlice();
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            if (symbolic_override) |override| if (override.input_index == dependency.path.input_index and dependency.path.projections.len == 0)
                continue;
            var argument = if (symbolic_override) |override|
                if (override.input_index == dependency.path.input_index) override.effect else try self.inferExpression(function, arguments[dependency.path.input_index].value)
            else
                try self.inferExpression(function, arguments[dependency.path.input_index].value);
            for (dependency.path.projections) |projection| argument = try self.projectValueEffect(argument, projection);
            if (dependency.transfers_ownership) argument = self.withOwnershipTransfer(argument) else argument = try self.withoutOwnershipTransfer(argument);
            result = try self.mergeValueEffects(result, argument);
        }
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function, field.value.*, arguments, symbolic_override);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function, variant.value.*, arguments, symbolic_override);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn mergeValueEffects(self: *SafetyChecker, left: facts.ValueEffect, right: facts.ValueEffect) !facts.ValueEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator.*);
        for (left.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        for (right.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.input_places) |path| try appendInputPath(&input_places, path);
        for (right.input_places) |path| try appendInputPath(&input_places, path);
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.input_place_values) |path| try appendInputPath(&input_place_values, path);
        for (right.input_place_values) |path| try appendInputPath(&input_place_values, path);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.opaque_generation_dependencies) |path| try appendInputPath(&opaque_generations, path);
        for (right.opaque_generation_dependencies) |path| try appendInputPath(&opaque_generations, path);
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.opaque_storage_dependencies) |path| try appendInputPath(&opaque_storages, path);
        for (right.opaque_storage_dependencies) |path| try appendInputPath(&opaque_storages, path);
        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator.*);
        for (left.fields) |left_field| {
            var merged = left_field.value.*;
            for (right.fields) |right_field| if (right_field.index == left_field.index) {
                merged = try self.mergeValueEffects(merged, right_field.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueEffect);
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
        var variants = std.array_list.Managed(facts.OutputVariantEffect).init(self.allocator.*);
        for (left.variants) |left_variant| {
            var merged = left_variant.value.*;
            for (right.variants) |right_variant| if (right_variant.index == left_variant.index) {
                merged = try self.mergeValueEffects(merged, right_variant.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.ValueEffect);
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
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_places = try input_places.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .opaque_generation_dependencies = try opaque_generations.toOwnedSlice(),
            .opaque_storage_dependencies = try opaque_storages.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .fresh_dependencies = try self.mergeFreshSources(left.fresh_dependencies, right.fresh_dependencies),
            .fresh_owned_roots = try self.mergeFreshSources(left.fresh_owned_roots, right.fresh_owned_roots),
            .fresh_storage_capabilities = try self.mergeFreshSources(left.fresh_storage_capabilities, right.fresh_storage_capabilities),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .variants = try variants.toOwnedSlice(),
            .known_choice_variant = if (left.variants.len == 0)
                right.known_choice_variant
            else if (right.variants.len == 0)
                left.known_choice_variant
            else if (left.known_choice_variant == right.known_choice_variant)
                left.known_choice_variant
            else
                null,
        };
    }
};

fn bindingIndex(bindings: []const *const sg.BindingDeclaration, target: *const sg.BindingDeclaration) ?usize {
    for (bindings, 0..) |binding, index| {
        if (binding == target or std.mem.eql(u8, binding.name, target.name)) return index;
    }
    return null;
}

fn alignFreshSources(
    canonical: []const facts.FreshEffectSource,
    candidate: []const facts.FreshEffectSource,
    mapping: *std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource),
) !bool {
    for (canonical, candidate) |canonical_source, candidate_source| {
        if (mapping.get(candidate_source)) |existing| {
            if (existing != canonical_source) return false;
        } else {
            var iterator = mapping.iterator();
            while (iterator.next()) |entry| {
                if (entry.value_ptr.* == canonical_source and entry.key_ptr.* != candidate_source) return false;
            }
            try mapping.put(candidate_source, canonical_source);
        }
    }
    return true;
}

fn containsInputDependency(haystack: []const facts.InputDependency, needle: facts.InputDependency) bool {
    for (haystack) |candidate| {
        if (candidate.path.input_index == needle.path.input_index and
            candidate.transfers_ownership == needle.transfers_ownership and
            projectionsEqual(candidate.path.projections, needle.path.projections)) return true;
    }
    return false;
}

fn findPlace(places: []const facts.PlaceFacts, storage: place.Place) ?*const facts.PlaceFacts {
    for (places) |*candidate| if (candidate.storage.eql(storage)) return candidate;
    return null;
}

fn findField(fields: []const facts.FieldFacts, index: u32) ?facts.FieldFacts {
    for (fields) |field| if (field.index == index) return field;
    return null;
}

fn findVariant(variants: []const facts.VariantFacts, index: u32) ?facts.VariantFacts {
    for (variants) |variant| if (variant.index == index) return variant;
    return null;
}

fn containsRoot(roots: []const facts.ValidityRootId, target: facts.ValidityRootId) bool {
    for (roots) |root| if (root == target) return true;
    return false;
}

fn collectOwnedRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.ValidityRootId)) !void {
    for (value.owned_roots) |root| try appendOwnedRoot(roots, root);
    for (value.fields) |field| try collectOwnedRoots(field.value.*, roots);
    for (value.variants) |variant| try collectOwnedRoots(variant.value.*, roots);
}

fn hasExternalOpaqueDependency(value: facts.ValueFacts, owned: []const facts.ValidityRootId) bool {
    for (value.dependencies) |dependency| if (!containsRoot(owned, dependency.root)) return true;
    for (value.fields) |field| if (hasExternalOpaqueDependency(field.value.*, owned)) return true;
    for (value.variants) |variant| if (hasExternalOpaqueDependency(variant.value.*, owned)) return true;
    return false;
}

fn valueContainsOwnedRoot(value: facts.ValueFacts, target: facts.ValidityRootId) bool {
    if (containsRoot(value.owned_roots, target)) return true;
    for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, target)) return true;
    for (value.variants) |variant| if (valueContainsOwnedRoot(variant.value.*, target)) return true;
    return false;
}

fn valueContainsOpaqueGeneration(value: facts.ValueFacts, storage: place.Place, root: facts.ValidityRootId) bool {
    for (value.opaque_provenance) |provenance|
        if (provenance.generation == root and provenance.storage.eql(storage)) return true;
    for (value.fields) |field| if (valueContainsOpaqueGeneration(field.value.*, storage, root)) return true;
    for (value.variants) |variant| if (valueContainsOpaqueGeneration(variant.value.*, storage, root)) return true;
    return false;
}

fn valueDependsOnRoot(value: facts.ValueFacts, target: facts.ValidityRootId) bool {
    for (value.dependencies) |dependency| if (dependency.root == target) return true;
    for (value.fields) |field| if (valueDependsOnRoot(field.value.*, target)) return true;
    for (value.variants) |variant| if (valueDependsOnRoot(variant.value.*, target)) return true;
    return false;
}

fn valueHasDependency(value: facts.ValueFacts) bool {
    if (value.dependencies.len != 0) return true;
    for (value.fields) |field| if (valueHasDependency(field.value.*)) return true;
    for (value.variants) |variant| if (valueHasDependency(variant.value.*)) return true;
    return false;
}

fn collectDependencyRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.ValidityRootId)) !void {
    for (value.dependencies) |dependency| try appendOwnedRoot(roots, dependency.root);
    for (value.fields) |field| try collectDependencyRoots(field.value.*, roots);
    for (value.variants) |variant| try collectDependencyRoots(variant.value.*, roots);
}

/// Activating a choice alternative realizes facts that belong directly to it
/// and its simultaneous fields. Nested variants remain conditional because
/// their runtime tag has not been tested yet.
fn activateConditionalFacts(value: facts.ValueFacts, state: *SafetyChecker.FunctionState) void {
    for (value.dependencies) |dependency| {
        const root = &state.tracker.roots.items[@intFromEnum(dependency.root)];
        if (root.state == .conditional) root.state = .alive;
    }
    for (value.owned_roots) |owned_root| {
        const root = &state.tracker.roots.items[@intFromEnum(owned_root)];
        if (root.state == .conditional) root.state = .alive;
    }
    for (value.storage_capabilities) |capability| {
        const capability_state = &state.storage_capabilities.items[@intFromEnum(capability)];
        if (capability_state.* == .conditional) capability_state.* = .available;
    }
    for (value.fields) |field| activateConditionalFacts(field.value.*, state);
}

/// Rejecting a choice alternative makes every fact exclusively contained by
/// it impossible, including facts below nested choices whose tags can no
/// longer be reached.
fn rejectConditionalFacts(value: facts.ValueFacts, state: *SafetyChecker.FunctionState) void {
    for (value.dependencies) |dependency| {
        const root = &state.tracker.roots.items[@intFromEnum(dependency.root)];
        if (root.state == .conditional) root.state = .dead;
    }
    for (value.owned_roots) |owned_root| {
        const root = &state.tracker.roots.items[@intFromEnum(owned_root)];
        if (root.state == .conditional) root.state = .dead;
    }
    for (value.storage_capabilities) |capability| {
        const capability_state = &state.storage_capabilities.items[@intFromEnum(capability)];
        if (capability_state.* == .conditional) capability_state.* = .consumed;
    }
    for (value.fields) |field| rejectConditionalFacts(field.value.*, state);
    for (value.variants) |variant| rejectConditionalFacts(variant.value.*, state);
}

fn appendOwnershipEdge(
    edges: *std.array_list.Managed(SafetyChecker.FunctionState.OwnershipEdge),
    candidate: SafetyChecker.FunctionState.OwnershipEdge,
) !void {
    for (edges.items) |edge| if (edge.owner == candidate.owner and edge.owned == candidate.owned) return;
    try edges.append(candidate);
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

fn ownershipPathExistsFrom(
    state: *const SafetyChecker.FunctionState,
    current: facts.ValidityRootId,
    target: facts.ValidityRootId,
    remaining: usize,
) bool {
    if (current == target) return true;
    if (remaining == 0) return false;
    for (state.ownership_edges.items) |edge| {
        if (edge.owner == current and ownershipPathExistsFrom(state, edge.owned, target, remaining - 1)) return true;
    }
    return false;
}

fn isLocalStorageGeneration(
    function: *const sg.FunctionDeclaration,
    state: *const SafetyChecker.FunctionState,
    root: facts.ValidityRootId,
) bool {
    if (containsRoot(state.lexical_storage_generations.items, root)) return true;
    for (state.storage_generations.items) |entry| {
        if (entry.generation != root) continue;
        return bindingIndex(function.input_bindings, entry.storage.root) == null;
    }
    return false;
}

fn typeContainsPointer(ty: sg.Type) bool {
    return switch (ty) {
        .pointer_type => true,
        .array_type => |array| typeContainsPointer(array.element_type.*),
        .struct_type => |struct_type| blk: {
            for (struct_type.fields) |field| if (typeContainsPointer(field.ty)) break :blk true;
            break :blk false;
        },
        .choice_type => |choice| blk: {
            for (choice.variants) |variant| if (variant.payload_type) |payload|
                if (typeContainsPointer(payload)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn joinInitializedness(left: value_state.Initializedness, right: value_state.Initializedness) value_state.Initializedness {
    if (left == right) return left;
    return .maybe_initialized;
}

fn statesEqual(left: *const SafetyChecker.FunctionState, right: *const SafetyChecker.FunctionState) bool {
    if (left.reachable != right.reachable or
        left.ownership_conflict_reported != right.ownership_conflict_reported or
        left.tracker.roots.items.len != right.tracker.roots.items.len or
        left.lexical_storage_generations.items.len != right.lexical_storage_generations.items.len or
        left.places.items.len != right.places.items.len or
        left.ownership_edges.items.len != right.ownership_edges.items.len or
        left.opaque_storages.items.len != right.opaque_storages.items.len or
        left.choice_active.items.len != right.choice_active.items.len or
        left.choice_rejected.items.len != right.choice_rejected.items.len or
        left.choice_temporary_active.items.len != right.choice_temporary_active.items.len) return false;
    for (left.tracker.roots.items, right.tracker.roots.items) |a, b|
        if (a.state != b.state or a.owned_resource != b.owned_resource) return false;
    for (left.lexical_storage_generations.items) |root|
        if (!containsRoot(right.lexical_storage_generations.items, root)) return false;
    for (left.places.items) |left_place| {
        const right_place = findPlace(right.places.items, left_place.storage) orelse return false;
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
    for (left.opaque_storages.items) |opaque_storage| {
        var matching: ?SafetyChecker.FunctionState.OpaqueStorage = null;
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
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len or
        left.variants.len != right.variants.len) return false;
    for (left.dependencies, right.dependencies) |a, b| if (a.root != b.root) return false;
    for (left.owned_roots, right.owned_roots) |a, b| if (a != b) return false;
    if ((left.referenced_place == null) != (right.referenced_place == null)) return false;
    if (left.referenced_place) |left_place| if (!left_place.eql(right.referenced_place.?)) return false;
    if (left.opaque_provenance.len != right.opaque_provenance.len) return false;
    for (left.opaque_provenance, right.opaque_provenance) |a, b|
        if (!a.storage.eql(b.storage) or a.generation != b.generation) return false;
    for (left.fields, right.fields) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    for (left.variants, right.variants) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    return true;
}

fn inputIndex(function: *const sg.FunctionDeclaration, target: *const sg.BindingDeclaration) ?usize {
    if (bindingIndex(function.input_bindings, target)) |index| return index;
    for (function.input.fields, 0..) |field, index| {
        if (std.mem.eql(u8, field.name, target.name)) return index;
    }
    return null;
}

fn effectsEqual(left: []const facts.ValueEffect, right: []const facts.ValueEffect) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!outputEffectEqual(a, b)) return false;
    return true;
}

fn inputDependencyEqual(left: facts.InputDependency, right: facts.InputDependency) bool {
    if (left.path.input_index != right.path.input_index or left.transfers_ownership != right.transfers_ownership or
        left.path.projections.len != right.path.projections.len) return false;
    for (left.path.projections, right.path.projections) |a, b| if (!a.eql(b)) return false;
    return true;
}

fn outputEffectHasFreshRole(effect: facts.ValueEffect) bool {
    if (effect.fresh_dependencies.len != 0 or effect.fresh_owned_roots.len != 0 or
        effect.fresh_storage_capabilities.len != 0) return true;
    for (effect.fields) |field| if (outputEffectHasFreshRole(field.value.*)) return true;
    for (effect.variants) |variant| if (outputEffectHasFreshRole(variant.value.*)) return true;
    return false;
}

fn outputEffectTransfersOwnership(effect: facts.ValueEffect) bool {
    for (effect.input_dependencies) |dependency| if (dependency.transfers_ownership) return true;
    for (effect.fields) |field| if (outputEffectTransfersOwnership(field.value.*)) return true;
    for (effect.variants) |variant| if (outputEffectTransfersOwnership(variant.value.*)) return true;
    return false;
}

fn findInputPostState(states: []const facts.PlacePostState, target: facts.InputPath) ?facts.PlacePostState {
    for (states) |state| if (inputPlaceTargetEqual(state.target, target)) return state;
    return null;
}

fn inputPostStatesEqual(left: []const facts.PlacePostState, right: []const facts.PlacePostState) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!inputPlaceTargetEqual(a.target, b.target) or a.initializedness != b.initializedness or
            a.ends_previous_roots != b.ends_previous_roots or a.refreshes_storage_generation != b.refreshes_storage_generation or
            a.requires_available_destination != b.requires_available_destination or
            a.may_repopulate_opaque_storage != b.may_repopulate_opaque_storage or
            a.opaque_ownership != b.opaque_ownership or
            !optionalInputPathEqual(a.opaque_storage, b.opaque_storage) or
            !outputEffectEqual(a.value, b.value)) return false;
    }
    return true;
}

fn inputPathsEqual(left: []const facts.InputPath, right: []const facts.InputPath) bool {
    if (left.len != right.len) return false;
    for (left) |path| {
        var found = false;
        for (right) |other| if (inputPlaceTargetEqual(path, other)) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn opaqueStorageEffectsEqual(left: []const facts.OpaqueStorageEffect, right: []const facts.OpaqueStorageEffect) bool {
    if (left.len != right.len) return false;
    for (left) |effect| {
        var found = false;
        for (right) |other| {
            if (!inputPlaceTargetEqual(effect.storage, other.storage)) continue;
            if (!outputEffectEqual(effect.hidden_dependencies, other.hidden_dependencies)) return false;
            found = true;
            break;
        }
        if (!found) return false;
    }
    return true;
}

fn summaryMayRepopulateOpaqueStorage(summary: facts.SafetySummary) bool {
    for (summary.input_post_states) |post_state| {
        if (post_state.opaque_ownership == .none and
            post_state.initializedness == .initialized and
            post_state.may_repopulate_opaque_storage) return true;
    }
    return false;
}

fn inputPlaceTargetEqual(left: facts.InputPath, right: facts.InputPath) bool {
    return left.input_index == right.input_index and projectionsEqual(left.projections, right.projections);
}

fn optionalInputPathEqual(left: ?facts.InputPath, right: ?facts.InputPath) bool {
    if ((left == null) != (right == null)) return false;
    return if (left) |path| inputPlaceTargetEqual(path, right.?) else true;
}

fn cloneInputPostStates(source: *const std.array_list.Managed(facts.PlacePostState), allocator: std.mem.Allocator) !std.array_list.Managed(facts.PlacePostState) {
    var result = std.array_list.Managed(facts.PlacePostState).init(allocator);
    try result.appendSlice(source.items);
    return result;
}

fn projectValueFacts(value: facts.ValueFacts, projections: []const place.Projection) facts.ValueFacts {
    var current = value;
    for (projections) |projection| switch (projection) {
        .field => |index| {
            var projected = false;
            for (current.fields) |field| if (field.index == index) {
                current = field.value.*;
                projected = true;
                break;
            };
            if (!projected) for (current.variants) |variant| if (variant.index == index) {
                current = variant.value.*;
                break;
            };
        },
        .static_index => |index| {
            for (current.fields) |field| if (field.index == index) {
                current = field.value.*;
                break;
            };
        },
        .dynamic_index, .dereference => {},
    };
    return current;
}

fn appendDependency(list: *std.array_list.Managed(facts.ValidityDependency), dependency: facts.ValidityDependency) !void {
    for (list.items) |existing| if (existing.root == dependency.root) return;
    try list.append(dependency);
}

fn appendPlace(list: *std.array_list.Managed(place.Place), storage: place.Place) !void {
    for (list.items) |existing| if (existing.eql(storage)) return;
    try list.append(storage);
}

fn appendOpaqueProvenance(list: *std.array_list.Managed(facts.OpaqueProvenance), provenance: facts.OpaqueProvenance) !void {
    for (list.items) |existing|
        if (existing.generation == provenance.generation and existing.storage.eql(provenance.storage)) return;
    try list.append(provenance);
}

fn appendOwnedRoot(list: *std.array_list.Managed(facts.ValidityRootId), owned_root: facts.ValidityRootId) !void {
    for (list.items) |existing| if (existing == owned_root) return;
    try list.append(owned_root);
}

fn appendStorageCapability(list: *std.array_list.Managed(facts.StorageCapabilityId), capability: facts.StorageCapabilityId) !void {
    for (list.items) |existing| if (existing == capability) return;
    try list.append(capability);
}

fn appendInputDependency(list: *std.array_list.Managed(facts.InputDependency), dependency: facts.InputDependency) !void {
    for (list.items) |existing| {
        if (existing.path.input_index != dependency.path.input_index or existing.transfers_ownership != dependency.transfers_ownership) continue;
        if (projectionsEqual(existing.path.projections, dependency.path.projections)) return;
    }
    try list.append(dependency);
}

fn appendInputPath(list: *std.array_list.Managed(facts.InputPath), path: facts.InputPath) !void {
    for (list.items) |existing|
        if (existing.input_index == path.input_index and projectionsEqual(existing.projections, path.projections)) return;
    try list.append(path);
}

fn appendFreshSource(list: *std.array_list.Managed(facts.FreshEffectSource), source: facts.FreshEffectSource) !void {
    for (list.items) |existing| if (existing == source) return;
    try list.append(source);
}

fn joinOpaqueOwnershipEffect(
    merged: *facts.PlacePostState,
    left: facts.PlacePostState,
    right: facts.PlacePostState,
) void {
    const left_ownership = left.opaque_ownership;
    const right_ownership = right.opaque_ownership;
    if (left_ownership == .ambiguous or right_ownership == .ambiguous) {
        merged.opaque_ownership = .ambiguous;
        merged.opaque_storage = null;
        return;
    }
    if (left_ownership == .none and right_ownership == .none) {
        merged.opaque_ownership = .none;
        merged.opaque_storage = null;
        return;
    }

    const left_storage = if (left_ownership == .none) right.opaque_storage else left.opaque_storage;
    const right_storage = if (right_ownership == .none) left.opaque_storage else right.opaque_storage;
    if (!optionalInputPathEqual(left_storage, right_storage)) {
        merged.opaque_ownership = .ambiguous;
        merged.opaque_storage = null;
        return;
    }

    merged.opaque_storage = left_storage;
    if (left_ownership == .none or right_ownership == .none or
        left_ownership == .conditional or right_ownership == .conditional)
    {
        merged.opaque_ownership = .conditional;
    } else {
        merged.opaque_ownership = .definite;
    }
}

fn mergeVirtualOpaqueOwnershipEffect(
    merged: *facts.PlacePostState,
    left: facts.PlacePostState,
    right: facts.PlacePostState,
) bool {
    const left_ownership = left.opaque_ownership;
    const right_ownership = right.opaque_ownership;
    if (left_ownership == .ambiguous or right_ownership == .ambiguous) return false;
    if (left_ownership == .none and right_ownership == .none) {
        merged.opaque_ownership = .none;
        merged.opaque_storage = null;
        return true;
    }

    const left_storage = if (left_ownership == .none) right.opaque_storage else left.opaque_storage;
    const right_storage = if (right_ownership == .none) left.opaque_storage else right.opaque_storage;
    if (!optionalInputPathEqual(left_storage, right_storage)) return false;
    merged.opaque_storage = left_storage;
    merged.opaque_ownership = if (left_ownership == .none or right_ownership == .none or
        left_ownership == .conditional or right_ownership == .conditional)
        .conditional
    else
        .definite;
    return true;
}

fn projectionsEqual(left: []const place.Projection, right: []const place.Projection) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!a.eql(b)) return false;
    return true;
}

fn outputEffectEqual(left: facts.ValueEffect, right: facts.ValueEffect) bool {
    if (left.known_choice_variant != right.known_choice_variant or
        left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        !std.mem.eql(facts.FreshEffectSource, left.fresh_dependencies, right.fresh_dependencies) or
        !std.mem.eql(facts.FreshEffectSource, left.fresh_owned_roots, right.fresh_owned_roots) or
        !std.mem.eql(facts.FreshEffectSource, left.fresh_storage_capabilities, right.fresh_storage_capabilities)) return false;
    if (left.input_dependencies.len != right.input_dependencies.len or
        left.input_places.len != right.input_places.len or
        left.input_place_values.len != right.input_place_values.len or
        left.opaque_generation_dependencies.len != right.opaque_generation_dependencies.len or
        left.opaque_storage_dependencies.len != right.opaque_storage_dependencies.len or
        left.fields.len != right.fields.len or left.variants.len != right.variants.len) return false;
    for (left.input_dependencies, right.input_dependencies) |a, b| {
        if (!inputDependencyEqual(a, b)) return false;
    }
    for (left.input_places, right.input_places) |a, b| if (!inputPlaceTargetEqual(a, b)) return false;
    for (left.input_place_values, right.input_place_values) |a, b| if (!inputPlaceTargetEqual(a, b)) return false;
    for (left.opaque_generation_dependencies, right.opaque_generation_dependencies) |a, b|
        if (!inputPlaceTargetEqual(a, b)) return false;
    for (left.opaque_storage_dependencies, right.opaque_storage_dependencies) |a, b|
        if (!inputPlaceTargetEqual(a, b)) return false;
    for (left.fields, right.fields) |a, b| {
        if (a.index != b.index or !outputEffectEqual(a.value.*, b.value.*)) return false;
    }
    for (left.variants, right.variants) |a, b| {
        if (a.index != b.index or !outputEffectEqual(a.value.*, b.value.*)) return false;
    }
    return true;
}

fn rootBinding(node: *const sg.SGNode) ?*const sg.BindingDeclaration {
    return switch (node.content) {
        .binding_use => |binding| binding,
        .struct_field_access => |access| rootBinding(access.struct_value),
        .array_index => |index| rootBinding(index.array_ptr),
        .dereference => |dereference| rootBinding(dereference.pointer),
        .address_of => |value| rootBinding(value),
        else => null,
    };
}

/// These nodes all route their operand through `evaluatePointerUse` locally;
/// summary inference consumes the same classification symbolically.
fn pointerUseOperand(node: *const sg.SGNode) ?*const sg.SGNode {
    return switch (node.content) {
        .dereference => |dereference| dereference.pointer,
        .array_index => |index| index.array_ptr,
        .array_store => |store| store.array_ptr,
        .struct_field_store => |store| store.struct_ptr,
        else => null,
    };
}

fn staticIndex(node: *const sg.SGNode) ?usize {
    if (node.content != .value_literal) return null;
    return switch (node.content.value_literal) {
        .int_literal => |index| if (index >= 0) @intCast(index) else null,
        else => null,
    };
}

test "virtual summaries require exact ownership and align fresh root roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const left_source: facts.FreshEffectSource = 11;
    const right_source: facts.FreshEffectSource = 29;
    const compatible = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{
            .fresh_dependencies = &.{left_source},
            .fresh_owned_roots = &.{left_source},
        }} },
        .{ .outputs = &.{.{
            .fresh_dependencies = &.{right_source},
            .fresh_owned_roots = &.{right_source},
        }} },
    );
    try std.testing.expect(compatible != null);
    try std.testing.expectEqual(left_source, compatible.?.outputs[0].fresh_dependencies[0]);
    try std.testing.expectEqual(left_source, compatible.?.outputs[0].fresh_owned_roots[0]);

    const incompatible = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .fresh_owned_roots = &.{left_source} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(incompatible == null);
}

test "virtual summaries reject destructive input state and require exact ownership transfer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const transfer = facts.InputDependency{ .path = .{ .input_index = 0 }, .transfers_ownership = true };
    const transfer_mismatch = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .input_dependencies = &.{transfer} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(transfer_mismatch == null);

    const deinit_alternative = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .deinitialized,
            .ends_previous_roots = true,
        }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(deinit_alternative == null);

    const opaque_mismatch = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .initialized,
            .opaque_ownership = .definite,
        }} },
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .initialized,
            .opaque_ownership = .conditional,
            .opaque_storage = .{ .input_index = 1 },
        }} },
    );
    try std.testing.expect(opaque_mismatch == null);
}

test "virtual input post states merge absent targets and caller-visible effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    const rewritten = facts.PlacePostState{
        .target = target,
        .initializedness = .initialized,
        .value = .{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }} },
        .ends_previous_roots = true,
        .refreshes_storage_generation = true,
        .requires_available_destination = true,
        .may_repopulate_opaque_storage = true,
    };
    const optional = try checker.mergeVirtualSafetySummary(
        .{ .input_post_states = &.{rewritten} },
        .{},
    );
    try std.testing.expect(optional != null);
    const merged = optional.?.input_post_states[0];
    try std.testing.expectEqual(value_state.Initializedness.initialized, merged.initializedness);
    try std.testing.expectEqual(@as(usize, 1), merged.value.input_place_values.len);
    try std.testing.expect(inputPlaceTargetEqual(target, merged.value.input_place_values[0]));
    try std.testing.expect(containsInputDependency(merged.value.input_dependencies, .{ .path = .{ .input_index = 1 } }));
    try std.testing.expect(merged.ends_previous_roots);
    try std.testing.expect(merged.refreshes_storage_generation);
    try std.testing.expect(merged.requires_available_destination);
    try std.testing.expect(merged.may_repopulate_opaque_storage);

    const identical = try checker.mergeVirtualSafetySummary(
        .{ .input_post_states = &.{rewritten} },
        .{ .input_post_states = &.{rewritten} },
    );
    try std.testing.expect(identical != null);
    try std.testing.expect(inputPostStatesEqual(&.{rewritten}, identical.?.input_post_states));

    const fresh_mismatch = try checker.mergeVirtualSafetySummary(
        .{ .input_post_states = &.{.{
            .target = target,
            .initializedness = .initialized,
            .value = .{ .fresh_owned_roots = &.{1} },
        }} },
        .{},
    );
    try std.testing.expect(fresh_mismatch == null);

    const transfer_mismatch = try checker.mergeVirtualSafetySummary(
        .{ .input_post_states = &.{.{
            .target = target,
            .initializedness = .initialized,
            .value = .{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 }, .transfers_ownership = true }} },
        }} },
        .{},
    );
    try std.testing.expect(transfer_mismatch == null);
}

test "virtual input effects reject opaque ownership without runtime drop correlation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    const storage = facts.InputPath{ .input_index = 1 };
    const other_storage = facts.InputPath{ .input_index = 2 };
    const none = facts.PlacePostState{ .target = target, .initializedness = .initialized };
    const definite = facts.PlacePostState{
        .target = target,
        .initializedness = .initialized,
        .opaque_ownership = .definite,
        .opaque_storage = storage,
    };
    const conditional = facts.PlacePostState{
        .target = target,
        .initializedness = .initialized,
        .opaque_ownership = .conditional,
        .opaque_storage = storage,
    };

    try std.testing.expect((try checker.mergeVirtualPlacePostState(none, definite)) == null);
    try std.testing.expect((try checker.mergeVirtualPlacePostState(none, conditional)) == null);
    try std.testing.expect((try checker.mergeVirtualPlacePostState(definite, conditional)) == null);
    try std.testing.expect((try checker.mergeVirtualPlacePostState(conditional, conditional)) == null);
    try std.testing.expect((try checker.mergeVirtualPlacePostState(definite, definite)) == null);

    var different = definite;
    different.opaque_storage = other_storage;
    try std.testing.expect((try checker.mergeVirtualPlacePostState(definite, different)) == null);
    var ambiguous = definite;
    ambiguous.opaque_ownership = .ambiguous;
    ambiguous.opaque_storage = null;
    try std.testing.expect((try checker.mergeVirtualPlacePostState(definite, ambiguous)) == null);
}

test "virtual summaries widen dependencies but require exact provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const from_self = facts.InputDependency{ .path = .{ .input_index = 0 } };
    const from_other = facts.InputDependency{ .path = .{ .input_index = 1 } };
    const widened = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .input_dependencies = &.{from_self} }} },
        .{ .outputs = &.{.{ .input_dependencies = &.{ from_self, from_other } }} },
    );
    try std.testing.expect(widened != null);
    try std.testing.expectEqual(@as(usize, 2), widened.?.outputs[0].input_dependencies.len);

    const required_union = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{}}, .required_live_inputs = &.{.{ .input_index = 0 }} },
        .{ .outputs = &.{.{}}, .required_live_inputs = &.{.{ .input_index = 1 }} },
    );
    try std.testing.expect(required_union != null);
    try std.testing.expectEqual(@as(usize, 2), required_union.?.required_live_inputs.len);

    const provenance_mismatch = try checker.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .fresh_storage_capabilities = &.{1} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(provenance_mismatch == null);
}

test "virtual summaries discharge opaque domains only when every implementation agrees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const emptied = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    const same_release = try checker.mergeVirtualSafetySummary(
        .{ .opaque_storage_empties = &.{emptied} },
        .{ .opaque_storage_empties = &.{emptied} },
    );
    try std.testing.expect(same_release != null);
    try std.testing.expectEqual(@as(usize, 1), same_release.?.opaque_storage_empties.len);
    try std.testing.expect(inputPlaceTargetEqual(emptied, same_release.?.opaque_storage_empties[0]));

    const absent_release = try checker.mergeVirtualSafetySummary(
        .{ .opaque_storage_empties = &.{emptied} },
        .{},
    );
    try std.testing.expect(absent_release != null);
    try std.testing.expectEqual(@as(usize, 0), absent_release.?.opaque_storage_empties.len);

    const release_then_write_implementation = facts.SafetySummary{
        .input_post_states = &.{.{
            .target = .{ .input_index = 1, .projections = &.{.{ .field = 0 }} },
            .initializedness = .initialized,
            .may_repopulate_opaque_storage = true,
        }},
    };
    const virtual_with_repopulation = try checker.mergeVirtualSafetySummary(
        .{
            .input_post_states = release_then_write_implementation.input_post_states,
            .opaque_storage_empties = &.{emptied},
        },
        release_then_write_implementation,
    );
    try std.testing.expect(virtual_with_repopulation != null);
    try std.testing.expectEqual(@as(usize, 0), virtual_with_repopulation.?.opaque_storage_empties.len);

    const hidden = facts.ValueEffect{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }} };
    const inconsistent_release = facts.SafetySummary{
        .opaque_storage_effects = &.{.{ .storage = emptied, .hidden_dependencies = hidden }},
        .opaque_storage_empties = &.{emptied},
    };
    const normalized = try checker.mergeVirtualSafetySummary(inconsistent_release, inconsistent_release);
    try std.testing.expect(normalized != null);
    try std.testing.expectEqual(@as(usize, 0), normalized.?.opaque_storage_empties.len);
    try std.testing.expectEqual(@as(usize, 1), normalized.?.opaque_storage_effects.len);

    const different_release = try checker.mergeVirtualSafetySummary(
        .{ .opaque_storage_empties = &.{emptied} },
        .{ .opaque_storage_empties = &.{.{ .input_index = 0, .projections = &.{.{ .field = 0 }} }} },
    );
    try std.testing.expect(different_release != null);
    try std.testing.expectEqual(@as(usize, 0), different_release.?.opaque_storage_empties.len);
}

test "required live input validation projects the selected aggregate path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(&allocator, &diags);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const live = try state.tracker.establish(.fresh);
    const stale = try state.tracker.establish(.fresh);
    state.tracker.end(stale);
    const live_value = facts.ValueFacts{ .dependencies = &.{.{ .root = live }} };
    const stale_value = facts.ValueFacts{ .dependencies = &.{.{ .root = stale }} };
    const aggregate = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = &live_value },
        .{ .index = 1, .value = &stale_value },
    } };
    const location = @import("../2_tokens/token.zig").Location{
        .file = "required_live_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    const function = sg.FunctionDeclaration{
        .id = 0,
        .name = "test",
        .location = location,
        .is_once = false,
        .input = undefined,
        .output = undefined,
        .body = null,
    };

    try std.testing.expect(try checker.validateRequiredLiveInputs(
        &function,
        .{ .required_live_inputs = &.{.{ .input_index = 0, .projections = &.{.{ .field = 0 }} }} },
        &.{aggregate},
        &state,
    ));
    try std.testing.expect(!try checker.validateRequiredLiveInputs(
        &function,
        .{ .required_live_inputs = &.{.{ .input_index = 0, .projections = &.{.{ .field = 1 }} }} },
        &.{aggregate},
        &state,
    ));
    try std.testing.expectEqual(@as(usize, 1), diags.list.items.len);
}

test "required live input validation rejects integer-derived safe references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(&allocator, &diags);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const location = @import("../2_tokens/token.zig").Location{
        .file = "required_live_integer_address_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    const function = sg.FunctionDeclaration{
        .id = 0,
        .name = "test",
        .location = location,
        .is_once = false,
        .input = undefined,
        .output = undefined,
        .body = null,
    };

    try std.testing.expect(!try checker.validateRequiredLiveInputs(
        &function,
        .{ .required_live_inputs = &.{.{ .input_index = 0 }} },
        &.{.{ .integer_address = true }},
        &state,
    ));
    try std.testing.expectEqual(@as(usize, 1), diags.list.items.len);
    try std.testing.expectEqualStrings(
        "an integer address cannot establish a safe reference; use RawPointer and explicit root establishment",
        diags.list.items[0].msg,
    );
}

test "output instantiation preserves sparse semantic field indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const dependency = try checker.allocator.create(facts.ValueEffect);
    dependency.* = .{ .fresh_dependencies = &.{91} };
    const empty = try checker.allocator.create(facts.ValueEffect);
    empty.* = .{};
    const fields = try checker.allocator.alloc(facts.OutputFieldEffect, 2);
    // The representation is deliberately sparse and out of semantic order.
    fields[0] = .{ .index = 2, .value = dependency };
    fields[1] = .{ .index = 0, .value = empty };
    const effect = facts.ValueEffect{
        .fresh_owned_roots = &.{91},
        .fields = fields,
    };

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const value = try checker.instantiateOutput(effect, &.{}, &state);
    const owned = value.owned_roots[0];
    const field_two = findField(value.fields, 2).?;
    const field_zero = findField(value.fields, 0).?;

    try std.testing.expectEqual(@as(usize, 1), value.owned_roots.len);
    try std.testing.expectEqual(@as(usize, 1), field_two.value.dependencies.len);
    try std.testing.expectEqual(owned, field_two.value.dependencies[0].root);
    try std.testing.expectEqual(@as(usize, 0), field_zero.value.dependencies.len);
}

test "choice values preserve complete payload facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const binding = try checker.allocator.create(sg.BindingDeclaration);
    binding.* = undefined;
    const dependency_root: facts.ValidityRootId = @enumFromInt(1);
    const owned_root: facts.ValidityRootId = @enumFromInt(2);
    const capability: facts.StorageCapabilityId = @enumFromInt(3);

    const nested = try checker.allocator.create(facts.ValueFacts);
    nested.* = .{
        .dependencies = &.{.{ .root = dependency_root }},
        .owned_roots = &.{owned_root},
        .integer_address = true,
        .foreign_storage = true,
        .storage_capabilities = &.{capability},
        .referenced_place = .{ .root = binding },
    };
    const payload_fields = try checker.allocator.alloc(facts.FieldFacts, 1);
    payload_fields[0] = .{ .index = 17, .value = nested };
    const payload = facts.ValueFacts{
        .dependencies = &.{.{ .root = dependency_root }},
        .owned_roots = &.{owned_root},
        .fields = payload_fields,
        .integer_address = true,
        .foreign_storage = true,
        .storage_capabilities = &.{capability},
        .referenced_place = .{ .root = binding },
    };

    const wrapped = try checker.choiceValue(5, payload);
    try std.testing.expectEqual(@as(usize, 0), wrapped.fields.len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.variants.len);
    try std.testing.expectEqual(@as(u32, 5), wrapped.variants[0].index);
    try std.testing.expect(valueFactsEqual(payload, wrapped.variants[0].value.*));

    const nested_wrapped = try checker.choiceValue(9, wrapped);
    const extracted = nested_wrapped.variants[0].value.variants[0].value.*;
    try std.testing.expect(valueFactsEqual(payload, extracted));
}

test "choice output effects preserve complete payload facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const nested = try checker.allocator.create(facts.ValueEffect);
    nested.* = .{
        .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }},
        .input_places = &.{.{ .input_index = 2 }},
        .fresh_dependencies = &.{ 11, 12 },
        .fresh_owned_roots = &.{12},
        .integer_address = true,
        .foreign_storage = true,
        .fresh_storage_capabilities = &.{13},
    };
    const payload_fields = try checker.allocator.alloc(facts.OutputFieldEffect, 1);
    payload_fields[0] = .{ .index = 17, .value = nested };
    const payload = facts.ValueEffect{
        .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }},
        .input_places = &.{.{ .input_index = 2 }},
        .fields = payload_fields,
        .fresh_dependencies = &.{11},
        .fresh_owned_roots = &.{12},
        .integer_address = true,
        .foreign_storage = true,
        .fresh_storage_capabilities = &.{13},
    };

    const wrapped = try checker.choiceValueEffect(5, payload);
    try std.testing.expectEqual(@as(usize, 0), wrapped.fields.len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.variants.len);
    try std.testing.expectEqual(@as(u32, 5), wrapped.variants[0].index);
    try std.testing.expect(outputEffectEqual(payload, wrapped.variants[0].value.*));

    const nested_wrapped = try checker.choiceValueEffect(9, wrapped);
    const extracted = nested_wrapped.variants[0].value.variants[0].value.*;
    try std.testing.expect(outputEffectEqual(payload, extracted));
}

test "choice alternatives activate fresh ownership by variant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const owned = facts.ValueEffect{ .fresh_owned_roots = &.{41} };
    const ok = try checker.choiceValueEffect(0, owned);
    const failed = try checker.choiceValueEffect(1, .{});
    const alternatives = try checker.mergeValueEffects(ok, failed);
    try std.testing.expectEqual(@as(usize, 0), alternatives.fields.len);
    try std.testing.expectEqual(@as(usize, 2), alternatives.variants.len);
    try std.testing.expectEqual(@as(usize, 0), alternatives.fresh_owned_roots.len);

    var failed_state = SafetyChecker.FunctionState.init(allocator);
    defer failed_state.deinit();
    const failed_value = try checker.instantiateOutput(alternatives, &.{}, &failed_state);
    try std.testing.expectEqual(@as(usize, 1), failed_state.tracker.roots.items.len);
    try std.testing.expectEqual(.conditional, failed_state.tracker.roots.items[0].state);
    checker.activateChoiceVariant(failed_value, 1, &failed_state);
    try std.testing.expectEqual(.dead, failed_state.tracker.roots.items[0].state);
    try std.testing.expectEqual(@as(usize, 0), failed_value.variants[1].value.owned_roots.len);

    var ok_state = SafetyChecker.FunctionState.init(allocator);
    defer ok_state.deinit();
    const ok_value = try checker.instantiateOutput(alternatives, &.{}, &ok_state);
    checker.activateChoiceVariant(ok_value, 0, &ok_state);
    try std.testing.expectEqual(.alive, ok_state.tracker.roots.items[0].state);
    try std.testing.expectEqual(@as(usize, 1), ok_value.variants[0].value.owned_roots.len);
}

test "payloadless choice case rejects facts from owned alternatives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const owned_root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(owned_root)].state = .conditional;

    const owned = facts.ValueFacts{ .owned_roots = &.{owned_root} };
    const choice = facts.ValueFacts{
        .variants = &.{
            .{ .index = 0, .value = &facts.ValueFacts{} }, // ..empty
            .{ .index = 1, .value = &owned }, // ..owned
        },
    };
    checker.activateChoiceVariant(choice, 0, &state);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(owned_root)].state);
}

test "outer choice refinement leaves nested variants conditional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root_a = try state.tracker.establish(.fresh);
    const root_b = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root_a)].state = .conditional;
    state.tracker.roots.items[@intFromEnum(root_b)].state = .conditional;

    const inner_a = facts.ValueFacts{ .owned_roots = &.{root_a} };
    const inner_b = facts.ValueFacts{ .owned_roots = &.{root_b} };
    const inner = facts.ValueFacts{ .variants = &.{
        .{ .index = 0, .value = &inner_a },
        .{ .index = 1, .value = &inner_b },
    } };
    const outer = facts.ValueFacts{
        .variants = &.{
            .{ .index = 0, .value = &inner }, // ..ok
            .{ .index = 1, .value = &facts.ValueFacts{} }, // ..error
        },
    };

    checker.activateChoiceVariant(outer, 0, &state);
    try std.testing.expectEqual(.conditional, state.tracker.roots.items[@intFromEnum(root_a)].state);
    try std.testing.expectEqual(.conditional, state.tracker.roots.items[@intFromEnum(root_b)].state);

    checker.activateChoiceVariant(inner, 0, &state);
    try std.testing.expectEqual(.alive, state.tracker.roots.items[@intFromEnum(root_a)].state);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(root_b)].state);
}

test "rejecting an outer choice rejects all nested alternative facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root_a = try state.tracker.establish(.fresh);
    const root_b = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root_a)].state = .conditional;
    state.tracker.roots.items[@intFromEnum(root_b)].state = .conditional;

    const inner_a = facts.ValueFacts{ .owned_roots = &.{root_a} };
    const inner_b = facts.ValueFacts{ .owned_roots = &.{root_b} };
    const inner = facts.ValueFacts{ .variants = &.{
        .{ .index = 0, .value = &inner_a },
        .{ .index = 1, .value = &inner_b },
    } };
    const errable = facts.ValueFacts{
        .variants = &.{
            .{ .index = 0, .value = &inner }, // ..ok: Choice<OwningA, OwningB>
            .{ .index = 1, .value = &facts.ValueFacts{} }, // ..error
        },
    };

    checker.activateChoiceVariant(errable, 1, &state);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(root_a)].state);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(root_b)].state);
}

test "trivial input writes retain initialized post states" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var states = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer states.deinit();
    const target = facts.InputPath{ .input_index = 0 };

    // The value is deliberately fact-free: recording this transition must not
    // depend on pointers in the value or on the callee's name.
    try checker.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expectEqual(@as(usize, 1), states.items.len);
    try std.testing.expectEqual(value_state.Initializedness.initialized, states.items[0].initializedness);
    try std.testing.expect(!states.items[0].refreshes_storage_generation);

    try checker.recordInputPostState(&states, &.{target}, .deinitialized, .{}, true, false, false, false);
    try checker.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expect(states.items[0].refreshes_storage_generation);
}

test "opaque ownership joins preserve conditional storage and reject ambiguity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    const storage = facts.InputPath{ .input_index = 1 };
    const other_storage = facts.InputPath{ .input_index = 2 };
    var opaque_branch = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer opaque_branch.deinit();
    try checker.recordOpaqueOwnershipConsumption(&opaque_branch, &.{target}, .definite, storage);
    var plain_branch = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer plain_branch.deinit();

    var forward = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer forward.deinit();
    try checker.joinInputPostStates(&forward, &opaque_branch, &plain_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.conditional, forward.items[0].opaque_ownership);
    try std.testing.expect(optionalInputPathEqual(storage, forward.items[0].opaque_storage));

    var reverse = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer reverse.deinit();
    try checker.joinInputPostStates(&reverse, &plain_branch, &opaque_branch);
    try std.testing.expect(inputPostStatesEqual(forward.items, reverse.items));

    var fixed_point = try cloneInputPostStates(&forward, allocator);
    defer fixed_point.deinit();
    try checker.joinInputPostStates(&fixed_point, &fixed_point, &opaque_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.conditional, fixed_point.items[0].opaque_ownership);
    try std.testing.expectEqual(@as(usize, 1), fixed_point.items.len);

    var same_storage = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer same_storage.deinit();
    try checker.joinInputPostStates(&same_storage, &opaque_branch, &opaque_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.definite, same_storage.items[0].opaque_ownership);
    try std.testing.expect(optionalInputPathEqual(storage, same_storage.items[0].opaque_storage));

    var other_branch = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer other_branch.deinit();
    try checker.recordOpaqueOwnershipConsumption(&other_branch, &.{target}, .definite, other_storage);
    var ambiguous = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer ambiguous.deinit();
    try checker.joinInputPostStates(&ambiguous, &opaque_branch, &other_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.ambiguous, ambiguous.items[0].opaque_ownership);
    try std.testing.expectEqual(@as(?facts.InputPath, null), ambiguous.items[0].opaque_storage);

    var sequential = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer sequential.deinit();
    try checker.recordOpaqueOwnershipConsumption(&sequential, &.{target}, .conditional, storage);
    try checker.recordOpaqueOwnershipConsumption(&sequential, &.{target}, .definite, storage);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.definite, sequential.items[0].opaque_ownership);
    try std.testing.expect(optionalInputPathEqual(storage, sequential.items[0].opaque_storage));
}

test "opaque ownership projections retain sibling facts" {
    const owned_field = facts.ValueFacts{ .owned_roots = &.{@enumFromInt(0)} };
    const sibling = facts.ValueFacts{ .owned_roots = &.{@enumFromInt(1)} };
    const value = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = &owned_field },
        .{ .index = 1, .value = &sibling },
    } };
    const projected = projectValueFacts(value, &.{.{ .field = 0 }});
    var roots = std.array_list.Managed(facts.ValidityRootId).init(std.testing.allocator);
    defer roots.deinit();
    try collectOwnedRoots(projected, &roots);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{@as(facts.ValidityRootId, @enumFromInt(0))}, roots.items);
}

test "opaque ownership distinguishes internal from external dependencies recursively" {
    const owned: facts.ValidityRootId = @enumFromInt(0);
    const external: facts.ValidityRootId = @enumFromInt(1);
    const internal_value = facts.ValueFacts{
        .owned_roots = &.{owned},
        .fields = &.{.{ .index = 0, .value = &facts.ValueFacts{ .dependencies = &.{.{ .root = owned }} } }},
    };
    const external_value = facts.ValueFacts{
        .variants = &.{.{ .index = 0, .value = &facts.ValueFacts{
            .owned_roots = &.{owned},
            .dependencies = &.{.{ .root = external }},
        } }},
    };
    try std.testing.expect(!hasExternalOpaqueDependency(internal_value, &.{owned}));
    try std.testing.expect(hasExternalOpaqueDependency(external_value, &.{owned}));
}

fn expectRejectedMultiEffectCallRestoresState(comptime use_virtual_call: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(&allocator, &diags);
    defer checker.deinit();

    const location = @import("../2_tokens/token.zig").Location{
        .file = "transaction_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    var first_binding = sg.BindingDeclaration{
        .name = "first",
        .location = location,
        .origin_file = location.file,
        .mutability = undefined,
        .ty = .{ .builtin = .Int32 },
        .initialization = null,
    };
    var second_binding = sg.BindingDeclaration{
        .name = "second",
        .location = location,
        .origin_file = location.file,
        .mutability = undefined,
        .ty = .{ .builtin = .Int32 },
        .initialization = null,
    };
    var first_use = sg.SGNode{ .location = location, .content = .{ .binding_use = &first_binding } };
    var second_use = sg.SGNode{ .location = location, .content = .{ .binding_use = &second_binding } };
    var first_move = sg.SGNode{ .location = location, .content = .{ .move_value = &first_use } };
    var second_move = sg.SGNode{ .location = location, .content = .{ .move_value = &second_use } };
    const argument_fields = [_]sg.StructValueLiteralField{
        .{ .name = "first", .value = &first_move },
        .{ .name = "second", .value = &second_move },
    };
    var input_literal = sg.StructValueLiteral{
        .fields = &argument_fields,
        .ty = .{ .builtin = .Void },
    };
    var input_node = sg.SGNode{ .location = location, .content = .{ .struct_value_literal = &input_literal } };
    var callee = sg.FunctionDeclaration{
        .id = 1,
        .name = "store_pair",
        .location = location,
        .is_once = false,
        .input = .{ .fields = &.{} },
        .output = .{ .fields = &.{} },
        .body = null,
    };
    var caller = sg.FunctionDeclaration{
        .id = 2,
        .name = "caller",
        .location = location,
        .is_once = false,
        .input = .{ .fields = &.{} },
        .output = .{ .fields = &.{} },
        .body = null,
    };
    var call = sg.FunctionCall{ .callee = &callee, .input = &input_node };
    var registry = sg.VirtualMethodRegistry{
        .implementations = std.array_list.Managed(*const sg.FunctionDeclaration).init(allocator),
    };
    defer registry.implementations.deinit();
    try registry.implementations.append(&callee);
    var virtual_call = sg.VirtualCall{
        .handle = &input_node,
        .input = &input_node,
        .self_input_index = 0,
        .method_index = 0,
        .method_count = 1,
        .method_name = "store_pair",
        .input_type = &callee.input,
        .output_type = &callee.output,
        .self_permission = undefined,
        .safety_methods = &registry,
    };

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const first_root = try state.tracker.establish(.fresh);
    const second_root = try state.tracker.establish(.fresh);
    const external_root = try state.tracker.establish(.fresh);
    const first_value = facts.ValueFacts{ .owned_roots = &.{first_root} };
    const second_value = facts.ValueFacts{
        .dependencies = &.{.{ .root = external_root }},
        .owned_roots = &.{second_root},
    };
    try checker.setPlace(&state, .{ .root = &first_binding }, .initialized, first_value);
    try checker.setPlace(&state, .{ .root = &second_binding }, .initialized, second_value);
    try checker.summaries.put(&callee, .{
        .input_post_states = &.{
            .{ .target = .{ .input_index = 0 }, .initializedness = .initialized, .opaque_ownership = .definite },
            .{ .target = .{ .input_index = 1 }, .initializedness = .initialized, .opaque_ownership = .definite },
        },
    });

    if (use_virtual_call) {
        _ = try checker.evaluateVirtualCall(&caller, &virtual_call, &state);
    } else {
        _ = try checker.evaluateCall(&caller, &call, &state);
    }

    try std.testing.expectEqual(@as(usize, 1), diags.list.items.len);
    try std.testing.expectEqualStrings(
        if (use_virtual_call)
            "virtual method 'store_pair' has incompatible safety effects across implementations"
        else
            "opaque ownership storage cannot hide dependencies on external roots",
        diags.list.items[0].msg,
    );
    try std.testing.expect(state.tracker.isAlive(first_root));
    try std.testing.expect(state.tracker.isAlive(second_root));
    try std.testing.expect(state.tracker.isAlive(external_root));
    const restored_first = checker.getPlace(&state, .{ .root = &first_binding }).?;
    const restored_second = checker.getPlace(&state, .{ .root = &second_binding }).?;
    try std.testing.expectEqual(value_state.Initializedness.initialized, restored_first.initializedness);
    try std.testing.expectEqual(value_state.Initializedness.initialized, restored_second.initializedness);
    try std.testing.expect(valueFactsEqual(first_value, restored_first.value));
    try std.testing.expect(valueFactsEqual(second_value, restored_second.value));
}

test "rejected multi-effect call restores roots and input value facts" {
    try expectRejectedMultiEffectCallRestoresState(false);
}

test "rejected multi-effect virtual call restores roots and input value facts" {
    try expectRejectedMultiEffectCallRestoresState(true);
}

test "root batches remain alive when any root is hidden" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const first = try state.tracker.establish(.fresh);
    const hidden = try state.tracker.establish(.fresh);
    try state.opaque_storages.append(.{
        .storage = .{ .root = undefined },
        .hidden_dependencies = &.{hidden},
    });

    try std.testing.expect(!try checker.endRoots(null, &state, &.{ first, hidden }));
    try std.testing.expect(state.tracker.isAlive(first));
    try std.testing.expect(state.tracker.isAlive(hidden));
}

test "auto deinit keeps every owned root and the binding alive when one root is hidden" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(&allocator, &diags);
    defer checker.deinit();

    const location = @import("../2_tokens/token.zig").Location{
        .file = "auto_deinit_transaction_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    var binding = sg.BindingDeclaration{
        .name = "owned_pair",
        .location = location,
        .origin_file = location.file,
        .mutability = undefined,
        .ty = .{ .builtin = .Int32 },
        .initialization = null,
    };
    var cleanup = sg.AutoDeinitBinding{
        .binding = &binding,
        .deinit_fn = null,
    };
    var cleanup_node = sg.SGNode{
        .location = location,
        .content = .{ .auto_deinit_binding = &cleanup },
    };
    const block = sg.CodeBlock{
        .nodes = &.{&cleanup_node},
        .ret_val = null,
    };
    const function = sg.FunctionDeclaration{
        .id = 1,
        .name = "auto_deinit_transaction",
        .location = location,
        .is_once = false,
        .input = .{ .fields = &.{} },
        .output = .{ .fields = &.{} },
        .body = &block,
    };

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const first = try state.tracker.establish(.fresh);
    const hidden = try state.tracker.establish(.fresh);
    const value = facts.ValueFacts{ .owned_roots = &.{ first, hidden } };
    try checker.setPlace(&state, .{ .root = &binding }, .initialized, value);
    try state.opaque_storages.append(.{
        .storage = .{ .root = undefined },
        .hidden_dependencies = &.{hidden},
    });

    try checker.validateBlock(&function, &block, &state, null);

    try std.testing.expectEqual(@as(usize, 1), diags.list.items.len);
    try std.testing.expectEqualStrings("cannot end a root while opaque storage hides a dependency on it", diags.list.items[0].msg);
    try std.testing.expect(state.tracker.isAlive(first));
    try std.testing.expect(state.tracker.isAlive(hidden));
    const preserved = checker.getPlace(&state, .{ .root = &binding }).?;
    try std.testing.expectEqual(value_state.Initializedness.initialized, preserved.initializedness);
    try std.testing.expect(valueFactsEqual(value, preserved.value));
}

test "loop root widening is stable and preserves historical aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const location = @import("../2_tokens/token.zig").Location{
        .file = "loop_root_phi_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    var owner_binding = sg.BindingDeclaration{
        .name = "owner",
        .location = location,
        .origin_file = location.file,
        .mutability = undefined,
        .ty = .{ .builtin = .Int32 },
        .initialization = null,
    };
    const owner = place.Place{ .root = &owner_binding, .projections = &.{.{ .field = 0 }} };
    const alias = place.Place{ .root = &owner_binding, .projections = &.{.{ .field = 1 }} };

    var entry = SafetyChecker.FunctionState.init(allocator);
    defer entry.deinit();
    const old = try entry.tracker.establish(.fresh);
    entry.tracker.roots.items[@intFromEnum(old)].owned_resource = true;
    const child = try entry.tracker.establish(.fresh);
    entry.tracker.roots.items[@intFromEnum(child)].owned_resource = true;
    try appendOwnershipEdge(&entry.ownership_edges, .{ .owner = old, .owned = child });
    try checker.setPlace(&entry, owner, .initialized, .{
        .dependencies = &.{.{ .root = old }},
        .owned_roots = &.{old},
    });
    try checker.setPlace(&entry, alias, .initialized, .{ .dependencies = &.{.{ .root = old }} });

    var iteration = try entry.clone(allocator);
    defer iteration.deinit();
    iteration.tracker.end(old);
    const replacement = try iteration.tracker.establish(.fresh);
    iteration.tracker.roots.items[@intFromEnum(replacement)].owned_resource = true;
    try appendOwnershipEdge(&iteration.ownership_edges, .{ .owner = replacement, .owned = child });
    try checker.setPlace(&iteration, owner, .initialized, .{
        .dependencies = &.{.{ .root = replacement }},
        .owned_roots = &.{replacement},
    });

    var context = SafetyChecker.LoopJoinContext.init(allocator);
    defer context.deinit();
    var joined = try entry.clone(allocator);
    defer joined.deinit();
    try checker.joinStates(undefined, &joined, &entry, &iteration);
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

    var second_iteration = try joined.clone(allocator);
    defer second_iteration.deinit();
    second_iteration.tracker.end(phi);
    const second_replacement = try second_iteration.tracker.establish(.fresh);
    second_iteration.tracker.roots.items[@intFromEnum(second_replacement)].owned_resource = true;
    try appendOwnershipEdge(&second_iteration.ownership_edges, .{ .owner = second_replacement, .owned = child });
    try checker.setPlace(&second_iteration, owner, .initialized, .{
        .dependencies = &.{.{ .root = second_replacement }},
        .owned_roots = &.{second_replacement},
    });
    var fixed_point = try entry.clone(allocator);
    defer fixed_point.deinit();
    try checker.joinStates(undefined, &fixed_point, &entry, &second_iteration);
    try checker.widenLoopOwnedRoots(&context, &fixed_point, &entry, &second_iteration);
    try std.testing.expectEqual(phi, checker.getPlace(&fixed_point, owner).?.value.owned_roots[0]);
    try std.testing.expectEqual(stable_root_count, fixed_point.tracker.roots.items.len);
    try std.testing.expectEqual(@as(usize, 1), fixed_point.ownership_edges.items.len);
    try std.testing.expectEqual(phi, fixed_point.ownership_edges.items[0].owner);
}

test "replacement collapse preserves simultaneous live owned roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const old = try state.tracker.establish(.fresh);
    const fresh = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(old)].owned_resource = true;
    state.tracker.roots.items[@intFromEnum(fresh)].owned_resource = true;
    const previous = facts.ValueFacts{ .owned_roots = &.{old} };
    const combined = facts.ValueFacts{ .owned_roots = &.{ old, fresh } };

    const preserved = try checker.collapseReplacedOwnedRoots(combined, previous, &state);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ old, fresh }, preserved.owned_roots);

    state.tracker.end(old);
    const collapsed = try checker.collapseReplacedOwnedRoots(combined, previous, &state);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{fresh}, collapsed.owned_roots);
}

test "replacement collapse preserves a stale sibling alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const old = try state.tracker.establish(.fresh);
    const fresh = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(old)].owned_resource = true;
    state.tracker.roots.items[@intFromEnum(fresh)].owned_resource = true;
    state.tracker.end(old);

    const previous_owner = try allocator.create(facts.ValueFacts);
    previous_owner.* = .{ .dependencies = &.{.{ .root = old }}, .owned_roots = &.{old} };
    const previous_alias = try allocator.create(facts.ValueFacts);
    previous_alias.* = .{ .dependencies = &.{.{ .root = old }} };
    const previous = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = previous_owner },
        .{ .index = 1, .value = previous_alias },
    } };

    const replaced_owner = try allocator.create(facts.ValueFacts);
    replaced_owner.* = .{
        .dependencies = &.{ .{ .root = old }, .{ .root = fresh } },
        .owned_roots = &.{ old, fresh },
    };
    const retained_alias = try allocator.create(facts.ValueFacts);
    retained_alias.* = .{ .dependencies = &.{.{ .root = old }} };
    const replacement = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = replaced_owner },
        .{ .index = 1, .value = retained_alias },
    } };

    const collapsed = try checker.collapseReplacedOwnedRoots(replacement, previous, &state);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{fresh}, collapsed.fields[0].value.owned_roots);
    try std.testing.expectEqual(fresh, collapsed.fields[0].value.dependencies[0].root);
    try std.testing.expectEqual(old, collapsed.fields[1].value.dependencies[0].root);
}

test "lexical storage cleanup keeps repeated loop activations root-stable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var binding: sg.BindingDeclaration = undefined;
    var declaration = sg.SGNode{
        .location = undefined,
        .content = .{ .binding_declaration = &binding },
    };
    const block = sg.CodeBlock{ .nodes = &.{&declaration}, .ret_val = null };
    const function: sg.FunctionDeclaration = undefined;
    const storage = place.Place{ .root = &binding, .projections = &.{.{ .field = 0 }} };

    for (0..4) |_| {
        try checker.setPlace(&state, .{ .root = &binding }, .initialized, .{});
        _ = try checker.storageGenerationForPlace(storage, &state);
        try std.testing.expectEqual(@as(usize, 1), state.tracker.roots.items.len);
        try checker.endBlockLocalStorage(&function, &block, &state);
        try std.testing.expectEqual(@as(usize, 0), state.tracker.roots.items.len);
        try std.testing.expectEqual(@as(usize, 0), state.storage_generations.items.len);
        try std.testing.expectEqual(@as(usize, 0), state.places.items.len);
    }
}

test "loop root widening does not hide crossed stale dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const binding: *const sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = binding };
    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    const first = try left.tracker.establish(.fresh);
    const second = try left.tracker.establish(.fresh);
    left.tracker.roots.items[@intFromEnum(first)].owned_resource = true;
    left.tracker.roots.items[@intFromEnum(second)].owned_resource = true;
    left.tracker.end(second);
    try checker.setPlace(&left, storage, .initialized, .{
        .dependencies = &.{ .{ .root = first }, .{ .root = second } },
        .owned_roots = &.{first},
    });
    var right = try left.clone(allocator);
    defer right.deinit();
    right.tracker.roots.items[@intFromEnum(first)].state = .dead;
    right.tracker.roots.items[@intFromEnum(second)].state = .alive;
    try checker.setPlace(&right, storage, .initialized, .{
        .dependencies = &.{ .{ .root = first }, .{ .root = second } },
        .owned_roots = &.{second},
    });

    var joined = try left.clone(allocator);
    defer joined.deinit();
    try checker.joinStates(undefined, &joined, &left, &right);
    var context = SafetyChecker.LoopJoinContext.init(allocator);
    defer context.deinit();
    try checker.widenLoopOwnedRoots(&context, &joined, &left, &right);
    try std.testing.expectEqual(@as(usize, 0), context.roots.items.len);
    try std.testing.expect(!joined.tracker.dependenciesAreAlive(checker.getPlace(&joined, storage).?.value));
}

test "relocation transfers storage capability into refreshed destination storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const source_binding = try checker.allocator.create(sg.BindingDeclaration);
    const destination_binding = try checker.allocator.create(sg.BindingDeclaration);
    source_binding.* = undefined;
    destination_binding.* = undefined;
    const source = place.Place{ .root = source_binding };
    const destination = place.Place{ .root = destination_binding };
    const resource = try state.tracker.establish(.fresh);
    const capability: facts.StorageCapabilityId = @enumFromInt(0);
    try state.storage_capabilities.append(.available);
    try state.places.append(.{
        .storage = source,
        .initializedness = .initialized,
        .value = .{
            .owned_roots = &.{resource},
            .foreign_storage = true,
            .storage_capabilities = &.{capability},
        },
    });
    try state.places.append(.{ .storage = destination, .initializedness = .deinitialized });
    const old_destination_root = try checker.storageGenerationForPlace(destination, &state);

    const arguments = [_]sg.StructValueLiteralField{ undefined, undefined };
    const values = [_]facts.ValueFacts{
        .{ .referenced_place = source },
        .{ .referenced_place = destination },
    };
    const function: sg.FunctionDeclaration = undefined;
    _ = try checker.relocatePlaces(&function, &arguments, &values, &state);

    const destination_facts = checker.getPlace(&state, destination).?;
    try std.testing.expectEqual(value_state.Initializedness.initialized, destination_facts.initializedness);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{resource}, destination_facts.value.owned_roots);
    try std.testing.expectEqualSlices(facts.StorageCapabilityId, &.{capability}, destination_facts.value.storage_capabilities);
    try std.testing.expectEqual(value_state.Initializedness.moved, checker.getPlace(&state, source).?.initializedness);
    const new_destination_root = try checker.storageGenerationForPlace(destination, &state);
    try std.testing.expect(old_destination_root != new_destination_root);
    try std.testing.expectEqual(@as(@TypeOf(state.tracker.roots.items[@intFromEnum(old_destination_root)].state), .dead), state.tracker.roots.items[@intFromEnum(old_destination_root)].state);
    try std.testing.expectEqual(@as(@TypeOf(state.tracker.roots.items[@intFromEnum(resource)].state), .alive), state.tracker.roots.items[@intFromEnum(resource)].state);
}

test "refreshing Storage Generations invalidates earlier aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const old_root = try checker.storageGenerationForPlace(storage, &state);
    const stale_alias = facts.ValueFacts{
        .dependencies = &.{.{ .root = old_root }},
        .referenced_place = storage,
    };

    try checker.refreshStorageGeneration(null, &state, storage);
    const fresh_root = try checker.storageGenerationForPlace(storage, &state);
    try std.testing.expect(old_root != fresh_root);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(old_root)].state);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(stale_alias));
    try std.testing.expect(state.tracker.isAlive(fresh_root));
}

test "releasing an opaque domain preserves its storage generation and extracted references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const generation = try checker.storageGenerationForPlace(storage, &state);
    const hidden = try state.tracker.establish(.fresh);
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{hidden} });
    const extracted = facts.ValueFacts{ .dependencies = &.{.{ .root = generation }} };

    checker.markOpaqueStorageEmpty(&state, storage);

    try std.testing.expectEqual(generation, try checker.storageGenerationForPlace(storage, &state));
    try std.testing.expect(state.tracker.dependenciesAreAlive(extracted));
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
}

test "stale opaque pointer provenance does not rebind to refreshed storage generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const old_root = try checker.storageGenerationForPlace(storage, &state);
    const stale_pointer = facts.ValueFacts{
        .dependencies = &.{.{ .root = old_root }},
        .referenced_place = storage,
        .opaque_provenance = &.{.{ .storage = storage, .generation = old_root }},
    };
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{} });

    try checker.refreshStorageGeneration(null, &state, storage);
    const fresh_root = try checker.storageGenerationForPlace(storage, &state);
    var remarked_stale_pointer = stale_pointer;
    try checker.addOpaqueAccessProvenance(&state, &remarked_stale_pointer, storage);
    var hidden = std.array_list.Managed(facts.ValidityRootId).init(allocator);
    defer hidden.deinit();
    try checker.collectOpaqueHiddenDependencies(&state, remarked_stale_pointer, &hidden);

    try std.testing.expect(containsRoot(hidden.items, old_root));
    try std.testing.expect(!containsRoot(hidden.items, fresh_root));
    try std.testing.expectEqual(@as(usize, 1), remarked_stale_pointer.opaque_provenance.len);
}

test "fresh opaque pointer provenance observes refreshed storage generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const old_root = try checker.storageGenerationForPlace(storage, &state);
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{} });
    try checker.refreshStorageGeneration(null, &state, storage);
    const fresh_root = try checker.storageGenerationForPlace(storage, &state);
    const fresh_pointer = facts.ValueFacts{ .dependencies = &.{.{ .root = fresh_root }} };

    const provenance = try checker.currentOpaqueProvenancesForValue(&state, fresh_pointer);
    try std.testing.expectEqual(@as(usize, 1), provenance.len);
    try std.testing.expect(provenance[0].storage.eql(storage));
    try std.testing.expectEqual(fresh_root, provenance[0].generation);
    try std.testing.expect(old_root != provenance[0].generation);
}

test "opaque provenance join preserves distinct generations of one domain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const first = try state.tracker.establish(.fresh);
    const second = try state.tracker.establish(.fresh);
    const merged = try checker.mergeValueFacts(
        .{ .opaque_provenance = &.{.{ .storage = storage, .generation = first }} },
        .{ .opaque_provenance = &.{.{ .storage = storage, .generation = second }} },
    );

    try std.testing.expectEqual(@as(usize, 2), merged.opaque_provenance.len);
    try std.testing.expectEqual(first, merged.opaque_provenance[0].generation);
    try std.testing.expectEqual(second, merged.opaque_provenance[1].generation);
}

test "opaque read envelopes preserve captured generations across refresh and joins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var storage_binding: sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = &storage_binding };
    const first = try checker.storageGenerationForPlace(storage, &state);
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{} });
    try checker.refreshStorageGeneration(null, &state, storage);
    const second = try checker.storageGenerationForPlace(storage, &state);

    var child_type = sg.Type{ .builtin = .UInt8 };
    var pointer_type = sg.PointerType{ .mutability = undefined, .child = &child_type };
    const reference_type = sg.Type{ .pointer_type = &pointer_type };
    const old_value = try checker.addOpaqueReadEnvelope(.{}, reference_type, &.{.{
        .storage = storage,
        .generation = first,
    }});
    const fresh_value = try checker.addOpaqueReadEnvelope(.{}, reference_type, &.{.{
        .storage = storage,
        .generation = second,
    }});

    try std.testing.expect(valueDependsOnRoot(old_value, first));
    try std.testing.expect(!valueDependsOnRoot(old_value, second));
    try std.testing.expect(valueDependsOnRoot(fresh_value, second));
    try std.testing.expect(!valueDependsOnRoot(fresh_value, first));

    const joined = try checker.mergeValueFacts(old_value, fresh_value);
    try std.testing.expect(valueDependsOnRoot(joined, first));
    try std.testing.expect(valueDependsOnRoot(joined, second));
}

test "symbolic opaque read generations instantiate without polluting identity outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const ordinary = try state.tracker.establish(.fresh);
    const first_generation = try state.tracker.establish(.fresh);
    const second_generation = try state.tracker.establish(.fresh);
    var first_storage_binding: sg.BindingDeclaration = undefined;
    var second_storage_binding: sg.BindingDeclaration = undefined;
    const arguments = [_]facts.ValueFacts{
        .{
            .dependencies = &.{.{ .root = ordinary }},
            .opaque_provenance = &.{.{
                .storage = .{ .root = &first_storage_binding },
                .generation = first_generation,
            }},
        },
        .{
            .opaque_provenance = &.{.{
                .storage = .{ .root = &second_storage_binding },
                .generation = second_generation,
            }},
        },
    };

    const opaque_read = facts.ValueEffect{
        .opaque_generation_dependencies = try checker.oneInputPath(0, &.{}),
    };
    const extracted = try checker.instantiateOutput(opaque_read, &arguments, &state);
    try std.testing.expect(valueDependsOnRoot(extracted, first_generation));
    try std.testing.expect(!valueDependsOnRoot(extracted, ordinary));

    const identity_effect = try checker.inputValueEffect(0, &.{});
    try std.testing.expectEqual(@as(usize, 0), identity_effect.opaque_generation_dependencies.len);
    const identity_sources = try checker.opaqueGenerationSourcePaths(identity_effect);
    const read_through_identity = try checker.withOpaqueReadGenerationDependencies(identity_sources, identity_effect);
    try std.testing.expectEqual(@as(usize, 1), read_through_identity.opaque_generation_dependencies.len);
    try std.testing.expectEqual(@as(u32, 0), read_through_identity.opaque_generation_dependencies[0].input_index);
    const read_through_double_identity = try checker.withOpaqueReadGenerationDependencies(identity_sources, read_through_identity);
    try std.testing.expectEqual(@as(usize, 1), read_through_double_identity.opaque_generation_dependencies.len);

    const identity = try checker.instantiateOutput(identity_effect, &arguments, &state);
    try std.testing.expect(valueDependsOnRoot(identity, ordinary));
    try std.testing.expect(!valueDependsOnRoot(identity, first_generation));
    try std.testing.expectEqual(@as(usize, 1), identity.opaque_provenance.len);
    try std.testing.expectEqual(first_generation, identity.opaque_provenance[0].generation);

    const joined_effect = try checker.mergeValueEffects(opaque_read, .{
        .opaque_generation_dependencies = try checker.oneInputPath(1, &.{}),
    });
    const joined = try checker.instantiateOutput(joined_effect, &arguments, &state);
    try std.testing.expect(valueDependsOnRoot(joined, first_generation));
    try std.testing.expect(valueDependsOnRoot(joined, second_generation));

    var fresh_map = std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource).init(allocator);
    defer fresh_map.deinit();
    const virtual_joined = (try checker.mergeVirtualValueEffect(
        opaque_read,
        .{ .opaque_generation_dependencies = try checker.oneInputPath(1, &.{}) },
        &fresh_map,
    )).?;
    try std.testing.expectEqual(@as(usize, 2), virtual_joined.opaque_generation_dependencies.len);

    var virtual_identity_map = std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource).init(allocator);
    defer virtual_identity_map.deinit();
    const virtual_identity = (try checker.mergeVirtualValueEffect(identity_effect, identity_effect, &virtual_identity_map)).?;
    const virtual_read = try checker.withOpaqueReadGenerationDependencies(
        try checker.opaqueGenerationSourcePaths(virtual_identity),
        virtual_identity,
    );
    try std.testing.expectEqual(@as(usize, 1), virtual_read.opaque_generation_dependencies.len);
}

test "input Place values instantiate the pointee rather than the pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var binding: sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = &binding };
    const pointer_root = try state.tracker.establish(.fresh);
    const pointee_root = try state.tracker.establish(.fresh);
    try checker.setPlace(&state, storage, .initialized, .{ .dependencies = &.{.{ .root = pointee_root }} });

    const effect = try checker.inputPlaceValueEffect(.{ .input_index = 0 });
    const value = try checker.instantiateOutput(effect, &.{.{
        .dependencies = &.{.{ .root = pointer_root }},
        .referenced_place = storage,
    }}, &state);
    try std.testing.expect(valueDependsOnRoot(value, pointee_root));
    try std.testing.expect(!valueDependsOnRoot(value, pointer_root));
    try std.testing.expect(value.referenced_place == null);
}

test "opaque input Place values hide pointee dependencies rather than pointer facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var binding: sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = &binding };
    const pointer_root = try state.tracker.establish(.fresh);
    const pointee_root = try state.tracker.establish(.fresh);
    const pointee_owned_root = try state.tracker.establish(.fresh);
    try checker.setPlace(&state, storage, .initialized, .{
        .dependencies = &.{.{ .root = pointee_root }},
        .owned_roots = &.{pointee_owned_root},
    });

    var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(allocator);
    defer fresh_roots.deinit();
    var hidden = std.array_list.Managed(facts.ValidityRootId).init(allocator);
    defer hidden.deinit();
    try checker.instantiateOpaqueDependencies(
        try checker.inputPlaceValueEffect(.{ .input_index = 0 }),
        &.{.{
            .dependencies = &.{.{ .root = pointer_root }},
            .referenced_place = storage,
        }},
        &state,
        &fresh_roots,
        &hidden,
    );

    try std.testing.expect(containsRoot(hidden.items, pointee_root));
    try std.testing.expect(!containsRoot(hidden.items, pointer_root));
    try std.testing.expect(!containsRoot(hidden.items, pointee_owned_root));
}

test "opaque generation dependencies instantiate into hidden opaque dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var storage_binding: sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = &storage_binding };
    const captured_generation = try checker.storageGenerationForPlace(storage, &state);
    try checker.refreshStorageGeneration(null, &state, storage);
    const current_generation = try checker.storageGenerationForPlace(storage, &state);
    try std.testing.expect(captured_generation != current_generation);

    const dependency_only = try checker.dependencyOnlyEffect(.{
        .opaque_generation_dependencies = try checker.oneInputPath(0, &.{}),
    });
    var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(allocator);
    defer fresh_roots.deinit();
    var hidden = std.array_list.Managed(facts.ValidityRootId).init(allocator);
    defer hidden.deinit();
    try checker.instantiateOpaqueDependencies(
        dependency_only,
        &.{.{ .opaque_provenance = &.{.{
            .storage = storage,
            .generation = captured_generation,
        }} }},
        &state,
        &fresh_roots,
        &hidden,
    );

    try std.testing.expect(containsRoot(hidden.items, captured_generation));
    try std.testing.expect(!containsRoot(hidden.items, current_generation));
}

test "array pointer operations reject stale pointer values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(&allocator, &diags);
    defer checker.deinit();

    const location = @import("../2_tokens/token.zig").Location{
        .file = "stale_array_pointer_test.rg",
        .offset = 0,
        .line = 1,
        .column = 1,
    };
    var binding = sg.BindingDeclaration{
        .name = "pointer",
        .location = location,
        .origin_file = location.file,
        .mutability = undefined,
        .ty = undefined,
        .initialization = null,
    };
    var pointer_node = sg.SGNode{ .location = location, .content = .{ .binding_use = &binding } };
    var index_node: sg.SGNode = undefined;
    var array_type: sg.ArrayType = undefined;
    var array_index = sg.SGNode{ .location = location, .content = .{ .array_index = .{
        .array_ptr = &pointer_node,
        .index = &index_node,
        .element_type = undefined,
        .array_type = &array_type,
    } } };
    var value_node: sg.SGNode = undefined;
    var array_store = sg.SGNode{ .location = location, .content = .{ .array_store = .{
        .array_ptr = &pointer_node,
        .index = &index_node,
        .value = &value_node,
        .element_type = undefined,
        .array_type = &array_type,
    } } };
    var block = sg.CodeBlock{ .nodes = &.{&array_store}, .ret_val = null };
    const function = sg.FunctionDeclaration{
        .id = 0,
        .name = "test",
        .location = location,
        .is_once = false,
        .input = undefined,
        .output = undefined,
        .body = null,
    };

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const stale_root = try state.tracker.establish(.fresh);
    state.tracker.end(stale_root);
    try checker.setPlace(&state, .{ .root = &binding }, .initialized, .{
        .dependencies = &.{.{ .root = stale_root }},
    });

    try std.testing.expect(!try checker.validateAddressablePath(&function, &array_index, &state));
    _ = try checker.evaluate(&function, &array_index, &state);
    try checker.validateBlock(&function, &block, &state, null);
    try std.testing.expectEqual(@as(usize, 3), diags.list.items.len);
    for (diags.list.items) |diagnostic|
        try std.testing.expectEqualStrings("reference depends on a root that has ended", diagnostic.msg);
}

test "reference restriction preserves provenance and only adds lifetime dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const pointee_binding = try checker.allocator.create(sg.BindingDeclaration);
    const lifetime_binding = try checker.allocator.create(sg.BindingDeclaration);
    pointee_binding.* = undefined;
    lifetime_binding.* = undefined;
    const pointee = place.Place{ .root = pointee_binding };
    const lifetime = place.Place{ .root = lifetime_binding };
    const pointee_root = try checker.storageGenerationForPlace(pointee, &state);
    const lifetime_root = try checker.storageGenerationForPlace(lifetime, &state);
    const effect = try checker.restrictReferenceEffect();
    try std.testing.expectEqual(@as(usize, 2), effect.input_dependencies.len);
    try std.testing.expect(!effect.input_dependencies[0].transfers_ownership);
    try std.testing.expect(!effect.input_dependencies[1].transfers_ownership);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_storage_capabilities.len);
    const input = [_]facts.ValueFacts{
        .{ .dependencies = &.{.{ .root = pointee_root }}, .referenced_place = pointee },
        .{ .dependencies = &.{.{ .root = lifetime_root }}, .referenced_place = lifetime },
    };

    const restricted = try checker.instantiateOutput(effect, &input, &state);
    try std.testing.expectEqual(@as(usize, 2), restricted.dependencies.len);
    try std.testing.expectEqual(pointee_root, restricted.dependencies[0].root);
    try std.testing.expectEqual(lifetime_root, restricted.dependencies[1].root);
    try std.testing.expect(restricted.referenced_place.?.eql(pointee));
    try std.testing.expectEqual(@as(usize, 0), restricted.owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), restricted.storage_capabilities.len);

    state.tracker.end(lifetime_root);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(restricted));
    try std.testing.expect(state.tracker.dependenciesAreAlive(input[0]));
    state.tracker.end(pointee_root);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(input[0]));
}

test "refreshing a Place drops descendant Storage Generation mappings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const parent = place.Place{ .root = undefined };
    const child = place.Place{ .root = parent.root, .projections = &.{.{ .field = 0 }} };
    const grandchild = place.Place{ .root = parent.root, .projections = &.{ .{ .field = 0 }, .{ .field = 1 } } };
    const sibling = place.Place{ .root = parent.root, .projections = &.{.{ .field = 2 }} };
    const indexed = place.Place{ .root = parent.root, .projections = &.{.{ .static_index = 3 }} };
    const old_parent = try checker.storageGenerationForPlace(parent, &state);
    const old_child = try checker.storageGenerationForPlace(child, &state);
    const old_grandchild = try checker.storageGenerationForPlace(grandchild, &state);
    const old_sibling = try checker.storageGenerationForPlace(sibling, &state);
    const old_indexed = try checker.storageGenerationForPlace(indexed, &state);
    const stale_child = facts.ValueFacts{ .dependencies = &.{.{ .root = old_child }} };

    try checker.refreshStorageGeneration(null, &state, parent);
    const fresh_parent = try checker.storageGenerationForPlace(parent, &state);
    const fresh_child = try checker.storageGenerationForPlace(child, &state);
    const fresh_grandchild = try checker.storageGenerationForPlace(grandchild, &state);
    const fresh_sibling = try checker.storageGenerationForPlace(sibling, &state);
    const fresh_indexed = try checker.storageGenerationForPlace(indexed, &state);
    try std.testing.expect(old_parent != fresh_parent);
    try std.testing.expect(old_child != fresh_child);
    try std.testing.expect(old_grandchild != fresh_grandchild);
    try std.testing.expect(old_sibling != fresh_sibling);
    try std.testing.expect(old_indexed != fresh_indexed);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(stale_child));

    const sibling_before_field_refresh = fresh_sibling;
    try checker.refreshStorageGeneration(null, &state, child);
    try std.testing.expectEqual(sibling_before_field_refresh, try checker.storageGenerationForPlace(sibling, &state));
}

test "opaque dependency projection cannot instantiate ownership or capabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const projected = try checker.dependencyOnlyEffect(.{
        .input_dependencies = &.{.{ .path = .{ .input_index = 0 }, .transfers_ownership = true }},
        .fresh_dependencies = &.{11},
        .fresh_owned_roots = &.{12},
        .fresh_storage_capabilities = &.{13},
        .integer_address = true,
        .foreign_storage = true,
    });
    try std.testing.expect(!projected.input_dependencies[0].transfers_ownership);
    try std.testing.expectEqualSlices(facts.FreshEffectSource, &.{11}, projected.fresh_dependencies);
    try std.testing.expectEqual(@as(usize, 0), projected.fresh_owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), projected.fresh_storage_capabilities.len);
    try std.testing.expect(!projected.integer_address);
    try std.testing.expect(!projected.foreign_storage);

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(allocator);
    defer fresh_roots.deinit();
    var hidden = std.array_list.Managed(facts.ValidityRootId).init(allocator);
    defer hidden.deinit();
    try checker.instantiateOpaqueDependencies(projected, &.{.{}}, &state, &fresh_roots, &hidden);
    try std.testing.expectEqual(@as(usize, 1), state.tracker.roots.items.len);
    try std.testing.expect(!state.tracker.roots.items[0].owned_resource);
    try std.testing.expectEqual(@as(usize, 0), state.storage_capabilities.items.len);
}

test "opaque move-out recovers external dependencies without backing roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var binding: sg.BindingDeclaration = undefined;
    const storage = place.Place{ .root = &binding };
    const backing = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(backing)].owned_resource = true;
    const storage_generation = try checker.storageGenerationForPlace(storage, &state);
    const external = try state.tracker.establish(.fresh);
    try checker.setPlace(&state, storage, .initialized, .{ .owned_roots = &.{backing} });
    try checker.mergeOpaqueStorage(&state, storage, &.{ backing, storage_generation, external });

    const moved_out = try checker.instantiateOutput(.{
        .opaque_storage_dependencies = try checker.oneInputPath(0, &.{}),
        .fresh_owned_roots = &.{91},
    }, &.{.{ .referenced_place = storage }}, &state);
    try std.testing.expect(valueDependsOnRoot(moved_out, external));
    try std.testing.expect(!valueDependsOnRoot(moved_out, backing));
    try std.testing.expect(!valueDependsOnRoot(moved_out, storage_generation));
    try std.testing.expectEqual(@as(usize, 1), moved_out.owned_roots.len);
}
