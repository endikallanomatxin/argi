const std = @import("std");
const profile = @import("../../1_base/profile.zig");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const primitives = @import("../primitives/schema.zig");
const facts = @import("facts.zig");
const summaries = @import("summaries.zig");
const value_state = @import("value_state.zig");
const primitive_transfer = @import("../primitives/registry.zig");
const initializer_contract = @import("../global/initializer_contract.zig");

/// Symbolic SafetySummary inference over the compact GlobalSG.
///
/// This is the indexed counterpart of the old checker's `inferBlock` /
/// `inferExpression` layer. Runtime validation must not be used to discover
/// recursive effects: this pass describes outputs in terms of function inputs
/// and lets `summaries.Engine` iterate callers/SCCs to a fixed point.
pub const Infer = struct {
    profile_io: ?std.Io = null,
    output_ns: u64 = 0,
    required_live_ns: u64 = 0,
    post_state_ns: u64 = 0,
    outcome_ns: u64 = 0,
    opaque_ns: u64 = 0,
    virtual_summary_ns: u64 = 0,
    virtual_receiver_ns: u64 = 0,
    virtual_summary_merges: u64 = 0,
    evaluations: u64 = 0,
    summary_changes: u64 = 0,
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    engine: *summaries.Engine,
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect),
    place_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath),
    local_address_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, []const graph_mod.GlobalNodeId),
    virtual_summaries: std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, facts.SafetySummary),
    invalid_virtual_summaries: std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, void),

    pub fn init(
        allocator: std.mem.Allocator,
        graph: *const graph_mod.GlobalSemanticGraph,
        engine: *summaries.Engine,
    ) Infer {
        return .{
            .allocator = allocator,
            .graph = graph,
            .engine = engine,
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect).init(allocator),
            .place_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath).init(allocator),
            .local_address_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, []const graph_mod.GlobalNodeId).init(allocator),
            .virtual_summaries = std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, facts.SafetySummary).init(allocator),
            .invalid_virtual_summaries = std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, void).init(allocator),
        };
    }

    pub fn deinit(self: *Infer) void {
        self.bindings.deinit();
        self.place_bindings.deinit();
        self.local_address_bindings.deinit();
        self.virtual_summaries.deinit();
        self.invalid_virtual_summaries.deinit();
    }

    /// Infer every SafetySummary dimension until reverse dependencies are stable:
    /// outputs, required-live inputs, input/outcome post-states, and opaque effects.
    /// Reading a previous approximation records a dependency, including the
    /// function's own approximation and implementations merged for virtual calls.
    pub fn inferSafetySummariesFixedPoint(self: *Infer) !void {
        var functions = std.array_list.Managed(graph_mod.GlobalFunctionId).init(self.allocator);
        defer functions.deinit();

        for (self.graph.functions.items, 0..) |function, raw| {
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!self.engine.summaries.contains(id)) {
                const outputs = try self.allocator.alloc(facts.ValueEffect, function.output_bindings.len);
                @memset(outputs, .{});
                if (function.flags.is_c_abi and !function.flags.has_declared_body and outputs.len == 1) {
                    const ty = self.graph.fields.items[function.output.start].ty;
                    if (self.graph.semanticType(ty) == .pointer or @import("../global/c_abi.zig").isRawPointer(self.graph, ty))
                        outputs[0].foreign_storage = true;
                }
                try self.engine.summaries.put(id, .{ .outputs = outputs });
            }
            if (function.flags.has_foreign_capability) {
                // Authorization must remain live even for imports whose other
                // storage effects are unknown. Callers compose this requirement
                // through the same summary dependency paths as dereferences.
                self.engine.summaries.getPtr(id).?.required_live_inputs = try self.allocator.dupe(facts.InputPath, &.{.{ .input_index = function.input.len - 1, .projections = &.{} }});
            }
            // These declarations retain their initial summary. Primitive
            // transfers are instantiated at calls with call-site identities;
            // extern declarations cannot infer effects from a missing body.
            if (function.body != null and function.safety_primitive == .none)
                try functions.append(id);
        }
        // All dimensions read callee approximations through summaryFor. The
        // engine records those reads and the read of our own prior outputs,
        // so a change schedules every observer, including recursive callers.
        try self.engine.seed(functions.items);
        while (self.engine.nextDirty()) |function| {
            // Successful and unrepresentable virtual merges both depend on
            // concrete summary approximations. Recompute them for each worklist
            // evaluation so changes cannot leave either kind of cache stale.
            self.virtual_summaries.clearRetainingCapacity();
            self.invalid_virtual_summaries.clearRetainingCapacity();
            self.evaluations += 1;
            self.engine.beginInference(function);
            const next = self.inferFunction(function) catch |err| {
                self.engine.current = null;
                return err;
            };
            try self.engine.endInference();
            if (try self.engine.updateSummary(function, next)) self.summary_changes += 1;
        }
        // A virtual summary may have been cached while one of its concrete
        // implementations still held an earlier fixed-point approximation.
        // Runtime validation must merge the final summaries.
        self.virtual_summaries.clearRetainingCapacity();
        self.invalid_virtual_summaries.clearRetainingCapacity();
    }

    pub fn virtualSummary(
        self: *Infer,
        registry_id: graph_mod.GlobalVirtualRegistryId,
    ) !?facts.SafetySummary {
        const start = profile.timestamp(self.profile_io);
        defer profile.accumulate(self.profile_io, start, &self.virtual_summary_ns);
        if (self.invalid_virtual_summaries.contains(registry_id)) return null;
        if (self.virtual_summaries.get(registry_id)) |summary| return summary;
        const registry = self.graph.virtual_registries.items[@intFromEnum(registry_id)];
        const implementations = self.graph.function_refs.items[registry.implementations.start..][0..registry.implementations.len];
        if (implementations.len == 0) return null;
        self.virtual_summary_merges += 1;

        const receiver = self.virtualReceiverIndex(registry_id);
        var merged = (try self.virtualImplementationSummary(implementations[0], receiver)) orelse return null;
        if (!virtualInputPostStatesRuntimeRepresentable(merged.input_post_states)) {
            try self.invalid_virtual_summaries.put(registry_id, {});
            return null;
        }
        for (implementations[1..]) |implementation| {
            const next = (try self.virtualImplementationSummary(implementation, receiver)) orelse return null;
            if (!virtualInputPostStatesRuntimeRepresentable(next.input_post_states)) {
                try self.invalid_virtual_summaries.put(registry_id, {});
                return null;
            }
            merged = (try self.mergeVirtualSafetySummary(merged, next)) orelse {
                try self.invalid_virtual_summaries.put(registry_id, {});
                return null;
            };
        }
        try self.virtual_summaries.put(registry_id, merged);
        return merged;
    }

    pub fn virtualReceiverIndex(self: *Infer, registry_id: graph_mod.GlobalVirtualRegistryId) ?u32 {
        const start = profile.timestamp(self.profile_io);
        defer profile.accumulate(self.profile_io, start, &self.virtual_receiver_ns);
        return self.graph.virtual_registries.items[@intFromEnum(registry_id)].receiver_input_index;
    }

    pub fn virtualizeReceiverIndex(self: *const Infer, virtualize: graph_mod.Virtualize, method_index: usize) u32 {
        const registry = self.graph.virtual_registry_refs.items[virtualize.safety_methods.start + method_index];
        return self.graph.virtual_registries.items[@intFromEnum(registry)].receiver_input_index;
    }

    fn virtualImplementationSummary(self: *Infer, implementation: graph_mod.GlobalFunctionId, receiver: ?u32) !?facts.SafetySummary {
        var summary = self.engine.summaryFor(implementation) orelse return null;
        var states = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        const function = self.graph.function(implementation);
        const outputs = try self.allocator.alloc(facts.ValueEffect, summary.outputs.len);
        for (summary.outputs, 0..) |output, index| {
            const erased = try self.eraseScalarOwnershipTransfers(function, output);
            outputs[index] = if (receiver) |receiver_index|
                try self.borrowVirtualReceiverGenerations(erased, receiver_index)
            else
                erased;
        }
        for (summary.storage_capability_uses) |use| {
            if (receiver != null and use.target.input_index == receiver.? and use.target.projections.len != 0) return null;
        }
        summary.outputs = outputs;
        for (summary.input_post_states) |state| {
            var ty = self.graph.fields.items[function.input.start + state.target.input_index].ty;
            var scalar_field = receiver != null and state.target.input_index == receiver.? and state.target.projections.len != 0;
            for (state.target.projections) |projection| {
                if (self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
                switch (projection) {
                    .field => |index| {
                        const fields = types.fields(self.graph, ty) orelse {
                            scalar_field = false;
                            break;
                        };
                        if (index >= fields.len) {
                            scalar_field = false;
                            break;
                        }
                        ty = types.effectiveFieldType(self.graph.fields.items[fields.start + index]);
                    },
                    else => {
                        scalar_field = false;
                        break;
                    },
                }
            }
            // Scalar receiver fields are implementation details, not fields of
            // the erased Virtual handle. They carry no published borrow state.
            if (scalar_field and !self.typeContainsPointer(ty) and
                state.initializedness == .initialized and state.opaque_ownership == .none and
                !state.ends_previous_roots and !state.refreshes_storage_generation and
                !state.requires_available_destination and !state.value.explicit_dependency and
                state.value.fresh_owned_roots.len == 0 and state.value.fresh_dependencies.len == 0 and
                state.value.fresh_storage_capabilities.len == 0) continue;
            try states.append(state);
        }
        summary.input_post_states = try states.toOwnedSlice();
        // Receiver layout disappears at dispatch. Its liveness requirement
        // covers the full receiver contents, which the concrete checker
        // validates before applying this erased summary. This also keeps
        // recursive wrapper composition from growing private field paths.
        var required = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (summary.required_live_inputs) |path| {
            var erased = path;
            if (receiver != null and path.input_index == receiver.?) erased.projections = &.{};
            try appendInputPath(&required, erased);
        }
        summary.required_live_inputs = try required.toOwnedSlice();
        return summary;
    }

    fn eraseScalarOwnershipTransfers(
        self: *Infer,
        function: graph_mod.Function,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        var result = effect;
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| {
            if (!dependency.transfers_ownership or dependency.path.projections.len != 0 or
                dependency.path.input_index >= function.input.len) continue;
            const input = self.graph.fields.items[function.input.start + dependency.path.input_index];
            // A syntactic move marks the input path as transferred even when
            // its value cannot carry an owned root. Erase only that vacuous
            // transfer before comparing concrete implementations of a
            // Virtual method; the input's validity dependency remains.
            const cannot_own = switch (self.graph.semanticType(input.ty)) {
                .builtin => |builtin| switch (builtin) {
                    .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64, .Char, .Bool, .Void, .Type => true,
                    else => false,
                },
                .pointer => true,
                else => false,
            };
            if (cannot_own) dependency.transfers_ownership = false;
        }
        result.input_dependencies = dependencies;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, 0..) |field, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.eraseScalarOwnershipTransfers(function, field.value.*);
            fields[index] = .{ .index = field.index, .value = value };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, 0..) |variant, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.eraseScalarOwnershipTransfers(function, variant.value.*);
            variants[index] = .{ .index = variant.index, .value = value };
        }
        result.variants = variants;
        return result;
    }

    pub fn virtualSummaryInvalid(self: *const Infer, registry_id: graph_mod.GlobalVirtualRegistryId) bool {
        return self.invalid_virtual_summaries.contains(registry_id);
    }

    fn mergeVirtualSafetySummary(
        self: *Infer,
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

        var fresh_map = std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource).init(self.allocator);
        defer fresh_map.deinit();
        // Match identities throughout the output before merging any field:
        // an optional root in an early field may be shared with a root that
        // both implementations expose in a later field.
        for (left.outputs, right.outputs) |left_output, right_output|
            if (!try self.prealignVirtualFreshSources(left_output, right_output, &fresh_map)) return null;
        const outputs = try self.allocator.alloc(facts.ValueEffect, left.outputs.len);
        for (left.outputs, right.outputs, 0..) |left_output, right_output, index|
            outputs[index] = (try self.mergeVirtualValueEffect(left_output, right_output, &fresh_map)) orelse return null;

        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator);
        for (left.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);
        for (right.opaque_storage_effects) |effect|
            try self.recordOpaqueStorageEffect(&opaque_storage_effects, effect.storage, effect.hidden_dependencies);

        const empty_intersection = try self.intersectInputPaths(left.opaque_storage_empties, right.opaque_storage_empties);
        var opaque_storage_empties = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (empty_intersection) |empty| {
            var repopulated = false;
            for (opaque_storage_effects.items) |effect| if (self.inputPathEqual(empty, effect.storage)) {
                repopulated = true;
                break;
            };
            if (!repopulated) try appendInputPath(&opaque_storage_empties, empty);
        }

        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.required_live_inputs) |input| try appendInputPath(&required_live_inputs, input);
        for (right.required_live_inputs) |input| try appendInputPath(&required_live_inputs, input);
        var left_capabilities = CapabilityFlow.init(self.allocator);
        defer left_capabilities.deinit();
        var right_capabilities = CapabilityFlow.init(self.allocator);
        defer right_capabilities.deinit();
        for (left.storage_capability_uses) |use| try self.add_capability_count(&left_capabilities, .{ .input = use.target }, use.minimum, use.maximum);
        for (right.storage_capability_uses) |use| try self.add_capability_count(&right_capabilities, .{ .input = use.target }, use.minimum, use.maximum);
        for (left.storage_capability_conflicts) |pair| try self.record_capability_conflict(&left_capabilities, .{ .input = pair.first }, .{ .input = pair.second });
        for (right.storage_capability_conflicts) |pair| try self.record_capability_conflict(&right_capabilities, .{ .input = pair.first }, .{ .input = pair.second });
        var joined_capabilities = CapabilityFlow.init(self.allocator);
        defer joined_capabilities.deinit();
        try self.join_capability_flows(&joined_capabilities, &left_capabilities, &right_capabilities);
        var capability_uses = std.array_list.Managed(facts.StorageCapabilityUse).init(self.allocator);
        for (joined_capabilities.counts.items) |count| try capability_uses.append(.{ .target = count.source.input, .minimum = count.minimum, .maximum = count.maximum });
        var capability_conflicts = std.array_list.Managed(facts.StorageCapabilityConflict).init(self.allocator);
        for (joined_capabilities.conflicts.items) |pair| try capability_conflicts.append(.{ .first = pair.first.input, .second = pair.second.input });
        return .{
            .outputs = outputs,
            .storage_capability_uses = try capability_uses.toOwnedSlice(),
            .storage_capability_conflicts = try capability_conflicts.toOwnedSlice(),

            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .input_post_states = input_post_states,
            .opaque_storage_effects = try opaque_storage_effects.toOwnedSlice(),
            .opaque_storage_empties = try opaque_storage_empties.toOwnedSlice(),
        };
    }

    fn prealignVirtualFreshSources(
        self: *Infer,
        left: facts.ValueEffect,
        right: facts.ValueEffect,
        mapping: *std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource),
    ) !bool {
        if (left.fresh_dependencies.len != 0 and right.fresh_dependencies.len != 0 and
            (left.fresh_dependencies.len != right.fresh_dependencies.len or
                !try alignFreshSources(left.fresh_dependencies, right.fresh_dependencies, mapping))) return false;
        if (left.fresh_owned_roots.len != 0 and right.fresh_owned_roots.len != 0 and
            (left.fresh_owned_roots.len != right.fresh_owned_roots.len or
                !try alignFreshSources(left.fresh_owned_roots, right.fresh_owned_roots, mapping))) return false;
        if (left.fresh_storage_capabilities.len != 0 and right.fresh_storage_capabilities.len != 0 and
            (left.fresh_storage_capabilities.len != right.fresh_storage_capabilities.len or
                !try alignFreshSources(left.fresh_storage_capabilities, right.fresh_storage_capabilities, mapping))) return false;
        for (left.fields) |left_field| for (right.fields) |right_field| {
            if (left_field.index == right_field.index and
                !try self.prealignVirtualFreshSources(left_field.value.*, right_field.value.*, mapping)) return false;
        };
        for (left.variants) |left_variant| for (right.variants) |right_variant| {
            if (left_variant.index == right_variant.index and
                !try self.prealignVirtualFreshSources(left_variant.value.*, right_variant.value.*, mapping)) return false;
        };
        return true;
    }

    fn mergeVirtualInputPostStates(
        self: *Infer,
        left: []const facts.PlacePostState,
        right: []const facts.PlacePostState,
    ) !?[]const facts.PlacePostState {
        var merged = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        for (left) |left_state| {
            const right_state = self.findInputPostState(right, left_state.target) orelse facts.PlacePostState{
                .target = left_state.target,
                .initializedness = .initialized,
                .value = try self.inputPlaceValueEffect(left_state.target),
            };
            try merged.append((try self.mergeVirtualPlacePostState(left_state, right_state)) orelse return null);
        }
        for (right) |right_state| if (self.findInputPostState(left, right_state.target) == null) {
            const unchanged = facts.PlacePostState{
                .target = right_state.target,
                .initializedness = .initialized,
                .value = try self.inputPlaceValueEffect(right_state.target),
            };
            try merged.append((try self.mergeVirtualPlacePostState(unchanged, right_state)) orelse return null);
        };
        return try merged.toOwnedSlice();
    }

    fn mergeVirtualPlacePostState(
        self: *Infer,
        left: facts.PlacePostState,
        right: facts.PlacePostState,
    ) !?facts.PlacePostState {
        if (!self.inputPathEqual(left.target, right.target)) return null;
        if (!virtualInputPostStateRuntimeRepresentable(left) or
            !virtualInputPostStateRuntimeRepresentable(right)) return null;

        const value = if (summaries.valueEffectEql(left.value, right.value))
            left.value
        else blk: {
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
        if (!self.mergeVirtualOpaqueOwnershipEffect(&result, left, right)) return null;
        return result;
    }

    fn mergeVirtualOpaqueOwnershipEffect(
        self: *Infer,
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
        if (!self.optionalInputPathEqual(left_storage, right_storage)) return false;
        merged.opaque_storage = left_storage;
        merged.opaque_ownership = if (left_ownership == .none or right_ownership == .none or
            left_ownership == .conditional or right_ownership == .conditional)
            .conditional
        else
            .definite;
        return true;
    }

    fn borrowVirtualReceiverGenerations(self: *Infer, effect: facts.ValueEffect, receiver_index: u32) !facts.ValueEffect {
        // Private receiver projections cannot be instantiated against an
        // erased Virtual handle. Carry their lifetime through the handle's
        // value and collapse opaque provenance paths before fixed-point
        // inference can extend them through recursive allocator wrappers.
        var result = effect;
        var private_receiver_borrow = false;
        var places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_places) |path| {
            if (path.input_index == receiver_index and path.projections.len != 0) {
                private_receiver_borrow = true;
            } else try appendInputPath(&places, path);
        }
        result.input_places = try places.toOwnedSlice();
        var generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_generation_dependencies) |path| {
            if (path.input_index == receiver_index and path.projections.len != 0) {
                private_receiver_borrow = true;
            } else try appendInputPath(&generations, path);
        }
        result.input_generation_dependencies = try generations.toOwnedSlice();
        var storage_capabilities = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_storage_capabilities) |path| {
            var erased = path;
            if (path.input_index == receiver_index) erased.projections = &.{};
            try appendInputPath(&storage_capabilities, erased);
        }
        result.input_storage_capabilities = try storage_capabilities.toOwnedSlice();
        var receiver_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_place_values) |path| {
            if (path.input_index == receiver_index and path.projections.len != 0) {
                private_receiver_borrow = true;
            } else try appendInputPath(&receiver_values, path);
        }
        if (private_receiver_borrow)
            try appendInputPath(&receiver_values, .{ .input_index = receiver_index });
        result.input_place_values = try receiver_values.toOwnedSlice();
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.opaque_generation_dependencies) |path| {
            // The erased receiver has no implementation-specific fields.
            // Its opaque provenance is carried by the whole Virtual value.
            const erased = if (path.input_index == receiver_index and path.projections.len != 0)
                facts.InputPath{ .input_index = receiver_index }
            else
                path;
            try appendInputPath(&opaque_generations, erased);
        }
        result.opaque_generation_dependencies = try opaque_generations.toOwnedSlice();
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.borrowVirtualReceiverGenerations(field.value.*, receiver_index);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.borrowVirtualReceiverGenerations(variant.value.*, receiver_index);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn mergeVirtualValueEffect(
        self: *Infer,
        left: facts.ValueEffect,
        right: facts.ValueEffect,
        fresh_map: *std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource),
    ) !?facts.ValueEffect {
        if (left.integer_address != right.integer_address or
            left.foreign_storage != right.foreign_storage or
            left.fresh_storage_capabilities.len != right.fresh_storage_capabilities.len or
            left.variants.len != right.variants.len) return null;

        const fresh_dependencies = (try mergeVirtualFreshRoots(self.allocator, left.fresh_dependencies, right.fresh_dependencies, fresh_map)) orelse return null;
        const fresh_owned_roots = (try mergeVirtualFreshRoots(self.allocator, left.fresh_owned_roots, right.fresh_owned_roots, fresh_map)) orelse return null;
        if (!try alignFreshSources(left.fresh_storage_capabilities, right.fresh_storage_capabilities, fresh_map)) return null;

        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        for (left.input_dependencies) |dependency| try appendInputDependency(&dependencies, dependency);
        for (right.input_dependencies) |dependency| {
            if (dependency.transfers_ownership and !containsInputDependency(left.input_dependencies, dependency)) return null;
            try appendInputDependency(&dependencies, dependency);
        }
        for (left.input_dependencies) |dependency| {
            if (dependency.transfers_ownership and !containsInputDependency(right.input_dependencies, dependency)) return null;
        }

        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_places) |input| try appendInputPath(&input_places, input);
        for (right.input_places) |input| try appendInputPath(&input_places, input);
        var input_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_generation_dependencies) |input| try appendInputPath(&input_generations, input);
        for (right.input_generation_dependencies) |input| try appendInputPath(&input_generations, input);
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_place_values) |input| try appendInputPath(&input_place_values, input);
        for (right.input_place_values) |input| try appendInputPath(&input_place_values, input);
        var input_owned_roots = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_owned_roots) |input| try appendInputPath(&input_owned_roots, input);
        for (right.input_owned_roots) |input| try appendInputPath(&input_owned_roots, input);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_generation_dependencies) |input| try appendInputPath(&opaque_generations, input);
        for (right.opaque_generation_dependencies) |input| try appendInputPath(&opaque_generations, input);
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_storage_dependencies) |input| try appendInputPath(&opaque_storages, input);
        for (right.opaque_storage_dependencies) |input| try appendInputPath(&opaque_storages, input);

        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator);
        for (left.fields) |left_field| {
            const right_value = blk: {
                for (right.fields) |right_field| if (right_field.index == left_field.index) break :blk right_field.value.*;
                break :blk try self.projectValueEffect(right, .{ .field = left_field.index });
            };
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = (try self.mergeVirtualValueEffect(left_field.value.*, right_value, fresh_map)) orelse return null;
            try fields.append(.{ .index = left_field.index, .value = value });
        }
        for (right.fields) |right_field| {
            var found = false;
            for (left.fields) |left_field| if (left_field.index == right_field.index) {
                found = true;
                break;
            };
            if (found) continue;
            const left_value = try self.projectValueEffect(left, .{ .field = right_field.index });
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = (try self.mergeVirtualValueEffect(left_value, right_field.value.*, fresh_map)) orelse return null;
            try fields.append(.{ .index = right_field.index, .value = value });
        }
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, left.variants.len);
        for (left.variants, right.variants, 0..) |left_variant, right_variant, index| {
            if (left_variant.index != right_variant.index) return null;
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = (try self.mergeVirtualValueEffect(left_variant.value.*, right_variant.value.*, fresh_map)) orelse return null;
            variants[index] = .{ .index = left_variant.index, .value = value };
        }
        const right_unavailable = try self.allocator.alloc(facts.FreshStorageCapabilityState, right.unavailable_fresh_storage.len);
        for (right.unavailable_fresh_storage, 0..) |entry, index| {
            right_unavailable[index] = entry;
            right_unavailable[index].source = fresh_map.get(entry.source) orelse entry.source;
            right_unavailable[index].maybe_consumed = true;
        }
        const unavailable = try self.merge_unavailable_fresh_storage(left.unavailable_fresh_storage, right_unavailable);
        return .{
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_storage_capabilities = try self.union_input_paths(left.input_storage_capabilities, right.input_storage_capabilities),
            .input_places = try input_places.toOwnedSlice(),
            .input_generation_dependencies = try input_generations.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .input_owned_roots = try input_owned_roots.toOwnedSlice(),
            .opaque_generation_dependencies = try opaque_generations.toOwnedSlice(),
            .opaque_storage_dependencies = try opaque_storages.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .variants = variants,
            .known_choice_variant = if (left.known_choice_variant == right.known_choice_variant) left.known_choice_variant else null,
            .fresh_dependencies = fresh_dependencies,
            .fresh_owned_roots = fresh_owned_roots,
            .fresh_storage_capabilities = left.fresh_storage_capabilities,
            .unavailable_fresh_storage = unavailable,
            .integer_address = left.integer_address,
            .explicit_dependency = left.explicit_dependency or right.explicit_dependency,
            .foreign_storage = left.foreign_storage,
        };
    }

    fn inferFunction(self: *Infer, function_id: graph_mod.GlobalFunctionId) !facts.SafetySummary {
        const function = self.graph.function(function_id);
        const previous = self.engine.summaryFor(function_id) orelse return error.MissingSafetySummary;
        const outputs = try self.allocator.dupe(facts.ValueEffect, previous.outputs);

        // Primitive effects are instantiated at the call site so their fresh
        // identities are call-site stable. Keeping declarations fact-free here
        // also prevents one global primitive root identity leaking across calls.
        if (function.safety_primitive != .none or function.body == null) return .{
            .outputs = outputs,
            .required_live_inputs = previous.required_live_inputs,
            .storage_capability_uses = previous.storage_capability_uses,
            .storage_capability_conflicts = previous.storage_capability_conflicts,
            .input_post_states = previous.input_post_states,
            .outcome_post_states = previous.outcome_post_states,
            .opaque_storage_effects = previous.opaque_storage_effects,
            .opaque_storage_empties = previous.opaque_storage_empties,
        };

        self.bindings.clearRetainingCapacity();
        self.place_bindings.clearRetainingCapacity();
        self.local_address_bindings.clearRetainingCapacity();
        var start = profile.timestamp(self.profile_io);
        try self.inferBlock(function_id, function.body.?, outputs);
        profile.accumulate(self.profile_io, start, &self.output_ns);

        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
        start = profile.timestamp(self.profile_io);
        try self.inferRequiredLiveInputsBlock(function_id, function.body.?, &required_live_inputs);
        profile.accumulate(self.profile_io, start, &self.required_live_ns);

        var post_flow = InputPostStateFlow.init(self.allocator);
        defer post_flow.deinit();
        var post_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
        defer if (post_exits) |*exits| exits.deinit();
        start = profile.timestamp(self.profile_io);
        try self.inferInputPostStates(function_id, function.body.?, &post_flow, &post_exits);
        if (post_flow.reachable) try self.recordInputPostStateExit(&post_exits, &post_flow.states);

        var post_states = if (post_exits) |*exits|
            try self.cloneInputPostStates(exits)
        else
            std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer post_states.deinit();

        profile.accumulate(self.profile_io, start, &self.post_state_ns);
        start = profile.timestamp(self.profile_io);
        const outcome_post_states = if (self.isFallibleInitializer(function_id))
            try self.inferInitializerOutcomePostStates(function_id, function.body.?)
        else
            &.{};

        profile.accumulate(self.profile_io, start, &self.outcome_ns);
        start = profile.timestamp(self.profile_io);
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator);
        defer opaque_storage_effects.deinit();
        const opaque_storage_empties = try self.inferOpaqueStorageEffects(
            function_id,
            function.body.?,
            &opaque_storage_effects,
        );
        profile.accumulate(self.profile_io, start, &self.opaque_ns);

        if (function.flags.is_deinit) {
            const input_fields = self.graph.fields.items[function.input.start..][0..function.input.len];
            for (input_fields, 0..) |input_field, index| {
                if (!std.mem.eql(u8, self.graph.text(input_field.name), "self")) continue;
                const mutable_pointer = switch (self.graph.semanticType(input_field.ty)) {
                    .pointer => |pointer| pointer.mutability == .read_write,
                    else => false,
                };
                if (!mutable_pointer) continue;
                const target = facts.InputPath{ .input_index = @intCast(index) };
                try self.recordInputPostState(
                    &post_states,
                    &.{target},
                    .deinitialized,
                    .{},
                    true,
                    false,
                    false,
                    false,
                );
                break;
            }
        }

        // This finite domain tracks authorization separately from lifetime:
        // counts saturate at two, so recursion can express repeated consumption
        // without growing symbolic histories or introducing another scheduler.
        var capability_flow = CapabilityFlow.init(self.allocator);
        defer capability_flow.deinit();
        var capability_exits: ?CapabilityFlow = null;
        defer if (capability_exits) |*exit| exit.deinit();
        try self.infer_capability_block(function_id, function.body.?, &capability_flow, &capability_exits);
        if (capability_flow.reachable) try self.record_capability_exit(&capability_flow, &capability_exits);
        const counts = if (capability_exits) |exit| exit.counts.items else capability_flow.counts.items;
        var capability_uses = std.array_list.Managed(facts.StorageCapabilityUse).init(self.allocator);
        for (counts) |count| if (count.source == .input) {
            try capability_uses.append(.{ .target = count.source.input, .minimum = count.minimum, .maximum = count.maximum });
        };
        var capability_conflicts = std.array_list.Managed(facts.StorageCapabilityConflict).init(self.allocator);
        const conflicts = if (capability_exits) |exit| exit.conflicts.items else capability_flow.conflicts.items;
        for (conflicts) |pair| if (pair.first == .input and pair.second == .input) {
            try capability_conflicts.append(.{ .first = pair.first.input, .second = pair.second.input });
        };
        const returned_bindings = if (capability_exits) |exit| exit.bindings else capability_flow.bindings;
        const output_bindings = self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
        const output_fields = self.graph.fields.items[function.output.start..][0..function.output.len];
        for (outputs, output_bindings, 0..) |*output, binding, index| {
            if (index >= output_fields.len) continue;
            if (returned_bindings.get(binding)) |origin| output.* = try self.overlay_capability_outputs(output.*, origin, output_fields[index].ty);
        }
        for (outputs) |*output| output.* = try self.mark_unavailable_fresh_storage(output.*, counts);
        for (post_states.items) |*post| post.value = try self.mark_unavailable_fresh_storage(post.value, counts);
        for (outcome_post_states) |outcome| for (@constCast(outcome.input_post_states)) |*post| {
            post.value = try self.mark_unavailable_fresh_storage(post.value, counts);
        };

        return .{
            .outputs = outputs,
            .storage_capability_uses = try capability_uses.toOwnedSlice(),
            .storage_capability_conflicts = try capability_conflicts.toOwnedSlice(),
            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .input_post_states = try post_states.toOwnedSlice(),
            .outcome_post_states = outcome_post_states,
            .opaque_storage_effects = try opaque_storage_effects.toOwnedSlice(),
            .opaque_storage_empties = opaque_storage_empties,
        };
    }

    fn inferBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        outputs: []facts.ValueEffect,
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            const node = self.graph.node(node_id);
            switch (node.content) {
                .binding_declaration => |binding| {
                    const initialization = self.graph.binding(binding).initialization orelse continue;
                    try self.local_address_bindings.put(binding, try self.localAddressTargets(initialization));
                    try self.bindings.put(binding, try self.inferExpression(function_id, initialization));
                    try self.place_bindings.put(binding, try self.inferInputPaths(function_id, initialization));
                },
                .assignment => |assignment| {
                    const effect = try self.inferExpression(function_id, assignment.value);
                    if (self.outputIndex(function_id, assignment.binding)) |output_index| {
                        outputs[output_index] = if (outputs[output_index].variants.len != 0 or effect.variants.len != 0)
                            try self.mergeValueEffects(outputs[output_index], effect)
                        else
                            effect;
                    } else {
                        const targets = try self.localAddressTargets(assignment.value);
                        var joined = std.array_list.Managed(graph_mod.GlobalNodeId).init(self.allocator);
                        try joined.appendSlice(self.local_address_bindings.get(assignment.binding) orelse &.{});
                        for (targets) |target| {
                            if (std.mem.indexOfScalar(graph_mod.GlobalNodeId, joined.items, target) == null) try joined.append(target);
                        }
                        try self.local_address_bindings.put(assignment.binding, try joined.toOwnedSlice());
                        try self.bindings.put(assignment.binding, effect);
                        try self.place_bindings.put(assignment.binding, try self.inferInputPaths(function_id, assignment.value));
                    }
                },
                .if_statement => |statement| {
                    try self.inferBlock(function_id, statement.then_block, outputs);
                    if (statement.else_block) |child| try self.inferBlock(function_id, child, outputs);
                },
                .while_statement => |statement| try self.inferBlock(function_id, statement.body, outputs),
                .for_statement => |statement| try self.inferBlock(function_id, statement.body, outputs),
                .switch_statement => |switch_id| {
                    const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                    const choice = try self.inferExpression(function_id, statement.expression);
                    for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                        if (case.payload_binding) |binding| {
                            const ty = self.graph.node(statement.expression).ty orelse continue;
                            const wanted = self.variantIndex(ty, case.variant) orelse continue;
                            const payload = try self.projectValueEffect(choice, .{ .variant = wanted });
                            try self.bindings.put(binding, payload);
                        }
                        try self.inferBlock(function_id, case.body, outputs);
                    }
                    if (statement.default_block) |child| try self.inferBlock(function_id, child, outputs);
                },
                .code_block => |child| try self.inferBlock(function_id, child, outputs),
                else => {},
            }
        }
    }

    const CapabilitySource = union(enum) { input: facts.InputPath, fresh: facts.FreshEffectSource };
    const CapabilityConflict = struct { first: CapabilitySource, second: CapabilitySource };
    const CapabilityCount = struct { source: CapabilitySource, minimum: u2, maximum: u2 };
    const CapabilityFlow = struct {
        conflicts: std.array_list.Managed(CapabilityConflict),
        counts: std.array_list.Managed(CapabilityCount),
        addresses: std.AutoHashMap(graph_mod.GlobalBindingId, []const graph_mod.GlobalNodeId),
        calls: std.AutoHashMap(graph_mod.GlobalNodeId, void),
        bindings: std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect),
        reachable: bool = true,
        breaks_loop: bool = false,

        fn init(allocator: std.mem.Allocator) CapabilityFlow {
            return .{ .conflicts = .init(allocator), .counts = .init(allocator), .bindings = .init(allocator), .calls = .init(allocator), .addresses = .init(allocator) };
        }
        fn deinit(self: *CapabilityFlow) void {
            self.counts.deinit();
            self.conflicts.deinit();
            self.bindings.deinit();
            self.calls.deinit();
            self.addresses.deinit();
        }
        fn clone(self: *const CapabilityFlow, allocator: std.mem.Allocator) !CapabilityFlow {
            var result = CapabilityFlow.init(allocator);
            errdefer result.deinit();
            try result.counts.appendSlice(self.counts.items);
            try result.conflicts.appendSlice(self.conflicts.items);
            result.bindings.deinit();
            result.bindings = try self.bindings.clone();
            result.calls.deinit();
            result.calls = try self.calls.clone();
            result.addresses.deinit();
            result.addresses = try self.addresses.clone();
            result.reachable = self.reachable;
            result.breaks_loop = self.breaks_loop;
            return result;
        }
    };

    fn capability_source_equal(self: *Infer, left: CapabilitySource, right: CapabilitySource) bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        return switch (left) {
            .input => |path| self.inputPathEqual(path, right.input),
            .fresh => |source| source == right.fresh,
        };
    }

    fn add_capability_count(self: *Infer, flow: *CapabilityFlow, source: CapabilitySource, minimum: u2, maximum: u2) !void {
        for (flow.counts.items) |*count| if (self.capability_source_equal(count.source, source)) {
            count.minimum = @intCast(@min(@as(u3, count.minimum) + minimum, 2));
            count.maximum = @intCast(@min(@as(u3, count.maximum) + maximum, 2));
            return;
        };
        try flow.counts.append(.{ .source = source, .minimum = minimum, .maximum = maximum });
    }

    fn join_capability_flows(self: *Infer, output: *CapabilityFlow, left: *const CapabilityFlow, right: *const CapabilityFlow) !void {
        var joined = CapabilityFlow.init(self.allocator);
        errdefer joined.deinit();
        for (left.counts.items) |count| {
            var next = count;
            var found = false;
            for (right.counts.items) |other| if (self.capability_source_equal(count.source, other.source)) {
                next.minimum = @min(count.minimum, other.minimum);
                next.maximum = @max(count.maximum, other.maximum);
                found = true;
                break;
            };
            if (!found) next.minimum = 0;
            try joined.counts.append(next);
        }
        for (right.counts.items) |count| {
            var found = false;
            for (left.counts.items) |other| if (self.capability_source_equal(count.source, other.source)) {
                found = true;
                break;
            };
            if (!found) {
                var next = count;
                next.minimum = 0;
                try joined.counts.append(next);
            }
        }
        try joined.conflicts.appendSlice(left.conflicts.items);
        for (right.conflicts.items) |conflict| try self.record_capability_conflict(&joined, conflict.first, conflict.second);
        var entries = left.bindings.iterator();
        while (entries.next()) |entry| try joined.bindings.put(entry.key_ptr.*, entry.value_ptr.*);
        entries = right.bindings.iterator();
        while (entries.next()) |entry| {
            const value = if (joined.bindings.get(entry.key_ptr.*)) |previous|
                try self.mergeValueEffects(previous, entry.value_ptr.*)
            else
                entry.value_ptr.*;
            try joined.bindings.put(entry.key_ptr.*, value);
        }
        var addresses = left.addresses.iterator();
        while (addresses.next()) |entry| try joined.addresses.put(entry.key_ptr.*, entry.value_ptr.*);
        addresses = right.addresses.iterator();
        while (addresses.next()) |entry| {
            var targets = std.array_list.Managed(graph_mod.GlobalNodeId).init(self.allocator);
            try targets.appendSlice(joined.addresses.get(entry.key_ptr.*) orelse &.{});
            for (entry.value_ptr.*) |target| if (std.mem.indexOfScalar(graph_mod.GlobalNodeId, targets.items, target) == null) {
                try targets.append(target);
            };
            try joined.addresses.put(entry.key_ptr.*, try targets.toOwnedSlice());
        }
        var calls = left.calls.keyIterator();
        while (calls.next()) |call| try joined.calls.put(call.*, {});
        calls = right.calls.keyIterator();
        while (calls.next()) |call| try joined.calls.put(call.*, {});
        joined.reachable = left.reachable or right.reachable;
        joined.breaks_loop = left.breaks_loop and right.breaks_loop;
        output.deinit();
        output.* = joined;
    }

    fn join_capability_fallthrough(self: *Infer, output: *CapabilityFlow, left: *const CapabilityFlow, right: *const CapabilityFlow) !void {
        if (left.reachable != right.reachable) {
            const copied = try (if (left.reachable) left else right).clone(self.allocator);
            output.deinit();
            output.* = copied;
        } else try self.join_capability_flows(output, left, right);
    }

    fn capability_address_targets(self: *Infer, node: graph_mod.GlobalNodeId, flow: *CapabilityFlow) ![]const graph_mod.GlobalNodeId {
        return switch (self.graph.node(node).content) {
            .address_of => |value| self.allocator.dupe(graph_mod.GlobalNodeId, &.{value}),
            .binding_use => |binding| flow.addresses.get(binding) orelse &.{},
            .move_value, .denied_implicit_copy => |value| self.capability_address_targets(value, flow),
            else => &.{},
        };
    }

    fn store_capability_field(self: *Infer, function: graph_mod.GlobalFunctionId, target: graph_mod.GlobalNodeId, index: u32, value: facts.ValueEffect, flow: *CapabilityFlow) anyerror!void {
        var aggregate = try self.capability_value(function, target, flow);
        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator);
        for (aggregate.fields) |field| if (field.index != index) {
            try fields.append(field);
        };
        const replacement = try self.allocator.create(facts.ValueEffect);
        replacement.* = value;
        try fields.append(.{ .index = index, .value = replacement });
        aggregate.fields = try fields.toOwnedSlice();
        try self.store_capability_target(function, target, aggregate, flow);
    }

    fn store_capability_target(self: *Infer, function: graph_mod.GlobalFunctionId, target: graph_mod.GlobalNodeId, value: facts.ValueEffect, flow: *CapabilityFlow) anyerror!void {
        switch (self.graph.node(target).content) {
            .binding_use => |binding| try flow.bindings.put(binding, value),
            .struct_field_access => |field| try self.store_capability_field(function, field.value, field.field_index, value, flow),
            .dereference => |read| {
                const targets = try self.capability_address_targets(read.pointer, flow);
                if (targets.len != 0) for (targets) |place| {
                    try self.store_capability_target(function, place, value, flow);
                } else try self.store_capability_target(function, read.pointer, value, flow);
            },
            else => {},
        }
    }

    fn capability_value(self: *Infer, function: graph_mod.GlobalFunctionId, node: graph_mod.GlobalNodeId, flow: *CapabilityFlow) anyerror!facts.ValueEffect {
        const saved = self.bindings;
        self.bindings = flow.bindings;
        defer {
            flow.bindings = self.bindings;
            self.bindings = saved;
        }
        // Scalar opaque reads intentionally drop lifetime envelopes. Capability
        // origins are a separate domain and survive loading an address value.
        const targets = try self.capability_address_targets(node, flow);
        if (targets.len != 0 and self.graph.node(node).content == .binding_use) {
            var current: facts.ValueEffect = .{};
            for (targets) |target| current = try self.mergeValueEffects(current, try self.capability_value(function, target, flow));
            return current;
        }
        return switch (self.graph.node(node).content) {
            .binding_use => |binding| if (flow.bindings.get(binding)) |value| value else self.inferExpression(function, node),
            .dereference => |read| blk: {
                const local = try self.capability_address_targets(read.pointer, flow);
                if (local.len != 0) {
                    var current: facts.ValueEffect = .{};
                    for (local) |target| current = try self.mergeValueEffects(current, try self.capability_value(function, target, flow));
                    break :blk current;
                }
                const value = try self.capability_value(function, read.pointer, flow);
                if (value.fields.len != 0 or value.variants.len != 0) break :blk value;
                break :blk try self.projectValueEffect(value, .dereference);
            },
            .address_of, .move_value, .denied_implicit_copy => |value| self.capability_value(function, value, flow),
            .struct_field_access => |field| self.projectValueEffect(try self.capability_value(function, field.value, flow), .{ .field = field.field_index }),
            .choice_payload_access => |access| blk: {
                const ty = self.graph.node(access.value).ty orelse break :blk .{};
                const index = self.variantIndex(ty, access.variant) orelse break :blk .{};
                break :blk try self.projectValueEffect(try self.capability_value(function, access.value, flow), .{ .variant = index });
            },
            .explicit_cast => |cast| self.capability_value(function, cast.value, flow),
            else => self.inferExpression(function, node),
        };
    }

    fn record_capability_conflict(self: *Infer, flow: *CapabilityFlow, first: CapabilitySource, second: CapabilitySource) !void {
        if (self.capability_source_equal(first, second)) {
            for (flow.counts.items) |*count| if (self.capability_source_equal(count.source, first)) {
                count.maximum = 2;
                return;
            };
        }
        for (flow.conflicts.items) |pair| if ((self.capability_source_equal(pair.first, first) and self.capability_source_equal(pair.second, second)) or
            (self.capability_source_equal(pair.first, second) and self.capability_source_equal(pair.second, first))) return;
        try flow.conflicts.append(.{ .first = first, .second = second });
    }

    fn capability_sources(self: *Infer, effect: facts.ValueEffect) ![]const CapabilitySource {
        var sources = std.array_list.Managed(CapabilitySource).init(self.allocator);
        for (effect.input_dependencies) |dependency| if (!dependency.validity_only) {
            try sources.append(.{ .input = dependency.path });
        };
        for (effect.input_storage_capabilities) |path| try sources.append(.{ .input = path });
        for (effect.input_place_values) |path| try sources.append(.{ .input = path });
        for (effect.fresh_storage_capabilities) |source| try sources.append(.{ .fresh = source });
        var unique = std.array_list.Managed(CapabilitySource).init(self.allocator);
        for (sources.items) |source| {
            var found = false;
            for (unique.items) |previous| if (self.capability_source_equal(source, previous)) {
                found = true;
                break;
            };
            if (!found) try unique.append(source);
        }
        return unique.toOwnedSlice();
    }

    fn apply_capability_flow(self: *Infer, flow: *CapabilityFlow, incoming: *const CapabilityFlow) !void {
        // Preserve alternatives: two paths consumed on disjoint branches must
        // remain a single use even when callers pass aliases for those paths.
        for (incoming.counts.items) |count| for (flow.counts.items) |previous| {
            if (previous.maximum != 0 and count.maximum != 0) try self.record_capability_conflict(flow, previous.source, count.source);
        };
        for (incoming.counts.items) |count| try self.add_capability_count(flow, count.source, count.minimum, count.maximum);
        for (incoming.conflicts.items) |pair| try self.record_capability_conflict(flow, pair.first, pair.second);
    }

    fn consume_capability_effect(self: *Infer, flow: *CapabilityFlow, effect: facts.ValueEffect, minimum: u2, maximum: u2) !void {
        const sources = try self.capability_sources(effect);
        var incoming = CapabilityFlow.init(self.allocator);
        defer incoming.deinit();
        for (sources) |source| try self.add_capability_count(&incoming, source, if (sources.len > 1) 0 else minimum, maximum);
        try self.apply_capability_flow(flow, &incoming);
    }

    fn infer_capability_block(self: *Infer, function: graph_mod.GlobalFunctionId, block: graph_mod.GlobalBlockId, flow: *CapabilityFlow, exits: *?CapabilityFlow) anyerror!void {
        const record = self.graph.blocks.items[@intFromEnum(block)];
        for (self.graph.node_refs.items[record.nodes.start..][0..record.nodes.len]) |node| {
            if (!flow.reachable) break;
            try self.infer_capability_node(function, node, flow, exits);
        }
        if (flow.reachable) if (record.ret_val) |value| try self.infer_capability_node(function, value, flow, exits);
    }

    fn record_capability_exit(self: *Infer, flow: *const CapabilityFlow, exits: *?CapabilityFlow) !void {
        if (exits.*) |*previous| try self.join_capability_flows(previous, previous, flow) else exits.* = try flow.clone(self.allocator);
    }

    fn infer_capability_call(self: *Infer, function: graph_mod.GlobalFunctionId, callee: graph_mod.GlobalFunctionId, arguments: []const graph_mod.ValueField, flow: *CapabilityFlow) !void {
        const primitive = self.graph.function(callee).safety_primitive;
        if (primitive_transfer.forPrimitive(primitive).consumes_storage_input) |index| {
            if (index < arguments.len) try self.consume_capability_effect(flow, try self.capability_value(function, arguments[index].value, flow), 1, 1);
            return;
        }
        const summary = self.engine.summaryFor(callee) orelse return;
        try self.substitute_capability_uses(function, summary, arguments, flow);
    }

    fn mapped_capability_value(self: *Infer, function: graph_mod.GlobalFunctionId, target: facts.InputPath, arguments: []const graph_mod.ValueField, flow: *CapabilityFlow) !facts.ValueEffect {
        if (target.input_index >= arguments.len) return .{};
        var value = try self.capability_value(function, arguments[target.input_index].value, flow);
        for (target.projections) |projection| value = try self.projectValueEffect(value, projection);
        return value;
    }

    fn substitute_capability_uses(self: *Infer, function: graph_mod.GlobalFunctionId, summary: facts.SafetySummary, arguments: []const graph_mod.ValueField, flow: *CapabilityFlow) !void {
        var incoming = CapabilityFlow.init(self.allocator);
        defer incoming.deinit();
        for (summary.storage_capability_uses) |use| {
            const sources = try self.capability_sources(try self.mapped_capability_value(function, use.target, arguments, flow));
            for (sources) |source| {
                var found = false;
                for (incoming.counts.items) |*count| if (self.capability_source_equal(count.source, source)) {
                    count.minimum = @max(count.minimum, if (sources.len > 1) @as(u2, 0) else use.minimum);
                    count.maximum = @max(count.maximum, use.maximum);
                    found = true;
                    break;
                };
                if (!found) try self.add_capability_count(&incoming, source, if (sources.len > 1) 0 else use.minimum, use.maximum);
            }
        }
        for (summary.storage_capability_conflicts) |pair| {
            const first = try self.capability_sources(try self.mapped_capability_value(function, pair.first, arguments, flow));
            const second = try self.capability_sources(try self.mapped_capability_value(function, pair.second, arguments, flow));
            for (first) |left| for (second) |right| {
                try self.record_capability_conflict(&incoming, left, right);
            };
        }
        try self.apply_capability_flow(flow, &incoming);
    }

    fn infer_capability_node(self: *Infer, function: graph_mod.GlobalFunctionId, node: graph_mod.GlobalNodeId, flow: *CapabilityFlow, exits: *?CapabilityFlow) anyerror!void {
        const content = self.graph.node(node).content;
        if (content == .function_call or content == .virtual_call or content == .type_initializer) {
            // Block result expressions can reference an already evaluated call
            // node. Codegen caches that value; do not consume it a second time.
            if (flow.calls.contains(node)) return;
            try flow.calls.put(node, {});
        }
        switch (self.graph.node(node).content) {
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (!record.deferred_initialization) if (record.initialization) |value| {
                    try self.infer_capability_node(function, value, flow, exits);
                    try flow.bindings.put(binding, try self.capability_value(function, value, flow));
                    try flow.addresses.put(binding, try self.capability_address_targets(value, flow));
                };
            },
            .assignment => |assignment| {
                try self.infer_capability_node(function, assignment.value, flow, exits);
                try flow.bindings.put(assignment.binding, try self.capability_value(function, assignment.value, flow));
                try flow.addresses.put(assignment.binding, try self.capability_address_targets(assignment.value, flow));
            },
            .function_call => |call| {
                try self.infer_capability_node(function, call.input, flow, exits);
                if (self.structArguments(call.input)) |arguments| try self.infer_capability_call(function, call.callee, arguments, flow);
            },
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.infer_capability_node(function, call.input, flow, exits);
                const summary = try self.virtualSummary(call.safety_methods) orelse return;
                if (self.structArguments(call.input)) |arguments| try self.substitute_capability_uses(function, summary, arguments, flow);
            },
            .type_initializer => |initializer| {
                try self.infer_capability_node(function, initializer.args, flow, exits);
                try self.infer_capability_call(function, initializer.init_fn, try self.initializerArguments(initializer.args), flow);
            },
            .if_statement => |branch| {
                try self.infer_capability_node(function, branch.condition, flow, exits);
                var left = try flow.clone(self.allocator);
                defer left.deinit();
                var right = try flow.clone(self.allocator);
                defer right.deinit();
                try self.infer_capability_block(function, branch.then_block, &left, exits);
                if (branch.else_block) |block| try self.infer_capability_block(function, block, &right, exits);
                try self.join_capability_fallthrough(flow, &left, &right);
            },
            .while_statement => |loop| {
                var before_loop = try flow.clone(self.allocator);
                defer before_loop.deinit();
                try self.infer_capability_node(function, loop.condition, flow, exits);
                var body = try flow.clone(self.allocator);
                defer body.deinit();
                try self.infer_capability_block(function, loop.body, &body, exits);
                if (!body.breaks_loop) for (body.counts.items) |*count| {
                    var before: u2 = 0;
                    for (before_loop.counts.items) |prior| if (self.capability_source_equal(count.source, prior.source)) {
                        before = prior.maximum;
                        break;
                    };
                    if (count.maximum > before) count.maximum = 2;
                };
                try self.join_capability_flows(flow, flow, &body);
            },
            .for_statement => |loop| {
                if (loop.init) |value| try self.infer_capability_node(function, value, flow, exits);
                var before_loop = try flow.clone(self.allocator);
                defer before_loop.deinit();
                try self.infer_capability_node(function, loop.condition, flow, exits);
                var body = try flow.clone(self.allocator);
                defer body.deinit();
                try self.infer_capability_block(function, loop.body, &body, exits);
                if (body.reachable) if (loop.increment) |value| try self.infer_capability_node(function, value, &body, exits);
                if (!body.breaks_loop) for (body.counts.items) |*count| {
                    var before: u2 = 0;
                    for (before_loop.counts.items) |prior| if (self.capability_source_equal(count.source, prior.source)) {
                        before = prior.maximum;
                        break;
                    };
                    if (count.maximum > before) count.maximum = 2;
                };
                try self.join_capability_flows(flow, flow, &body);
            },
            .choice_literal => |literal| {
                if (literal.payload) |value| try self.infer_capability_node(function, value, flow, exits);
            },
            .switch_statement => |id| {
                const statement = self.graph.switches.items[@intFromEnum(id)];
                try self.infer_capability_node(function, statement.expression, flow, exits);
                const choice = try self.capability_value(function, statement.expression, flow);
                var joined: ?CapabilityFlow = null;
                defer if (joined) |*value| value.deinit();
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    if (case.payload_binding) |binding| {
                        if (self.graph.node(statement.expression).ty) |ty| if (self.variantIndex(ty, case.variant)) |index| {
                            try branch.bindings.put(binding, try self.projectValueEffect(choice, .{ .variant = index }));
                        };
                    }
                    try self.infer_capability_block(function, case.body, &branch, exits);
                    if (joined) |*value| try self.join_capability_fallthrough(value, value, &branch) else joined = try branch.clone(self.allocator);
                }
                if (statement.default_block) |block| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.infer_capability_block(function, block, &branch, exits);
                    if (joined) |*value| try self.join_capability_fallthrough(value, value, &branch) else joined = try branch.clone(self.allocator);
                } else if (!statement.exhaustive) {
                    if (joined) |*value| try self.join_capability_fallthrough(value, value, flow) else joined = try flow.clone(self.allocator);
                }
                if (joined) |*value| {
                    const copied = try value.clone(self.allocator);
                    flow.deinit();
                    flow.* = copied;
                }
            },
            .logical_operation => |op| {
                try self.infer_capability_node(function, op.left, flow, exits);
                var right = try flow.clone(self.allocator);
                defer right.deinit();
                try self.infer_capability_node(function, op.right, &right, exits);
                try self.join_capability_flows(flow, flow, &right);
            },
            .nullable_unwrap_or => |id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                try self.infer_capability_node(function, unwrap.nullable_value, flow, exits);
                var fallback = try flow.clone(self.allocator);
                defer fallback.deinit();
                try self.infer_capability_node(function, unwrap.fallback_value, &fallback, exits);
                try self.join_capability_flows(flow, flow, &fallback);
            },
            .pointer_assignment => |assignment| {
                try self.infer_capability_node(function, assignment.pointer, flow, exits);
                try self.infer_capability_node(function, assignment.value, flow, exits);
                const value = try self.capability_value(function, assignment.value, flow);
                const targets = try self.capability_address_targets(assignment.pointer, flow);
                if (targets.len != 0) for (targets) |target| {
                    try self.store_capability_target(function, target, value, flow);
                } else try self.store_capability_target(function, assignment.pointer, value, flow);
            },
            .struct_field_store => |store| {
                try self.infer_capability_node(function, store.struct_ptr, flow, exits);
                try self.infer_capability_node(function, store.value, flow, exits);
                const value = try self.capability_value(function, store.value, flow);
                const targets = try self.capability_address_targets(store.struct_ptr, flow);
                if (targets.len != 0) for (targets) |target| {
                    try self.store_capability_field(function, target, store.field_index, value, flow);
                } else try self.store_capability_field(function, store.struct_ptr, store.field_index, value, flow);
            },
            .array_store => |store| {
                try self.infer_capability_node(function, store.array_ptr, flow, exits);
                try self.infer_capability_node(function, store.index, flow, exits);
                try self.infer_capability_node(function, store.value, flow, exits);
            },
            .array_index => |index| {
                try self.infer_capability_node(function, index.array_ptr, flow, exits);
                try self.infer_capability_node(function, index.index, flow, exits);
            },
            .error_propagation => |id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(id)];
                try self.infer_capability_node(function, propagation.errable_value, flow, exits);
                var failed = try flow.clone(self.allocator);
                defer failed.deinit();
                for (self.graph.node_refs.items[propagation.cleanup_nodes.start..][0..propagation.cleanup_nodes.len]) |value| try self.infer_capability_node(function, value, &failed, exits);
                try self.record_capability_exit(&failed, exits);
            },
            .error_context => |id| {
                const context = self.graph.error_contexts.items[@intFromEnum(id)];
                try self.infer_capability_node(function, context.errable_value, flow, exits);
                try self.infer_capability_node(function, context.context, flow, exits);
                for (self.graph.node_refs.items[context.cleanup_nodes.start..][0..context.cleanup_nodes.len]) |value| try self.infer_capability_node(function, value, flow, exits);
            },
            .auto_deinit_binding => |id| {
                const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
                if (cleanup.input) |input| {
                    try self.infer_capability_node(function, input, flow, exits);
                    if (cleanup.deinit_fn) |callee| if (self.structArguments(input)) |arguments| try self.infer_capability_call(function, callee, arguments, flow);
                }
            },
            .return_statement => |ret| {
                if (ret.expression) |value| try self.infer_capability_node(function, value, flow, exits);
                for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |value| try self.infer_capability_node(function, value, flow, exits);
                try self.record_capability_exit(flow, exits);
                flow.reachable = false;
                flow.breaks_loop = true;
            },
            .break_statement => {
                flow.reachable = false;
                flow.breaks_loop = true;
            },
            .continue_statement => flow.reachable = false,
            .abort_statement => {
                try self.record_capability_exit(flow, exits);
                flow.reachable = false;
                flow.breaks_loop = true;
            },
            .code_block => |block| try self.infer_capability_block(function, block, flow, exits),
            .move_value, .denied_implicit_copy, .address_of => |value| try self.infer_capability_node(function, value, flow, exits),
            .dereference => |read| try self.infer_capability_node(function, read.pointer, flow, exits),
            .struct_field_access => |field| try self.infer_capability_node(function, field.value, flow, exits),
            .choice_payload_access => |payload| try self.infer_capability_node(function, payload.value, flow, exits),
            .explicit_cast => |cast| try self.infer_capability_node(function, cast.value, flow, exits),
            .struct_value_literal => |literal| for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
                try self.infer_capability_node(function, field.value, flow, exits);
            },
            .array_literal => |literal| for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value| {
                try self.infer_capability_node(function, value, flow, exits);
            },
            .list_literal => |literal| for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |value| {
                try self.infer_capability_node(function, value, flow, exits);
            },
            .binary_operation => |op| {
                try self.infer_capability_node(function, op.left, flow, exits);
                try self.infer_capability_node(function, op.right, flow, exits);
            },
            .comparison => |op| {
                try self.infer_capability_node(function, op.left, flow, exits);
                try self.infer_capability_node(function, op.right, flow, exits);
            },
            else => {},
        }
    }

    fn mark_unavailable_fresh_storage(self: *Infer, effect: facts.ValueEffect, counts: []const CapabilityCount) anyerror!facts.ValueEffect {
        var result = effect;
        var unavailable = std.array_list.Managed(facts.FreshStorageCapabilityState).init(self.allocator);
        try unavailable.appendSlice(effect.unavailable_fresh_storage);
        for (effect.fresh_storage_capabilities) |source| for (counts) |count| {
            if (count.source != .fresh or count.source.fresh != source or count.maximum == 0) continue;
            var found = false;
            for (unavailable.items) |*entry| if (entry.source == source) {
                entry.maybe_consumed = entry.maybe_consumed or count.minimum == 0;
                found = true;
                break;
            };
            if (!found) try unavailable.append(.{ .source = source, .maybe_consumed = count.minimum == 0 });
        };
        result.unavailable_fresh_storage = try unavailable.toOwnedSlice();
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.mark_unavailable_fresh_storage(field.value.*, counts);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.mark_unavailable_fresh_storage(variant.value.*, counts);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    const SymbolicInputOverride = struct {
        input_index: u32,
        effect: facts.ValueEffect,
    };

    const InputPostStateFlow = struct {
        states: std.array_list.Managed(facts.PlacePostState),
        reachable: bool = true,
        outcome_variant: ?u32 = null,

        fn init(allocator: std.mem.Allocator) InputPostStateFlow {
            return .{ .states = std.array_list.Managed(facts.PlacePostState).init(allocator) };
        }

        fn deinit(self: *InputPostStateFlow) void {
            self.states.deinit();
        }

        fn clone(self: *const InputPostStateFlow, allocator: std.mem.Allocator) !InputPostStateFlow {
            var states = std.array_list.Managed(facts.PlacePostState).init(allocator);
            try states.appendSlice(self.states.items);
            return .{ .states = states, .reachable = self.reachable, .outcome_variant = self.outcome_variant };
        }
    };

    const OutcomeFlowSet = struct {
        flows: std.array_list.Managed(InputPostStateFlow),

        fn init(allocator: std.mem.Allocator) OutcomeFlowSet {
            return .{ .flows = std.array_list.Managed(InputPostStateFlow).init(allocator) };
        }

        fn deinit(self: *OutcomeFlowSet) void {
            for (self.flows.items) |*flow| flow.deinit();
            self.flows.deinit();
        }
    };

    fn isFallibleInitializer(self: *Infer, function_id: graph_mod.GlobalFunctionId) bool {
        const function = self.graph.function(function_id);
        if (function.input.len == 0 or function.output.len != 1) return false;
        if (!std.mem.eql(u8, self.graph.text(self.graph.declaration(function.declaration).name), "init")) return false;
        const destination = self.graph.semanticType(self.graph.fields.items[function.input.start].ty);
        if (destination != .pointer or destination.pointer.mutability != .read_write) return false;
        return initializer_contract.classify(self.graph, function_id) == .fallible;
    }

    fn inferInitializerOutcomePostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        body: graph_mod.GlobalBlockId,
    ) ![]const facts.OutcomePostStates {
        const function = self.graph.function(function_id);
        const result_ty = self.graph.fields.items[function.output.start].ty;
        const ok = types.findVariant(self.graph, result_ty, "ok") orelse return error.InvalidInitializerResult;
        const failure = types.findVariant(self.graph, result_ty, "error") orelse return error.InvalidInitializerResult;
        const output_binding = self.graph.binding_refs.items[function.output_bindings.start];
        var initial = InputPostStateFlow.init(self.allocator);
        defer initial.deinit();
        try initial.states.append(.{ .target = .{ .input_index = 0 }, .initializedness = .deinitialized });
        var exits = [_]?std.array_list.Managed(facts.PlacePostState){ null, null };
        defer for (&exits) |*entry| if (entry.*) |*states| states.deinit();
        var remaining = try self.inferOutcomeBlock(function_id, body, output_binding, initial, .{ ok.index, failure.index }, &exits);
        defer remaining.deinit();
        for (remaining.flows.items) |*flow|
            try self.recordOutcomeExit(flow, .{ ok.index, failure.index }, &exits);
        var results = std.array_list.Managed(facts.OutcomePostStates).init(self.allocator);
        for (exits, 0..) |entry, index| if (entry) |states| {
            try results.append(.{
                .variant_index = if (index == 0) ok.index else failure.index,
                .input_post_states = try self.allocator.dupe(facts.PlacePostState, states.items),
            });
        };
        return results.toOwnedSlice();
    }

    fn recordOutcomeExit(
        self: *Infer,
        flow: *const InputPostStateFlow,
        variants: [2]u32,
        exits: *[2]?std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (!flow.reachable) return;
        for (variants, 0..) |variant, index| {
            if (flow.outcome_variant != null and flow.outcome_variant.? != variant) continue;
            try self.recordInputPostStateExit(&exits[index], &flow.states);
        }
    }

    fn appendOutcomeFlow(self: *Infer, set: *OutcomeFlowSet, source: *const InputPostStateFlow) !void {
        if (!source.reachable) return;
        for (set.flows.items) |*existing| if (existing.outcome_variant == source.outcome_variant) {
            var merged = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
            defer merged.deinit();
            try self.joinInputPostStates(&merged, &existing.states, &source.states);
            existing.states.clearRetainingCapacity();
            try existing.states.appendSlice(merged.items);
            return;
        };
        try set.flows.append(try source.clone(self.allocator));
    }

    fn inferOutcomeBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        output_binding: graph_mod.GlobalBindingId,
        initial: InputPostStateFlow,
        variants: [2]u32,
        exits: *[2]?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!OutcomeFlowSet {
        var active = OutcomeFlowSet.init(self.allocator);
        try self.appendOutcomeFlow(&active, &initial);
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            var next = OutcomeFlowSet.init(self.allocator);
            errdefer next.deinit();
            const node = self.graph.node(node_id);
            for (active.flows.items) |*flow| {
                var branch = try flow.clone(self.allocator);
                defer branch.deinit();
                var early_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
                defer if (early_exits) |*states| states.deinit();
                switch (node.content) {
                    .if_statement => |statement| {
                        try self.inferInputPostStatesExpression(function_id, statement.condition, &branch.states, &early_exits);
                        var then_flows = try self.inferOutcomeBlock(function_id, statement.then_block, output_binding, branch, variants, exits);
                        defer then_flows.deinit();
                        for (then_flows.flows.items) |*child| try self.appendOutcomeFlow(&next, child);
                        if (statement.else_block) |else_block| {
                            var else_flows = try self.inferOutcomeBlock(function_id, else_block, output_binding, branch, variants, exits);
                            defer else_flows.deinit();
                            for (else_flows.flows.items) |*child| try self.appendOutcomeFlow(&next, child);
                        } else try self.appendOutcomeFlow(&next, &branch);
                    },
                    .switch_statement => |switch_id| {
                        const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                        try self.inferInputPostStatesExpression(function_id, statement.expression, &branch.states, &early_exits);
                        for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                            var child_flows = try self.inferOutcomeBlock(function_id, case.body, output_binding, branch, variants, exits);
                            defer child_flows.deinit();
                            for (child_flows.flows.items) |*child| try self.appendOutcomeFlow(&next, child);
                        }
                        if (statement.default_block) |default_block| {
                            var child_flows = try self.inferOutcomeBlock(function_id, default_block, output_binding, branch, variants, exits);
                            defer child_flows.deinit();
                            for (child_flows.flows.items) |*child| try self.appendOutcomeFlow(&next, child);
                        } else if (!statement.exhaustive) try self.appendOutcomeFlow(&next, &branch);
                    },
                    .code_block => |child| {
                        var children = try self.inferOutcomeBlock(function_id, child, output_binding, branch, variants, exits);
                        defer children.deinit();
                        for (children.flows.items) |*child_flow| try self.appendOutcomeFlow(&next, child_flow);
                    },
                    .return_statement => |statement| {
                        if (statement.expression) |expression| {
                            try self.inferInputPostStatesExpression(function_id, expression, &branch.states, &early_exits);
                            branch.outcome_variant = (try self.inferExpression(function_id, expression)).known_choice_variant;
                        }
                        try self.inferInputPostStatesRange(function_id, statement.cleanup, &branch, &early_exits);
                        try self.recordOutcomeExit(&branch, variants, exits);
                    },
                    else => {
                        try self.inferInputPostStatesNode(function_id, node_id, &branch, &early_exits);
                        // The ordinary loop transfer joins iterations without
                        // retaining which result variant each iteration chose.
                        // Both outcomes must therefore satisfy the contract.
                        if (node.content == .while_statement or node.content == .for_statement)
                            branch.outcome_variant = null;
                        if (node.content == .assignment and node.content.assignment.binding == output_binding)
                            branch.outcome_variant = (try self.inferExpression(function_id, node.content.assignment.value)).known_choice_variant;
                        try self.appendOutcomeFlow(&next, &branch);
                    },
                }
                if (early_exits) |states| {
                    var early = InputPostStateFlow.init(self.allocator);
                    defer early.deinit();
                    try early.states.appendSlice(states.items);
                    early.outcome_variant = variants[1];
                    try self.recordOutcomeExit(&early, variants, exits);
                }
            }
            active.deinit();
            active = next;
        }
        if (block.ret_val) |value| for (active.flows.items) |*flow| {
            var early_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
            defer if (early_exits) |*states| states.deinit();
            try self.inferInputPostStatesExpression(function_id, value, &flow.states, &early_exits);
            if (early_exits) |states| {
                var early = InputPostStateFlow.init(self.allocator);
                defer early.deinit();
                try early.states.appendSlice(states.items);
                early.outcome_variant = variants[1];
                try self.recordOutcomeExit(&early, variants, exits);
            }
        };
        return active;
    }

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

    fn inferInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!flow.reachable) break;
            try self.inferInputPostStatesNode(function_id, node_id, flow, exits);
        }
        if (flow.reachable) if (block.ret_val) |value|
            try self.inferInputPostStatesExpression(function_id, value, &flow.states, exits);
    }

    fn inferInputPostStatesNode(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        const states = &flow.states;
        switch (node.content) {
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (!record.deferred_initialization) if (record.initialization) |initialization|
                    try self.inferInputPostStatesExpression(function_id, initialization, states, exits);
            },
            .assignment => |assignment| try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits),
            .function_call, .virtual_call => try self.inferInputPostStatesExpression(function_id, node_id, states, exits),
            .pointer_assignment => |assignment| {
                try self.inferInputPostStatesExpression(function_id, assignment.pointer, states, exits);
                try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits);
                try self.recordInputPostState(
                    states,
                    try self.inferInputPaths(function_id, assignment.pointer),
                    .initialized,
                    try self.inferExpression(function_id, assignment.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .struct_field_store => |store| {
                try self.inferInputPostStatesExpression(function_id, store.struct_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.value, states, exits);
                const targets = try self.projectInputPaths(
                    try self.inferInputPaths(function_id, store.struct_ptr),
                    .{ .field = store.field_index },
                );
                try self.recordInputPostState(
                    states,
                    targets,
                    .initialized,
                    try self.inferExpression(function_id, store.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .array_store => |store| {
                try self.inferInputPostStatesExpression(function_id, store.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.index, states, exits);
                try self.inferInputPostStatesExpression(function_id, store.value, states, exits);
                const projection: facts.Projection = if (self.staticIndex(store.index)) |index|
                    .{ .static_index = index }
                else
                    .dynamic_index;
                const targets = try self.projectInputPaths(
                    try self.inferInputPaths(function_id, store.array_ptr),
                    projection,
                );
                try self.recordInputPostState(
                    states,
                    targets,
                    .initialized,
                    try self.inferExpression(function_id, store.value),
                    false,
                    false,
                    false,
                    true,
                );
            },
            .if_statement => |statement| {
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var then_flow = try flow.clone(self.allocator);
                defer then_flow.deinit();
                try self.inferInputPostStates(function_id, statement.then_block, &then_flow, exits);
                var else_flow = try flow.clone(self.allocator);
                defer else_flow.deinit();
                if (statement.else_block) |child|
                    try self.inferInputPostStates(function_id, child, &else_flow, exits);
                try self.joinInputPostStateFallthrough(flow, &then_flow, &else_flow);
            },
            .while_statement => |statement| {
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization|
                    try self.inferInputPostStatesNode(function_id, initialization, flow, exits);
                if (!flow.reachable) return;
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                if (body_flow.reachable) if (statement.increment) |increment|
                    try self.inferInputPostStatesNode(function_id, increment, &body_flow, exits);
                try self.joinInputPostStates(states, states, &body_flow.states);
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.inferInputPostStatesExpression(function_id, statement.expression, states, exits);
                var joined: ?InputPostStateFlow = null;
                defer if (joined) |*joined_flow| joined_flow.deinit();

                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferInputPostStates(function_id, case.body, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                }
                if (statement.default_block) |child| {
                    var branch = try flow.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferInputPostStates(function_id, child, &branch, exits);
                    try self.joinInputPostStateFlowBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinInputPostStateFlowBranch(&joined, flow);
                }
                if (joined) |*joined_flow|
                    try self.copyInputPostStateFlow(flow, joined_flow)
                else
                    flow.reachable = false;
            },
            .return_statement => |statement| {
                if (statement.expression) |expression|
                    try self.inferInputPostStatesExpression(function_id, expression, states, exits);
                try self.inferInputPostStatesRange(function_id, statement.cleanup, flow, exits);
                if (flow.reachable) try self.recordInputPostStateExit(exits, states);
                flow.reachable = false;
            },
            .code_block => |child| try self.inferInputPostStates(function_id, child, flow, exits),
            .break_statement, .continue_statement, .abort_statement => flow.reachable = false,
            .auto_deinit_binding => |auto_id| try self.applyAutoDeinitInputPostStates(function_id, auto_id, states),
            else => try self.inferInputPostStatesExpression(function_id, node_id, states, exits),
        }
    }

    fn inferInputPostStatesRange(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        range: graph_mod.NodeRange,
        flow: *InputPostStateFlow,
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |node| {
            if (!flow.reachable) break;
            try self.inferInputPostStatesNode(function_id, node, flow, exits);
        }
    }

    fn inferInputPostStatesExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        switch (node.content) {
            .move_value, .denied_implicit_copy, .address_of => |value| try self.inferInputPostStatesExpression(function_id, value, states, exits),
            .dereference => |value| try self.inferInputPostStatesExpression(function_id, value.pointer, states, exits),
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.inferInputPostStatesExpression(function_id, field.value, states, exits);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferInputPostStatesExpression(function_id, element, states, exits);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferInputPostStatesExpression(function_id, element, states, exits);
            },
            .choice_literal => |literal| {
                if (literal.payload) |payload|
                    try self.inferInputPostStatesExpression(function_id, payload, states, exits);
            },
            .struct_field_access => |access| try self.inferInputPostStatesExpression(function_id, access.value, states, exits),
            .choice_payload_access => |access| try self.inferInputPostStatesExpression(function_id, access.value, states, exits),
            .array_index => |index| {
                try self.inferInputPostStatesExpression(function_id, index.array_ptr, states, exits);
                try self.inferInputPostStatesExpression(function_id, index.index, states, exits);
            },
            .explicit_cast => |cast| try self.inferInputPostStatesExpression(function_id, cast.value, states, exits),
            .binary_operation => |operation| {
                try self.inferInputPostStatesExpression(function_id, operation.left, states, exits);
                try self.inferInputPostStatesExpression(function_id, operation.right, states, exits);
            },
            .comparison => |comparison| {
                try self.inferInputPostStatesExpression(function_id, comparison.left, states, exits);
                try self.inferInputPostStatesExpression(function_id, comparison.right, states, exits);
            },
            .logical_operation => |operation| {
                try self.inferInputPostStatesExpression(function_id, operation.left, states, exits);
                try self.inferConditionalInputPostStatesExpression(function_id, operation.right, states, exits);
            },
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.inferInputPostStatesExpression(function_id, unwrap.nullable_value, states, exits);
                try self.inferConditionalInputPostStatesExpression(function_id, unwrap.fallback_value, states, exits);
            },
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.inferInputPostStatesExpression(function_id, expect.expected_reason, states, exits);
                try self.inferInputPostStatesExpression(function_id, expect.actual_result, states, exits);
                if (expect.test_fail_input) |input| try self.inferConditionalInputPostStatesExpression(function_id, input, states, exits);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.inferInputPostStatesExpression(function_id, propagation.errable_value, states, exits);
                var error_flow = InputPostStateFlow.init(self.allocator);
                defer error_flow.deinit();
                try error_flow.states.appendSlice(states.items);
                for (self.graph.node_refs.items[propagation.cleanup_nodes.start..][0..propagation.cleanup_nodes.len]) |cleanup| {
                    if (!error_flow.reachable) break;
                    try self.inferInputPostStatesNode(function_id, cleanup, &error_flow, exits);
                }
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferInputPostStatesExpression(function_id, context.errable_value, states, exits);
                var error_flow = InputPostStateFlow.init(self.allocator);
                defer error_flow.deinit();
                try error_flow.states.appendSlice(states.items);
                try self.inferInputPostStatesExpression(function_id, context.context, &error_flow.states, exits);
                for (self.graph.node_refs.items[context.cleanup_nodes.start..][0..context.cleanup_nodes.len]) |cleanup| {
                    if (!error_flow.reachable) break;
                    try self.inferInputPostStatesNode(function_id, cleanup, &error_flow, exits);
                }
                if (error_flow.reachable) try self.recordInputPostStateExit(exits, &error_flow.states);
            },
            .function_call => |call| {
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
                try self.applyInputPostStatesFromFunctionCall(function_id, call.callee, call.input, states);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferInputPostStatesExpression(function_id, call.handle, states, exits);
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.applyInputPostStatesFromSummary(function_id, summary, call.input, states, null);
            },
            .virtualize => |virtualize_id| try self.inferInputPostStatesExpression(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                states,
                exits,
            ),
            .type_initializer => |initializer| {
                try self.inferInputPostStatesExpression(function_id, initializer.args, states, exits);
                const summary = self.engine.summaryFor(initializer.init_fn) orelse return;
                try self.applyInputPostStatesFromArguments(function_id, summary, try self.initializerArguments(initializer.args), states, .{ .input_index = 0, .effect = .{} });
            },
            else => {},
        }
    }

    fn inferConditionalInputPostStatesExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        exits: *?std.array_list.Managed(facts.PlacePostState),
    ) !void {
        var executed = try self.cloneInputPostStates(states);
        defer executed.deinit();
        try self.inferInputPostStatesExpression(function_id, node_id, &executed, exits);
        var skipped = try self.cloneInputPostStates(states);
        defer skipped.deinit();
        try self.joinInputPostStates(states, &executed, &skipped);
    }

    fn applyInputPostStatesFromFunctionCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        const callee_function = self.graph.function(callee);
        const input_transfer = primitive_transfer.forPrimitive(callee_function.safety_primitive).input;
        switch (input_transfer) {
            .consume_opaque_owner => {
                if (primitive_transfer.opaqueMoveOperands(arguments.len)) |operands| {
                    const targets = try self.inferInputPaths(function_id, arguments[operands.owner].value);
                    const storage = if (operands.storage) |storage_index| blk: {
                        const storage_targets = try self.inferInputPaths(function_id, arguments[storage_index].value);
                        break :blk if (storage_targets.len == 1) storage_targets[0] else null;
                    } else null;
                    try self.recordOpaqueOwnershipConsumption(states, targets, .definite, storage);
                }
                return;
            },
            .ignore => return,
            .none, .relocate => {},
        }
        if (input_transfer == .relocate) {
            if (arguments.len != 2) return;
            const source_targets = try self.inferInputPaths(function_id, arguments[0].value);
            const destination_targets = try self.inferInputPaths(function_id, arguments[1].value);
            for (source_targets) |source| {
                try self.recordInputPostState(states, &.{source}, .moved, .{}, false, false, false, false);
                const transferred = try self.inputPlaceValueEffect(source);
                for (destination_targets) |destination|
                    try self.recordInputPostState(
                        states,
                        &.{destination},
                        .initialized,
                        transferred,
                        false,
                        true,
                        true,
                        false,
                    );
            }
            return;
        }
        const summary = self.engine.summaryFor(callee) orelse return;
        try self.applyInputPostStatesFromSummary(function_id, summary, input, states, null);
    }

    fn applyInputPostStatesFromSummary(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        input: graph_mod.GlobalNodeId,
        states: *std.array_list.Managed(facts.PlacePostState),
        override: ?SymbolicInputOverride,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        try self.applyInputPostStatesFromArguments(function_id, summary, arguments, states, override);
    }

    fn applyInputPostStatesFromArguments(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        arguments: []const graph_mod.ValueField,
        states: *std.array_list.Managed(facts.PlacePostState),
        override: ?SymbolicInputOverride,
    ) !void {
        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            const targets = try self.substituteRequiredInputPath(
                function_id,
                post_state.target,
                arguments,
                override,
            );
            if (post_state.opaque_ownership != .none) {
                const storage = if (post_state.opaque_storage) |opaque_storage| blk: {
                    if (opaque_storage.input_index >= arguments.len) break :blk null;
                    const mapped = try self.substituteRequiredInputPath(
                        function_id,
                        opaque_storage,
                        arguments,
                        override,
                    );
                    break :blk if (mapped.len == 1) mapped[0] else null;
                } else null;
                try self.recordOpaqueOwnershipConsumption(
                    states,
                    targets,
                    post_state.opaque_ownership,
                    storage,
                );
                continue;
            }
            const value = try self.substituteOutputWithOverride(
                function_id,
                post_state.value,
                arguments,
                override,
            );
            try self.recordInputPostState(
                states,
                targets,
                post_state.initializedness,
                value,
                post_state.ends_previous_roots,
                post_state.refreshes_storage_generation,
                post_state.requires_available_destination,
                post_state.may_repopulate_opaque_storage,
            );
        }
    }

    fn applyAutoDeinitInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        auto_id: graph_mod.GlobalAutoDeinitId,
        states: *std.array_list.Managed(facts.PlacePostState),
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.deinit_fn) |deinit_fn| if (cleanup.input) |input| {
            if (self.engine.summaryFor(deinit_fn)) |summary|
                try self.applyInputPostStatesFromSummary(
                    function_id,
                    summary,
                    input,
                    states,
                    if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null,
                );
        };
        if (binding_effect) |effect|
            try self.applyAutoDeinitFieldInputPostStates(function_id, cleanup.fields, states, effect);
    }

    fn applyAutoDeinitFieldInputPostStates(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        field_range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        states: *std.array_list.Managed(facts.PlacePostState),
        parent_effect: facts.ValueEffect,
    ) !void {
        for (self.graph.auto_deinit_fields.items[field_range.start..][0..field_range.len]) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.deinit_fn) |deinit_fn| if (field.input) |input| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.applyInputPostStatesFromSummary(
                        function_id,
                        summary,
                        input,
                        states,
                        .{ .input_index = field.self_field_index, .effect = field_effect },
                    );
            };
            try self.applyAutoDeinitFieldInputPostStates(function_id, field.fields, states, field_effect);
        }
    }

    fn recordInputPostState(
        self: *Infer,
        states: *std.array_list.Managed(facts.PlacePostState),
        targets: []const facts.InputPath,
        initializedness: value_state.Initializedness,
        value: facts.ValueEffect,
        ends_roots: bool,
        refreshes_storage_generation: bool,
        requires_available_destination: bool,
        may_repopulate_opaque_storage: bool,
    ) !void {
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (self.inputPathEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                const was_deinitialized = existing.initializedness != .initialized;
                existing.initializedness = initializedness;
                existing.value = value;
                existing.ends_previous_roots = existing.ends_previous_roots or ends_roots;
                existing.refreshes_storage_generation =
                    existing.refreshes_storage_generation or
                    refreshes_storage_generation or
                    (was_deinitialized and initializedness == .initialized);
                existing.requires_available_destination =
                    existing.requires_available_destination or requires_available_destination;
                existing.may_repopulate_opaque_storage =
                    existing.may_repopulate_opaque_storage or may_repopulate_opaque_storage;
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

    fn recordOpaqueOwnershipConsumption(
        self: *Infer,
        states: *std.array_list.Managed(facts.PlacePostState),
        targets: []const facts.InputPath,
        consumption: facts.OpaqueOwnershipConsumption,
        storage: ?facts.InputPath,
    ) !void {
        for (targets) |target| {
            var existing_state: ?*facts.PlacePostState = null;
            for (states.items) |*existing| if (self.inputPathEqual(existing.target, target)) {
                existing_state = existing;
                break;
            };
            if (existing_state) |existing| {
                existing.opaque_ownership = consumption;
                existing.opaque_storage = storage;
            } else try states.append(.{
                .target = target,
                .initializedness = .initialized,
                .opaque_ownership = consumption,
                .opaque_storage = storage,
            });
        }
    }

    fn joinInputPostStates(
        self: *Infer,
        destination: *std.array_list.Managed(facts.PlacePostState),
        left: *const std.array_list.Managed(facts.PlacePostState),
        right: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        var joined = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer joined.deinit();

        for (left.items) |left_state| {
            var merged = left_state;
            if (self.findInputPostState(right.items, left_state.target)) |right_state| {
                merged.initializedness = joinInitializedness(left_state.initializedness, right_state.initializedness);
                merged.value = try self.mergeValueEffects(left_state.value, right_state.value);
                merged.ends_previous_roots = left_state.ends_previous_roots or right_state.ends_previous_roots;
                merged.refreshes_storage_generation =
                    left_state.refreshes_storage_generation or right_state.refreshes_storage_generation;
                merged.requires_available_destination =
                    left_state.requires_available_destination or right_state.requires_available_destination;
                merged.may_repopulate_opaque_storage =
                    left_state.may_repopulate_opaque_storage or right_state.may_repopulate_opaque_storage;
                self.joinOpaqueOwnershipEffect(&merged, left_state, right_state);
            } else {
                if (left_state.initializedness != .initialized) {
                    merged.initializedness = .maybe_initialized;
                } else {
                    merged.value = try self.mergeValueEffects(
                        left_state.value,
                        try self.inputPlaceValueEffect(left_state.target),
                    );
                }
                self.joinOpaqueOwnershipEffect(
                    &merged,
                    left_state,
                    .{ .target = left_state.target, .initializedness = .initialized },
                );
            }
            try joined.append(merged);
        }

        for (right.items) |right_state| {
            if (self.findInputPostState(left.items, right_state.target) != null) continue;
            var merged = right_state;
            if (right_state.initializedness != .initialized) {
                merged.initializedness = .maybe_initialized;
            } else {
                merged.value = try self.mergeValueEffects(
                    right_state.value,
                    try self.inputPlaceValueEffect(right_state.target),
                );
            }
            self.joinOpaqueOwnershipEffect(
                &merged,
                .{ .target = right_state.target, .initializedness = .initialized },
                right_state,
            );
            try joined.append(merged);
        }

        destination.clearRetainingCapacity();
        try destination.appendSlice(joined.items);
    }

    fn joinInputPostStateFallthrough(
        self: *Infer,
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
        self: *Infer,
        joined: *?InputPostStateFlow,
        branch: *const InputPostStateFlow,
    ) !void {
        if (joined.*) |*current| {
            var combined = InputPostStateFlow.init(self.allocator);
            try self.joinInputPostStateFallthrough(&combined, current, branch);
            current.deinit();
            current.* = combined;
        } else {
            joined.* = try branch.clone(self.allocator);
        }
    }

    fn copyInputPostStateFlow(
        self: *Infer,
        destination: *InputPostStateFlow,
        source: *const InputPostStateFlow,
    ) !void {
        _ = self;
        destination.states.clearRetainingCapacity();
        try destination.states.appendSlice(source.states.items);
        destination.reachable = source.reachable;
    }

    fn recordInputPostStateExit(
        self: *Infer,
        exits: *?std.array_list.Managed(facts.PlacePostState),
        states: *const std.array_list.Managed(facts.PlacePostState),
    ) !void {
        if (exits.*) |*current| {
            var combined = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
            defer combined.deinit();
            try self.joinInputPostStates(&combined, current, states);
            current.clearRetainingCapacity();
            try current.appendSlice(combined.items);
        } else {
            exits.* = try self.cloneInputPostStates(states);
        }
    }

    fn cloneInputPostStates(
        self: *Infer,
        source: *const std.array_list.Managed(facts.PlacePostState),
    ) !std.array_list.Managed(facts.PlacePostState) {
        var result = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        try result.appendSlice(source.items);
        return result;
    }

    fn findInputPostState(
        self: *Infer,
        states: []const facts.PlacePostState,
        target: facts.InputPath,
    ) ?facts.PlacePostState {
        for (states) |state| if (self.inputPathEqual(state.target, target)) return state;
        return null;
    }

    fn inputPathEqual(self: *Infer, left: facts.InputPath, right: facts.InputPath) bool {
        _ = self;
        if (left.input_index != right.input_index or left.projections.len != right.projections.len) return false;
        for (left.projections, right.projections) |a, b| if (!std.meta.eql(a, b)) return false;
        return true;
    }

    fn optionalInputPathEqual(self: *Infer, left: ?facts.InputPath, right: ?facts.InputPath) bool {
        if ((left == null) != (right == null)) return false;
        return if (left) |path| self.inputPathEqual(path, right.?) else true;
    }

    fn joinOpaqueOwnershipEffect(
        self: *Infer,
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
        if (!self.optionalInputPathEqual(left_storage, right_storage)) {
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

    fn inputPlaceValueEffect(self: *Infer, target: facts.InputPath) !facts.ValueEffect {
        return .{ .input_place_values = try self.oneInputPath(target.input_index, target.projections) };
    }

    fn inferOpaqueStorageEffects(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
    ) ![]const facts.InputPath {
        var state = OpaqueEmptyState.init(self.allocator);
        defer state.deinit();
        var exits: ?std.array_list.Managed(facts.InputPath) = null;
        defer if (exits) |*emptied| emptied.deinit();
        try self.inferOpaqueEmptyBlock(function_id, block_id, effects, &state, &exits);
        if (state.reachable) try self.recordOpaqueEmptyExit(&exits, state.emptied.items);

        const emptied = if (exits) |*items|
            try self.allocator.dupe(facts.InputPath, items.items)
        else
            &.{};
        for (emptied) |storage| self.removeOpaqueStorageEffects(effects, storage);
        return emptied;
    }

    fn inferOpaqueEmptyBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!state.reachable) break;
            try self.inferOpaqueEmptyNode(function_id, node_id, effects, state, exits);
        }
        if (state.reachable) if (block.ret_val) |value|
            try self.inferOpaqueEmptyExpression(function_id, value, effects, state, exits);
    }

    fn inferOpaqueEmptyNode(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        switch (node.content) {
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (!record.deferred_initialization) if (record.initialization) |initialization|
                    try self.inferOpaqueEmptyExpression(function_id, initialization, effects, state, exits);
            },
            .assignment => |assignment| try self.inferOpaqueEmptyExpression(function_id, assignment.value, effects, state, exits),
            .function_call, .virtual_call => try self.inferOpaqueEmptyExpression(function_id, node_id, effects, state, exits),
            .if_statement => |statement| {
                try self.inferOpaqueEmptyExpression(function_id, statement.condition, effects, state, exits);
                var then_state = try state.clone(self.allocator);
                defer then_state.deinit();
                try self.inferOpaqueEmptyBlock(function_id, statement.then_block, effects, &then_state, exits);
                var else_state = try state.clone(self.allocator);
                defer else_state.deinit();
                if (statement.else_block) |child|
                    try self.inferOpaqueEmptyBlock(function_id, child, effects, &else_state, exits);
                try self.joinOpaqueEmptyFallthrough(state, &then_state, &else_state);
            },
            .while_statement => |statement| {
                try self.inferOpaqueEmptyExpression(function_id, statement.condition, effects, state, exits);
                var body_state = try state.clone(self.allocator);
                defer body_state.deinit();
                try self.inferOpaqueEmptyBlock(function_id, statement.body, effects, &body_state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .for_statement => |statement| {
                if (statement.init) |initialization|
                    try self.inferOpaqueEmptyNode(function_id, initialization, effects, state, exits);
                if (!state.reachable) return;
                try self.inferOpaqueEmptyExpression(function_id, statement.condition, effects, state, exits);
                var body_state = try state.clone(self.allocator);
                defer body_state.deinit();
                try self.inferOpaqueEmptyBlock(function_id, statement.body, effects, &body_state, exits);
                if (body_state.reachable) if (statement.increment) |increment|
                    try self.inferOpaqueEmptyNode(function_id, increment, effects, &body_state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.inferOpaqueEmptyExpression(function_id, statement.expression, effects, state, exits);
                var joined: ?OpaqueEmptyState = null;
                defer if (joined) |*joined_state| joined_state.deinit();
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    var branch = try state.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferOpaqueEmptyBlock(function_id, case.body, effects, &branch, exits);
                    try self.joinOpaqueEmptyBranch(&joined, &branch);
                }
                if (statement.default_block) |child| {
                    var branch = try state.clone(self.allocator);
                    defer branch.deinit();
                    try self.inferOpaqueEmptyBlock(function_id, child, effects, &branch, exits);
                    try self.joinOpaqueEmptyBranch(&joined, &branch);
                } else if (!statement.exhaustive) {
                    try self.joinOpaqueEmptyBranch(&joined, state);
                }
                if (joined) |*joined_state|
                    try self.copyOpaqueEmptyState(state, joined_state)
                else
                    state.reachable = false;
            },
            .return_statement => |statement| {
                if (statement.expression) |expression|
                    try self.inferOpaqueEmptyExpression(function_id, expression, effects, state, exits);
                try self.inferOpaqueEmptyRange(function_id, statement.cleanup, effects, state, exits);
                if (state.reachable) try self.recordOpaqueEmptyExit(exits, state.emptied.items);
                state.reachable = false;
            },
            .struct_field_store => |store| {
                try self.inferOpaqueEmptyExpression(function_id, store.struct_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .array_store => |store| {
                try self.inferOpaqueEmptyExpression(function_id, store.array_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.index, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .pointer_assignment => |assignment| {
                try self.inferOpaqueEmptyExpression(function_id, assignment.pointer, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, assignment.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
            },
            .code_block => |child| try self.inferOpaqueEmptyBlock(function_id, child, effects, state, exits),
            .break_statement, .continue_statement, .abort_statement => state.reachable = false,
            .auto_deinit_binding => |auto_id| try self.applyAutoDeinitOpaqueEffects(function_id, auto_id, effects, state),
            else => try self.inferOpaqueEmptyExpression(function_id, node_id, effects, state, exits),
        }
    }

    fn inferOpaqueEmptyRange(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        range: graph_mod.NodeRange,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |node_id| {
            if (!state.reachable) break;
            try self.inferOpaqueEmptyNode(function_id, node_id, effects, state, exits);
        }
    }

    fn applyAutoDeinitOpaqueEffects(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        auto_id: graph_mod.GlobalAutoDeinitId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.deinit_fn) |deinit_fn| if (cleanup.input) |input| {
            if (self.engine.summaryFor(deinit_fn)) |summary|
                try self.applyOpaqueEmptySummary(
                    function_id,
                    summary,
                    input,
                    effects,
                    state,
                    if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null,
                );
        };
        if (binding_effect) |effect|
            try self.applyAutoDeinitFieldOpaqueEffects(function_id, cleanup.fields, effects, state, effect);
    }

    fn applyAutoDeinitFieldOpaqueEffects(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        field_range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        parent_effect: facts.ValueEffect,
    ) !void {
        for (self.graph.auto_deinit_fields.items[field_range.start..][0..field_range.len]) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.deinit_fn) |deinit_fn| if (field.input) |input| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.applyOpaqueEmptySummary(
                        function_id,
                        summary,
                        input,
                        effects,
                        state,
                        .{ .input_index = field.self_field_index, .effect = field_effect },
                    );
            };
            try self.applyAutoDeinitFieldOpaqueEffects(function_id, field.fields, effects, state, field_effect);
        }
    }

    fn inferOpaqueEmptyExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        switch (node.content) {
            .move_value, .denied_implicit_copy, .address_of => |value| try self.inferOpaqueEmptyExpression(function_id, value, effects, state, exits),
            .dereference => |value| try self.inferOpaqueEmptyExpression(function_id, value.pointer, effects, state, exits),
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.inferOpaqueEmptyExpression(function_id, field.value, effects, state, exits);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferOpaqueEmptyExpression(function_id, element, effects, state, exits);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferOpaqueEmptyExpression(function_id, element, effects, state, exits);
            },
            .choice_literal => |literal| {
                if (literal.payload) |payload|
                    try self.inferOpaqueEmptyExpression(function_id, payload, effects, state, exits);
            },
            .struct_field_access => |access| try self.inferOpaqueEmptyExpression(function_id, access.value, effects, state, exits),
            .choice_payload_access => |access| try self.inferOpaqueEmptyExpression(function_id, access.value, effects, state, exits),
            .array_index => |index| {
                try self.inferOpaqueEmptyExpression(function_id, index.array_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, index.index, effects, state, exits);
            },
            .explicit_cast => |cast| try self.inferOpaqueEmptyExpression(function_id, cast.value, effects, state, exits),
            .binary_operation => |operation| {
                try self.inferOpaqueEmptyExpression(function_id, operation.left, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, operation.right, effects, state, exits);
            },
            .comparison => |comparison| {
                try self.inferOpaqueEmptyExpression(function_id, comparison.left, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, comparison.right, effects, state, exits);
            },
            .logical_operation => |operation| {
                try self.inferOpaqueEmptyExpression(function_id, operation.left, effects, state, exits);
                try self.inferConditionalOpaqueEmptyExpression(function_id, operation.right, effects, state, exits);
            },
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.inferOpaqueEmptyExpression(function_id, unwrap.nullable_value, effects, state, exits);
                try self.inferConditionalOpaqueEmptyExpression(function_id, unwrap.fallback_value, effects, state, exits);
            },
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.inferOpaqueEmptyExpression(function_id, expect.expected_reason, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, expect.actual_result, effects, state, exits);
                if (expect.test_fail_input) |input| try self.inferConditionalOpaqueEmptyExpression(function_id, input, effects, state, exits);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.inferOpaqueEmptyExpression(function_id, propagation.errable_value, effects, state, exits);
                var error_state = try state.clone(self.allocator);
                defer error_state.deinit();
                try self.inferOpaqueEmptyRange(function_id, propagation.cleanup_nodes, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, error_state.emptied.items);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferOpaqueEmptyExpression(function_id, context.errable_value, effects, state, exits);
                var error_state = try state.clone(self.allocator);
                defer error_state.deinit();
                try self.inferOpaqueEmptyExpression(function_id, context.context, effects, &error_state, exits);
                try self.inferOpaqueEmptyRange(function_id, context.cleanup_nodes, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, error_state.emptied.items);
            },
            .function_call => |call| {
                try self.inferOpaqueEmptyExpression(function_id, call.input, effects, state, exits);
                try self.applyOpaqueEmptyFunctionCall(function_id, call.callee, call.input, effects, state);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferOpaqueEmptyExpression(function_id, call.handle, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, call.input, effects, state, exits);
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.applyOpaqueEmptySummary(function_id, summary, call.input, effects, state, null);
            },
            .virtualize => |virtualize_id| try self.inferOpaqueEmptyExpression(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                effects,
                state,
                exits,
            ),
            .type_initializer => |initializer| {
                try self.inferOpaqueEmptyExpression(function_id, initializer.args, effects, state, exits);
                const summary = self.engine.summaryFor(initializer.init_fn) orelse return;
                try self.applyOpaqueEmptySummaryArguments(function_id, summary, try self.initializerArguments(initializer.args), effects, state, .{ .input_index = 0, .effect = .{} });
            },
            else => {},
        }
    }

    fn inferConditionalOpaqueEmptyExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        exits: *?std.array_list.Managed(facts.InputPath),
    ) !void {
        var executed = try state.clone(self.allocator);
        defer executed.deinit();
        try self.inferOpaqueEmptyExpression(function_id, node_id, effects, &executed, exits);
        var skipped = try state.clone(self.allocator);
        defer skipped.deinit();
        try self.joinOpaqueEmptyFallthrough(state, &executed, &skipped);
    }

    fn applyOpaqueEmptyFunctionCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        const callee_function = self.graph.function(callee);
        switch (primitive_transfer.forPrimitive(callee_function.safety_primitive).opaque_state) {
            .clear_empty => {
                state.emptied.clearRetainingCapacity();
                return;
            },
            .store_hidden => {
                if (arguments.len != 3) return;
                const storages = try self.inferInputPaths(function_id, arguments[0].value);
                const hidden = try self.inferExpression(function_id, arguments[2].value);
                try self.recordOpaqueStorageWrites(effects, state, storages, hidden);
                return;
            },
            .mark_empty => {
                if (arguments.len != 1) return;
                const storages = try self.inferInputPaths(function_id, arguments[0].value);
                try self.recordOpaqueStorageEmpties(state, storages);
                return;
            },
            .none => {},
        }
        const summary = self.engine.summaryFor(callee) orelse return;
        try self.applyOpaqueEmptySummary(function_id, summary, input, effects, state, null);
    }

    fn applyOpaqueEmptySummary(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        input: graph_mod.GlobalNodeId,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        override: ?SymbolicInputOverride,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        try self.applyOpaqueEmptySummaryArguments(function_id, summary, arguments, effects, state, override);
    }

    fn applyOpaqueEmptySummaryArguments(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        arguments: []const graph_mod.ValueField,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        override: ?SymbolicInputOverride,
    ) !void {
        if (self.summaryMayRepopulateOpaqueStorage(summary)) state.emptied.clearRetainingCapacity();
        for (summary.opaque_storage_effects) |effect| {
            if (effect.storage.input_index >= arguments.len) continue;
            const storages = try self.substituteRequiredInputPath(function_id, effect.storage, arguments, override);
            const hidden = try self.substituteOutputWithOverride(function_id, effect.hidden_dependencies, arguments, override);
            try self.recordOpaqueStorageWrites(effects, state, storages, hidden);
        }
        for (summary.opaque_storage_empties) |empty| {
            if (empty.input_index >= arguments.len) continue;
            const storages = try self.substituteRequiredInputPath(function_id, empty, arguments, override);
            try self.recordOpaqueStorageEmpties(state, storages);
        }
    }

    fn recordOpaqueStorageWrites(
        self: *Infer,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        state: *OpaqueEmptyState,
        storages: []const facts.InputPath,
        hidden: facts.ValueEffect,
    ) !void {
        for (storages) |storage| {
            self.removeOpaqueStorageRelease(&state.emptied, storage);
            try self.recordOpaqueStorageEffect(effects, storage, hidden);
        }
    }

    fn recordOpaqueStorageEmpties(
        self: *Infer,
        state: *OpaqueEmptyState,
        storages: []const facts.InputPath,
    ) !void {
        for (storages) |storage| try self.recordOpaqueStorageRelease(&state.emptied, storage);
    }

    fn joinOpaqueEmptyFallthrough(
        self: *Infer,
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
        self: *Infer,
        joined: *?OpaqueEmptyState,
        branch: *const OpaqueEmptyState,
    ) !void {
        if (joined.*) |*current| {
            var combined = OpaqueEmptyState.init(self.allocator);
            try self.joinOpaqueEmptyFallthrough(&combined, current, branch);
            current.deinit();
            current.* = combined;
        } else {
            joined.* = try branch.clone(self.allocator);
        }
    }

    fn copyOpaqueEmptyState(
        self: *Infer,
        destination: *OpaqueEmptyState,
        source: *const OpaqueEmptyState,
    ) !void {
        _ = self;
        destination.emptied.clearRetainingCapacity();
        try destination.emptied.appendSlice(source.emptied.items);
        destination.reachable = source.reachable;
    }

    fn recordOpaqueEmptyExit(
        self: *Infer,
        exits: *?std.array_list.Managed(facts.InputPath),
        emptied: []const facts.InputPath,
    ) !void {
        if (exits.*) |*current| {
            const joined = try self.intersectInputPaths(current.items, emptied);
            current.clearRetainingCapacity();
            try current.appendSlice(joined);
        } else {
            var first = std.array_list.Managed(facts.InputPath).init(self.allocator);
            try first.appendSlice(emptied);
            exits.* = first;
        }
    }

    fn removeOpaqueStorageRelease(
        self: *Infer,
        empties: *std.array_list.Managed(facts.InputPath),
        storage: facts.InputPath,
    ) void {
        var index: usize = 0;
        while (index < empties.items.len) {
            if (self.inputPathEqual(empties.items[index], storage)) {
                _ = empties.orderedRemove(index);
            } else {
                index += 1;
            }
        }
    }

    fn recordOpaqueStorageEffect(
        self: *Infer,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        storage: facts.InputPath,
        hidden: facts.ValueEffect,
    ) !void {
        const dependencies_only = try self.dependencyOnlyEffect(hidden);
        for (effects.items) |*existing| {
            if (!self.inputPathEqual(existing.storage, storage)) continue;
            existing.hidden_dependencies = try self.mergeValueEffects(existing.hidden_dependencies, dependencies_only);
            return;
        }
        try effects.append(.{ .storage = storage, .hidden_dependencies = dependencies_only });
    }

    fn recordOpaqueStorageRelease(
        self: *Infer,
        empties: *std.array_list.Managed(facts.InputPath),
        storage: facts.InputPath,
    ) !void {
        _ = self;
        try appendInputPath(empties, storage);
    }

    fn removeOpaqueStorageEffects(
        self: *Infer,
        effects: *std.array_list.Managed(facts.OpaqueStorageEffect),
        storage: facts.InputPath,
    ) void {
        var index: usize = 0;
        while (index < effects.items.len) {
            if (self.inputPathEqual(effects.items[index].storage, storage)) {
                _ = effects.orderedRemove(index);
            } else {
                index += 1;
            }
        }
    }

    fn intersectInputPaths(
        self: *Infer,
        left: []const facts.InputPath,
        right: []const facts.InputPath,
    ) ![]const facts.InputPath {
        var result = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left) |candidate| {
            for (right) |other| {
                if (!self.inputPathEqual(candidate, other)) continue;
                try appendInputPath(&result, candidate);
                break;
            }
        }
        return result.toOwnedSlice();
    }

    fn summaryMayRepopulateOpaqueStorage(self: *Infer, summary: facts.SafetySummary) bool {
        for (summary.input_post_states) |post_state| {
            if (post_state.opaque_ownership != .none or
                post_state.initializedness != .initialized or
                !post_state.may_repopulate_opaque_storage) continue;

            // A write-like effect on a projection is irrelevant when the
            // summary final state ends an ancestor place. This occurs when
            // destructor dispatch mutates a field before deinitializing self.
            var ended_by_ancestor = false;
            for (summary.input_post_states) |terminal| {
                if (terminal.initializedness != .deinitialized and
                    terminal.initializedness != .moved) continue;
                if (self.inputPathPrefix(terminal.target, post_state.target)) {
                    ended_by_ancestor = true;
                    break;
                }
            }
            if (!ended_by_ancestor) return true;
        }
        return false;
    }

    fn inputPathPrefix(self: *Infer, prefix: facts.InputPath, path: facts.InputPath) bool {
        _ = self;
        if (prefix.input_index != path.input_index or prefix.projections.len > path.projections.len) return false;
        for (prefix.projections, path.projections[0..prefix.projections.len]) |left, right|
            if (!std.meta.eql(left, right)) return false;
        return true;
    }

    fn dependencyOnlyEffect(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var owned_sources = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        defer owned_sources.deinit();
        try self.collectFreshOwnedSources(effect, &owned_sources);
        return self.dependencyOnlyEffectExcludingOwned(effect, owned_sources.items);
    }

    fn collectFreshOwnedSources(
        self: *Infer,
        effect: facts.ValueEffect,
        sources: *std.array_list.Managed(facts.FreshEffectSource),
    ) !void {
        for (effect.fresh_owned_roots) |source| try appendFresh(sources, source);
        for (effect.fields) |field| try self.collectFreshOwnedSources(field.value.*, sources);
        for (effect.variants) |variant| try self.collectFreshOwnedSources(variant.value.*, sources);
    }

    fn dependencyOnlyEffectExcludingOwned(
        self: *Infer,
        effect: facts.ValueEffect,
        owned_sources: []const facts.FreshEffectSource,
    ) !facts.ValueEffect {
        const input_dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (input_dependencies) |*dependency| dependency.transfers_ownership = false;

        var fresh_dependencies = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (effect.fresh_dependencies) |source| {
            var owned = false;
            for (owned_sources) |owned_source| if (owned_source == source) {
                owned = true;
                break;
            };
            if (!owned) try appendFresh(&fresh_dependencies, source);
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
            .input_generation_dependencies = effect.input_generation_dependencies,
            .input_place_values = effect.input_place_values,
            .input_owned_roots = effect.input_owned_roots,
            .opaque_generation_dependencies = effect.opaque_generation_dependencies,
            .opaque_storage_dependencies = effect.opaque_storage_dependencies,
            .fields = fields,
            .variants = variants,
            .fresh_dependencies = try fresh_dependencies.toOwnedSlice(),
        };
    }

    fn inferRequiredLiveInputsBlock(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id|
            try self.inferRequiredLiveInputsNode(function_id, node_id, required);
        if (block.ret_val) |value| try self.inferRequiredLiveInputsNode(function_id, value, required);
    }

    fn inferRequiredLiveInputsNode(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        const node = self.graph.node(node_id);
        if (pointerUseOperand(node.content)) |pointer|
            try self.recordPointerUseRequirement(function_id, pointer, required);

        switch (node.content) {
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (!record.deferred_initialization) if (record.initialization) |initialization|
                    try self.inferRequiredLiveInputsNode(function_id, initialization, required);
            },
            .assignment => |assignment| try self.inferRequiredLiveInputsNode(function_id, assignment.value, required),
            .move_value, .denied_implicit_copy, .address_of => |value| try self.inferRequiredLiveInputsNode(function_id, value, required),
            .dereference => |value| try self.inferRequiredLiveInputsNode(function_id, value.pointer, required),
            .array_index => |index| {
                try self.inferRequiredLiveInputsNode(function_id, index.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, index.index, required);
            },
            .array_store => |store| {
                try self.inferRequiredLiveInputsNode(function_id, store.array_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, store.index, required);
                try self.inferRequiredLiveInputsNode(function_id, store.value, required);
            },
            .pointer_assignment => |assignment| {
                try self.inferRequiredLiveInputsNode(function_id, assignment.pointer, required);
                try self.inferRequiredLiveInputsNode(function_id, assignment.value, required);
            },
            .struct_field_access => |access| try self.inferRequiredLiveInputsNode(function_id, access.value, required),
            .choice_payload_access => |access| try self.inferRequiredLiveInputsNode(function_id, access.value, required),
            .explicit_cast => |cast| try self.inferRequiredLiveInputsNode(function_id, cast.value, required),
            .struct_field_store => |store| {
                try self.inferRequiredLiveInputsNode(function_id, store.struct_ptr, required);
                try self.inferRequiredLiveInputsNode(function_id, store.value, required);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.inferRequiredLiveInputsNode(function_id, field.value, required);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferRequiredLiveInputsNode(function_id, element, required);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.inferRequiredLiveInputsNode(function_id, element, required);
            },
            .choice_literal => |literal| {
                if (literal.payload) |payload| try self.inferRequiredLiveInputsNode(function_id, payload, required);
            },
            .function_call => |call| {
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                if (self.engine.summaryFor(call.callee)) |summary|
                    try self.substituteRequiredLiveInputs(function_id, summary.required_live_inputs, call.input, required);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferRequiredLiveInputsNode(function_id, call.handle, required);
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(
                        function_id,
                        summary.required_live_inputs,
                        call.input,
                        required,
                        null,
                    );
            },
            .virtualize => |virtualize_id| try self.inferRequiredLiveInputsNode(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                required,
            ),
            .binary_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function_id, operation.left, required);
                try self.inferRequiredLiveInputsNode(function_id, operation.right, required);
            },
            .comparison => |comparison| {
                try self.inferRequiredLiveInputsNode(function_id, comparison.left, required);
                try self.inferRequiredLiveInputsNode(function_id, comparison.right, required);
            },
            .logical_operation => |operation| {
                try self.inferRequiredLiveInputsNode(function_id, operation.left, required);
                try self.inferRequiredLiveInputsNode(function_id, operation.right, required);
            },
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.inferRequiredLiveInputsNode(function_id, unwrap.nullable_value, required);
                try self.inferRequiredLiveInputsNode(function_id, unwrap.fallback_value, required);
            },
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.inferRequiredLiveInputsNode(function_id, expect.expected_reason, required);
                try self.inferRequiredLiveInputsNode(function_id, expect.actual_result, required);
                if (expect.test_fail_input) |input| try self.inferRequiredLiveInputsNode(function_id, input, required);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.inferRequiredLiveInputsNode(function_id, propagation.errable_value, required);
                try self.inferRequiredLiveInputsRange(function_id, propagation.cleanup_nodes, required);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferRequiredLiveInputsNode(function_id, context.errable_value, required);
                try self.inferRequiredLiveInputsNode(function_id, context.context, required);
                try self.inferRequiredLiveInputsRange(function_id, context.cleanup_nodes, required);
            },
            .if_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.then_block, required);
                if (statement.else_block) |child| try self.inferRequiredLiveInputsBlock(function_id, child, required);
            },
            .while_statement => |statement| {
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.body, required);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| try self.inferRequiredLiveInputsNode(function_id, initialization, required);
                try self.inferRequiredLiveInputsNode(function_id, statement.condition, required);
                if (statement.increment) |increment| try self.inferRequiredLiveInputsNode(function_id, increment, required);
                try self.inferRequiredLiveInputsBlock(function_id, statement.body, required);
            },
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                try self.inferRequiredLiveInputsNode(function_id, statement.expression, required);
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                    try self.inferRequiredLiveInputsNode(function_id, case.value, required);
                    try self.inferRequiredLiveInputsBlock(function_id, case.body, required);
                }
                if (statement.default_block) |child| try self.inferRequiredLiveInputsBlock(function_id, child, required);
            },
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.inferRequiredLiveInputsNode(function_id, expression, required);
                try self.inferRequiredLiveInputsRange(function_id, statement.cleanup, required);
            },
            .code_block => |child| try self.inferRequiredLiveInputsBlock(function_id, child, required),
            .type_initializer => |initializer| {
                try self.inferRequiredLiveInputsNode(function_id, initializer.args, required);
                const summary = self.engine.summaryFor(initializer.init_fn) orelse return;
                const arguments = try self.initializerArguments(initializer.args);
                for (summary.required_live_inputs) |path| {
                    const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, .{ .input_index = 0, .effect = .{} });
                    for (mapped) |candidate| try appendInputPath(required, candidate);
                }
            },
            .auto_deinit_binding => |auto_id| try self.inferAutoDeinitRequiredLiveInputs(function_id, auto_id, required),
            else => {},
        }
    }

    fn inferRequiredLiveInputsRange(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        range: graph_mod.NodeRange,
        required: *std.array_list.Managed(facts.InputPath),
    ) anyerror!void {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |node|
            try self.inferRequiredLiveInputsNode(function_id, node, required);
    }

    fn recordPointerUseRequirement(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        pointer: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const effect = try self.inferExpression(function_id, pointer);
        for (try self.symbolicSourcePaths(function_id, pointer, effect)) |path|
            try appendInputPath(required, path);
    }

    fn symbolicSourcePaths(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) ![]const facts.InputPath {
        const direct = try self.inferInputPaths(function_id, node_id);
        if (direct.len != 0) return direct;
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn substituteRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee_required: []const facts.InputPath,
        input: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        try self.substituteRequiredLiveInputsWithOverride(function_id, callee_required, input, required, null);
    }

    fn substituteRequiredLiveInputsWithOverride(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        callee_required: []const facts.InputPath,
        input: graph_mod.GlobalNodeId,
        required: *std.array_list.Managed(facts.InputPath),
        override: ?SymbolicInputOverride,
    ) !void {
        const arguments = self.structArguments(input) orelse return;
        for (callee_required) |path| {
            if (path.input_index >= arguments.len) continue;
            const substituted = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (substituted) |candidate| try appendInputPath(required, candidate);
        }
    }

    // Keep local addresses separate from reference value effects: projections
    // in a callee describe the pointee, rather than fields of the pointer.
    // Resolve its value at the use site instead of freezing an initializer's
    // dependencies. Assignment retains possible targets across control flow.
    fn localAddressTargets(self: *Infer, node_id: graph_mod.GlobalNodeId) ![]const graph_mod.GlobalNodeId {
        return switch (self.graph.node(node_id).content) {
            .address_of => |value| blk: {
                const targets = try self.allocator.alloc(graph_mod.GlobalNodeId, 1);
                targets[0] = value;
                break :blk targets;
            },
            .binding_use => |binding| self.local_address_bindings.get(binding) orelse &.{},
            .move_value, .denied_implicit_copy => |value| self.localAddressTargets(value),
            else => &.{},
        };
    }

    fn localPointeeEffect(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) !?facts.ValueEffect {
        const targets = try self.localAddressTargets(node_id);
        if (targets.len == 0) return null;
        var result: facts.ValueEffect = .{};
        for (targets) |target| result = try self.mergeValueEffects(result, try self.inferExpression(function_id, target));
        return result;
    }

    fn substituteRequiredInputPath(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        path: facts.InputPath,
        arguments: []const graph_mod.ValueField,
        override: ?SymbolicInputOverride,
    ) ![]const facts.InputPath {
        if (path.input_index >= arguments.len) return &.{};
        if (override) |symbolic| if (symbolic.input_index == path.input_index) {
            if (path.projections.len == 0) return &.{};
            var effect = symbolic.effect;
            for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
            return self.opaqueGenerationSourcePaths(effect);
        };

        const argument = arguments[path.input_index].value;
        var direct = try self.inferInputPaths(function_id, argument);
        if (direct.len != 0) {
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            return direct;
        }

        var effect = try self.inferExpression(function_id, argument);
        for (path.projections) |projection| effect = try self.projectValueEffect(effect, projection);
        return self.opaqueGenerationSourcePaths(effect);
    }

    fn inferAutoDeinitRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        auto_id: graph_mod.GlobalAutoDeinitId,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.input) |input| {
            try self.inferRequiredLiveInputsNode(function_id, input, required);
            if (cleanup.deinit_fn) |deinit_fn| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(
                        function_id,
                        summary.required_live_inputs,
                        input,
                        required,
                        if (binding_effect) |effect| .{ .input_index = cleanup.self_field_index, .effect = effect } else null,
                    );
            }
        }
        if (binding_effect) |effect|
            try self.inferAutoDeinitFieldRequiredLiveInputs(function_id, cleanup.fields, effect, required);
    }

    fn inferAutoDeinitFieldRequiredLiveInputs(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        fields_range: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        parent_effect: facts.ValueEffect,
        required: *std.array_list.Managed(facts.InputPath),
    ) !void {
        for (self.graph.auto_deinit_fields.items[fields_range.start..][0..fields_range.len]) |field| {
            const field_effect = try self.projectValueEffect(parent_effect, .{ .field = field.field_index });
            if (field.input) |input| {
                try self.inferRequiredLiveInputsNode(function_id, input, required);
                if (field.deinit_fn) |deinit_fn| {
                    if (self.engine.summaryFor(deinit_fn)) |summary|
                        try self.substituteRequiredLiveInputsWithOverride(
                            function_id,
                            summary.required_live_inputs,
                            input,
                            required,
                            .{ .input_index = field.self_field_index, .effect = field_effect },
                        );
                }
            }
            try self.inferAutoDeinitFieldRequiredLiveInputs(function_id, field.fields, field_effect, required);
        }
    }

    fn inferExpression(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
    ) anyerror!facts.ValueEffect {
        const node = self.graph.node(node_id);
        return switch (node.content) {
            .binding_use => |binding| if (self.inputIndex(function_id, binding)) |index|
                try self.inputValueEffect(index, &.{})
            else
                self.bindings.get(binding) orelse .{},
            .move_value => |value| try self.withOwnershipTransfer(try self.inferExpression(function_id, value)),
            .denied_implicit_copy => |value| try self.inferExpression(function_id, value),
            .address_of => |value| blk: {
                if (self.graph.node(value).content == .array_index) {
                    const index = self.graph.node(value).content.array_index;
                    // An indexed address borrows the storage reached by the
                    // array pointer, which may itself be stored in an input
                    // field. The iterator's pointer field is not the root of
                    // the indexed element.
                    break :blk .{ .input_place_values = try self.inferInputPaths(function_id, index.array_ptr) };
                }
                break :blk .{ .input_places = try self.inferInputPaths(function_id, value) };
            },
            .dereference => |value| try self.inferOpaqueRead(
                function_id,
                node_id,
                value.pointer,
                try self.inferExpression(function_id, value.pointer),
            ),
            .struct_value_literal => |literal| try self.inferAggregate(function_id, node_id, literal.fields),
            .list_literal => |literal| try self.inferElements(function_id, literal.elements),
            .array_literal => |literal| try self.inferElements(function_id, literal.elements),
            .choice_literal => |literal| try self.choiceValueEffect(
                self.variantIndex(literal.choice_type, literal.variant) orelse 0,
                if (literal.payload) |payload| try self.inferExpression(function_id, payload) else .{},
            ),
            .struct_field_access => |access| try self.inferOpaqueReadFromSyntax(
                function_id,
                node_id,
                try self.projectValueEffect(try self.inferExpression(function_id, access.value), .{ .field = access.field_index }),
            ),
            .choice_payload_access => |access| blk: {
                const choice = try self.inferExpression(function_id, access.value);
                const variant_index = self.variantIndex(self.graph.node(access.value).ty orelse break :blk .{}, access.variant) orelse break :blk .{};
                const payload = try self.projectValueEffect(choice, .{ .variant = variant_index });
                break :blk try self.inferOpaqueReadFromSyntax(function_id, node_id, payload);
            },
            .array_index => |index| try self.inferOpaqueRead(
                function_id,
                node_id,
                index.array_ptr,
                try self.projectValueEffect(
                    try self.inferExpression(function_id, index.array_ptr),
                    if (self.staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index,
                ),
            ),
            .explicit_cast => |cast| if (self.graph.types.items[@intFromEnum(cast.target_type)] == .pointer)
                try self.inferExpression(function_id, cast.value)
            else
                .{},
            .type_initializer => |initializer| blk: {
                const arguments = try self.initializerArguments(initializer.args);
                const effect = try self.constructorResultEffect(initializer.init_fn, node.ty orelse return error.InvalidInitializerType);
                const substituted = try self.substituteOutputWithOverride(function_id, effect, arguments, .{ .input_index = 0, .effect = .{} });
                break :blk try self.rebaseFreshSources(substituted, node_id);
            },
            .testing_expect_error => |id| blk: {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                const input = expect.test_fail_input orelse break :blk .{};
                break :blk try self.inferCall(function_id, node_id, expect.test_fail_function, input);
            },
            .function_call => |call| try self.inferCall(function_id, node_id, call.callee, call.input),
            .virtualize => |virtualize_id| try self.inferVirtualize(function_id, virtualize_id),
            .virtual_call => |virtual_call_id| try self.inferVirtualCall(function_id, node_id, virtual_call_id),
            .error_propagation => |id| blk: {
                const propagation = self.graph.error_propagations.items[@intFromEnum(id)];
                break :blk try self.error_success_effect(function_id, propagation.errable_value, propagation.ok_variant, propagation.ok_value_field_index);
            },
            .error_context => |id| blk: {
                const context = self.graph.error_contexts.items[@intFromEnum(id)];
                break :blk try self.error_success_effect(function_id, context.errable_value, context.ok_variant, context.ok_value_field_index);
            },
            .nullable_unwrap_or => |unwrap_id| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                break :blk try self.mergeValueEffects(
                    try self.inferExpression(function_id, unwrap.nullable_value),
                    try self.inferExpression(function_id, unwrap.fallback_value),
                );
            },
            else => .{},
        };
    }

    // Match codegen's success projection. Only the selected payload reaches
    // the continuation; its ownership moves with it across summary boundaries.
    fn error_success_effect(
        self: *Infer,
        function: graph_mod.GlobalFunctionId,
        errable: graph_mod.GlobalNodeId,
        ok_variant: graph_mod.GlobalVariantId,
        value_field: ?u32,
    ) !facts.ValueEffect {
        const ty = self.graph.node(errable).ty orelse return .{};
        const index = self.variantIndex(ty, ok_variant) orelse return .{};
        var success = try self.projectValueEffect(try self.inferExpression(function, errable), .{ .variant = index });
        if (value_field) |field| success = try self.projectValueEffect(success, .{ .field = field });
        return self.withOwnershipTransfer(success);
    }

    fn inferCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        call_node: graph_mod.GlobalNodeId,
        callee: graph_mod.GlobalFunctionId,
        input: graph_mod.GlobalNodeId,
    ) !facts.ValueEffect {
        const callee_function = self.graph.function(callee);
        const arguments = self.structArguments(input) orelse return .{};
        if (callee_function.safety_primitive != .none) {
            const effect = try self.primitiveValueEffect(callee_function.safety_primitive, self.freshSource(call_node, 0));
            return self.substituteOutput(function_id, effect, arguments);
        }
        const summary = self.engine.summaryFor(callee) orelse return .{};
        return self.substitute_summary_outputs(function_id, summary.outputs, arguments, call_node);
    }

    fn substitute_summary_outputs(self: *Infer, function: graph_mod.GlobalFunctionId, outputs: []const facts.ValueEffect, arguments: []const graph_mod.ValueField, call_node: graph_mod.GlobalNodeId) !facts.ValueEffect {
        if (outputs.len == 0) return .{};
        if (outputs.len == 1) return self.rebaseFreshSources(try self.substituteOutput(function, outputs[0], arguments), call_node);
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, outputs.len);
        var aggregate: facts.ValueEffect = .{};
        for (outputs, 0..) |output, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.substituteOutput(function, output, arguments);
            fields[index] = .{ .index = @intCast(index), .value = value };
            aggregate = try self.mergeValueEffects(aggregate, value.*);
        }
        aggregate.fields = fields;
        aggregate.variants = &.{};
        aggregate.known_choice_variant = null;
        return self.rebaseFreshSources(aggregate, call_node);
    }

    fn initializerArguments(self: *Infer, input: graph_mod.GlobalNodeId) ![]const graph_mod.ValueField {
        const explicit = self.structArguments(input) orelse return error.InvalidInitializerArguments;
        const arguments = try self.allocator.alloc(graph_mod.ValueField, explicit.len + 1);
        // The implicit destination has no caller-input identity. Substitution
        // always overrides this placeholder with its symbolic value.
        arguments[0] = .{ .name = .{ .start = 0, .len = 0 }, .value = input };
        @memcpy(arguments[1..], explicit);
        return arguments;
    }

    /// Constructors publish the value established by init's destination
    /// post-state, rather than an ordinary function output. Parameter indices
    /// remain those of init, including destination input zero.
    pub fn initializerResultEffect(self: *Infer, init_fn: graph_mod.GlobalFunctionId) !facts.ValueEffect {
        const summary = self.engine.summaryFor(init_fn) orelse return .{};
        const function = self.graph.function(init_fn);
        var post_states = summary.input_post_states;
        if (function.output.len == 1) {
            post_states = &.{};
            const result_ty = self.graph.fields.items[function.output.start].ty;
            const ok = types.findVariant(self.graph, result_ty, "ok") orelse return error.InvalidInitializerResult;
            for (summary.outcome_post_states) |outcome| if (outcome.variant_index == ok.index) {
                post_states = outcome.input_post_states;
                break;
            };
        }
        var result: facts.ValueEffect = .{};
        for (post_states) |state| {
            if (state.target.input_index != 0 or state.initializedness != .initialized) continue;
            result = try self.storeEffectProjection(result, state.target.projections, state.value);
        }
        return result;
    }

    pub fn constructorResultEffect(
        self: *Infer,
        init_fn: graph_mod.GlobalFunctionId,
        result_ty: graph_mod.GlobalTypeId,
    ) !facts.ValueEffect {
        const success = try self.initializerResultEffect(init_fn);
        const function = self.graph.function(init_fn);
        if (function.output.len == 0) return success;
        const summary = self.engine.summaryFor(init_fn) orelse return .{};
        const source_ty = self.graph.fields.items[function.output.start].ty;
        const source_error = types.findVariant(self.graph, source_ty, "error") orelse return error.InvalidInitializerResult;
        const target_ok = types.findVariant(self.graph, result_ty, "ok") orelse return error.InvalidInitializerResult;
        const target_error = types.findVariant(self.graph, result_ty, "error") orelse return error.InvalidInitializerResult;
        const error_effect = if (summary.outputs.len == 1)
            try self.projectValueEffect(summary.outputs[0], .{ .variant = source_error.index })
        else
            facts.ValueEffect{};
        const ok_value = try self.allocator.create(facts.ValueEffect);
        ok_value.* = success;
        const err_value = try self.allocator.create(facts.ValueEffect);
        err_value.* = error_effect;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, 2);
        variants[0] = .{ .index = target_ok.index, .value = ok_value };
        variants[1] = .{ .index = target_error.index, .value = err_value };
        return .{ .variants = variants };
    }

    fn storeEffectProjection(self: *Infer, previous: facts.ValueEffect, projections: []const facts.Projection, value: facts.ValueEffect) anyerror!facts.ValueEffect {
        if (projections.len == 0) return value;
        const index: u32 = switch (projections[0]) {
            .field => |index| index,
            .static_index => |index| std.math.cast(u32, index) orelse return self.mergeValueEffects(previous, value),
            else => return self.mergeValueEffects(previous, value),
        };
        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator);
        var found = false;
        for (previous.fields) |field| {
            var updated = field;
            if (field.index == index) {
                const child = try self.allocator.create(facts.ValueEffect);
                child.* = try self.storeEffectProjection(field.value.*, projections[1..], value);
                updated.value = child;
                found = true;
            }
            try fields.append(updated);
        }
        if (!found) {
            const child = try self.allocator.create(facts.ValueEffect);
            child.* = try self.storeEffectProjection(.{}, projections[1..], value);
            try fields.append(.{ .index = index, .value = child });
        }
        var result = previous;
        for (fields.items) |field| result = try self.mergeValueEffects(result, field.value.*);
        result.fields = try fields.toOwnedSlice();
        return result;
    }

    fn inferVirtualize(self: *Infer, function_id: graph_mod.GlobalFunctionId, id: graph_mod.GlobalVirtualizeId) !facts.ValueEffect {
        const virtualize = self.graph.virtualizes.items[@intFromEnum(id)];
        var result = try self.inferExpression(function_id, virtualize.value);
        const receiver_paths = try self.inferInputPaths(function_id, virtualize.value);
        var generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        try generations.appendSlice(result.input_generation_dependencies);
        for (self.graph.function_refs.items[virtualize.methods.start..][0..virtualize.methods.len], 0..) |method, index| {
            const receiver_index = self.virtualizeReceiverIndex(virtualize, index);
            const summary = self.engine.summaryFor(method) orelse continue;
            for (summary.outputs) |output| {
                const borrowed = try facts.receiverBorrowedPlaces(self.allocator, output, receiver_index);
                for (receiver_paths) |receiver_path| for (borrowed) |borrowed_path| {
                    const projections = try self.allocator.alloc(facts.Projection, receiver_path.projections.len + borrowed_path.projections.len);
                    @memcpy(projections[0..receiver_path.projections.len], receiver_path.projections);
                    @memcpy(projections[receiver_path.projections.len..], borrowed_path.projections);
                    try appendInputPath(&generations, .{ .input_index = receiver_path.input_index, .projections = projections });
                };
            }
        }
        result.input_generation_dependencies = try generations.toOwnedSlice();
        return result;
    }

    fn inferVirtualCall(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        call_node: graph_mod.GlobalNodeId,
        virtual_call_id: graph_mod.GlobalVirtualCallId,
    ) !facts.ValueEffect {
        const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
        const summary = try self.virtualSummary(call.safety_methods) orelse return .{};
        const arguments = self.structArguments(call.input) orelse return .{};
        return self.substitute_summary_outputs(function_id, summary.outputs, arguments, call_node);
    }

    fn structArguments(self: *Infer, node_id: graph_mod.GlobalNodeId) ?[]const graph_mod.ValueField {
        const node = self.graph.node(node_id);
        const literal = switch (node.content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        return self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len];
    }

    fn inferAggregate(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        fields_range: primitives.Range(graph_mod.GlobalValueFieldId),
    ) !facts.ValueEffect {
        if (self.graph.node(node_id).ty == null) return .{};
        const source_fields = self.graph.value_fields.items[fields_range.start..][0..fields_range.len];
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, source_fields.len);
        var result: facts.ValueEffect = .{};
        for (source_fields, 0..) |field, position| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.inferExpression(function_id, field.value);
            // Aggregate safety facts are storage-position based. This mirrors
            // the runtime checker and the pre-GlobalSG safety model; source
            // field labels may differ from the contextual storage field names.
            output_fields[position] = .{ .index = @intCast(position), .value = value };
            result = try self.mergeValueEffects(result, value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields;
        return result;
    }

    fn inferElements(self: *Infer, function_id: graph_mod.GlobalFunctionId, range: graph_mod.NodeRange) !facts.ValueEffect {
        var result: facts.ValueEffect = .{};
        const output_fields = try self.allocator.alloc(facts.OutputFieldEffect, range.len);
        for (self.graph.node_refs.items[range.start..][0..range.len], 0..) |element, index| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.inferExpression(function_id, element);
            output_fields[index] = .{ .index = @intCast(index), .value = value };
            result = try self.mergeValueEffects(result, value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields;
        return result;
    }

    fn inferOpaqueRead(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        pointer: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = self.graph.node(node_id).ty orelse return .{};
        if (!self.typeContainsPointer(ty)) return self.scalar_storage_effect(effect);
        const input_paths = try self.inferInputPaths(function_id, pointer);
        var pointee = effect;
        if (input_paths.len != 0) {
            pointee.input_dependencies = &.{};
            pointee.input_places = &.{};
            pointee.input_place_values = input_paths;
        }
        const direct = try self.inferInputPaths(function_id, pointer);
        const sources = if (direct.len != 0) direct else try self.opaqueGenerationSourcePaths(pointee);
        return self.withOpaqueGenerationDependencies(sources, pointee);
    }

    fn inferOpaqueReadFromSyntax(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        node_id: graph_mod.GlobalNodeId,
        effect: facts.ValueEffect,
    ) !facts.ValueEffect {
        const ty = self.graph.node(node_id).ty orelse return effect;
        if (!self.typeContainsPointer(ty)) return self.scalar_storage_effect(effect);
        return self.withOpaqueGenerationDependencies(try self.inferOpaqueReadInputPaths(function_id, node_id), effect);
    }

    fn inferOpaqueReadInputPaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) ![]const facts.InputPath {
        return switch (self.graph.node(node_id).content) {
            .move_value, .denied_implicit_copy => |value| self.inferOpaqueReadInputPaths(function_id, value),
            .struct_field_access => |access| self.inferOpaqueReadInputPaths(function_id, access.value),
            .choice_payload_access => |access| self.inferOpaqueReadInputPaths(function_id, access.value),
            .dereference => |dereference| self.inferInputPaths(function_id, dereference.pointer),
            .array_index => |index| self.inferInputPaths(function_id, index.array_ptr),
            else => &.{},
        };
    }

    fn inferInputPaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) anyerror![]const facts.InputPath {
        return switch (self.graph.node(node_id).content) {
            .binding_use => |binding| if (self.inputIndex(function_id, binding)) |index|
                try self.oneInputPath(index, &.{})
            else
                self.place_bindings.get(binding) orelse &.{},
            .address_of => |value| self.inferInputPaths(function_id, value),
            .move_value, .denied_implicit_copy => |value| self.inferInputPaths(function_id, value),
            .dereference => |value| self.inferInputPaths(function_id, value.pointer),
            .explicit_cast => |cast| if (self.graph.types.items[@intFromEnum(cast.target_type)] == .pointer)
                self.inferInputPaths(function_id, cast.value)
            else
                &.{},
            .struct_field_access => |access| self.projectInputPaths(
                try self.inferInputPaths(function_id, access.value),
                .{ .field = access.field_index },
            ),
            .choice_payload_access => |access| blk: {
                const ty = self.graph.node(access.value).ty orelse break :blk &.{};
                const index = self.variantIndex(ty, access.variant) orelse break :blk &.{};
                break :blk try self.projectInputPaths(try self.inferInputPaths(function_id, access.value), .{ .variant = index });
            },
            .array_index => |index| self.projectInputPaths(
                try self.inferInputPaths(function_id, index.array_ptr),
                if (self.staticIndex(index.index)) |value| .{ .static_index = value } else .dynamic_index,
            ),
            else => &.{},
        };
    }

    fn substituteOutput(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        effect: facts.ValueEffect,
        arguments: []const graph_mod.ValueField,
    ) !facts.ValueEffect {
        return self.substituteOutputWithOverride(function_id, effect, arguments, null);
    }

    fn substituteOutputWithOverride(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        effect: facts.ValueEffect,
        arguments: []const graph_mod.ValueField,
        override: ?SymbolicInputOverride,
    ) !facts.ValueEffect {
        var result: facts.ValueEffect = .{
            .explicit_dependency = effect.explicit_dependency,
            .fresh_dependencies = effect.fresh_dependencies,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .unavailable_fresh_storage = effect.unavailable_fresh_storage,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
            .known_choice_variant = effect.known_choice_variant,
        };

        for (effect.input_storage_capabilities) |path| {
            if (path.input_index >= arguments.len) continue;
            var value = if (override) |symbolic|
                if (symbolic.input_index == path.input_index) symbolic.effect else try self.inferExpression(function_id, arguments[path.input_index].value)
            else
                try self.inferExpression(function_id, arguments[path.input_index].value);
            if ((try self.inferInputPaths(function_id, arguments[path.input_index].value)).len == 0) {
                if (try self.localPointeeEffect(function_id, arguments[path.input_index].value)) |pointee| value = pointee;
            }
            for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
            result = try self.mergeValueEffects(result, try self.scalar_storage_effect(value));
        }
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_places) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_places, candidate);
        }
        result.input_places = try input_places.toOwnedSlice();

        var input_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_generation_dependencies) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_generations, candidate);
        }
        result.input_generation_dependencies = try input_generations.toOwnedSlice();

        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        var input_place_value_overrides: facts.ValueEffect = .{};
        for (effect.input_place_values) |path| {
            if (path.input_index >= arguments.len) continue;
            if (override) |symbolic| if (symbolic.input_index == path.input_index) {
                var value = symbolic.effect;
                for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
                input_place_value_overrides = try self.mergeValueEffects(input_place_value_overrides, value);
                continue;
            };
            const argument = arguments[path.input_index].value;
            if ((try self.inferInputPaths(function_id, argument)).len == 0) {
                if (try self.localPointeeEffect(function_id, argument)) |pointee| {
                    var value = pointee;
                    for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
                    input_place_value_overrides = try self.mergeValueEffects(input_place_value_overrides, value);
                    continue;
                }
            }
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_place_values, candidate);
        }
        result.input_place_values = try input_place_values.toOwnedSlice();
        result = try self.mergeValueEffects(result, input_place_value_overrides);

        var input_owned_roots = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_owned_roots) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&input_owned_roots, candidate);
        }
        result.input_owned_roots = try input_owned_roots.toOwnedSlice();

        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.opaque_generation_dependencies) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&opaque_generations, candidate);
        }
        result.opaque_generation_dependencies = try opaque_generations.toOwnedSlice();

        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.opaque_storage_dependencies) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&opaque_storages, candidate);
        }
        result.opaque_storage_dependencies = try opaque_storages.toOwnedSlice();

        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            if (override) |symbolic| {
                if (symbolic.input_index == dependency.path.input_index and dependency.path.projections.len == 0)
                    continue;
            }
            var argument = if (override) |symbolic|
                if (symbolic.input_index == dependency.path.input_index)
                    symbolic.effect
                else
                    try self.inferExpression(function_id, arguments[dependency.path.input_index].value)
            else
                try self.inferExpression(function_id, arguments[dependency.path.input_index].value);
            if (dependency.validity_only and dependency.path.projections.len != 0 and dependency.path.projections[0] != .dereference) {
                if (try self.localPointeeEffect(function_id, arguments[dependency.path.input_index].value)) |pointee|
                    argument = pointee;
            }
            for (dependency.path.projections) |projection|
                argument = try self.projectValueEffect(argument, projection);
            argument = if (dependency.transfers_ownership)
                try self.withOwnershipTransfer(argument)
            else
                try self.withoutOwnershipTransfer(argument);
            if (dependency.validity_only) argument = try self.validityOnlyEffect(argument);
            result = try self.mergeValueEffects(result, argument);
        }

        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function_id, field.value.*, arguments, override);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.substituteOutputWithOverride(function_id, variant.value.*, arguments, override);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn substitutePaths(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        paths: []const facts.InputPath,
        arguments: []const graph_mod.ValueField,
    ) ![]const facts.InputPath {
        var result = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (paths) |path| {
            if (path.input_index >= arguments.len) continue;
            var direct = try self.inferInputPaths(function_id, arguments[path.input_index].value);
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            for (direct) |candidate| try appendInputPath(&result, candidate);
        }
        return result.toOwnedSlice();
    }

    fn projectValueEffect(self: *Infer, effect: facts.ValueEffect, projection: facts.Projection) !facts.ValueEffect {
        switch (projection) {
            .field => |field_index| {
                for (effect.fields) |field| if (field.index == field_index) return field.value.*;
            },
            .variant => |variant_index| {
                for (effect.variants) |variant| if (variant.index == variant_index) return variant.value.*;
            },
            else => {},
        }
        var result = effect;
        const dependencies = try self.allocator.alloc(facts.InputDependency, effect.input_dependencies.len);
        for (effect.input_dependencies, 0..) |dependency, index| {
            dependencies[index] = dependency;
            // Validity dependencies belong to the source lifetime, even when
            // selecting a field of the dependent value.
            if (!dependency.validity_only)
                dependencies[index].path.projections = try self.appendProjection(dependency.path.projections, projection);
        }
        result.input_dependencies = dependencies;
        result.input_storage_capabilities = try self.projectInputPaths(effect.input_storage_capabilities, projection);
        result.input_places = try self.projectInputPaths(effect.input_places, projection);
        // Borrowed generations describe the source value's lifetime, not
        // storage selected by a projection of that value.
        result.input_place_values = try self.projectInputPaths(effect.input_place_values, projection);
        result.input_owned_roots = try self.projectInputPaths(effect.input_owned_roots, projection);
        result.fields = &.{};
        result.variants = &.{};
        result.known_choice_variant = null;
        return result;
    }

    fn projectInputPaths(self: *Infer, paths: []const facts.InputPath, projection: facts.Projection) ![]const facts.InputPath {
        const result = try self.allocator.alloc(facts.InputPath, paths.len);
        for (paths, 0..) |path, index| result[index] = .{
            .input_index = path.input_index,
            .projections = try self.appendProjection(path.projections, projection),
        };
        return result;
    }

    fn appendProjection(self: *Infer, projections: []const facts.Projection, projection: facts.Projection) ![]const facts.Projection {
        const result = try self.allocator.alloc(facts.Projection, projections.len + 1);
        @memcpy(result[0..projections.len], projections);
        result[projections.len] = projection;
        return result;
    }

    fn mergeValueEffects(self: *Infer, left: facts.ValueEffect, right: facts.ValueEffect) !facts.ValueEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        for (left.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        for (right.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_places) |value| try appendInputPath(&input_places, value);
        for (right.input_places) |value| try appendInputPath(&input_places, value);
        var input_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_generation_dependencies) |value| try appendInputPath(&input_generations, value);
        for (right.input_generation_dependencies) |value| try appendInputPath(&input_generations, value);
        var input_place_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_place_values) |value| try appendInputPath(&input_place_values, value);
        for (right.input_place_values) |value| try appendInputPath(&input_place_values, value);
        var input_owned_roots = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_owned_roots) |value| try appendInputPath(&input_owned_roots, value);
        for (right.input_owned_roots) |value| try appendInputPath(&input_owned_roots, value);
        var opaque_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_generation_dependencies) |value| try appendInputPath(&opaque_generations, value);
        for (right.opaque_generation_dependencies) |value| try appendInputPath(&opaque_generations, value);
        var opaque_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.opaque_storage_dependencies) |value| try appendInputPath(&opaque_storages, value);
        for (right.opaque_storage_dependencies) |value| try appendInputPath(&opaque_storages, value);
        var fresh_dependencies = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_dependencies) |value| try appendFresh(&fresh_dependencies, value);
        for (right.fresh_dependencies) |value| try appendFresh(&fresh_dependencies, value);
        var fresh_owned = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_owned_roots) |value| try appendFresh(&fresh_owned, value);
        for (right.fresh_owned_roots) |value| try appendFresh(&fresh_owned, value);
        var fresh_capabilities = std.array_list.Managed(facts.FreshEffectSource).init(self.allocator);
        for (left.fresh_storage_capabilities) |value| try appendFresh(&fresh_capabilities, value);
        for (right.fresh_storage_capabilities) |value| try appendFresh(&fresh_capabilities, value);

        var fields = std.array_list.Managed(facts.OutputFieldEffect).init(self.allocator);
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

        var variants = std.array_list.Managed(facts.OutputVariantEffect).init(self.allocator);
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
            .explicit_dependency = left.explicit_dependency or right.explicit_dependency,
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_storage_capabilities = try self.union_input_paths(left.input_storage_capabilities, right.input_storage_capabilities),
            .input_places = try input_places.toOwnedSlice(),
            .input_generation_dependencies = try input_generations.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .input_owned_roots = try input_owned_roots.toOwnedSlice(),
            .opaque_generation_dependencies = try opaque_generations.toOwnedSlice(),
            .opaque_storage_dependencies = try opaque_storages.toOwnedSlice(),
            .fields = try fields.toOwnedSlice(),
            .variants = try variants.toOwnedSlice(),
            .known_choice_variant = if (left.variants.len == 0)
                right.known_choice_variant
            else if (right.variants.len == 0)
                left.known_choice_variant
            else if (left.known_choice_variant == right.known_choice_variant)
                left.known_choice_variant
            else
                null,
            .fresh_dependencies = try fresh_dependencies.toOwnedSlice(),
            .fresh_owned_roots = try fresh_owned.toOwnedSlice(),
            .integer_address = left.integer_address or right.integer_address,
            .foreign_storage = left.foreign_storage or right.foreign_storage,
            .fresh_storage_capabilities = try fresh_capabilities.toOwnedSlice(),
            .unavailable_fresh_storage = try self.merge_unavailable_fresh_storage(left.unavailable_fresh_storage, right.unavailable_fresh_storage),
        };
    }

    fn withOwnershipTransfer(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = true;
        result.input_dependencies = dependencies;
        return result;
    }

    fn withoutOwnershipTransfer(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        const dependencies = try self.allocator.dupe(facts.InputDependency, effect.input_dependencies);
        for (dependencies) |*dependency| dependency.transfers_ownership = false;
        result.input_dependencies = dependencies;
        return result;
    }

    /// Retain the input's lifetime without claiming its referent as the output's
    /// referent. Raw-address establishment chooses the latter independently.
    fn validityOnlyEffect(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        for (effect.input_dependencies) |dependency| {
            try appendInputDependency(&dependencies, .{ .path = dependency.path, .validity_only = true });
        }
        // A loaded anchor field contributes its stored reference lifetime,
        // rather than only the generation of the field containing it.
        for (effect.input_place_values) |path| try appendInputDependency(&dependencies, .{ .path = path, .validity_only = true });
        var generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_generation_dependencies) |path| try appendInputPath(&generations, path);
        for (effect.input_places) |path| try appendInputPath(&generations, path);
        return .{
            .explicit_dependency = effect.explicit_dependency,
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_generation_dependencies = try generations.toOwnedSlice(),
            .input_owned_roots = effect.input_owned_roots,
            .opaque_generation_dependencies = effect.opaque_generation_dependencies,
            .opaque_storage_dependencies = effect.opaque_storage_dependencies,
            .fresh_dependencies = effect.fresh_dependencies,
        };
    }

    fn choiceValueEffect(self: *Infer, variant_index: u32, payload: facts.ValueEffect) !facts.ValueEffect {
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, 1);
        const value = try self.allocator.create(facts.ValueEffect);
        value.* = payload;
        variants[0] = .{ .index = variant_index, .value = value };
        return .{ .variants = variants, .known_choice_variant = variant_index };
    }

    fn inputValueEffect(self: *Infer, input_index: u32, projections: []const facts.Projection) !facts.ValueEffect {
        const dependencies = try self.allocator.alloc(facts.InputDependency, 1);
        dependencies[0] = .{ .path = .{ .input_index = input_index, .projections = projections } };
        return .{ .input_dependencies = dependencies };
    }

    fn oneInputPath(self: *Infer, input_index: u32, projections: []const facts.Projection) ![]const facts.InputPath {
        const result = try self.allocator.alloc(facts.InputPath, 1);
        result[0] = .{ .input_index = input_index, .projections = projections };
        return result;
    }

    /// Symbolic transfer for one primitive invocation, with call-site identity.
    pub fn primitiveValueEffect(self: *Infer, primitive: primitives.SafetyPrimitive, source: facts.FreshEffectSource) !facts.ValueEffect {
        return switch (primitive_transfer.forPrimitive(primitive).value) {
            .reference_copy => self.withoutOwnershipTransfer(try self.inputValueEffect(0, &.{})),
            .allocation_slot => blk: {
                var result = try self.withoutOwnershipTransfer(try self.inputValueEffect(2, &.{}));
                result.input_owned_roots = try self.oneInputPath(0, &.{});
                break :blk result;
            },
            .restrict_reference, .depend_on => |transfer| blk: {
                var result = try self.mergeValueEffects(
                    if (transfer == .depend_on)
                        try self.inputValueEffect(0, &.{})
                    else
                        try self.withoutOwnershipTransfer(try self.inputValueEffect(0, &.{})),
                    try self.validityOnlyEffect(try self.inputValueEffect(1, &.{})),
                );
                result.explicit_dependency = transfer == .depend_on;
                break :blk result;
            },
            .empty, .relocate, .opaque_move, .opaque_relocate, .opaque_drop, .opaque_mark_empty => .{},
            .inherited_reference, .inherited_storage => self.validityOnlyEffect(try self.inputValueEffect(1, &.{})),
            .allocation => self.ownedAllocationEffect(source),
            .raw_storage => .{ .foreign_storage = true, .fresh_storage_capabilities = try self.oneFresh(source) },
            .opaque_move_out => .{
                .opaque_storage_dependencies = try self.oneInputPath(0, &.{}),
                .fresh_owned_roots = try self.oneFresh(source),
            },
        };
    }

    fn ownedAllocationEffect(self: *Infer, source: facts.FreshEffectSource) !facts.ValueEffect {
        // Keep this structural effect in the same order as Allocation. Raw
        // data carries the fresh lifetime. A backing-region anchor is copied
        // from the input without transferring ownership from the allocator.
        const shape = primitive_transfer.AllocationTransfer;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, shape.field_count);
        const empty = try self.allocator.create(facts.ValueEffect);
        empty.* = .{};
        for (fields, 0..) |*field, index| field.* = .{ .index = @intCast(index), .value = empty };
        const data = try self.allocator.create(facts.ValueEffect);
        data.* = .{ .fresh_dependencies = try self.oneFresh(source) };
        fields[shape.data_field].value = data;
        for (shape.borrowed_fields) |borrowed| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.withoutOwnershipTransfer(try self.inputValueEffect(borrowed.input, &.{}));
            fields[borrowed.field].value = value;
        }
        return .{ .fresh_owned_roots = try self.oneFresh(source), .fields = fields };
    }

    fn oneFresh(self: *Infer, source: facts.FreshEffectSource) ![]const facts.FreshEffectSource {
        const result = try self.allocator.alloc(facts.FreshEffectSource, 1);
        result[0] = source;
        return result;
    }

    fn rebaseFreshSources(self: *Infer, effect: facts.ValueEffect, call_node: graph_mod.GlobalNodeId) !facts.ValueEffect {
        var result = effect;
        result.fresh_dependencies = try self.rebaseFreshSlice(effect.fresh_dependencies, call_node);
        result.fresh_owned_roots = try self.rebaseFreshSlice(effect.fresh_owned_roots, call_node);
        result.fresh_storage_capabilities = try self.rebaseFreshSlice(effect.fresh_storage_capabilities, call_node);
        const unavailable = try self.allocator.alloc(facts.FreshStorageCapabilityState, effect.unavailable_fresh_storage.len);
        for (effect.unavailable_fresh_storage, 0..) |entry, index| {
            unavailable[index] = entry;
            unavailable[index].source = (try self.rebaseFreshSlice(&.{entry.source}, call_node))[0];
        }
        result.unavailable_fresh_storage = unavailable;
        if (effect.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
            for (effect.fields, 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.rebaseFreshSources(field.value.*, call_node);
                fields[index] = .{ .index = field.index, .value = value };
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.rebaseFreshSources(variant.value.*, call_node);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        return result;
    }

    fn union_input_paths(self: *Infer, left: []const facts.InputPath, right: []const facts.InputPath) ![]const facts.InputPath {
        var paths = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left) |path| try appendInputPath(&paths, path);
        for (right) |path| try appendInputPath(&paths, path);
        return paths.toOwnedSlice();
    }

    fn scalar_storage_effect(self: *Infer, effect: facts.ValueEffect) !facts.ValueEffect {
        var paths = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_storage_capabilities) |path| try appendInputPath(&paths, path);
        for (effect.input_dependencies) |dependency| if (!dependency.validity_only) {
            try appendInputPath(&paths, dependency.path);
        };
        for (effect.input_place_values) |path| try appendInputPath(&paths, path);
        return .{
            .input_storage_capabilities = try paths.toOwnedSlice(),
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .unavailable_fresh_storage = effect.unavailable_fresh_storage,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
        };
    }

    fn overlay_capability_outputs(self: *Infer, destination: facts.ValueEffect, origin: facts.ValueEffect, ty: graph_mod.GlobalTypeId) anyerror!facts.ValueEffect {
        var result = destination;
        if (self.graph.semanticType(ty) == .builtin) {
            const storage = try self.scalar_storage_effect(origin);
            result.input_storage_capabilities = storage.input_storage_capabilities;
            result.fresh_storage_capabilities = storage.fresh_storage_capabilities;
            result.unavailable_fresh_storage = storage.unavailable_fresh_storage;
            const validity = try self.allocator.dupe(facts.InputDependency, result.input_dependencies);
            for (validity) |*dependency| {
                dependency.validity_only = true;
                dependency.transfers_ownership = false;
            }
            result.input_dependencies = validity;
            return result;
        }
        if (types.fields(self.graph, ty)) |range| {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, range.len);
            for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
                const value = try self.allocator.create(facts.ValueEffect);
                const projection = facts.Projection{ .field = @intCast(index) };
                value.* = try self.overlay_capability_outputs(try self.projectValueEffect(destination, projection), try self.projectValueEffect(origin, projection), types.effectiveFieldType(field));
                fields[index] = .{ .index = @intCast(index), .value = value };
            }
            result.fields = fields;
        }
        if (types.variants(self.graph, ty)) |range| if (destination.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, destination.variants.len);
            for (destination.variants, 0..) |variant, index| {
                const payload_ty = self.graph.variants.items[range.start + variant.index].payload_type orelse {
                    variants[index] = variant;
                    continue;
                };
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.overlay_capability_outputs(variant.value.*, try self.projectValueEffect(origin, .{ .variant = variant.index }), payload_ty);
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        };
        return result;
    }

    fn merge_unavailable_fresh_storage(self: *Infer, left: []const facts.FreshStorageCapabilityState, right: []const facts.FreshStorageCapabilityState) ![]const facts.FreshStorageCapabilityState {
        var result = std.array_list.Managed(facts.FreshStorageCapabilityState).init(self.allocator);
        try result.appendSlice(left);
        for (right) |entry| {
            var found = false;
            for (result.items) |*previous| if (previous.source == entry.source) {
                previous.maybe_consumed = previous.maybe_consumed or entry.maybe_consumed;
                found = true;
                break;
            };
            if (!found) try result.append(entry);
        }
        return result.toOwnedSlice();
    }

    fn rebaseFreshSlice(self: *Infer, sources: []const facts.FreshEffectSource, call_node: graph_mod.GlobalNodeId) ![]const facts.FreshEffectSource {
        const result = try self.allocator.alloc(facts.FreshEffectSource, sources.len);
        const call_raw: u32 = @intFromEnum(call_node);
        for (sources, 0..) |source, index| {
            var hash = std.hash.Wyhash.init(0);
            hash.update(std.mem.asBytes(&call_raw));
            hash.update(std.mem.asBytes(&source));
            result[index] = @intCast(hash.final());
        }
        return result;
    }

    fn withOpaqueGenerationDependencies(self: *Infer, paths: []const facts.InputPath, effect: facts.ValueEffect) !facts.ValueEffect {
        var result = effect;
        var dependencies = std.array_list.Managed(facts.InputPath).init(self.allocator);
        try dependencies.appendSlice(effect.opaque_generation_dependencies);
        for (paths) |path| try appendInputPath(&dependencies, path);
        result.opaque_generation_dependencies = try dependencies.toOwnedSlice();
        return result;
    }

    fn opaqueGenerationSourcePaths(self: *Infer, effect: facts.ValueEffect) ![]const facts.InputPath {
        if (effect.input_places.len != 0) return effect.input_places;
        var paths = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_dependencies) |dependency| try appendInputPath(&paths, dependency.path);
        // Loading a reference from a field/choice payload borrows the value
        // at that input Place. Its dependencies must remain required when a
        // caller consumes the reference inside a scalar-returning wrapper.
        for (effect.input_place_values) |path| try appendInputPath(&paths, path);
        return paths.toOwnedSlice();
    }

    fn inputIndex(self: *Infer, function_id: graph_mod.GlobalFunctionId, binding: graph_mod.GlobalBindingId) ?u32 {
        const function = self.graph.function(function_id);
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len], 0..) |candidate, index|
            if (candidate == binding) return @intCast(index);
        return null;
    }

    fn outputIndex(self: *Infer, function_id: graph_mod.GlobalFunctionId, binding: graph_mod.GlobalBindingId) ?usize {
        const function = self.graph.function(function_id);
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len], 0..) |candidate, index|
            if (candidate == binding) return index;
        return null;
    }

    fn variantIndex(self: *Infer, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId) ?u32 {
        const range = types.variants(self.graph, ty) orelse return null;
        const raw = @intFromEnum(variant);
        if (raw < range.start or raw >= range.start + range.len) return null;
        return raw - range.start;
    }

    fn staticIndex(self: *Infer, node_id: graph_mod.GlobalNodeId) ?u32 {
        return switch (self.graph.node(node_id).content) {
            .int_literal => |value| if (value >= 0 and value <= std.math.maxInt(u32)) @intCast(value) else null,
            else => null,
        };
    }

    fn typeContainsPointer(self: *Infer, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.resolvedSemanticType(ty) orelse return false) {
            .pointer, .virtual => true,
            .array => |array| self.typeContainsPointer(array.element),
            .nullable => |child| self.typeContainsPointer(child),
            .inferred_errable => |child| self.typeContainsPointer(child),
            .structural, .declared, .generic => blk: {
                const range = types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[range.start..][0..range.len]) |field|
                    if (self.typeContainsPointer(types.effectiveFieldType(field))) break :blk true;
                break :blk false;
            },
            .structural_choice, .inferred_choice => blk: {
                const range = types.variants(self.graph, ty) orelse break :blk false;
                for (self.graph.variants.items[range.start..][0..range.len]) |variant|
                    if (variant.payload_type) |payload| if (self.typeContainsPointer(payload)) break :blk true;
                break :blk false;
            },
            .builtin => false,
        };
    }

    fn freshSource(self: *Infer, node: graph_mod.GlobalNodeId, role: u32) facts.FreshEffectSource {
        _ = self;
        const node_raw: u32 = @intFromEnum(node);
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&node_raw));
        hash.update(std.mem.asBytes(&role));
        return @intCast(hash.final());
    }
};

fn virtualInputPostStatesRuntimeRepresentable(states: []const facts.PlacePostState) bool {
    for (states) |state| if (!virtualInputPostStateRuntimeRepresentable(state)) return false;
    return true;
}

fn virtualInputPostStateRuntimeRepresentable(state: facts.PlacePostState) bool {
    return state.initializedness == .initialized and state.opaque_ownership == .none;
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
            while (iterator.next()) |entry|
                if (entry.value_ptr.* == canonical_source and entry.key_ptr.* != candidate_source) return false;
            try mapping.put(candidate_source, canonical_source);
        }
    }
    return true;
}

fn mergeVirtualFreshRoots(
    allocator: std.mem.Allocator,
    canonical: []const facts.FreshEffectSource,
    candidate: []const facts.FreshEffectSource,
    mapping: *std.AutoHashMap(facts.FreshEffectSource, facts.FreshEffectSource),
) !?[]const facts.FreshEffectSource {
    // A fresh temporal identity can conservatively represent either a
    // separately released allocation or a child of a shared region. The
    // latter still carries its region dependency through the other effects.
    if (candidate.len == 0) return canonical;
    if (canonical.len == 0) {
        const result = try allocator.dupe(facts.FreshEffectSource, candidate);
        for (result) |*source| {
            if (mapping.get(source.*)) |mapped| {
                source.* = mapped;
            } else {
                try mapping.put(source.*, source.*);
            }
        }
        return result;
    }
    if (canonical.len != candidate.len or !try alignFreshSources(canonical, candidate, mapping)) return null;
    return canonical;
}

fn containsInputDependency(haystack: []const facts.InputDependency, needle: facts.InputDependency) bool {
    for (haystack) |candidate| {
        if (candidate.path.input_index != needle.path.input_index or
            candidate.transfers_ownership != needle.transfers_ownership or
            candidate.validity_only != needle.validity_only or
            candidate.path.projections.len != needle.path.projections.len) continue;
        var equal = true;
        for (candidate.path.projections, needle.path.projections) |left, right| if (!std.meta.eql(left, right)) {
            equal = false;
            break;
        };
        if (equal) return true;
    }
    return false;
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

fn pointerUseOperand(content: graph_mod.Node.Content) ?graph_mod.GlobalNodeId {
    return switch (content) {
        .dereference => |value| value.pointer,
        .array_index => |value| value.array_ptr,
        .array_store => |value| value.array_ptr,
        .struct_field_store => |value| value.struct_ptr,
        else => null,
    };
}

fn appendInputPath(list: *std.array_list.Managed(facts.InputPath), path: facts.InputPath) !void {
    for (list.items) |existing| {
        if (existing.input_index != path.input_index or existing.projections.len != path.projections.len) continue;
        var equal = true;
        for (existing.projections, path.projections) |left, right| if (!std.meta.eql(left, right)) {
            equal = false;
            break;
        };
        if (equal) return;
    }
    try list.append(path);
}

fn appendInputDependency(list: *std.array_list.Managed(facts.InputDependency), dependency: facts.InputDependency) !void {
    for (list.items) |existing| {
        if (existing.transfers_ownership != dependency.transfers_ownership or
            existing.validity_only != dependency.validity_only) continue;
        var paths = std.array_list.Managed(facts.InputPath).init(list.allocator);
        defer paths.deinit();
        try paths.append(existing.path);
        const before = paths.items.len;
        try appendInputPath(&paths, dependency.path);
        if (paths.items.len == before) return;
    }
    try list.append(dependency);
}

fn appendFresh(list: *std.array_list.Managed(facts.FreshEffectSource), source: facts.FreshEffectSource) !void {
    for (list.items) |existing| if (existing == source) return;
    try list.append(source);
}

test "output summaries reach a fixed point through reverse call dependencies" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const int_ty: graph_mod.GlobalTypeId = @enumFromInt(0);
    const pointer_ty: graph_mod.GlobalTypeId = @enumFromInt(1);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .pointer = .{ .child = int_ty, .mutability = .read_only } });
    const empty_name = try graph.addString(allocator, "");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };

    // wrapper(input0) -> output1 = identity(input0)
    // identity(input2) -> output3 = input2
    for (0..4) |_| try graph.bindings.append(allocator, .{
        .name = empty_name,
        .source = source,
        .ty = pointer_ty,
        .mutability = .variable,
    });
    try graph.binding_refs.appendSlice(allocator, &.{
        @as(graph_mod.GlobalBindingId, @enumFromInt(0)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(1)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(2)),
        @as(graph_mod.GlobalBindingId, @enumFromInt(3)),
    });

    const n0: graph_mod.GlobalNodeId = @enumFromInt(0);
    const n1: graph_mod.GlobalNodeId = @enumFromInt(1);
    const n2: graph_mod.GlobalNodeId = @enumFromInt(2);
    const n3: graph_mod.GlobalNodeId = @enumFromInt(3);
    const n4: graph_mod.GlobalNodeId = @enumFromInt(4);
    const n5: graph_mod.GlobalNodeId = @enumFromInt(5);
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .binding_use = @enumFromInt(0) } });
    try graph.value_fields.append(allocator, .{ .name = empty_name, .value = n0 });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .function_call = .{ .callee = @enumFromInt(1), .input = n1 } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(1), .value = n2 } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .binding_use = @enumFromInt(2) } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .assignment = .{ .binding = @enumFromInt(3), .value = n4 } } });
    const n6: graph_mod.GlobalNodeId = @enumFromInt(6);
    try graph.nodes.append(allocator, .{ .source = source, .ty = int_ty, .content = .{ .dereference = .{ .pointer = n4, .ty = int_ty, .pointer_type = pointer_ty } } });
    try graph.node_refs.appendSlice(allocator, &.{ n3, n6, n5 });
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 1 } });
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 1, .len = 2 } });

    // Declaration identity is irrelevant to summary inference; valid slots keep
    // graph invariants intact for other consumers.
    for (0..2) |_| try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = empty_name,
        .source = source,
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(0),
        .input_bindings = .{ .start = 0, .len = 1 },
        .output_bindings = .{ .start = 1, .len = 1 },
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .body = @enumFromInt(1),
        .input_bindings = .{ .start = 2, .len = 1 },
        .output_bindings = .{ .start = 3, .len = 1 },
    });
    try graph.function_operators.appendSlice(allocator, &.{ null, null });

    // An unrelated extern population must not add inference work or prevent
    // convergence of callers whose summaries do carry effects.
    for (0..128) |_| {
        const declaration: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(graph.declarations.items.len)));
        try graph.declarations.append(allocator, .{ .kind = .function, .name = empty_name, .source = source });
        try graph.functions.append(allocator, .{
            .declaration = declaration,
            .input = .{ .start = 0, .len = 0 },
            .output = .{ .start = 0, .len = 0 },
            .body = null,
            .input_bindings = .{ .start = 0, .len = 0 },
            .output_bindings = .{ .start = 0, .len = 0 },
        });
        try graph.function_operators.append(allocator, null);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const summary_allocator = arena.allocator();
    var engine = summaries.Engine.init(summary_allocator);
    defer engine.deinit();
    var infer = Infer.init(summary_allocator, &graph, &engine);
    defer infer.deinit();
    try infer.inferSafetySummariesFixedPoint();
    try std.testing.expect(infer.evaluations < graph.functions.items.len);

    const wrapper = engine.summaries.get(@enumFromInt(0)).?;
    const identity = engine.summaries.get(@enumFromInt(1)).?;
    try std.testing.expectEqual(@as(usize, 1), identity.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), identity.outputs[0].input_dependencies.len);
    try std.testing.expectEqual(@as(u32, 0), identity.outputs[0].input_dependencies[0].path.input_index);
    try std.testing.expectEqual(@as(usize, 1), wrapper.outputs[0].input_dependencies.len);
    try std.testing.expectEqual(@as(u32, 0), wrapper.outputs[0].input_dependencies[0].path.input_index);

    try std.testing.expectEqual(@as(usize, 1), identity.required_live_inputs.len);
    try std.testing.expectEqual(@as(u32, 0), identity.required_live_inputs[0].input_index);
    try std.testing.expectEqual(@as(usize, 1), wrapper.required_live_inputs.len);
    try std.testing.expectEqual(@as(u32, 0), wrapper.required_live_inputs[0].input_index);
    try expectGlobalReseedingStable(&infer);

    // Add a back edge while preserving identity's local source of effects.
    // Reversing the function IDs then exercises both initial scheduling orders.
    const back_input: graph_mod.GlobalNodeId = @enumFromInt(7);
    const back_call: graph_mod.GlobalNodeId = @enumFromInt(8);
    try graph.value_fields.append(allocator, .{ .name = empty_name, .value = n4 });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 1, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = pointer_ty, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = back_input } } });
    try graph.node_refs.append(allocator, back_call);
    graph.blocks.items[1].nodes.len = 3;
    for (0..2) |order| {
        if (order == 1) {
            std.mem.swap(graph_mod.Function, &graph.functions.items[0], &graph.functions.items[1]);
            graph.nodes.items[@intFromEnum(n2)].content.function_call.callee = @enumFromInt(0);
            graph.nodes.items[@intFromEnum(back_call)].content.function_call.callee = @enumFromInt(1);
        }
        var recursive_engine = summaries.Engine.init(summary_allocator);
        defer recursive_engine.deinit();
        var recursive_infer = Infer.init(summary_allocator, &graph, &recursive_engine);
        defer recursive_infer.deinit();
        try recursive_infer.inferSafetySummariesFixedPoint();
        for (0..2) |raw| {
            const summary = recursive_engine.summaries.get(@enumFromInt(raw)).?;
            try std.testing.expect(summaries.summaryEql(identity, summary));
        }
        try expectGlobalReseedingStable(&recursive_infer);
    }
}

/// A complete global sweep must observe the same summaries after dependency
/// convergence. This compares all dimensions through the engine's equality,
/// independently of whether a missing dependency would schedule an observer.
fn expectGlobalReseedingStable(infer: *Infer) !void {
    for (infer.graph.functions.items, 0..) |_, raw| {
        const function: graph_mod.GlobalFunctionId = @enumFromInt(raw);
        infer.virtual_summaries.clearRetainingCapacity();
        infer.invalid_virtual_summaries.clearRetainingCapacity();
        infer.engine.beginInference(function);
        const next = try infer.inferFunction(function);
        try infer.engine.endInference();
        try std.testing.expect(summaries.summaryEql(infer.engine.summaries.get(function).?, next));
    }
}

test "input post-state joins retain caller-visible transitions" {
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    var engine = summaries.Engine.init(std.testing.allocator);
    defer engine.deinit();
    var inference = Infer.init(std.testing.allocator, &graph, &engine);
    defer inference.deinit();

    var states = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer states.deinit();
    const target = facts.InputPath{ .input_index = 0 };

    try inference.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expectEqual(@as(usize, 1), states.items.len);
    try std.testing.expectEqual(value_state.Initializedness.initialized, states.items[0].initializedness);
    try std.testing.expect(!states.items[0].refreshes_storage_generation);

    try inference.recordInputPostState(&states, &.{target}, .deinitialized, .{}, true, false, false, false);
    try inference.recordInputPostState(&states, &.{target}, .initialized, .{}, false, false, false, false);
    try std.testing.expect(states.items[0].refreshes_storage_generation);

    var changed = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer changed.deinit();
    try changed.append(.{ .target = target, .initializedness = .moved });
    var unchanged = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer unchanged.deinit();
    var joined = std.array_list.Managed(facts.PlacePostState).init(std.testing.allocator);
    defer joined.deinit();
    try inference.joinInputPostStates(&joined, &changed, &unchanged);
    try std.testing.expectEqual(value_state.Initializedness.maybe_initialized, joined.items[0].initializedness);
}

test "repopulation under an ended ancestor does not survive a summary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, &graph, &engine);
    defer inference.deinit();

    const child_projections = [_]facts.Projection{.{ .field = 0 }};
    const states = [_]facts.PlacePostState{
        .{
            .target = .{ .input_index = 0, .projections = &child_projections },
            .initializedness = .initialized,
            .may_repopulate_opaque_storage = true,
        },
        .{
            .target = .{ .input_index = 0 },
            .initializedness = .deinitialized,
        },
    };
    try std.testing.expect(!inference.summaryMayRepopulateOpaqueStorage(.{ .input_post_states = &states }));

    const unrelated = [_]facts.PlacePostState{
        states[0],
        .{
            .target = .{ .input_index = 1 },
            .initializedness = .deinitialized,
        },
    };
    try std.testing.expect(inference.summaryMayRepopulateOpaqueStorage(.{ .input_post_states = &unrelated }));
}
test "opaque ownership post-state joins preserve storage correlation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, &graph, &engine);
    defer inference.deinit();

    const target = facts.InputPath{ .input_index = 0 };
    const storage = facts.InputPath{ .input_index = 1 };
    const other_storage = facts.InputPath{ .input_index = 2 };
    var opaque_branch = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer opaque_branch.deinit();
    try inference.recordOpaqueOwnershipConsumption(&opaque_branch, &.{target}, .definite, storage);
    var plain = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer plain.deinit();
    var conditional = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer conditional.deinit();
    try inference.joinInputPostStates(&conditional, &opaque_branch, &plain);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.conditional, conditional.items[0].opaque_ownership);
    try std.testing.expect(inference.optionalInputPathEqual(storage, conditional.items[0].opaque_storage));

    var other = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer other.deinit();
    try inference.recordOpaqueOwnershipConsumption(&other, &.{target}, .definite, other_storage);
    var ambiguous = std.array_list.Managed(facts.PlacePostState).init(allocator);
    defer ambiguous.deinit();
    try inference.joinInputPostStates(&ambiguous, &opaque_branch, &other);
    try std.testing.expectEqual(facts.OpaqueOwnershipConsumption.ambiguous, ambiguous.items[0].opaque_ownership);
    try std.testing.expect(ambiguous.items[0].opaque_storage == null);
}

fn joinInitializedness(left: value_state.Initializedness, right: value_state.Initializedness) value_state.Initializedness {
    if (left == right) return left;
    return .maybe_initialized;
}

test "virtual summaries align fresh roles and reject ownership mismatches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, &graph, &engine);
    defer infer.deinit();

    const left_source: facts.FreshEffectSource = 11;
    const right_source: facts.FreshEffectSource = 29;
    const compatible = try infer.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .fresh_dependencies = &.{left_source}, .fresh_owned_roots = &.{left_source} }} },
        .{ .outputs = &.{.{ .fresh_dependencies = &.{right_source}, .fresh_owned_roots = &.{right_source} }} },
    );
    try std.testing.expect(compatible != null);
    try std.testing.expectEqual(left_source, compatible.?.outputs[0].fresh_dependencies[0]);
    try std.testing.expectEqual(left_source, compatible.?.outputs[0].fresh_owned_roots[0]);

    const region_dependency = facts.InputDependency{ .path = .{ .input_index = 0 } };
    const separately_released = facts.SafetySummary{
        .outputs = &.{.{ .fresh_dependencies = &.{left_source}, .fresh_owned_roots = &.{left_source} }},
    };
    const region_child = facts.SafetySummary{
        .outputs = &.{.{ .input_dependencies = &.{region_dependency} }},
    };
    const heap_first = (try infer.mergeVirtualSafetySummary(separately_released, region_child)).?;
    const region_first = (try infer.mergeVirtualSafetySummary(region_child, separately_released)).?;
    for ([_]facts.SafetySummary{ heap_first, region_first }) |merged| {
        try std.testing.expectEqualSlices(facts.FreshEffectSource, &.{left_source}, merged.outputs[0].fresh_owned_roots);
        try std.testing.expectEqual(@as(usize, 1), merged.outputs[0].input_dependencies.len);
    }

    const transfer = facts.InputDependency{ .path = .{ .input_index = 0 }, .transfers_ownership = true };
    try std.testing.expect((try infer.mergeVirtualSafetySummary(
        .{ .outputs = &.{.{ .input_dependencies = &.{transfer} }} },
        .{ .outputs = &.{.{}} },
    )) == null);
}

test "virtual summary merge preserves fresh identity across output fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, &graph, &engine);
    defer infer.deinit();

    const empty = facts.ValueEffect{};
    const left_root = facts.ValueEffect{ .fresh_dependencies = &.{11}, .fresh_owned_roots = &.{11} };
    const right_root = facts.ValueEffect{ .fresh_dependencies = &.{29}, .fresh_owned_roots = &.{29} };
    const left = facts.SafetySummary{ .outputs = &.{.{ .fields = &.{
        .{ .index = 0, .value = &empty },
        .{ .index = 1, .value = &left_root },
    } }} };
    const right = facts.SafetySummary{ .outputs = &.{.{ .fields = &.{
        .{ .index = 0, .value = &right_root },
        .{ .index = 1, .value = &right_root },
    } }} };
    const merged_optional_first = (try infer.mergeVirtualSafetySummary(left, right)).?;
    try std.testing.expectEqual(@as(facts.FreshEffectSource, 11), merged_optional_first.outputs[0].fields[0].value.fresh_owned_roots[0]);
    try std.testing.expectEqual(@as(facts.FreshEffectSource, 11), merged_optional_first.outputs[0].fields[1].value.fresh_owned_roots[0]);

    const aligned_first = facts.SafetySummary{ .outputs = &.{.{ .fields = &.{
        .{ .index = 0, .value = &left_root },
        .{ .index = 1, .value = &empty },
    } }} };
    const merged = (try infer.mergeVirtualSafetySummary(aligned_first, right)).?;
    try std.testing.expectEqual(@as(facts.FreshEffectSource, 11), merged.outputs[0].fields[0].value.fresh_owned_roots[0]);
    try std.testing.expectEqual(@as(facts.FreshEffectSource, 11), merged.outputs[0].fields[1].value.fresh_owned_roots[0]);

    const second_left_root = facts.ValueEffect{ .fresh_dependencies = &.{17}, .fresh_owned_roots = &.{17} };
    const incompatible_left = facts.SafetySummary{ .outputs = &.{.{ .fields = &.{
        .{ .index = 0, .value = &left_root },
        .{ .index = 1, .value = &second_left_root },
    } }} };
    try std.testing.expect((try infer.mergeVirtualSafetySummary(incompatible_left, right)) == null);
}

test "virtual summaries intersect opaque empty guarantees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, &graph, &engine);
    defer infer.deinit();

    const emptied = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    const same = try infer.mergeVirtualSafetySummary(
        .{ .opaque_storage_empties = &.{emptied} },
        .{ .opaque_storage_empties = &.{emptied} },
    );
    try std.testing.expectEqual(@as(usize, 1), same.?.opaque_storage_empties.len);
    const absent = try infer.mergeVirtualSafetySummary(
        .{ .opaque_storage_empties = &.{emptied} },
        .{},
    );
    try std.testing.expectEqual(@as(usize, 0), absent.?.opaque_storage_empties.len);
}

test "validity-only transfer retains loaded input anchor paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, undefined, &engine);
    defer inference.deinit();
    const projections = [_]facts.Projection{.{ .field = 3 }};
    const path = facts.InputPath{ .input_index = 0, .projections = &projections };
    const effect = try inference.validityOnlyEffect(.{ .input_place_values = &.{path} });
    try std.testing.expectEqual(@as(usize, 1), effect.input_dependencies.len);
    try std.testing.expect(effect.input_dependencies[0].validity_only);
    try std.testing.expect(!effect.input_dependencies[0].transfers_ownership);
    try std.testing.expectEqualDeep(path, effect.input_dependencies[0].path);
    try std.testing.expectEqual(@as(usize, 0), effect.input_place_values.len);
    const projected = try inference.projectValueEffect(effect, .{ .field = 7 });
    try std.testing.expectEqualDeep(path, projected.input_dependencies[0].path);
}
