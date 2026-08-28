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
    summaries: std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary),
    virtual_summaries: std.AutoHashMap(*const sg.VirtualMethodRegistry, facts.FunctionSummary),
    invalid_virtual_summaries: std.AutoHashMap(*const sg.VirtualMethodRegistry, void),
    inference_bindings: ?*std.AutoHashMap(*const sg.BindingDeclaration, facts.OutputEffect),
    inference_place_bindings: ?*std.AutoHashMap(*const sg.BindingDeclaration, []const facts.InputPath),

    pub fn init(allocator: *const std.mem.Allocator, diags: *diagnostics.Diagnostics) SafetyChecker {
        return .{
            .allocator = allocator,
            .diagnostics = diags,
            .summaries = std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary).init(allocator.*),
            .virtual_summaries = std.AutoHashMap(*const sg.VirtualMethodRegistry, facts.FunctionSummary).init(allocator.*),
            .invalid_virtual_summaries = std.AutoHashMap(*const sg.VirtualMethodRegistry, void).init(allocator.*),
            .inference_bindings = null,
            .inference_place_bindings = null,
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
        const OwnershipEdge = struct { owner: facts.RootId, owned: facts.RootId };
        const StorageRoot = struct { storage: place.Place, root: facts.RootId };
        const OpaqueStorage = struct { storage: place.Place, hidden_dependencies: []const facts.RootId };
        const ChoiceActive = struct { storage: place.Place, variant_index: u32 };
        const ChoiceRejected = struct { storage: place.Place, variant_index: u32 };
        const StorageAuthorityState = enum { available, conditional, maybe_consumed, consumed };
        tracker: facts.Tracker,
        storage_authorities: std.array_list.Managed(StorageAuthorityState),
        places: std.array_list.Managed(facts.PlaceFacts),
        ownership_edges: std.array_list.Managed(OwnershipEdge),
        storage_roots: std.array_list.Managed(StorageRoot),
        opaque_storages: std.array_list.Managed(OpaqueStorage),
        choice_active: std.array_list.Managed(ChoiceActive),
        choice_rejected: std.array_list.Managed(ChoiceRejected),
        reachable: bool = true,
        ownership_conflict_reported: bool = false,

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .storage_authorities = std.array_list.Managed(StorageAuthorityState).init(allocator),
                .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
                .ownership_edges = std.array_list.Managed(OwnershipEdge).init(allocator),
                .storage_roots = std.array_list.Managed(StorageRoot).init(allocator),
                .opaque_storages = std.array_list.Managed(OpaqueStorage).init(allocator),
                .choice_active = std.array_list.Managed(ChoiceActive).init(allocator),
                .choice_rejected = std.array_list.Managed(ChoiceRejected).init(allocator),
            };
        }

        fn deinit(self: *FunctionState) void {
            self.tracker.deinit();
            self.storage_authorities.deinit();
            self.places.deinit();
            self.ownership_edges.deinit();
            self.storage_roots.deinit();
            self.opaque_storages.deinit();
            self.choice_active.deinit();
            self.choice_rejected.deinit();
        }

        fn clone(self: *const FunctionState, allocator: std.mem.Allocator) !FunctionState {
            var result = FunctionState.init(allocator);
            errdefer result.deinit();
            try result.tracker.roots.appendSlice(self.tracker.roots.items);
            try result.storage_authorities.appendSlice(self.storage_authorities.items);
            try result.places.appendSlice(self.places.items);
            try result.ownership_edges.appendSlice(self.ownership_edges.items);
            try result.storage_roots.appendSlice(self.storage_roots.items);
            try result.opaque_storages.appendSlice(self.opaque_storages.items);
            try result.choice_active.appendSlice(self.choice_active.items);
            try result.choice_rejected.appendSlice(self.choice_rejected.items);
            result.reachable = self.reachable;
            result.ownership_conflict_reported = self.ownership_conflict_reported;
            return result;
        }
    };

    fn validateFunction(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        const body = function.body orelse return;
        if (function.safety_primitive != .none) return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        // Argi pointer parameters may alias. Until a call-site proof can
        // partition them, one shared root conservatively represents any
        // temporal invalidation observable through compatible inputs.
        var pointer_input_root: ?facts.RootId = null;
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
        try self.validateBlock(function, body, &state);
        if (state.reachable) try self.rejectEscapingLocalRoots(function, &state);
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
    ) anyerror!void {
        for (block.nodes) |node| {
            switch (node.content) {
                .binding_declaration => |binding| {
                    const value = if (binding.initialization) |initialization|
                        try self.evaluate(function, initialization, state)
                    else
                        facts.ValueFacts{};
                    try self.setPlace(state, .{ .root = binding }, .initialized, value);
                },
                .binding_assignment => |assignment| {
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.setPlace(state, .{ .root = assignment.sym_id }, .initialized, value);
                },
                .auto_deinit_binding => |cleanup| {
                    const storage = place.Place{ .root = cleanup.binding };
                    if (self.getPlace(state, storage)) |owned_value| {
                        if (!try self.endRoots(function, state, owned_value.value.owned_roots)) continue;
                    }
                    try self.setPlace(state, storage, .deinitialized, .{});
                },
                .struct_field_store => |store| {
                    const pointer = try self.evaluate(function, store.struct_ptr, state);
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
                    const pointer = try self.evaluate(function, store.array_ptr, state);
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
                    const pointer = try self.evaluate(function, assignment.pointer, state);
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
                        try self.refreshStorageRoot(function, state, target);
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
                    try self.validateBlock(function, statement.then_block, &then_state);
                    var else_state = try state.clone(self.allocator.*);
                    defer else_state.deinit();
                    if (statement.choice_test) |tag_test|
                        try self.refineChoiceTest(function, tag_test, &else_state, !tag_test.then_has_variant);
                    if (statement.else_block) |else_block| try self.validateBlock(function, else_block, &else_state);
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
                        try self.refineChoiceVariant(try self.resolvePlace(statement.expression, &branch), choice, statement.expression.sem_type.?.choice_type.variants.len, case.variant_index, true, &branch);
                        try self.validateBlock(function, case.body, &branch);
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
                        try self.validateBlock(function, default_case, &branch);
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
                else => {},
            }
            try self.validateUniqueOwnership(function, state);
            if (!state.reachable) return;
        }
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
                const result = if (moving_choice and try self.resolvePlace(value, state) != null)
                    self.valueAtPlace(state, (try self.resolvePlace(value, state)).?) orelse facts.ValueFacts{}
                else
                    try self.evaluate(function, value, state);
                if (try self.resolvePlace(value, state)) |source|
                    try self.setPlace(state, source, .moved, if (moving_choice) result else .{});
                break :blk result;
            },
            .address_of => |value| blk: {
                const target = try self.resolvePlace(value, state);
                const opaque_origins = try self.opaqueOriginsForAccess(value, state);
                var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
                if (opaque_origins.len == 0) {
                    try appendDependency(&dependencies, .{ .root = try self.storageRoot(value, state) });
                } else {
                    for (opaque_origins) |origin|
                        try appendDependency(&dependencies, .{ .root = try self.storageRootForPlace(origin, state) });
                }
                break :blk .{
                    .dependencies = try dependencies.toOwnedSlice(),
                    .referenced_place = target,
                    .opaque_origins = opaque_origins,
                };
            },
            .dereference => |dereference| blk: {
                const pointer = try self.evaluate(function, dereference.pointer, state);
                if (!state.tracker.dependenciesAreAlive(pointer)) {
                    try self.diagnostics.add(function.location, .semantic, "reference depends on a root that has ended", .{});
                }
                if (pointer.referenced_place) |target| {
                    if (self.getPlace(state, target)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
                    }
                }
                break :blk facts.ValueFacts{};
            },
            .struct_value_literal => |literal| try self.aggregate(function, literal.fields, state),
            .struct_field_access => |access| blk: {
                if (try self.resolvePlace(node, state)) |storage| {
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
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
                const choice = if (try self.resolvePlace(access.choice_value, state)) |storage|
                    self.valueAtPlace(state, storage) orelse facts.ValueFacts{}
                else
                    try self.evaluate(function, access.choice_value, state);
                if (try self.resolvePlace(access.choice_value, state)) |storage| {
                    if (!self.choiceVariantIsActive(state, storage, access.variant_index)) {
                        try self.diagnostics.add(function.location, .semantic, "choice payload '..{d}' requires its variant to be proven active", .{access.variant_index});
                        break :blk .{};
                    }
                } else {
                    try self.diagnostics.add(function.location, .semantic, "choice payload access requires a choice Place with a proven active variant", .{});
                    break :blk .{};
                }
                for (choice.variants) |variant| {
                    if (variant.index == access.variant_index) break :blk variant.value.*;
                }
                break :blk .{};
            },
            .array_index => |index| blk: {
                _ = try self.evaluate(function, index.array_ptr, state);
                if (try self.resolvePlace(node, state)) |storage| {
                    if (self.getPlace(state, storage)) |place_facts| {
                        try self.requireInitialized(function, place_facts);
                        break :blk place_facts.value;
                    }
                }
                break :blk .{};
            },
            .explicit_cast => |cast| blk: {
                const value = try self.evaluate(function, cast.value, state);
                const target_is_integer = cast.target_type == .builtin and cast.target_type.builtin == .UIntNative;
                const target_is_reference = cast.target_type == .pointer_type;
                const target_is_raw_any = target_is_reference and
                    cast.target_type.pointer_type.child.* == .builtin and
                    cast.target_type.pointer_type.child.*.builtin == .Any;
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
                        .storage_authorities = value.storage_authorities,
                    };
                if (target_is_reference and !target_is_raw_any and (source_is_integer or value.integer_address)) {
                    try self.diagnostics.add(function.location, .semantic, "an integer address cannot establish a safe reference; use RawPointer and explicit root establishment", .{});
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
        if (call.callee.safety_primitive == .trusted_opaque_store_owned or
            call.callee.safety_primitive == .trusted_opaque_store_owned_in)
        {
            if (argument_values.len == 3) {
                try self.closeOpaqueOwnedRoots(function, argument_values[2], state);
                if (argument_values[0].referenced_place) |storage| {
                    try self.markOpaqueAccess(arguments[1].value, state, storage);
                    try self.hideOpaqueDependencies(state, storage, argument_values[2]);
                } else if (rootBinding(arguments[0].value)) |binding| {
                    // Pointer inputs name caller storage symbolically. The
                    // FunctionSummary carries this obligation to the caller,
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
                try self.closeOpaqueOwnedRoots(function, argument_values[1], state);
                if (try self.inferOpaqueDomain(state, argument_values[0])) |storage| {
                    try self.markOpaqueAccess(arguments[0].value, state, storage);
                    try self.hideOpaqueDependencies(state, storage, argument_values[1]);
                }
            }
            return .{};
        }
        // Opaque-slot occupancy and contents deliberately have no precise
        // checker representation. Relocation only consults domain-level
        // dependencies; its source-live/destination-empty contract remains
        // the caller's responsibility.
        if (call.callee.safety_primitive == .trusted_opaque_relocate_owned) {
            if (argument_values.len != 0) try self.rejectOpaqueRelocation(function, state, argument_values[0]);
            return .{};
        }
        if (call.callee.safety_primitive == .raw_allocated_storage) {
            const authority: facts.StorageAuthorityId = @enumFromInt(state.storage_authorities.items.len);
            try state.storage_authorities.append(.available);
            return .{ .foreign_storage = true, .storage_authorities = try self.oneStorageAuthority(authority) };
        }
        if (call.callee.safety_primitive == .establish_fresh_reference)
            try self.diagnostics.add(function.location, .semantic, "fresh raw-to-safe reference establishment is restricted to compiler-owned storage boundaries", .{});
        if (call.callee.safety_primitive == .establish_allocation or
            call.callee.safety_primitive == .establish_inherited_reference or
            call.callee.safety_primitive == .establish_inherited_storage)
        {
            const requires_authority = call.callee.safety_primitive == .establish_allocation or
                call.callee.safety_primitive == .establish_inherited_storage;
            if (requires_authority and (argument_values.len == 0 or argument_values[0].storage_authorities.len == 0)) {
                try self.diagnostics.add(function.location, .semantic, "allocation root establishment requires storage returned by an authorized allocator boundary", .{});
            } else if (argument_values.len != 0) {
                for (argument_values[0].storage_authorities) |authority| {
                    const index = @intFromEnum(authority);
                    if (index >= state.storage_authorities.items.len or state.storage_authorities.items[index] != .available) {
                        try self.diagnostics.add(function.location, .semantic, "physical storage authority has already been consumed", .{});
                    } else {
                        state.storage_authorities.items[index] = .consumed;
                    }
                }
            }
        }
        if (call.callee.body == null and call.callee.output.fields.len == 1 and
            call.callee.output.fields[0].ty == .pointer_type)
            return .{ .foreign_storage = true };
        const summary = self.summaries.get(call.callee) orelse return .{};
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
        try self.applyInputEffects(function, summary, arguments, argument_values, state);
        try self.applyOpaqueStorageEffects(summary, arguments, argument_values, state);
        if (summary.outputs.len != 1) return .{};
        return self.instantiateOutput(summary.outputs[0], argument_values, state);
    }

    /// Relocation transfers one existing value representation between distinct
    /// Places. It deliberately leaves structural storage roots alone: aliases
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

    fn closeOpaqueOwnedRoots(self: *SafetyChecker, function: *const sg.FunctionDeclaration, value: facts.ValueFacts, state: *FunctionState) !void {
        var roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        defer roots.deinit();
        try collectOwnedRoots(value, &roots);
        // Validate the complete boundary before changing root liveness. A
        // rejected call must not leave analysis state partly committed.
        for (roots.items) |root| {
            for (state.places.items) |candidate| {
                if (candidate.initializedness != .initialized or !valueDependsOnRoot(candidate.value, root)) continue;
                try self.diagnostics.add(function.location, .semantic, "opaque ownership storage requires no live external aliases to the consumed root", .{});
                return;
            }
        }
        _ = try self.endRoots(function, state, roots.items);
    }

    fn hideOpaqueDependencies(self: *SafetyChecker, state: *FunctionState, storage: place.Place, value: facts.ValueFacts) !void {
        var hidden = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        defer hidden.deinit();
        try self.collectOpaqueHiddenDependencies(state, value, &hidden);
        try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
    }

    /// Opaque origins are destination provenance when a pointer is used for
    /// access, but temporal value provenance when that pointer is stored as
    /// data. In the latter role each origin depends on the domain's logical
    /// storage generation. Domain inference also covers aliases created before
    /// their backing storage was registered as opaque.
    fn collectOpaqueHiddenDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        value: facts.ValueFacts,
        hidden: *std.array_list.Managed(facts.RootId),
    ) !void {
        for (value.dependencies) |dependency| try appendOwnedRoot(hidden, dependency.root);

        var origins = std.array_list.Managed(place.Place).init(self.allocator.*);
        defer origins.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, value, &origins);
        for (origins.items) |origin|
            try appendOwnedRoot(hidden, try self.storageRootForPlace(origin, state));

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
        var origins = std.array_list.Managed(place.Place).init(self.allocator.*);
        try origins.appendSlice(pointer.value.opaque_origins);
        try appendPlace(&origins, storage);
        pointer.value.opaque_origins = try origins.toOwnedSlice();
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
        for (pointer.opaque_origins) |storage| try appendPlace(result, storage);
        for (state.opaque_storages.items) |opaque_storage| {
            if (self.valueAtPlace(state, opaque_storage.storage)) |storage_value| {
                for (pointer.dependencies) |dependency|
                    if (valueContainsOwnedRoot(storage_value, dependency.root)) try appendPlace(result, opaque_storage.storage);
            }
            for (state.storage_roots.items) |entry| {
                if (!opaque_storage.storage.isPrefixOf(entry.storage)) continue;
                for (pointer.dependencies) |dependency|
                    if (dependency.root == entry.root) try appendPlace(result, opaque_storage.storage);
            }
        }
    }

    fn opaqueOriginsForAccess(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) ![]const place.Place {
        return switch (node.content) {
            .binding_use => |binding| blk: {
                const value = self.getPlace(state, .{ .root = binding }) orelse break :blk &.{};
                var origins = std.array_list.Managed(place.Place).init(self.allocator.*);
                try self.collectOpaqueDomainsAccessedBy(state, value.value, &origins);
                break :blk try origins.toOwnedSlice();
            },
            .move_value => |value| try self.opaqueOriginsForAccess(value, state),
            .address_of => |value| try self.opaqueOriginsForAccess(value, state),
            .struct_field_access => |access| try self.opaqueOriginsForAccess(access.struct_value, state),
            .array_index => |index| try self.opaqueOriginsForAccess(index.array_ptr, state),
            .dereference => |dereference| blk: {
                const pointer_place = try self.resolvePlace(dereference.pointer, state) orelse break :blk &.{};
                const pointer = self.getPlace(state, pointer_place) orelse break :blk &.{};
                var origins = std.array_list.Managed(place.Place).init(self.allocator.*);
                try self.collectOpaqueDomainsAccessedBy(state, pointer.value, &origins);
                break :blk try origins.toOwnedSlice();
            },
            else => &.{},
        };
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
            const storage_root = try self.storageRootForPlace(storage, state);
            for (state.opaque_storages.items) |opaque_storage| {
                if (!opaque_storage.storage.eql(storage) or !containsRoot(opaque_storage.hidden_dependencies, storage_root)) continue;
                try self.diagnostics.add(function.location, .semantic, "relocation would invalidate a hidden opaque dependency", .{});
                return;
            }
        }
    }

    fn applyOpaqueStorageEffects(
        self: *SafetyChecker,
        summary: facts.FunctionSummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_effects) |effect| {
            if (effect.storage.input_index >= arguments.len) continue;
            var storage = argument_values[effect.storage.input_index].referenced_place orelse
                try self.resolvePlace(arguments[effect.storage.input_index].value, state) orelse continue;
            for (effect.storage.projections) |projection| storage = try self.projectedPlace(storage, projection);
            var hidden = std.array_list.Managed(facts.RootId).init(self.allocator.*);
            defer hidden.deinit();
            var fresh_roots = std.AutoHashMap(facts.FreshRootSource, facts.RootId).init(self.allocator.*);
            defer fresh_roots.deinit();
            try self.instantiateOpaqueDependencies(effect.hidden_dependencies, argument_values, state, &fresh_roots, &hidden);
            try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
        }
    }

    fn mergeLiveOpaqueDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        dependencies: []const facts.RootId,
    ) !void {
        var live = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        defer live.deinit();
        for (dependencies) |dependency|
            if (state.tracker.isAlive(dependency)) try appendOwnedRoot(&live, dependency);
        try self.mergeOpaqueStorage(state, storage, live.items);
    }

    fn instantiateOpaqueDependencies(
        self: *SafetyChecker,
        effect: facts.OutputEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshRootSource, facts.RootId),
        hidden: *std.array_list.Managed(facts.RootId),
    ) !void {
        for (effect.fresh_dependencies) |source|
            try appendOwnedRoot(hidden, try self.instantiateFreshRoot(source, state, fresh_roots));
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            var target = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| target = try self.projectedPlace(target, projection);
            try appendOwnedRoot(hidden, try self.storageRootForPlace(target, state));
        }
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            const input = projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
            try self.collectOpaqueHiddenDependencies(state, input, hidden);
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
        const summary = try self.virtualSummary(call.safety_methods) orelse {
            if (self.invalid_virtual_summaries.contains(call.safety_methods))
                try self.diagnostics.add(call.input.location, .semantic, "virtual method '{s}' has incompatible safety effects across implementations", .{call.method_name});
            return .{};
        };
        for (summary.input_post_states) |post_state| {
            const index = post_state.target.input_index;
            if ((post_state.initializedness != .deinitialized and post_state.initializedness != .moved) or
                post_state.target.projections.len != 0 or index >= arguments.len) continue;
            if (arguments[index].value.content == .address_of and rootBinding(arguments[index].value.content.address_of) != null) {
                @constCast(call).consumes_auto_deinit = arguments[index].value.content.address_of;
            }
        }
        try self.applyInputEffects(function, summary, arguments, argument_values, state);
        try self.applyOpaqueStorageEffects(summary, arguments, argument_values, state);
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

    fn applyInputEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        summary: facts.FunctionSummary,
        arguments: []const sg.StructValueLiteralField,
        argument_values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        var fresh_roots = std.AutoHashMap(facts.FreshRootSource, facts.RootId).init(self.allocator.*);
        defer fresh_roots.deinit();
        var fresh_authorities = std.AutoHashMap(facts.FreshRootSource, facts.StorageAuthorityId).init(self.allocator.*);
        defer fresh_authorities.deinit();
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
                post_state.target.projections.len != 0)
            {
                var opaque_storages = std.array_list.Managed(place.Place).init(self.allocator.*);
                defer opaque_storages.deinit();
                try self.collectOpaqueDomainsAccessedBy(state, argument_values[post_state.target.input_index], &opaque_storages);
                if (opaque_storages.items.len != 0) {
                    var hidden = std.array_list.Managed(facts.RootId).init(self.allocator.*);
                    defer hidden.deinit();
                    try self.instantiateOpaqueDependencies(post_state.value, argument_values, state, &fresh_roots, &hidden);
                    for (opaque_storages.items) |storage|
                        try self.mergeLiveOpaqueDependencies(state, storage, hidden.items);
                }
            }
            if (post_state.opaque_ownership == .maybe) {
                try self.diagnostics.add(function.location, .semantic, "opaque ownership storage is conditional and cannot be summarized safely", .{});
                continue;
            }
            if (post_state.opaque_ownership == .definite) {
                const value = projectValueFacts(argument_values[post_state.target.input_index], post_state.target.projections);
                const opaque_path = post_state.opaque_storage orelse {
                    if (hasExternalOpaqueDependency(value, value.owned_roots))
                        try self.diagnostics.add(function.location, .semantic, "opaque ownership storage cannot hide dependencies on external roots", .{});
                    try self.closeOpaqueOwnedRoots(function, value, state);
                    continue;
                };
                if (opaque_path.input_index >= arguments.len) continue;
                var storage = argument_values[opaque_path.input_index].referenced_place orelse
                    try self.resolvePlace(arguments[opaque_path.input_index].value, state) orelse continue;
                for (opaque_path.projections) |projection| storage = try self.projectedPlace(storage, projection);
                // Match the primitive boundary: consuming the old ownership
                // is validated before the destination storage starts hiding
                // the transferred value's dependencies.
                try self.closeOpaqueOwnedRoots(function, value, state);
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
            if (post_state.ends_previous_roots) {
                if (self.valueAtPlace(state, target)) |old| {
                    for (old.owned_roots) |root| _ = try self.endRoot(function, state, root);
                }
            }
            if (post_state.initializedness == .deinitialized) try self.endStorageRootsUnder(function, state, target);
            if (!post_state.requires_available_destination and (reinitializes_dead_place or post_state.refreshes_storage_root))
                try self.refreshStorageRoot(function, state, target);
            const value = if (post_state.initializedness == .initialized)
                try self.instantiateOutputWithFresh(post_state.value, argument_values, state, &fresh_roots, &fresh_authorities)
            else
                facts.ValueFacts{};
            try self.setPlace(state, target, post_state.initializedness, value);
        }
    }

    fn inputEffectTarget(
        self: *SafetyChecker,
        post_state: facts.InputPlaceEffect,
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
            .deinitialized => try self.refreshStorageRoot(function, state, destination),
            .moved => {},
        }
        return true;
    }

    fn instantiateOutput(
        self: *SafetyChecker,
        effect: facts.OutputEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        var fresh_roots = std.AutoHashMap(facts.FreshRootSource, facts.RootId).init(self.allocator.*);
        defer fresh_roots.deinit();
        var fresh_authorities = std.AutoHashMap(facts.FreshRootSource, facts.StorageAuthorityId).init(self.allocator.*);
        defer fresh_authorities.deinit();
        return self.instantiateOutputWithFresh(effect, arguments, state, &fresh_roots, &fresh_authorities);
    }

    fn instantiateOutputWithFresh(
        self: *SafetyChecker,
        effect: facts.OutputEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshRootSource, facts.RootId),
        fresh_authorities: *std.AutoHashMap(facts.FreshRootSource, facts.StorageAuthorityId),
    ) !facts.ValueFacts {
        var result: facts.ValueFacts = .{};
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        for (effect.fresh_dependencies) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            try appendDependency(&dependencies, .{ .root = root });
        }
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (effect.fresh_owned_roots) |source| {
            const root = try self.instantiateFreshRoot(source, state, fresh_roots);
            state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
            try appendOwnedRoot(&owned_roots, root);
        }
        result.owned_roots = try owned_roots.toOwnedSlice();
        var authorities = std.array_list.Managed(facts.StorageAuthorityId).init(self.allocator.*);
        for (effect.fresh_storage_authorities) |source|
            try appendStorageAuthority(&authorities, try self.instantiateFreshStorageAuthority(source, state, fresh_authorities));
        result.storage_authorities = try authorities.toOwnedSlice();
        // `input_places` names the provenance of the output. Apply it after
        // dependencies: an effect may intentionally combine a reference with
        // unrelated lifetime dependencies without changing where it points.
        var referenced_place: ?place.Place = null;
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            if (arguments[path.input_index].referenced_place) |argument_place| {
                var target = argument_place;
                for (path.projections) |projection| target = try self.projectedPlace(target, projection);
                try appendDependency(&dependencies, .{ .root = try self.storageRootForPlace(target, state) });
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
        if (effect.fields.len != 0) {
            const enclosing_variants = result.variants;
            const fields = try self.allocator.alloc(facts.FieldFacts, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(field.value.*, arguments, state, fresh_roots, fresh_authorities);
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
                const first_authority = state.storage_authorities.items.len;
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(variant.value.*, arguments, state, fresh_roots, fresh_authorities);
                for (state.tracker.roots.items[first_root..]) |*root| root.state = .conditional;
                for (state.storage_authorities.items[first_authority..]) |*authority| authority.* = .conditional;
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        result.integer_address = effect.integer_address;
        result.foreign_storage = result.foreign_storage or effect.foreign_storage;
        if (referenced_place) |target| result.referenced_place = target;
        return result;
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
        try self.refineChoiceVariant(try self.resolvePlace(tag_test.choice_value, state), choice, tag_test.choice_type.variants.len, tag_test.variant_index, has_variant, state);
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
        choice: facts.ValueFacts,
        variant_count: usize,
        variant_index: u32,
        has_variant: bool,
        state: *FunctionState,
    ) !void {
        if (has_variant) {
            self.activateChoiceVariant(choice, variant_index, state);
            if (storage) |target| try self.setChoiceActive(state, target, variant_index);
            return;
        }

        for (choice.variants) |variant| if (variant.index == variant_index) {
            rejectConditionalFacts(variant.value.*, state);
            break;
        };
        const target = storage orelse return;
        try self.setChoiceRejected(state, target, variant_index);
        var remaining: ?u32 = null;
        for (0..variant_count) |index| {
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

    fn setChoiceRejected(self: *SafetyChecker, state: *FunctionState, storage: place.Place, variant_index: u32) !void {
        if (self.choiceVariantIsRejected(state, storage, variant_index)) return;
        try state.choice_rejected.append(.{ .storage = storage, .variant_index = variant_index });
    }

    fn choiceVariantIsActive(self: *SafetyChecker, state: *const FunctionState, storage: place.Place, variant_index: u32) bool {
        _ = self;
        for (state.choice_active.items) |active|
            if (active.storage.eql(storage)) return active.variant_index == variant_index;
        return false;
    }

    fn choiceVariantIsRejected(self: *SafetyChecker, state: *const FunctionState, storage: place.Place, variant_index: u32) bool {
        _ = self;
        for (state.choice_rejected.items) |rejected|
            if (rejected.storage.eql(storage) and rejected.variant_index == variant_index) return true;
        return false;
    }

    fn instantiateFreshStorageAuthority(self: *SafetyChecker, source: facts.FreshRootSource, state: *FunctionState, fresh: *std.AutoHashMap(facts.FreshRootSource, facts.StorageAuthorityId)) !facts.StorageAuthorityId {
        _ = self;
        if (fresh.get(source)) |authority| return authority;
        const authority: facts.StorageAuthorityId = @enumFromInt(state.storage_authorities.items.len);
        try state.storage_authorities.append(.available);
        try fresh.put(source, authority);
        return authority;
    }

    fn instantiateFreshRoot(
        self: *SafetyChecker,
        source: facts.FreshRootSource,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshRootSource, facts.RootId),
    ) !facts.RootId {
        _ = self;
        if (fresh_roots.get(source)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try fresh_roots.put(source, root);
        return root;
    }

    fn mergeValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        for (left.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        for (right.dependencies) |dependency| try appendDependency(&dependencies, dependency);
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (left.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        for (right.owned_roots) |owned_root| try appendOwnedRoot(&owned_roots, owned_root);
        var authorities = std.array_list.Managed(facts.StorageAuthorityId).init(self.allocator.*);
        for (left.storage_authorities) |authority| try appendStorageAuthority(&authorities, authority);
        for (right.storage_authorities) |authority| try appendStorageAuthority(&authorities, authority);
        var opaque_origins = std.array_list.Managed(place.Place).init(self.allocator.*);
        for (left.opaque_origins) |origin| try appendPlace(&opaque_origins, origin);
        for (right.opaque_origins) |origin| try appendPlace(&opaque_origins, origin);
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
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .storage_authorities = try authorities.toOwnedSlice(),
            .referenced_place = if (left.referenced_place != null and right.referenced_place != null and left.referenced_place.?.eql(right.referenced_place.?))
                left.referenced_place
            else
                null,
            .opaque_origins = try opaque_origins.toOwnedSlice(),
        };
    }

    /// Dependencies and cleanup obligations both widen at a join. A place may
    /// own a root on only some incoming paths; initializedness records that the
    /// value cannot be used unconditionally, while auto-deinit consumes the
    /// remaining per-path obligation through its runtime drop flag.
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
            const id: facts.RootId = @enumFromInt(index);
            const left_state = if (index < left.tracker.roots.items.len) left.tracker.roots.items[index].state else .dead;
            const right_state = if (index < right.tracker.roots.items.len) right.tracker.roots.items[index].state else .dead;
            const root_state: @TypeOf(left_state) = if (left_state == right_state)
                left_state
            else
                .maybe_alive;
            const left_owned = index < left.tracker.roots.items.len and left.tracker.roots.items[index].owned_resource;
            const right_owned = index < right.tracker.roots.items.len and right.tracker.roots.items[index].owned_resource;
            try joined.tracker.roots.append(.{ .id = id, .state = root_state, .owned_resource = left_owned or right_owned });
        }
        const authority_count = @max(left.storage_authorities.items.len, right.storage_authorities.items.len);
        for (0..authority_count) |index| {
            const left_state: FunctionState.StorageAuthorityState = if (index < left.storage_authorities.items.len) left.storage_authorities.items[index] else .consumed;
            const right_state: FunctionState.StorageAuthorityState = if (index < right.storage_authorities.items.len) right.storage_authorities.items[index] else .consumed;
            try joined.storage_authorities.append(if (left_state == right_state) left_state else .maybe_consumed);
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
        try joined.storage_roots.appendSlice(left.storage_roots.items);
        for (right.storage_roots.items) |candidate| {
            var found = false;
            for (joined.storage_roots.items) |existing| if (existing.storage.eql(candidate.storage)) {
                found = true;
                break;
            };
            if (!found) try joined.storage_roots.append(candidate);
        }
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
        joined.reachable = true;
        joined.ownership_conflict_reported = left.ownership_conflict_reported or right.ownership_conflict_reported;
        destination.deinit();
        destination.* = joined;
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
        for (existing_places) |place_facts| _ = try self.storageRootForPlace(place_facts.storage, state);
        var entry = try state.clone(self.allocator.*);
        defer entry.deinit();
        var current = try state.clone(self.allocator.*);
        defer current.deinit();
        for (0..8) |_| {
            var iteration = try current.clone(self.allocator.*);
            defer iteration.deinit();
            try self.validateBlock(function, body, &iteration);
            if (iteration.reachable) {
                if (increment) |node| _ = try self.evaluate(function, node, &iteration);
            }
            var next = try entry.clone(self.allocator.*);
            try self.joinStates(function, &next, &entry, &iteration);
            if (statesEqual(&current, &next)) {
                try self.copyState(state, &next);
                next.deinit();
                return;
            }
            current.deinit();
            current = next;
        }
        try self.copyState(state, &current);
    }

    fn aggregate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var contains_integer_address = false;
        var contains_foreign_storage = false;
        var storage_authorities = std.array_list.Managed(facts.StorageAuthorityId).init(self.allocator.*);
        for (fields, 0..) |field, index| {
            const value = try self.evaluate(function, field.value, state);
            try dependencies.appendSlice(value.dependencies);
            try owned_roots.appendSlice(value.owned_roots);
            const stored = try self.allocator.create(facts.ValueFacts);
            stored.* = value;
            try field_facts.append(.{ .index = @intCast(index), .value = stored });
            contains_integer_address = contains_integer_address or value.integer_address;
            contains_foreign_storage = contains_foreign_storage or value.foreign_storage;
            for (value.storage_authorities) |authority| try appendStorageAuthority(&storage_authorities, authority);
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .owned_roots = try owned_roots.toOwnedSlice(),
            .fields = try field_facts.toOwnedSlice(),
            .integer_address = contains_integer_address,
            .foreign_storage = contains_foreign_storage,
            .storage_authorities = try storage_authorities.toOwnedSlice(),
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
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        var owned_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        var field_facts = std.array_list.Managed(facts.FieldFacts).init(self.allocator.*);
        var storage_authorities = std.array_list.Managed(facts.StorageAuthorityId).init(self.allocator.*);
        var opaque_origins = std.array_list.Managed(place.Place).init(self.allocator.*);
        var contains_integer_address = false;
        var contains_foreign_storage = false;
        for (fields, 0..) |field, index| {
            const value = try self.evaluateOpaqueMutationValue(function, field.value, state);
            for (value.dependencies) |dependency| try appendDependency(&dependencies, dependency);
            for (value.owned_roots) |root| try appendOwnedRoot(&owned_roots, root);
            for (value.storage_authorities) |authority| try appendStorageAuthority(&storage_authorities, authority);
            for (value.opaque_origins) |origin| try appendPlace(&opaque_origins, origin);
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
            .storage_authorities = try storage_authorities.toOwnedSlice(),
            .opaque_origins = try opaque_origins.toOwnedSlice(),
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

    fn storageRoot(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !facts.RootId {
        const storage = try self.resolvePlace(node, state) orelse return state.tracker.establish(.fresh);
        return self.storageRootForPlace(storage, state);
    }

    fn storageRootForPlace(self: *SafetyChecker, storage: place.Place, state: *FunctionState) !facts.RootId {
        _ = self;
        for (state.storage_roots.items) |entry| if (entry.storage.eql(storage)) return entry.root;
        const root = try state.tracker.establish(.fresh);
        try state.storage_roots.append(.{ .storage = storage, .root = root });
        return root;
    }

    fn mergeOpaqueStorage(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: place.Place,
        dependencies: []const facts.RootId,
    ) !void {
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            var merged = std.array_list.Managed(facts.RootId).init(self.allocator.*);
            try merged.appendSlice(opaque_storage.hidden_dependencies);
            for (dependencies) |dependency| try appendOwnedRoot(&merged, dependency);
            opaque_storage.hidden_dependencies = try merged.toOwnedSlice();
            return;
        }
        var hidden = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (dependencies) |dependency| try appendOwnedRoot(&hidden, dependency);
        try state.opaque_storages.append(.{
            .storage = storage,
            .hidden_dependencies = try hidden.toOwnedSlice(),
        });
    }

    fn rootIsHidden(state: *const FunctionState, root: facts.RootId) bool {
        for (state.opaque_storages.items) |opaque_storage|
            if (containsRoot(opaque_storage.hidden_dependencies, root)) return true;
        return false;
    }

    fn endRoot(
        self: *SafetyChecker,
        function: ?*const sg.FunctionDeclaration,
        state: *FunctionState,
        root: facts.RootId,
    ) !bool {
        return self.endRoots(function, state, &.{root});
    }

    fn endRoots(
        self: *SafetyChecker,
        function: ?*const sg.FunctionDeclaration,
        state: *FunctionState,
        roots: []const facts.RootId,
    ) !bool {
        // Root termination is a transaction: opaque barriers are checked for
        // the complete batch before any liveness fact changes.
        for (roots) |root| {
            if (!rootIsHidden(state, root)) continue;
            if (function) |current|
                try self.diagnostics.add(current.location, .semantic, "cannot end a root while opaque storage hides a dependency on it", .{});
            return false;
        }
        for (roots) |root| state.tracker.end(root);
        return true;
    }

    fn refreshStorageRoot(self: *SafetyChecker, function: ?*const sg.FunctionDeclaration, state: *FunctionState, storage: place.Place) !void {
        for (state.storage_roots.items) |entry| {
            if (storage.isPrefixOf(entry.storage) and rootIsHidden(state, entry.root)) {
                _ = try self.endRoot(function, state, entry.root);
                return;
            }
        }
        var refreshed = false;
        var index: usize = 0;
        while (index < state.storage_roots.items.len) {
            const entry = state.storage_roots.items[index];
            if (!storage.isPrefixOf(entry.storage)) {
                index += 1;
                continue;
            }
            _ = try self.endRoot(function, state, entry.root);
            if (entry.storage.eql(storage)) {
                state.storage_roots.items[index].root = try state.tracker.establish(.fresh);
                refreshed = true;
                index += 1;
            } else {
                // Descendant mappings name storage from the old generation.
                // Drop them so a later address-of establishes each new root
                // lazily, without reviving aliases to the old roots.
                _ = state.storage_roots.orderedRemove(index);
            }
        }
        if (!refreshed)
            try state.storage_roots.append(.{ .storage = storage, .root = try state.tracker.establish(.fresh) });
    }

    fn endStorageRootsUnder(self: *SafetyChecker, function: ?*const sg.FunctionDeclaration, state: *FunctionState, storage: place.Place) !void {
        for (state.storage_roots.items) |entry| {
            if (storage.isPrefixOf(entry.storage) and rootIsHidden(state, entry.root)) {
                _ = try self.endRoot(function, state, entry.root);
                return;
            }
        }
        for (state.storage_roots.items) |entry| {
            if (storage.isPrefixOf(entry.storage)) _ = try self.endRoot(function, state, entry.root);
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
        }
    }

    fn clearChoiceRefinementsUnder(self: *SafetyChecker, state: *FunctionState, storage: place.Place) void {
        _ = self;
        var index: usize = 0;
        while (index < state.choice_active.items.len) {
            const refined = state.choice_active.items[index].storage;
            if (storage.isPrefixOf(refined) or refined.isPrefixOf(storage)) {
                _ = state.choice_active.orderedRemove(index);
            } else index += 1;
        }
        index = 0;
        while (index < state.choice_rejected.items.len) {
            const refined = state.choice_rejected.items[index].storage;
            if (storage.isPrefixOf(refined) or refined.isPrefixOf(storage)) {
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

        var direct_roots = std.array_list.Managed(facts.RootId).init(self.allocator.*);
        for (container.owned_roots) |root| {
            var belongs_to_field = false;
            for (container.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) {
                belongs_to_field = true;
                break;
            };
            if (!belongs_to_field) try appendOwnedRoot(&direct_roots, root);
        }
        var direct_dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
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
        root: facts.RootId,
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
        from: facts.RootId,
        target: facts.RootId,
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
            if (!isLocalStorageRoot(function, state, dependency.root)) continue;
            try self.diagnostics.add(function.location, .semantic, "function output cannot depend on a local storage root that ends before return", .{});
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

    fn oneDependency(self: *SafetyChecker, root: facts.RootId) ![]const facts.ReferenceDependency {
        const result = try self.allocator.alloc(facts.ReferenceDependency, 1);
        result[0] = .{ .root = root };
        return result;
    }

    fn oneFreshSource(self: *SafetyChecker, source: facts.FreshRootSource) ![]const facts.FreshRootSource {
        const result = try self.allocator.alloc(facts.FreshRootSource, 1);
        result[0] = source;
        return result;
    }

    fn mergeFreshSources(
        self: *SafetyChecker,
        left: []const facts.FreshRootSource,
        right: []const facts.FreshRootSource,
    ) ![]const facts.FreshRootSource {
        var result = std.array_list.Managed(facts.FreshRootSource).init(self.allocator.*);
        for (left) |source| try appendFreshSource(&result, source);
        for (right) |source| try appendFreshSource(&result, source);
        return result.toOwnedSlice();
    }

    fn oneOwnedRoot(self: *SafetyChecker, root: facts.RootId) ![]const facts.RootId {
        const result = try self.allocator.alloc(facts.RootId, 1);
        result[0] = root;
        return result;
    }

    fn oneStorageAuthority(self: *SafetyChecker, authority: facts.StorageAuthorityId) ![]const facts.StorageAuthorityId {
        const result = try self.allocator.alloc(facts.StorageAuthorityId, 1);
        result[0] = authority;
        return result;
    }

    fn ensureEmptySummary(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        if (self.summaries.contains(function)) return;
        const outputs = try self.allocator.alloc(facts.OutputEffect, function.output.fields.len);
        @memset(outputs, .{});
        try self.summaries.put(function, .{ .outputs = outputs });
    }

    fn virtualSummary(self: *SafetyChecker, registry: *const sg.VirtualMethodRegistry) !?facts.FunctionSummary {
        if (self.invalid_virtual_summaries.contains(registry)) return null;
        if (self.virtual_summaries.get(registry)) |summary| return summary;
        if (registry.implementations.items.len == 0) return null;

        var merged = self.summaries.get(registry.implementations.items[0]) orelse return null;
        for (registry.implementations.items[1..]) |implementation| {
            const next = self.summaries.get(implementation) orelse return null;
            merged = (try self.mergeVirtualFunctionSummary(merged, next)) orelse {
                try self.invalid_virtual_summaries.put(registry, {});
                return null;
            };
        }
        try self.virtual_summaries.put(registry, merged);
        return merged;
    }

    fn mergeVirtualFunctionSummary(
        self: *SafetyChecker,
        left: facts.FunctionSummary,
        right: facts.FunctionSummary,
    ) !?facts.FunctionSummary {
        if (!inputPostStatesEqual(left.input_post_states, right.input_post_states) or
            left.outputs.len != right.outputs.len) return null;

        var fresh_map = std.AutoHashMap(facts.FreshRootSource, facts.FreshRootSource).init(self.allocator.*);
        defer fresh_map.deinit();
        const outputs = try self.allocator.alloc(facts.OutputEffect, left.outputs.len);
        for (left.outputs, right.outputs, 0..) |left_output, right_output, index| {
            outputs[index] = (try self.mergeVirtualOutputEffect(left_output, right_output, &fresh_map)) orelse return null;
        }
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator.*);
        for (left.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);
        for (right.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);
        return .{
            .outputs = outputs,
            .input_post_states = left.input_post_states,
            .opaque_storage_effects = try opaque_storage_effects.toOwnedSlice(),
        };
    }

    fn mergeVirtualOutputEffect(
        self: *SafetyChecker,
        left: facts.OutputEffect,
        right: facts.OutputEffect,
        fresh_map: *std.AutoHashMap(facts.FreshRootSource, facts.FreshRootSource),
    ) !?facts.OutputEffect {
        if (left.integer_address != right.integer_address or
            left.foreign_storage != right.foreign_storage or
            left.fresh_dependencies.len != right.fresh_dependencies.len or
            left.fresh_owned_roots.len != right.fresh_owned_roots.len or
            left.fresh_storage_authorities.len != right.fresh_storage_authorities.len or
            left.fields.len != right.fields.len or
            left.variants.len != right.variants.len) return null;

        if (!try alignFreshSources(left.fresh_dependencies, right.fresh_dependencies, fresh_map) or
            !try alignFreshSources(left.fresh_owned_roots, right.fresh_owned_roots, fresh_map) or
            !try alignFreshSources(left.fresh_storage_authorities, right.fresh_storage_authorities, fresh_map)) return null;

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

        const fields = try self.allocator.alloc(facts.OutputFieldEffect, left.fields.len);
        for (left.fields, right.fields, 0..) |left_field, right_field, index| {
            if (left_field.index != right_field.index) return null;
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = (try self.mergeVirtualOutputEffect(left_field.value.*, right_field.value.*, fresh_map)) orelse return null;
            fields[index] = .{ .index = left_field.index, .value = value };
        }
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, left.variants.len);
        for (left.variants, right.variants, 0..) |left_variant, right_variant, index| {
            if (left_variant.index != right_variant.index) return null;
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = (try self.mergeVirtualOutputEffect(left_variant.value.*, right_variant.value.*, fresh_map)) orelse return null;
            variants[index] = .{ .index = left_variant.index, .value = value };
        }
        return .{
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_places = try input_places.toOwnedSlice(),
            .fields = fields,
            .variants = variants,
            .fresh_dependencies = left.fresh_dependencies,
            .fresh_owned_roots = left.fresh_owned_roots,
            .fresh_storage_authorities = left.fresh_storage_authorities,
            .integer_address = left.integer_address,
            .foreign_storage = left.foreign_storage,
        };
    }

    fn infer(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !bool {
        if (function.safety_primitive != .none)
            return self.replaceSingleOutput(function, try self.primitiveOutputEffect(function.safety_primitive, @intFromPtr(function)));
        const body = function.body orelse return false;
        const previous = self.summaries.get(function).?;
        const outputs = try self.allocator.dupe(facts.OutputEffect, previous.outputs);
        var bindings = std.AutoHashMap(*const sg.BindingDeclaration, facts.OutputEffect).init(self.allocator.*);
        defer bindings.deinit();
        var place_bindings = std.AutoHashMap(*const sg.BindingDeclaration, []const facts.InputPath).init(self.allocator.*);
        defer place_bindings.deinit();
        self.inference_bindings = &bindings;
        defer self.inference_bindings = null;
        self.inference_place_bindings = &place_bindings;
        defer self.inference_place_bindings = null;
        try self.inferBlock(function, body, outputs);
        var post_states = std.array_list.Managed(facts.InputPlaceEffect).init(self.allocator.*);
        try self.inferInputPostStates(function, body, &post_states);
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator.*);
        try self.inferOpaqueStorageEffects(function, body, &opaque_storage_effects);
        if (function.is_deinit) {
            for (function.input.fields, 0..) |input_field, index| {
                if (!std.mem.eql(u8, input_field.name, "self") or input_field.ty != .pointer_type or
                    input_field.ty.pointer_type.mutability != .read_write) continue;
                try self.recordInputPostState(&post_states, try self.oneInputPath(@intCast(index), &.{}), .deinitialized, .{}, true, false, false);
                break;
            }
        }
        const post_state_slice = try post_states.toOwnedSlice();
        const opaque_storage_effect_slice = try opaque_storage_effects.toOwnedSlice();
        if (effectsEqual(previous.outputs, outputs) and
            inputPostStatesEqual(previous.input_post_states, post_state_slice) and
            opaqueStorageEffectsEqual(previous.opaque_storage_effects, opaque_storage_effect_slice)) return false;
        try self.summaries.put(function, .{
            .outputs = outputs,
            .input_post_states = post_state_slice,
            .opaque_storage_effects = opaque_storage_effect_slice,
        });
        return true;
    }

    fn inferInputPostStates(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        states: *std.array_list.Managed(facts.InputPlaceEffect),
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .function_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const arguments = call.input.content.struct_value_literal.fields;
                if (call.callee.safety_primitive == .trusted_opaque_store_owned or
                    call.callee.safety_primitive == .trusted_opaque_store_owned_in)
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
                    continue;
                }
                if (call.callee.safety_primitive == .trusted_opaque_relocate_owned) continue;
                if (call.callee.safety_primitive == .relocate) {
                    if (arguments.len != 2) continue;
                    const source_targets = try self.inferInputPaths(function, arguments[0].value);
                    const destination_targets = try self.inferInputPaths(function, arguments[1].value);
                    for (source_targets) |source| {
                        try self.recordInputPostState(states, &.{source}, .moved, .{}, false, false, false);
                        var transferred = try self.inputOutputEffect(source.input_index, source.projections);
                        transferred = self.withOwnershipTransfer(transferred);
                        for (destination_targets) |destination|
                            try self.recordInputPostState(states, &.{destination}, .initialized, transferred, false, false, true);
                    }
                    continue;
                }
                const summary = self.summaries.get(call.callee) orelse continue;
                for (summary.input_post_states) |post_state| {
                    if (post_state.target.input_index >= arguments.len) continue;
                    var targets = try self.inferInputPaths(function, arguments[post_state.target.input_index].value);
                    for (post_state.target.projections) |projection| targets = try self.projectInputPaths(targets, projection);
                    if (post_state.opaque_ownership != .none) {
                        const storage = if (post_state.opaque_storage) |opaque_storage| blk: {
                            if (opaque_storage.input_index >= arguments.len) break :blk null;
                            var mapped = try self.inferInputPaths(function, arguments[opaque_storage.input_index].value);
                            for (opaque_storage.projections) |projection| mapped = try self.projectInputPaths(mapped, projection);
                            break :blk if (mapped.len == 1) mapped[0] else null;
                        } else null;
                        try self.recordOpaqueOwnershipConsumption(states, targets, post_state.opaque_ownership, storage);
                        continue;
                    }
                    const value = try self.substituteOutput(function, post_state.value, arguments);
                    try self.recordInputPostState(states, targets, post_state.initializedness, value, post_state.ends_previous_roots, post_state.refreshes_storage_root, post_state.requires_available_destination);
                }
            },
            .virtual_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const summary = try self.virtualSummary(call.safety_methods) orelse continue;
                const arguments = call.input.content.struct_value_literal.fields;
                for (summary.input_post_states) |post_state| {
                    if (post_state.target.input_index >= arguments.len) continue;
                    var targets = try self.inferInputPaths(function, arguments[post_state.target.input_index].value);
                    for (post_state.target.projections) |projection| targets = try self.projectInputPaths(targets, projection);
                    if (post_state.opaque_ownership != .none) {
                        try self.recordOpaqueOwnershipConsumption(states, targets, post_state.opaque_ownership, null);
                        continue;
                    }
                    try self.recordInputPostState(states, targets, post_state.initializedness, try self.substituteOutput(function, post_state.value, arguments), post_state.ends_previous_roots, post_state.refreshes_storage_root, post_state.requires_available_destination);
                }
            },
            .pointer_assignment => |assignment| {
                try self.recordInputPostState(states, try self.inferInputPaths(function, assignment.pointer), .initialized, try self.inferExpression(function, assignment.value), false, false, false);
            },
            .struct_field_store => |store| {
                const targets = try self.projectInputPaths(try self.inferInputPaths(function, store.struct_ptr), .{ .field = store.field_index });
                try self.recordInputPostState(states, targets, .initialized, try self.inferExpression(function, store.value), false, false, false);
            },
            .array_store => |store| {
                const projection: place.Projection = if (staticIndex(store.index)) |index| .{ .static_index = index } else .dynamic_index;
                const targets = try self.projectInputPaths(try self.inferInputPaths(function, store.array_ptr), projection);
                try self.recordInputPostState(states, targets, .initialized, try self.inferExpression(function, store.value), false, false, false);
            },
            .if_statement => |statement| {
                var then_states = try cloneInputPostStates(states, self.allocator.*);
                defer then_states.deinit();
                try self.inferInputPostStates(function, statement.then_block, &then_states);
                var else_states = try cloneInputPostStates(states, self.allocator.*);
                defer else_states.deinit();
                if (statement.else_block) |else_block| try self.inferInputPostStates(function, else_block, &else_states);
                try self.joinInputPostStates(states, &then_states, &else_states);
            },
            .while_statement => |statement| {
                var body_states = try cloneInputPostStates(states, self.allocator.*);
                defer body_states.deinit();
                try self.inferInputPostStates(function, statement.body, &body_states);
                try self.joinInputPostStates(states, states, &body_states);
            },
            .for_statement => |statement| {
                var body_states = try cloneInputPostStates(states, self.allocator.*);
                defer body_states.deinit();
                try self.inferInputPostStates(function, statement.body, &body_states);
                try self.joinInputPostStates(states, states, &body_states);
            },
            .switch_statement => |statement| {
                var joined: ?std.array_list.Managed(facts.InputPlaceEffect) = null;
                defer if (joined) |*joined_states| joined_states.deinit();

                for (statement.cases) |case| {
                    var branch = try cloneInputPostStates(states, self.allocator.*);
                    defer branch.deinit();
                    try self.inferInputPostStates(function, case.body, &branch);
                    try self.joinInputPostStateBranch(&joined, &branch);
                }
                if (statement.default_case) |default_case| {
                    var branch = try cloneInputPostStates(states, self.allocator.*);
                    defer branch.deinit();
                    try self.inferInputPostStates(function, default_case, &branch);
                    try self.joinInputPostStateBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinInputPostStateBranch(&joined, states);
                }
                if (joined) |*joined_states| {
                    states.clearRetainingCapacity();
                    try states.appendSlice(joined_states.items);
                }
            },
            else => {},
        };
    }

    fn inferOpaqueStorageEffects(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .function_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const arguments = call.input.content.struct_value_literal.fields;
                if (call.callee.safety_primitive == .trusted_opaque_store_owned_in) {
                    if (arguments.len != 3) continue;
                    const storages = try self.inferInputPaths(function, arguments[0].value);
                    const hidden = try self.inferExpression(function, arguments[2].value);
                    for (storages) |storage| try self.recordOpaqueStorageEffect(effects, storage, hidden);
                    continue;
                }
                const summary = self.summaries.get(call.callee) orelse continue;
                for (summary.opaque_storage_effects) |effect| {
                    if (effect.storage.input_index >= arguments.len) continue;
                    var storages = try self.inferInputPaths(function, arguments[effect.storage.input_index].value);
                    for (effect.storage.projections) |projection| storages = try self.projectInputPaths(storages, projection);
                    const hidden = try self.substituteOutput(function, effect.hidden_dependencies, arguments);
                    for (storages) |storage| try self.recordOpaqueStorageEffect(effects, storage, hidden);
                }
            },
            .virtual_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const summary = try self.virtualSummary(call.safety_methods) orelse continue;
                const arguments = call.input.content.struct_value_literal.fields;
                for (summary.opaque_storage_effects) |effect| {
                    if (effect.storage.input_index >= arguments.len) continue;
                    var storages = try self.inferInputPaths(function, arguments[effect.storage.input_index].value);
                    for (effect.storage.projections) |projection| storages = try self.projectInputPaths(storages, projection);
                    const hidden = try self.substituteOutput(function, effect.hidden_dependencies, arguments);
                    for (storages) |storage| try self.recordOpaqueStorageEffect(effects, storage, hidden);
                }
            },
            .if_statement => |statement| {
                try self.inferOpaqueStorageEffects(function, statement.then_block, effects);
                if (statement.else_block) |else_block| try self.inferOpaqueStorageEffects(function, else_block, effects);
            },
            .while_statement => |statement| try self.inferOpaqueStorageEffects(function, statement.body, effects),
            .for_statement => |statement| try self.inferOpaqueStorageEffects(function, statement.body, effects),
            .switch_statement => |statement| {
                for (statement.cases) |case| try self.inferOpaqueStorageEffects(function, case.body, effects);
                if (statement.default_case) |default_case| try self.inferOpaqueStorageEffects(function, default_case, effects);
            },
            else => {},
        };
    }

    fn recordOpaqueStorageEffect(
        self: *SafetyChecker,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        storage: facts.InputPath,
        hidden: facts.OutputEffect,
    ) !void {
        const dependencies_only = try self.dependencyOnlyEffect(hidden);
        for (effects.items) |*existing| {
            if (!inputPlaceTargetEqual(existing.storage, storage)) continue;
            existing.hidden_dependencies = try self.mergeOutputEffects(existing.hidden_dependencies, dependencies_only);
            return;
        }
        try effects.append(.{ .storage = storage, .hidden_dependencies = dependencies_only });
    }

    fn dependencyOnlyEffect(self: *SafetyChecker, effect: facts.OutputEffect) !facts.OutputEffect {
        const input_dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (input_dependencies) |*dependency| dependency.transfers_ownership = false;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.dependencyOnlyEffect(field.value.*);
            fields[index] = .{ .index = field.index, .value = value };
        }
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, 0..) |variant, index| {
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.dependencyOnlyEffect(variant.value.*);
            variants[index] = .{ .index = variant.index, .value = value };
        }
        return .{
            .input_dependencies = input_dependencies,
            .input_places = effect.input_places,
            .fields = fields,
            .variants = variants,
            .fresh_dependencies = effect.fresh_dependencies,
        };
    }

    fn joinInputPostStateBranch(
        self: *SafetyChecker,
        joined: *?std.array_list.Managed(facts.InputPlaceEffect),
        branch: *const std.array_list.Managed(facts.InputPlaceEffect),
    ) !void {
        if (joined.*) |*previous| {
            var combined = std.array_list.Managed(facts.InputPlaceEffect).init(self.allocator.*);
            try self.joinInputPostStates(&combined, previous, branch);
            previous.deinit();
            joined.* = combined;
        } else {
            joined.* = try cloneInputPostStates(branch, self.allocator.*);
        }
    }

    fn recordInputPostState(self: *SafetyChecker, states: *std.array_list.Managed(facts.InputPlaceEffect), targets: []const facts.InputPath, initializedness: value_state.Initializedness, value: facts.OutputEffect, ends_roots: bool, refreshes_storage_root: bool, requires_available_destination: bool) !void {
        _ = self;
        for (targets) |target| {
            var existing_state: ?*facts.InputPlaceEffect = null;
            for (states.items) |*existing| if (inputPlaceTargetEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                const was_deinitialized = existing.initializedness != .initialized;
                existing.initializedness = initializedness;
                existing.value = value;
                existing.ends_previous_roots = existing.ends_previous_roots or ends_roots;
                existing.refreshes_storage_root = existing.refreshes_storage_root or refreshes_storage_root or (was_deinitialized and initializedness == .initialized);
                existing.requires_available_destination = existing.requires_available_destination or requires_available_destination;
            } else try states.append(.{
                .target = target,
                .initializedness = initializedness,
                .value = value,
                .ends_previous_roots = ends_roots,
                .refreshes_storage_root = refreshes_storage_root,
                .requires_available_destination = requires_available_destination,
            });
        }
    }

    fn recordOpaqueOwnershipConsumption(self: *SafetyChecker, states: *std.array_list.Managed(facts.InputPlaceEffect), targets: []const facts.InputPath, consumption: facts.OpaqueOwnershipConsumption, storage: ?facts.InputPath) !void {
        _ = self;
        for (targets) |target| {
            var existing_state: ?*facts.InputPlaceEffect = null;
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

    fn joinInputPostStates(self: *SafetyChecker, destination: *std.array_list.Managed(facts.InputPlaceEffect), left: *const std.array_list.Managed(facts.InputPlaceEffect), right: *const std.array_list.Managed(facts.InputPlaceEffect)) !void {
        var joined = std.array_list.Managed(facts.InputPlaceEffect).init(self.allocator.*);
        for (left.items) |left_state| {
            var merged = left_state;
            if (findInputPostState(right.items, left_state.target)) |right_state| {
                merged.initializedness = joinInitializedness(left_state.initializedness, right_state.initializedness);
                merged.value = try self.mergeOutputEffects(left_state.value, right_state.value);
                merged.ends_previous_roots = left_state.ends_previous_roots or right_state.ends_previous_roots;
                merged.refreshes_storage_root = left_state.refreshes_storage_root or right_state.refreshes_storage_root;
                merged.requires_available_destination = left_state.requires_available_destination or right_state.requires_available_destination;
                merged.opaque_ownership = joinOpaqueOwnership(left_state.opaque_ownership, right_state.opaque_ownership);
                if (!optionalInputPathEqual(left_state.opaque_storage, right_state.opaque_storage)) merged.opaque_storage = null;
            } else {
                if (left_state.initializedness != .initialized) {
                    merged.initializedness = .maybe_initialized;
                } else {
                    merged.value = try self.mergeOutputEffects(left_state.value, try self.inputOutputEffect(left_state.target.input_index, left_state.target.projections));
                }
                merged.opaque_ownership = joinOpaqueOwnership(left_state.opaque_ownership, .none);
            }
            try joined.append(merged);
        }
        for (right.items) |right_state| if (findInputPostState(left.items, right_state.target) == null) {
            var merged = right_state;
            if (right_state.initializedness != .initialized) {
                merged.initializedness = .maybe_initialized;
            } else {
                merged.value = try self.mergeOutputEffects(right_state.value, try self.inputOutputEffect(right_state.target.input_index, right_state.target.projections));
            }
            merged.opaque_ownership = joinOpaqueOwnership(.none, right_state.opaque_ownership);
            try joined.append(merged);
        };
        destination.clearRetainingCapacity();
        try destination.appendSlice(joined.items);
        joined.deinit();
    }

    fn replaceSingleOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.OutputEffect,
    ) !bool {
        const previous = self.summaries.get(function).?;
        if (previous.outputs.len != 1 or std.meta.eql(previous.outputs[0], effect)) return false;
        const outputs = try self.allocator.alloc(facts.OutputEffect, 1);
        outputs[0] = effect;
        try self.summaries.put(function, .{ .outputs = outputs });
        return true;
    }

    fn inferBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        outputs: []facts.OutputEffect,
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
                        try self.mergeOutputEffects(outputs[output_index], effect)
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
    ) anyerror!facts.OutputEffect {
        return switch (node.content) {
            .binding_use => |binding| if (inputIndex(function, binding)) |index|
                try self.inputOutputEffect(@intCast(index), &.{})
            else if (self.inference_bindings) |bindings| bindings.get(binding) orelse .{} else .{},
            .move_value => |value| self.withOwnershipTransfer(try self.inferExpression(function, value)),
            .address_of => |value| .{ .input_places = try self.inferInputPaths(function, value) },
            .dereference => |value| try self.inferExpression(function, value.pointer),
            .struct_value_literal => |literal| try self.inferAggregate(function, literal),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.choiceOutputEffect(literal.variant_index, try self.inferExpression(function, payload))
            else
                try self.choiceOutputEffect(literal.variant_index, .{}),
            .struct_field_access => |access| try self.inferProjection(function, access.struct_value, .{ .field = access.field_index }),
            .choice_payload_access => |access| try self.inferChoicePayload(function, access.choice_value, access.variant_index),
            .array_index => |index| try self.inferProjection(function, index.array_ptr, if (staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index),
            .explicit_cast => |cast| try self.inferExpression(function, cast.value),
            .function_call => |call| try self.inferCall(function, call),
            .virtualize => |virtualize| try self.inferExpression(function, virtualize.value),
            .virtual_call => |call| try self.inferVirtualCall(function, call),
            else => .{},
        };
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

    fn inferCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.FunctionCall) !facts.OutputEffect {
        if (call.callee.safety_primitive != .none) {
            const effect = try self.primitiveOutputEffect(call.callee.safety_primitive, @intFromPtr(call));
            if (call.input.content != .struct_value_literal) return effect;
            return self.substituteOutput(function, effect, call.input.content.struct_value_literal.fields);
        }
        const callee_summary = self.summaries.get(call.callee) orelse return .{};
        if (callee_summary.outputs.len != 1 or call.input.content != .struct_value_literal) return .{};
        const substituted = try self.substituteOutput(function, callee_summary.outputs[0], call.input.content.struct_value_literal.fields);
        return self.rebaseFreshSources(substituted, @intFromPtr(call));
    }

    fn inferVirtualCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.VirtualCall) !facts.OutputEffect {
        const summary = try self.virtualSummary(call.safety_methods) orelse return .{};
        if (summary.outputs.len != 1 or call.input.content != .struct_value_literal) return .{};
        const substituted = try self.substituteOutput(function, summary.outputs[0], call.input.content.struct_value_literal.fields);
        return self.rebaseFreshSources(substituted, @intFromPtr(call));
    }

    fn rebaseFreshSources(self: *SafetyChecker, effect: facts.OutputEffect, call_site: usize) !facts.OutputEffect {
        const Context = struct { call_site: usize, source: facts.FreshRootSource };
        var result = effect;
        const dependencies = try self.allocator.alloc(facts.FreshRootSource, effect.fresh_dependencies.len);
        for (effect.fresh_dependencies, 0..) |source, index|
            dependencies[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_dependencies = dependencies;
        const owned_roots = try self.allocator.alloc(facts.FreshRootSource, effect.fresh_owned_roots.len);
        for (effect.fresh_owned_roots, 0..) |source, index|
            owned_roots[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_owned_roots = owned_roots;
        const authorities = try self.allocator.alloc(facts.FreshRootSource, effect.fresh_storage_authorities.len);
        for (effect.fresh_storage_authorities, 0..) |source, index|
            authorities[index] = std.hash.Wyhash.hash(0, std.mem.asBytes(&Context{ .call_site = call_site, .source = source }));
        result.fresh_storage_authorities = authorities;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.rebaseFreshSources(field.value.*, call_site);
            fields[index] = .{ .index = field.index, .value = value };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, 0..) |variant, index| {
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.rebaseFreshSources(variant.value.*, call_site);
            variants[index] = .{ .index = variant.index, .value = value };
        }
        result.variants = variants;
        return result;
    }

    fn inputOutputEffect(self: *SafetyChecker, input_index: u32, projections: []const place.Projection) !facts.OutputEffect {
        return .{ .input_dependencies = try self.oneInputDependency(input_index, projections) };
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

    fn primitiveOutputEffect(self: *SafetyChecker, primitive: sg.SafetyPrimitive, source: facts.FreshRootSource) !facts.OutputEffect {
        return switch (primitive) {
            .none => .{},
            .relocate => .{},
            .establish_fresh_reference => .{ .fresh_dependencies = try self.oneFreshSource(source) },
            .establish_inherited_reference => self.inputOutputEffect(1, &.{}),
            .establish_inherited_storage => self.inputOutputEffect(1, &.{}),
            .establish_allocation => self.ownedAllocationEffect(source),
            .raw_allocated_storage => .{ .foreign_storage = true, .fresh_storage_authorities = try self.oneFreshSource(source) },
            .reference_offset,
            .mutable_reference_offset,
            .reinterpret_reference,
            .mutable_reinterpret_reference,
            .read_reference,
            => self.inputOutputEffect(0, &.{}),
            .restrict_reference => self.restrictReferenceEffect(),
            .trusted_opaque_store_owned,
            .trusted_opaque_store_owned_in,
            .trusted_opaque_relocate_owned,
            .trusted_opaque_drop_owned,
            => .{},
        };
    }

    /// Restriction retains every fact of the input reference and appends the
    /// storage generation of the lifetime Place. `input_places` preserves the
    /// input reference's provenance; neither root ownership nor authority is
    /// transferred by either dependency.
    fn restrictReferenceEffect(self: *SafetyChecker) !facts.OutputEffect {
        var result = try self.inputOutputEffect(0, &.{});
        result = try self.mergeOutputEffects(result, try self.inputOutputEffect(1, &.{}));
        result.input_places = try self.oneInputPath(0, &.{});
        return result;
    }

    fn ownedAllocationEffect(self: *SafetyChecker, source: facts.FreshRootSource) !facts.OutputEffect {
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, 3);
        const data = try self.allocator.create(facts.OutputEffect);
        data.* = .{ .fresh_dependencies = try self.oneFreshSource(source) };
        const size = try self.allocator.create(facts.OutputEffect);
        size.* = .{};
        const allocator = try self.allocator.create(facts.OutputEffect);
        allocator.* = try self.inputOutputEffect(2, &.{});
        fields[0] = .{ .index = 0, .value = data };
        fields[1] = .{ .index = 1, .value = size };
        fields[2] = .{ .index = 2, .value = allocator };
        return .{
            .fresh_owned_roots = try self.oneFreshSource(source),
            .fields = fields,
        };
    }

    fn withOwnershipTransfer(self: *SafetyChecker, effect: facts.OutputEffect) facts.OutputEffect {
        _ = self;
        for (effect.input_dependencies) |*dependency| @constCast(dependency).transfers_ownership = true;
        return effect;
    }

    fn withoutOwnershipTransfer(self: *SafetyChecker, effect: facts.OutputEffect) !facts.OutputEffect {
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = false;
        var result = effect;
        result.input_dependencies = dependencies;
        return result;
    }

    fn inferAggregate(self: *SafetyChecker, function: *const sg.FunctionDeclaration, literal: *const sg.StructValueLiteral) !facts.OutputEffect {
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, literal.fields.len);
        var result: facts.OutputEffect = .{};
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
            const value = try self.allocator.create(facts.OutputEffect);
            value.* = try self.inferExpression(function, field.value);
            output_fields[position] = .{ .index = semantic_index, .value = value };
            result = try self.mergeOutputEffects(result, value.*);
            // A struct contains the choice; it is not itself refined by the
            // tags of choice-valued fields.
            result.variants = &.{};
        }
        result.fields = output_fields;
        return result;
    }

    fn choiceValue(self: *SafetyChecker, variant_index: u32, payload: facts.ValueFacts) !facts.ValueFacts {
        const variants = try self.allocator.alloc(facts.VariantFacts, 1);
        const stored = try self.allocator.create(facts.ValueFacts);
        stored.* = payload;
        variants[0] = .{ .index = variant_index, .value = stored };
        return .{ .variants = variants };
    }

    fn choiceOutputEffect(self: *SafetyChecker, variant_index: u32, payload: facts.OutputEffect) !facts.OutputEffect {
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, 1);
        const stored = try self.allocator.create(facts.OutputEffect);
        stored.* = payload;
        variants[0] = .{ .index = variant_index, .value = stored };
        return .{ .variants = variants };
    }

    fn inferProjection(self: *SafetyChecker, function: *const sg.FunctionDeclaration, base_node: *const sg.SGNode, projection: place.Projection) !facts.OutputEffect {
        return self.projectOutputEffect(try self.inferExpression(function, base_node), projection);
    }

    fn inferChoicePayload(self: *SafetyChecker, function: *const sg.FunctionDeclaration, base_node: *const sg.SGNode, variant_index: u32) !facts.OutputEffect {
        const effect = try self.inferExpression(function, base_node);
        for (effect.variants) |variant| if (variant.index == variant_index) return variant.value.*;
        return .{};
    }

    fn projectOutputEffect(self: *SafetyChecker, effect: facts.OutputEffect, projection: place.Projection) !facts.OutputEffect {
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
        return .{
            .input_dependencies = dependencies,
            .input_places = input_places,
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_authorities = effect.fresh_storage_authorities,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
    }

    fn substituteOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.OutputEffect,
        arguments: []const sg.StructValueLiteralField,
    ) !facts.OutputEffect {
        var result: facts.OutputEffect = .{
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_authorities = effect.fresh_storage_authorities,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            var substituted = try self.inferInputPaths(function, arguments[path.input_index].value);
            for (path.projections) |projection| substituted = try self.projectInputPaths(substituted, projection);
            for (substituted) |candidate| try appendInputPath(&input_places, candidate);
        }
        result.input_places = try input_places.toOwnedSlice();
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            var argument = try self.inferExpression(function, arguments[dependency.path.input_index].value);
            for (dependency.path.projections) |projection| argument = try self.projectOutputEffect(argument, projection);
            if (dependency.transfers_ownership) argument = self.withOwnershipTransfer(argument) else argument = try self.withoutOwnershipTransfer(argument);
            result = try self.mergeOutputEffects(result, argument);
        }
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.OutputEffect);
                value.* = try self.substituteOutput(function, field.value.*, arguments);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.OutputEffect);
                value.* = try self.substituteOutput(function, variant.value.*, arguments);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn mergeOutputEffects(self: *SafetyChecker, left: facts.OutputEffect, right: facts.OutputEffect) !facts.OutputEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator.*);
        for (left.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        for (right.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator.*);
        for (left.input_places) |path| try appendInputPath(&input_places, path);
        for (right.input_places) |path| try appendInputPath(&input_places, path);
        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator.*);
        for (left.fields) |left_field| {
            var merged = left_field.value.*;
            for (right.fields) |right_field| if (right_field.index == left_field.index) {
                merged = try self.mergeOutputEffects(merged, right_field.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.OutputEffect);
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
                merged = try self.mergeOutputEffects(merged, right_variant.value.*);
                break;
            };
            const stored = try self.allocator.create(facts.OutputEffect);
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
            .fields = try fields.toOwnedSlice(),
            .fresh_dependencies = try self.mergeFreshSources(left.fresh_dependencies, right.fresh_dependencies),
            .fresh_owned_roots = try self.mergeFreshSources(left.fresh_owned_roots, right.fresh_owned_roots),
            .fresh_storage_authorities = try self.mergeFreshSources(left.fresh_storage_authorities, right.fresh_storage_authorities),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .variants = try variants.toOwnedSlice(),
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
    canonical: []const facts.FreshRootSource,
    candidate: []const facts.FreshRootSource,
    mapping: *std.AutoHashMap(facts.FreshRootSource, facts.FreshRootSource),
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

fn containsRoot(roots: []const facts.RootId, target: facts.RootId) bool {
    for (roots) |root| if (root == target) return true;
    return false;
}

fn collectOwnedRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.RootId)) !void {
    for (value.owned_roots) |root| try appendOwnedRoot(roots, root);
    for (value.fields) |field| try collectOwnedRoots(field.value.*, roots);
    for (value.variants) |variant| try collectOwnedRoots(variant.value.*, roots);
}

fn hasExternalOpaqueDependency(value: facts.ValueFacts, owned: []const facts.RootId) bool {
    for (value.dependencies) |dependency| if (!containsRoot(owned, dependency.root)) return true;
    for (value.fields) |field| if (hasExternalOpaqueDependency(field.value.*, owned)) return true;
    for (value.variants) |variant| if (hasExternalOpaqueDependency(variant.value.*, owned)) return true;
    return false;
}

fn valueContainsOwnedRoot(value: facts.ValueFacts, target: facts.RootId) bool {
    if (containsRoot(value.owned_roots, target)) return true;
    for (value.fields) |field| if (valueContainsOwnedRoot(field.value.*, target)) return true;
    for (value.variants) |variant| if (valueContainsOwnedRoot(variant.value.*, target)) return true;
    return false;
}

fn valueDependsOnRoot(value: facts.ValueFacts, target: facts.RootId) bool {
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

fn collectDependencyRoots(value: facts.ValueFacts, roots: *std.array_list.Managed(facts.RootId)) !void {
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
    for (value.storage_authorities) |authority| {
        const authority_state = &state.storage_authorities.items[@intFromEnum(authority)];
        if (authority_state.* == .conditional) authority_state.* = .available;
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
    for (value.storage_authorities) |authority| {
        const authority_state = &state.storage_authorities.items[@intFromEnum(authority)];
        if (authority_state.* == .conditional) authority_state.* = .consumed;
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

fn ownershipPathExistsFrom(
    state: *const SafetyChecker.FunctionState,
    current: facts.RootId,
    target: facts.RootId,
    remaining: usize,
) bool {
    if (current == target) return true;
    if (remaining == 0) return false;
    for (state.ownership_edges.items) |edge| {
        if (edge.owner == current and ownershipPathExistsFrom(state, edge.owned, target, remaining - 1)) return true;
    }
    return false;
}

fn isLocalStorageRoot(
    function: *const sg.FunctionDeclaration,
    state: *const SafetyChecker.FunctionState,
    root: facts.RootId,
) bool {
    for (state.storage_roots.items) |entry| {
        if (entry.root != root) continue;
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
        left.places.items.len != right.places.items.len or
        left.ownership_edges.items.len != right.ownership_edges.items.len or
        left.opaque_storages.items.len != right.opaque_storages.items.len) return false;
    for (left.tracker.roots.items, right.tracker.roots.items) |a, b|
        if (a.state != b.state or a.owned_resource != b.owned_resource) return false;
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
    return true;
}

fn valueFactsEqual(left: facts.ValueFacts, right: facts.ValueFacts) bool {
    if (left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        !std.mem.eql(facts.StorageAuthorityId, left.storage_authorities, right.storage_authorities) or
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len or
        left.variants.len != right.variants.len) return false;
    for (left.dependencies, right.dependencies) |a, b| if (a.root != b.root) return false;
    for (left.owned_roots, right.owned_roots) |a, b| if (a != b) return false;
    if ((left.referenced_place == null) != (right.referenced_place == null)) return false;
    if (left.referenced_place) |left_place| if (!left_place.eql(right.referenced_place.?)) return false;
    if (left.opaque_origins.len != right.opaque_origins.len) return false;
    for (left.opaque_origins, right.opaque_origins) |a, b| if (!a.eql(b)) return false;
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

fn effectsEqual(left: []const facts.OutputEffect, right: []const facts.OutputEffect) bool {
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

fn findInputPostState(states: []const facts.InputPlaceEffect, target: facts.InputPath) ?facts.InputPlaceEffect {
    for (states) |state| if (inputPlaceTargetEqual(state.target, target)) return state;
    return null;
}

fn inputPostStatesEqual(left: []const facts.InputPlaceEffect, right: []const facts.InputPlaceEffect) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!inputPlaceTargetEqual(a.target, b.target) or a.initializedness != b.initializedness or
            a.ends_previous_roots != b.ends_previous_roots or a.refreshes_storage_root != b.refreshes_storage_root or
            a.requires_available_destination != b.requires_available_destination or
            a.opaque_ownership != b.opaque_ownership or
            !optionalInputPathEqual(a.opaque_storage, b.opaque_storage) or
            !outputEffectEqual(a.value, b.value)) return false;
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

fn inputPlaceTargetEqual(left: facts.InputPath, right: facts.InputPath) bool {
    return left.input_index == right.input_index and projectionsEqual(left.projections, right.projections);
}

fn optionalInputPathEqual(left: ?facts.InputPath, right: ?facts.InputPath) bool {
    if ((left == null) != (right == null)) return false;
    return if (left) |path| inputPlaceTargetEqual(path, right.?) else true;
}

fn cloneInputPostStates(source: *const std.array_list.Managed(facts.InputPlaceEffect), allocator: std.mem.Allocator) !std.array_list.Managed(facts.InputPlaceEffect) {
    var result = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
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

fn appendDependency(list: *std.array_list.Managed(facts.ReferenceDependency), dependency: facts.ReferenceDependency) !void {
    for (list.items) |existing| if (existing.root == dependency.root) return;
    try list.append(dependency);
}

fn appendPlace(list: *std.array_list.Managed(place.Place), storage: place.Place) !void {
    for (list.items) |existing| if (existing.eql(storage)) return;
    try list.append(storage);
}

fn appendOwnedRoot(list: *std.array_list.Managed(facts.RootId), owned_root: facts.RootId) !void {
    for (list.items) |existing| if (existing == owned_root) return;
    try list.append(owned_root);
}

fn appendStorageAuthority(list: *std.array_list.Managed(facts.StorageAuthorityId), authority: facts.StorageAuthorityId) !void {
    for (list.items) |existing| if (existing == authority) return;
    try list.append(authority);
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

fn appendFreshSource(list: *std.array_list.Managed(facts.FreshRootSource), source: facts.FreshRootSource) !void {
    for (list.items) |existing| if (existing == source) return;
    try list.append(source);
}

fn joinOpaqueOwnership(left: facts.OpaqueOwnershipConsumption, right: facts.OpaqueOwnershipConsumption) facts.OpaqueOwnershipConsumption {
    if (left == right) return left;
    if (left == .none and right == .none) return .none;
    return .maybe;
}

fn projectionsEqual(left: []const place.Projection, right: []const place.Projection) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!a.eql(b)) return false;
    return true;
}

fn outputEffectEqual(left: facts.OutputEffect, right: facts.OutputEffect) bool {
    if (left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        !std.mem.eql(facts.FreshRootSource, left.fresh_dependencies, right.fresh_dependencies) or
        !std.mem.eql(facts.FreshRootSource, left.fresh_owned_roots, right.fresh_owned_roots) or
        !std.mem.eql(facts.FreshRootSource, left.fresh_storage_authorities, right.fresh_storage_authorities)) return false;
    if (left.input_dependencies.len != right.input_dependencies.len or left.input_places.len != right.input_places.len or left.fields.len != right.fields.len or left.variants.len != right.variants.len) return false;
    for (left.input_dependencies, right.input_dependencies) |a, b| {
        if (!inputDependencyEqual(a, b)) return false;
    }
    for (left.input_places, right.input_places) |a, b| if (!inputPlaceTargetEqual(a, b)) return false;
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

    const left_source: facts.FreshRootSource = 11;
    const right_source: facts.FreshRootSource = 29;
    const compatible = try checker.mergeVirtualFunctionSummary(
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

    const incompatible = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{ .fresh_owned_roots = &.{left_source} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(incompatible == null);
}

test "virtual summaries require exact ownership transfer and deinitialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const transfer = facts.InputDependency{ .path = .{ .input_index = 0 }, .transfers_ownership = true };
    const transfer_mismatch = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{ .input_dependencies = &.{transfer} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(transfer_mismatch == null);

    const deinit_mismatch = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .deinitialized,
            .ends_previous_roots = true,
        }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(deinit_mismatch == null);

    const opaque_mismatch = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .initialized,
            .opaque_ownership = .definite,
        }} },
        .{ .outputs = &.{.{}}, .input_post_states = &.{.{
            .target = .{ .input_index = 0 },
            .initializedness = .initialized,
            .opaque_ownership = .maybe,
        }} },
    );
    try std.testing.expect(opaque_mismatch == null);
}

test "virtual summaries widen dependencies but require exact provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const from_self = facts.InputDependency{ .path = .{ .input_index = 0 } };
    const from_other = facts.InputDependency{ .path = .{ .input_index = 1 } };
    const widened = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{ .input_dependencies = &.{from_self} }} },
        .{ .outputs = &.{.{ .input_dependencies = &.{ from_self, from_other } }} },
    );
    try std.testing.expect(widened != null);
    try std.testing.expectEqual(@as(usize, 2), widened.?.outputs[0].input_dependencies.len);

    const provenance_mismatch = try checker.mergeVirtualFunctionSummary(
        .{ .outputs = &.{.{ .fresh_storage_authorities = &.{1} }} },
        .{ .outputs = &.{.{}} },
    );
    try std.testing.expect(provenance_mismatch == null);
}

test "output instantiation preserves sparse semantic field indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const dependency = try checker.allocator.create(facts.OutputEffect);
    dependency.* = .{ .fresh_dependencies = &.{91} };
    const empty = try checker.allocator.create(facts.OutputEffect);
    empty.* = .{};
    const fields = try checker.allocator.alloc(facts.OutputFieldEffect, 2);
    // The representation is deliberately sparse and out of semantic order.
    fields[0] = .{ .index = 2, .value = dependency };
    fields[1] = .{ .index = 0, .value = empty };
    const effect = facts.OutputEffect{
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
    const dependency_root: facts.RootId = @enumFromInt(1);
    const owned_root: facts.RootId = @enumFromInt(2);
    const authority: facts.StorageAuthorityId = @enumFromInt(3);

    const nested = try checker.allocator.create(facts.ValueFacts);
    nested.* = .{
        .dependencies = &.{.{ .root = dependency_root }},
        .owned_roots = &.{owned_root},
        .integer_address = true,
        .foreign_storage = true,
        .storage_authorities = &.{authority},
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
        .storage_authorities = &.{authority},
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

    const nested = try checker.allocator.create(facts.OutputEffect);
    nested.* = .{
        .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }},
        .input_places = &.{.{ .input_index = 2 }},
        .fresh_dependencies = &.{11},
        .fresh_owned_roots = &.{12},
        .integer_address = true,
        .foreign_storage = true,
        .fresh_storage_authorities = &.{13},
    };
    const payload_fields = try checker.allocator.alloc(facts.OutputFieldEffect, 1);
    payload_fields[0] = .{ .index = 17, .value = nested };
    const payload = facts.OutputEffect{
        .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }},
        .input_places = &.{.{ .input_index = 2 }},
        .fields = payload_fields,
        .fresh_dependencies = &.{11},
        .fresh_owned_roots = &.{12},
        .integer_address = true,
        .foreign_storage = true,
        .fresh_storage_authorities = &.{13},
    };

    const wrapped = try checker.choiceOutputEffect(5, payload);
    try std.testing.expectEqual(@as(usize, 0), wrapped.fields.len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.variants.len);
    try std.testing.expectEqual(@as(u32, 5), wrapped.variants[0].index);
    try std.testing.expect(outputEffectEqual(payload, wrapped.variants[0].value.*));

    const nested_wrapped = try checker.choiceOutputEffect(9, wrapped);
    const extracted = nested_wrapped.variants[0].value.variants[0].value.*;
    try std.testing.expect(outputEffectEqual(payload, extracted));
}

test "choice alternatives activate fresh ownership by variant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const owned = facts.OutputEffect{ .fresh_owned_roots = &.{41} };
    const ok = try checker.choiceOutputEffect(0, owned);
    const failed = try checker.choiceOutputEffect(1, .{});
    const alternatives = try checker.mergeOutputEffects(ok, failed);
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

    var states = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
    defer states.deinit();
    const target = facts.InputPath{ .input_index = 0 };

    // The value is deliberately fact-free: recording this transition must not
    // depend on pointers in the value or on the callee's name.
    try checker.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false);
    try std.testing.expectEqual(@as(usize, 1), states.items.len);
    try std.testing.expectEqual(value_state.Initializedness.initialized, states.items[0].initializedness);
    try std.testing.expect(!states.items[0].refreshes_storage_root);

    try checker.recordInputPostState(&states, &.{target}, .deinitialized, .{}, true, false, false);
    try checker.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false);
    try std.testing.expect(states.items[0].refreshes_storage_root);
}

test "opaque ownership joins are path-order independent and finite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    var opaque_branch = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
    defer opaque_branch.deinit();
    try checker.recordOpaqueOwnershipConsumption(&opaque_branch, &.{target}, .definite, null);
    var plain_branch = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
    defer plain_branch.deinit();

    var forward = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
    defer forward.deinit();
    try checker.joinInputPostStates(&forward, &opaque_branch, &plain_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.maybe, forward.items[0].opaque_ownership);

    var reverse = std.array_list.Managed(facts.InputPlaceEffect).init(allocator);
    defer reverse.deinit();
    try checker.joinInputPostStates(&reverse, &plain_branch, &opaque_branch);
    try std.testing.expect(inputPostStatesEqual(forward.items, reverse.items));

    var fixed_point = try cloneInputPostStates(&forward, allocator);
    defer fixed_point.deinit();
    try checker.joinInputPostStates(&fixed_point, &fixed_point, &opaque_branch);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.maybe, fixed_point.items[0].opaque_ownership);
    try std.testing.expectEqual(@as(usize, 1), fixed_point.items.len);
}

test "opaque ownership projections retain sibling facts" {
    const owned_field = facts.ValueFacts{ .owned_roots = &.{@enumFromInt(0)} };
    const sibling = facts.ValueFacts{ .owned_roots = &.{@enumFromInt(1)} };
    const value = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = &owned_field },
        .{ .index = 1, .value = &sibling },
    } };
    const projected = projectValueFacts(value, &.{.{ .field = 0 }});
    var roots = std.array_list.Managed(facts.RootId).init(std.testing.allocator);
    defer roots.deinit();
    try collectOwnedRoots(projected, &roots);
    try std.testing.expectEqualSlices(facts.RootId, &.{@as(facts.RootId, @enumFromInt(0))}, roots.items);
}

test "opaque ownership distinguishes internal from external dependencies recursively" {
    const owned: facts.RootId = @enumFromInt(0);
    const external: facts.RootId = @enumFromInt(1);
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
    try std.testing.expectEqualStrings("opaque ownership storage cannot hide dependencies on external roots", diags.list.items[0].msg);
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

    try checker.validateBlock(&function, &block, &state);

    try std.testing.expectEqual(@as(usize, 1), diags.list.items.len);
    try std.testing.expectEqualStrings("cannot end a root while opaque storage hides a dependency on it", diags.list.items[0].msg);
    try std.testing.expect(state.tracker.isAlive(first));
    try std.testing.expect(state.tracker.isAlive(hidden));
    const preserved = checker.getPlace(&state, .{ .root = &binding }).?;
    try std.testing.expectEqual(value_state.Initializedness.initialized, preserved.initializedness);
    try std.testing.expect(valueFactsEqual(value, preserved.value));
}

test "relocation transfers storage authority into refreshed destination storage" {
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
    const authority: facts.StorageAuthorityId = @enumFromInt(0);
    try state.storage_authorities.append(.available);
    try state.places.append(.{
        .storage = source,
        .initializedness = .initialized,
        .value = .{
            .owned_roots = &.{resource},
            .foreign_storage = true,
            .storage_authorities = &.{authority},
        },
    });
    try state.places.append(.{ .storage = destination, .initializedness = .deinitialized });
    const old_destination_root = try checker.storageRootForPlace(destination, &state);

    const arguments = [_]sg.StructValueLiteralField{ undefined, undefined };
    const values = [_]facts.ValueFacts{
        .{ .referenced_place = source },
        .{ .referenced_place = destination },
    };
    const function: sg.FunctionDeclaration = undefined;
    _ = try checker.relocatePlaces(&function, &arguments, &values, &state);

    const destination_facts = checker.getPlace(&state, destination).?;
    try std.testing.expectEqual(value_state.Initializedness.initialized, destination_facts.initializedness);
    try std.testing.expectEqualSlices(facts.RootId, &.{resource}, destination_facts.value.owned_roots);
    try std.testing.expectEqualSlices(facts.StorageAuthorityId, &.{authority}, destination_facts.value.storage_authorities);
    try std.testing.expectEqual(value_state.Initializedness.moved, checker.getPlace(&state, source).?.initializedness);
    const new_destination_root = try checker.storageRootForPlace(destination, &state);
    try std.testing.expect(old_destination_root != new_destination_root);
    try std.testing.expectEqual(@as(@TypeOf(state.tracker.roots.items[@intFromEnum(old_destination_root)].state), .dead), state.tracker.roots.items[@intFromEnum(old_destination_root)].state);
    try std.testing.expectEqual(@as(@TypeOf(state.tracker.roots.items[@intFromEnum(resource)].state), .alive), state.tracker.roots.items[@intFromEnum(resource)].state);
}

test "refreshing storage roots invalidates earlier aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = place.Place{ .root = undefined };
    const old_root = try checker.storageRootForPlace(storage, &state);
    const stale_alias = facts.ValueFacts{
        .dependencies = &.{.{ .root = old_root }},
        .referenced_place = storage,
    };

    try checker.refreshStorageRoot(null, &state, storage);
    const fresh_root = try checker.storageRootForPlace(storage, &state);
    try std.testing.expect(old_root != fresh_root);
    try std.testing.expectEqual(.dead, state.tracker.roots.items[@intFromEnum(old_root)].state);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(stale_alias));
    try std.testing.expect(state.tracker.isAlive(fresh_root));
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
    const pointee_root = try checker.storageRootForPlace(pointee, &state);
    const lifetime_root = try checker.storageRootForPlace(lifetime, &state);
    const effect = try checker.restrictReferenceEffect();
    try std.testing.expectEqual(@as(usize, 2), effect.input_dependencies.len);
    try std.testing.expect(!effect.input_dependencies[0].transfers_ownership);
    try std.testing.expect(!effect.input_dependencies[1].transfers_ownership);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), effect.fresh_storage_authorities.len);
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
    try std.testing.expectEqual(@as(usize, 0), restricted.storage_authorities.len);

    state.tracker.end(lifetime_root);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(restricted));
    try std.testing.expect(state.tracker.dependenciesAreAlive(input[0]));
    state.tracker.end(pointee_root);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(input[0]));
}

test "refreshing a place drops descendant storage root mappings" {
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
    const old_parent = try checker.storageRootForPlace(parent, &state);
    const old_child = try checker.storageRootForPlace(child, &state);
    const old_grandchild = try checker.storageRootForPlace(grandchild, &state);
    const old_sibling = try checker.storageRootForPlace(sibling, &state);
    const old_indexed = try checker.storageRootForPlace(indexed, &state);
    const stale_child = facts.ValueFacts{ .dependencies = &.{.{ .root = old_child }} };

    try checker.refreshStorageRoot(null, &state, parent);
    const fresh_parent = try checker.storageRootForPlace(parent, &state);
    const fresh_child = try checker.storageRootForPlace(child, &state);
    const fresh_grandchild = try checker.storageRootForPlace(grandchild, &state);
    const fresh_sibling = try checker.storageRootForPlace(sibling, &state);
    const fresh_indexed = try checker.storageRootForPlace(indexed, &state);
    try std.testing.expect(old_parent != fresh_parent);
    try std.testing.expect(old_child != fresh_child);
    try std.testing.expect(old_grandchild != fresh_grandchild);
    try std.testing.expect(old_sibling != fresh_sibling);
    try std.testing.expect(old_indexed != fresh_indexed);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(stale_child));

    const sibling_before_field_refresh = fresh_sibling;
    try checker.refreshStorageRoot(null, &state, child);
    try std.testing.expectEqual(sibling_before_field_refresh, try checker.storageRootForPlace(sibling, &state));
}

test "opaque dependency projection cannot instantiate ownership or authorities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(&allocator, undefined);
    defer checker.deinit();

    const projected = try checker.dependencyOnlyEffect(.{
        .input_dependencies = &.{.{ .path = .{ .input_index = 0 }, .transfers_ownership = true }},
        .fresh_dependencies = &.{11},
        .fresh_owned_roots = &.{12},
        .fresh_storage_authorities = &.{13},
        .integer_address = true,
        .foreign_storage = true,
    });
    try std.testing.expect(!projected.input_dependencies[0].transfers_ownership);
    try std.testing.expectEqualSlices(facts.FreshRootSource, &.{11}, projected.fresh_dependencies);
    try std.testing.expectEqual(@as(usize, 0), projected.fresh_owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), projected.fresh_storage_authorities.len);
    try std.testing.expect(!projected.integer_address);
    try std.testing.expect(!projected.foreign_storage);

    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    var fresh_roots = std.AutoHashMap(facts.FreshRootSource, facts.RootId).init(allocator);
    defer fresh_roots.deinit();
    var hidden = std.array_list.Managed(facts.RootId).init(allocator);
    defer hidden.deinit();
    try checker.instantiateOpaqueDependencies(projected, &.{.{}}, &state, &fresh_roots, &hidden);
    try std.testing.expectEqual(@as(usize, 1), state.tracker.roots.items.len);
    try std.testing.expect(!state.tracker.roots.items[0].owned_resource);
    try std.testing.expectEqual(@as(usize, 0), state.storage_authorities.items.len);
}
