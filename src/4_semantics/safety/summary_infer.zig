const lifecycle_contracts = @import("../global/lifecycle_contracts.zig");
const std = @import("std");
const profile = @import("../../1_base/profile.zig");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const primitives = @import("../primitives/schema.zig");
const facts = @import("facts.zig");
const summaries = @import("summaries.zig");
const value_state = @import("value_state.zig");
const outcome_selectors = @import("outcome_selectors.zig");
const contracts = @import("contracts.zig");
const cleanup_activation = @import("cleanup_activation.zig");
const primitive_transfer = @import("../primitives/registry.zig");

/// Symbolic SafetySummary inference over the compact GlobalSG.
///
/// This is the indexed counterpart of the old checker's `inferBlock` /
/// `inferExpression` layer. Runtime validation must not be used to discover
/// recursive effects: this pass describes outputs in terms of function inputs
/// and lets `summaries.Engine` iterate callers/SCCs to a fixed point.
pub const Infer = struct {
    cleanup: ?*const cleanup_activation.Activation = null,
    cleanup_activations: std.AutoHashMap(graph_mod.GlobalFunctionId, cleanup_activation.Activation),
    profile_io: ?std.Io = null,
    output_ns: u64 = 0,
    required_live_ns: u64 = 0,
    // Both requirement scans share control-flow and cleanup traversal. Their
    // obligations remain separate so metadata access does not read elements.
    collecting_opaque_requirements: bool = false,
    post_state_ns: u64 = 0,
    outcome_ns: u64 = 0,
    opaque_ns: u64 = 0,
    unbound_opaque_dependencies: facts.ValueEffect = .{},
    opaque_empty_seen: bool = false,
    virtual_summary_ns: u64 = 0,
    evaluations: u64 = 0,
    summary_changes: u64 = 0,
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    engine: *summaries.Engine,
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect),
    place_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath),
    local_address_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, []const graph_mod.GlobalNodeId),
    addressed_outputs: std.AutoHashMap(graph_mod.GlobalBindingId, void),
    virtual_summaries: std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, facts.SafetySummary),
    domain_invalidations: std.array_list.Managed(facts.InputDomain),
    requested_selectors: std.AutoHashMap(graph_mod.GlobalFunctionId, []const outcome_selectors.Selector),
    selected_outcome: ?struct { output_index: u32, parent_variants: []const u32 = &.{}, variant_index: u32, binding: graph_mod.GlobalBindingId } = null,
    forwarded_outcome: ?outcome_selectors.Selector = null,
    forwarded_leaf_selected: bool = false,
    selected_forward: ?struct { call: graph_mod.GlobalNodeId, selector: outcome_selectors.Selector } = null,
    selected_forward_applied: bool = false,

    post_domain_sink: ?*std.array_list.Managed(facts.InputDomain) = null,
    loop_post_effects: ?*InputPostStateFlow = null,

    const ForwardOrigin = struct {
        call: graph_mod.GlobalNodeId,
        // A multi-output call is a result record until one field is selected.
        output_index: ?u32 = 0,
        parent_variants: []const u32 = &.{},
    };

    pub fn init(
        allocator: std.mem.Allocator,
        graph: *const graph_mod.GlobalSemanticGraph,
        engine: *summaries.Engine,
    ) Infer {
        return .{
            .requested_selectors = .init(allocator),
            .cleanup_activations = .init(allocator),
            .allocator = allocator,
            .graph = graph,
            .engine = engine,
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, facts.ValueEffect).init(allocator),
            .place_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, []const facts.InputPath).init(allocator),
            .local_address_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, []const graph_mod.GlobalNodeId).init(allocator),
            .addressed_outputs = std.AutoHashMap(graph_mod.GlobalBindingId, void).init(allocator),
            .virtual_summaries = std.AutoHashMap(graph_mod.GlobalVirtualRegistryId, facts.SafetySummary).init(allocator),
            .domain_invalidations = std.array_list.Managed(facts.InputDomain).init(allocator),
        };
    }

    pub fn deinit(self: *Infer) void {
        var activations = self.cleanup_activations.valueIterator();
        while (activations.next()) |activation| activation.deinit();
        self.cleanup_activations.deinit();
        self.requested_selectors.deinit();
        self.bindings.deinit();
        self.place_bindings.deinit();
        self.local_address_bindings.deinit();
        self.addressed_outputs.deinit();
        self.virtual_summaries.deinit();
        self.domain_invalidations.deinit();
    }

    /// Infer every SafetySummary dimension until reverse dependencies are stable:
    /// outputs, pointer/opaque-content requirements, input/outcome post-states,
    /// and opaque effects.
    /// Reading a previous approximation records a dependency, including the
    /// function's own approximation. Virtual effects come from fixed contracts,
    /// independently of implementation reachability and conformance checks.
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
                    outputs[0] = try @import("foreign_result.zig").value(facts.ValueEffect, self.allocator, self.graph, ty);
                }
                try self.engine.summaries.put(id, .{ .outputs = outputs });
            }
            if (function.flags.has_foreign_capability) {
                // Authorization must remain live even for imports whose other
                // storage effects are unknown. Callers compose this requirement
                // through the same summary dependency paths as dereferences.
                self.engine.summaries.getPtr(id).?.required_live_inputs = try self.allocator.dupe(facts.InputPath, &.{.{ .input_index = function.input.len - 1, .projections = &.{} }});
            }
            if (function.safety_primitive == .trusted_opaque_drop) {
                self.engine.summaries.getPtr(id).?.required_opaque_inputs = try self.oneInputPath(0, &.{});
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
        // Concrete summaries need enough selectors to prove their declarations.
        // These hints select precision only; they never infer virtual effects
        // from concrete implementations or depend on their final summaries.
        for (self.graph.abstract_safety_conformances.items) |proof| try self.requestContractSelectors(proof.method, proof.contract);
        for (self.graph.virtualizes.items) |virtualize| {
            for (self.graph.virtual_registry_refs.items[virtualize.safety_methods.start..][0..virtualize.safety_methods.len], 0..) |registry_id, index| {
                const declared = self.graph.virtual_registries.items[@intFromEnum(registry_id)].safety_contract orelse continue;
                try self.requestContractSelectors(self.graph.function_refs.items[virtualize.methods.start + index], declared);
            }
        }
        try self.engine.seed(functions.items);
        while (self.engine.nextDirty()) |function| {
            self.evaluations += 1;
            self.engine.beginInference(function);
            const next = self.inferFunction(function) catch |err| {
                self.engine.current = null;
                return err;
            };
            try self.engine.endInference();
            if (try self.engine.updateSummary(function, next)) self.summary_changes += 1;
        }
    }

    pub fn virtualSummary(
        self: *Infer,
        registry_id: graph_mod.GlobalVirtualRegistryId,
    ) !?facts.SafetySummary {
        const start = profile.timestamp(self.profile_io);
        defer profile.accumulate(self.profile_io, start, &self.virtual_summary_ns);
        if (self.virtual_summaries.get(registry_id)) |summary| return summary;
        const registry = self.graph.virtual_registries.items[@intFromEnum(registry_id)];
        if (registry.contract_input_count) |input_count| {
            const declared = registry.safety_contract orelse return error.MissingVirtualSafetyContract;
            // This summary depends on the declaration and fixed signature only.
            // Concrete summaries are read separately for conformance after the
            // fixed point. Only an explicit referent clause can select an input's
            // storage; dependency permissions alone never establish aliases.
            const contract = try @import("contracts.zig").fromDeclaration(self.allocator, declared);
            if (contract.general_conditions) {
                const result = try self.generalVirtualSummary(registry_id, contract);
                try self.virtual_summaries.put(registry_id, result);
                return result;
            }
            const outputs = try self.allocator.alloc(facts.ValueEffect, contract.outputs.len);
            for (contract.outputs, outputs, 0..) |allowed, *output, index| {
                if (registry.contract_output_type) |ty| {
                    const fields = types.fields(self.graph, ty) orelse return error.InvalidContractOutput;
                    const field = self.graph.fields.items[fields.start + index];
                    output.* = try @import("contract_outputs.zig").build(self.allocator, self.graph, field.ty, allowed, @as(usize, @truncate(std.hash.Wyhash.hash(@intFromEnum(registry_id), std.mem.asBytes(&index)))));
                } else {
                    const dependencies = try self.allocator.alloc(facts.InputDependency, allowed.dependencies.len);
                    for (allowed.dependencies, dependencies) |path, *dependency| dependency.* = .{
                        .path = path,
                        .validity_only = if (allowed.referent) |referent| path.input_index != referent.input_index else true,
                    };
                    output.* = .{ .input_dependencies = dependencies, .input_domains = allowed.domains, .opaque_storage_dependencies = allowed.storage_sources, .explicit_dependency = dependencies.len != 0 or allowed.domains.len != 0 };
                }
            }
            for (outputs) |*output| output.* = try self.bindVirtualReceiverValues(output.*, registry.receiver_input_index);
            var required_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
            for (0..input_count) |index| {
                var destination = false;
                for (contract.relocations) |relocation| if (relocation.destination.input_index == index) {
                    destination = true;
                    break;
                };
                for (contract.outcomes) |outcome| for (outcome.effects.relocations) |relocation| {
                    if (relocation.destination.input_index == index) destination = true;
                };
                if (!destination) try required_inputs.append(.{ .input_index = @intCast(index) });
            }
            const required = try required_inputs.toOwnedSlice();
            const post_states = try self.allocator.alloc(facts.PlacePostState, contract.invalidates.len + contract.consumed_inputs.len + contract.relocations.len * 2 + contract.retained_inputs.len);
            for (contract.invalidates, post_states[0..contract.invalidates.len]) |path, *post_state| post_state.* = .{
                .target = path,
                .initializedness = .initialized,
                .refreshes_storage_generation = true,
            };
            for (contract.consumed_inputs, post_states[contract.invalidates.len..][0..contract.consumed_inputs.len]) |path, *post_state| post_state.* = .{
                .target = path,
                .initializedness = .deinitialized,
                .ends_previous_roots = true,
            };
            for (contract.relocations, 0..) |relocation, index| {
                const offset = contract.invalidates.len + contract.consumed_inputs.len + index * 2;
                post_states[offset] = .{ .target = relocation.source, .initializedness = .moved };
                post_states[offset + 1] = .{
                    .target = relocation.destination,
                    .initializedness = .initialized,
                    .value = .{ .input_place_values = try self.allocator.dupe(facts.InputPath, &.{relocation.source}) },
                    .requires_available_destination = true,
                    .refreshes_storage_generation = true,
                };
            }
            for (contract.retained_inputs, post_states[contract.invalidates.len + contract.consumed_inputs.len + contract.relocations.len * 2 ..]) |retention, *post| post.* = .{
                .target = retention.input,
                .initializedness = .initialized,
                .opaque_ownership = .conditional,
                .opaque_storage = retention.storage,
            };
            const invalidated_domains = try self.allocator.alloc(facts.InputDomain, declared.invalidated_domains.len);
            for (declared.invalidated_domains, invalidated_domains) |domain, *effect| effect.* = .{ .path = .{ .input_index = domain.input_index }, .domain_index = domain.domain_index };
            var conditional = std.array_list.Managed(facts.OutcomePostStates).init(self.allocator);
            // Every variant gets a record, including preservation alternatives.
            // Effect guards describe inputs independently of output payload facts.
            var wanted = std.array_list.Managed(outcome_selectors.Selector).init(self.allocator);
            defer wanted.deinit();
            for (contract.outcomes) |outcome| try wanted.append(.{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index });
            for (outputs, 0..) |_, output_index| {
                var guarded_generation = false;
                for (contract.outcomes) |outcome| if (outcome.output_index == output_index and (outcome.effects.invalidates.len != 0 or outcome.effects.invalidated_domains.len != 0 or outcome.effects.consumed_inputs.len != 0 or outcome.effects.relocations.len != 0 or outcome.effects.emptied_inputs.len != 0)) {
                    guarded_generation = true;
                    break;
                };
                if (!guarded_generation) continue;
                const output_ty = registry.contract_output_type orelse continue;
                const fields = types.fields(self.graph, output_ty) orelse continue;
                const ty = self.graph.fields.items[fields.start + @as(u32, @intCast(output_index))].ty;
                for (try outcome_selectors.partition(self.allocator, self.graph, @intCast(output_index), ty, wanted.items)) |selector| {
                    const effects = contracts.effectsForSelector(contract, selector);
                    var states = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
                    for (effects.invalidates) |path| try states.append(.{ .target = path, .initializedness = .initialized, .refreshes_storage_generation = true });
                    for (effects.consumed_inputs) |path| try states.append(.{ .target = path, .initializedness = .deinitialized, .ends_previous_roots = true });
                    for (effects.relocations) |relocation| {
                        try states.append(.{ .target = relocation.source, .initializedness = .moved });
                        try states.append(.{ .target = relocation.destination, .initializedness = .initialized, .value = .{ .input_place_values = try self.allocator.dupe(facts.InputPath, &.{relocation.source}) }, .requires_available_destination = true, .refreshes_storage_generation = true });
                    }
                    try conditional.append(.{ .output_index = selector.output_index, .parent_variants = selector.parent_variants, .variant_index = selector.variant_index, .input_post_states = try states.toOwnedSlice(), .invalidated_domains = effects.invalidated_domains, .opaque_storage_empties = effects.emptied_inputs });
                }
            }
            var fallback_states = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
            try fallback_states.appendSlice(post_states);
            var fallback_domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
            try fallback_domains.appendSlice(invalidated_domains);
            for (conditional.items) |outcome| {
                for (outcome.input_post_states) |post| {
                    if (self.findInputPostState(fallback_states.items, post.target) == null) {
                        var fallback = post;
                        if (fallback.initializedness == .deinitialized or fallback.initializedness == .moved or fallback.requires_available_destination) fallback.initializedness = .maybe_initialized;
                        try fallback_states.append(fallback);
                    }
                }
                for (outcome.invalidated_domains) |domain| try appendDomain(&fallback_domains, domain);
            }
            var retained = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator);
            for (contract.retained_inputs) |retention| try retained.append(.{
                .storage = retention.storage,
                .hidden_dependencies = .{ .input_dependencies = try self.allocator.dupe(facts.InputDependency, &.{.{ .path = retention.input, .transfers_ownership = true }}) },
            });
            const result = try summaries.withOutcomeGuards(self.allocator, facts.SafetySummary{ .outputs = outputs, .required_live_inputs = required, .input_post_states = try fallback_states.toOwnedSlice(), .invalidated_domains = try fallback_domains.toOwnedSlice(), .outcome_post_states = try conditional.toOwnedSlice(), .opaque_storage_effects = try retained.toOwnedSlice(), .opaque_storage_empties = contract.emptied_inputs });
            try self.virtual_summaries.put(registry_id, result);
            return result;
        }
        return error.MissingVirtualSafetyContract;
    }

    fn generalVirtualSummary(self: *Infer, registry_id: graph_mod.GlobalVirtualRegistryId, contract: contracts.Contract) !facts.SafetySummary {
        var result = try self.generalContractEffects(registry_id, try contracts.possibleEffects(self.allocator, contract));
        const guarded = try self.allocator.alloc(facts.GuardedSafetyEffects, contract.guarded_effects.len);
        for (contract.guarded_effects, guarded) |clause, *target| {
            const effects = try self.allocator.create(facts.SafetySummary);
            effects.* = try self.generalContractEffects(registry_id, try contracts.effectsUnderConditions(self.allocator, contract, clause.conditions));
            target.* = .{ .conditions = clause.conditions, .effects = effects };
        }
        result.guarded_effects = guarded;
        return result;
    }

    fn generalContractEffects(self: *Infer, registry_id: graph_mod.GlobalVirtualRegistryId, contract: contracts.Contract) !facts.SafetySummary {
        const registry = self.graph.virtual_registries.items[@intFromEnum(registry_id)];
        const output_ty = registry.contract_output_type orelse return error.InvalidContractOutput;
        const fields = types.fields(self.graph, output_ty) orelse return error.InvalidContractOutput;
        const outputs = try self.allocator.alloc(facts.ValueEffect, contract.outputs.len);
        for (contract.outputs, outputs, 0..) |allowed, *output, index| {
            output.* = try @import("contract_outputs.zig").build(self.allocator, self.graph, self.graph.fields.items[fields.start + index].ty, allowed, @as(usize, @truncate(std.hash.Wyhash.hash(@intFromEnum(registry_id), std.mem.asBytes(&index)))));
            output.* = try self.bindVirtualReceiverValues(output.*, registry.receiver_input_index);
        }
        var required: std.ArrayList(facts.InputPath) = .empty;
        for (0..registry.contract_input_count orelse return error.InvalidContractInput) |index| {
            var destination = false;
            for (contract.relocations) |relocation| if (relocation.destination.input_index == index) {
                destination = true;
                break;
            };
            if (!destination) try required.append(self.allocator, .{ .input_index = @intCast(index) });
        }
        var states: std.ArrayList(facts.PlacePostState) = .empty;
        for (contract.invalidates) |path| try states.append(self.allocator, .{ .target = path, .initializedness = .initialized, .refreshes_storage_generation = true });
        for (contract.consumed_inputs) |path| try states.append(self.allocator, .{ .target = path, .initializedness = .deinitialized, .ends_previous_roots = true });
        for (contract.relocations) |relocation| {
            try states.append(self.allocator, .{ .target = relocation.source, .initializedness = .moved });
            try states.append(self.allocator, .{ .target = relocation.destination, .initializedness = .initialized, .value = .{ .input_place_values = try self.allocator.dupe(facts.InputPath, &.{relocation.source}) }, .requires_available_destination = true, .refreshes_storage_generation = true });
        }
        var retained: std.ArrayList(facts.OpaqueStorageEffect) = .empty;
        for (contract.retained_inputs) |retention| {
            try states.append(self.allocator, .{ .target = retention.input, .initializedness = .initialized, .opaque_ownership = .conditional, .opaque_storage = retention.storage });
            try retained.append(self.allocator, .{ .storage = retention.storage, .hidden_dependencies = .{ .input_dependencies = try self.allocator.dupe(facts.InputDependency, &.{.{ .path = retention.input, .transfers_ownership = true }}) } });
        }
        return .{ .outputs = outputs, .required_live_inputs = try required.toOwnedSlice(self.allocator), .input_post_states = try states.toOwnedSlice(self.allocator), .invalidated_domains = contract.invalidated_domains, .opaque_storage_empties = contract.emptied_inputs, .opaque_storage_effects = try retained.toOwnedSlice(self.allocator) };
    }

    fn requestContractSelectors(self: *Infer, method: graph_mod.GlobalFunctionId, declared: primitives.MethodSafetyContract) !void {
        if (declared.outcomes.len == 0 or declared.general_conditions) return;
        const contract = try contracts.fromDeclaration(self.allocator, declared);
        var wanted = std.array_list.Managed(outcome_selectors.Selector).init(self.allocator);
        try wanted.appendSlice(self.requested_selectors.get(method) orelse &.{});
        for (contract.outcomes) |outcome| {
            if (outcome.effects.invalidates.len == 0 and outcome.effects.invalidated_domains.len == 0 and outcome.effects.consumed_inputs.len == 0 and outcome.effects.relocations.len == 0 and outcome.effects.emptied_inputs.len == 0) continue;
            const selector = outcome_selectors.Selector{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index };
            var duplicate = false;
            for (wanted.items) |existing| if (existing.output_index == selector.output_index and existing.variant_index == selector.variant_index and std.mem.eql(u32, existing.parent_variants, selector.parent_variants)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try wanted.append(selector);
        }
        try self.requested_selectors.put(method, try wanted.toOwnedSlice());
    }

    /// Stable lexical definitions preserve the identity of one returned call.
    /// Select that call before visiting its effects; never undo a joined caller
    /// state when a later binding use reveals its tag. Subsequent calls and
    /// writes still contribute their ordinary effects in source order.
    fn forwardOrigin(self: *Infer, value: graph_mod.GlobalNodeId, parents: []const u32, seen: *std.array_list.Managed(graph_mod.GlobalBindingId)) anyerror!?ForwardOrigin {
        return switch (self.graph.node(value).content) {
            .function_call => |call| .{ .call = value, .output_index = if (self.graph.function(call.callee).output.len == 1) 0 else null, .parent_variants = parents },
            .virtual_call => |id| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                const contract = self.graph.virtual_registries.items[@intFromEnum(call.safety_methods)].safety_contract orelse break :blk null;
                break :blk .{ .call = value, .output_index = if (contract.output_count == 1) 0 else null, .parent_variants = parents };
            },
            .struct_field_access => |field| blk: {
                var origin = try self.forwardOrigin(field.value, parents, seen) orelse break :blk null;
                // Only the call's result record selects an output. A field
                // inside a returned value does not inherit its discriminant.
                if (origin.output_index != null or origin.parent_variants.len != parents.len) break :blk null;
                origin.output_index = field.field_index;
                break :blk origin;
            },
            .binding_use => |binding| blk: {
                if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, seen.items, binding) != null) break :blk null;
                const initialization = if (self.cleanup) |cleanup| cleanup.stableInitializer(binding) else null;
                try seen.append(binding);
                break :blk if (initialization) |initializer| try self.forwardOrigin(initializer, parents, seen) else null;
            },
            .move_value, .denied_implicit_copy => |child| try self.forwardOrigin(child, parents, seen),
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.forwardOrigin(payload, try std.mem.concat(self.allocator, u32, &.{ parents, &.{self.variantIndex(literal.choice_type, literal.variant) orelse return null} }), seen)
            else
                null,
            else => null,
        };
    }

    fn expressionForwardOrigin(self: *Infer, value: graph_mod.GlobalNodeId) !?ForwardOrigin {
        var seen = std.array_list.Managed(graph_mod.GlobalBindingId).init(self.allocator);
        defer seen.deinit();
        return self.forwardOrigin(value, &.{}, &seen);
    }

    fn selectForwardedCall(self: *Infer, function: graph_mod.GlobalFunctionId, block_id: graph_mod.GlobalBlockId) anyerror!void {
        const selected = self.selected_outcome orelse return;
        if (self.addressed_outputs.contains(selected.binding) or self.cleanup == null or !self.cleanup.?.canForward(selected.binding)) return;
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |id| switch (self.graph.node(id).content) {
            .assignment => |assignment| {
                if (assignment.binding != selected.binding) continue;
                const origin = try self.expressionForwardOrigin(assignment.value) orelse continue;
                const origin_output = origin.output_index orelse continue;
                if (origin.parent_variants.len > selected.parent_variants.len or
                    !std.mem.eql(u32, origin.parent_variants, selected.parent_variants[0..origin.parent_variants.len])) continue;
                self.selected_forward = .{ .call = origin.call, .selector = .{
                    .output_index = origin_output,
                    .parent_variants = selected.parent_variants[origin.parent_variants.len..],
                    .variant_index = selected.variant_index,
                } };
            },
            .if_statement => |statement| {
                try self.selectForwardedCall(function, statement.then_block);
                if (statement.else_block) |child| try self.selectForwardedCall(function, child);
            },
            .switch_statement => |id_switch| {
                const statement = self.graph.switches.items[@intFromEnum(id_switch)];
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| try self.selectForwardedCall(function, case.body);
                if (statement.default_block) |child| try self.selectForwardedCall(function, child);
            },
            .code_block, .value_sequence => |child| try self.selectForwardedCall(function, child),
            else => {},
        };
    }

    fn knownOutcome(self: *Infer, effect: facts.ValueEffect, parents: []const u32) anyerror!struct { mismatch: bool = false, variant: ?u32 = null } {
        var current = effect;
        for (parents) |parent| {
            const known = current.known_choice_variant orelse return .{};
            if (known != parent) return .{ .mismatch = true };
            var payload: ?facts.ValueEffect = null;
            for (current.variants) |variant| if (variant.index == parent) {
                payload = variant.value.*;
                break;
            };
            current = payload orelse return .{};
        }
        _ = self;
        return .{ .variant = current.known_choice_variant };
    }

    fn forwardingSelectors(self: *Infer, function: graph_mod.GlobalFunctionId, block_id: graph_mod.GlobalBlockId, wanted: *std.array_list.Managed(outcome_selectors.Selector)) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |id| switch (self.graph.node(id).content) {
            .assignment => |assignment| if (self.outputIndex(function, assignment.binding)) |index| {
                try self.forwardingExpressionSelectors(assignment.value, @intCast(index), &.{}, wanted);
            },
            .if_statement => |statement| {
                try self.forwardingSelectors(function, statement.then_block, wanted);
                if (statement.else_block) |child| try self.forwardingSelectors(function, child, wanted);
            },
            .while_statement => |statement| try self.forwardingSelectors(function, statement.body, wanted),
            .for_statement => |statement| try self.forwardingSelectors(function, statement.body, wanted),
            .switch_statement => |switch_id| {
                const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| try self.forwardingSelectors(function, case.body, wanted);
                if (statement.default_block) |child| try self.forwardingSelectors(function, child, wanted);
            },
            .code_block, .value_sequence => |child| try self.forwardingSelectors(function, child, wanted),
            else => {},
        };
    }

    fn forwardingExpressionSelectors(self: *Infer, value: graph_mod.GlobalNodeId, output_index: u32, parents: []const u32, wanted: *std.array_list.Managed(outcome_selectors.Selector)) anyerror!void {
        const origin = try self.expressionForwardOrigin(value) orelse return;
        const origin_output = origin.output_index orelse return;
        const enclosing = try std.mem.concat(self.allocator, u32, &.{ parents, origin.parent_variants });
        const summary = switch (self.graph.node(origin.call).content) {
            .function_call => |call| self.engine.summaryFor(call.callee),
            .virtual_call => |id| try self.virtualSummary(self.graph.virtual_calls.items[@intFromEnum(id)].safety_methods),
            else => unreachable,
        } orelse return;
        if (origin_output >= summary.outputs.len) return;
        for (summary.outcome_post_states) |outcome| {
            if (outcome.output_index != origin_output) continue;
            try wanted.append(.{ .output_index = output_index, .parent_variants = try std.mem.concat(self.allocator, u32, &.{ enclosing, outcome.parent_variants }), .variant_index = outcome.variant_index });
        }
    }

    fn bindVirtualReceiverValues(self: *Infer, effect: facts.ValueEffect, receiver: u32) anyerror!facts.ValueEffect {
        var result = effect;
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        var receivers = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index == receiver and dependency.validity_only) {
                try appendInputPath(&receivers, dependency.path);
            } else try appendInputDependency(&dependencies, dependency);
        }
        result.input_dependencies = try dependencies.toOwnedSlice();
        result.input_receiver_values = try receivers.toOwnedSlice();
        if (effect.fields.len != 0) {
            const fields = try self.allocator.dupe(facts.OutputFieldEffect, effect.fields);
            for (fields) |*field| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.bindVirtualReceiverValues(field.value.*, receiver);
                field.value = value;
            }
            result.fields = fields;
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.dupe(facts.OutputVariantEffect, effect.variants);
            for (variants) |*variant| {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.bindVirtualReceiverValues(variant.value.*, receiver);
                variant.value = value;
            }
            result.variants = variants;
        }
        return result;
    }

    pub fn contractImplementationSummary(self: *Infer, implementation: graph_mod.GlobalFunctionId, receiver: ?u32) !?facts.SafetySummary {
        return self.implementationSummary(implementation, receiver);
    }

    fn implementationSummary(self: *Infer, implementation: graph_mod.GlobalFunctionId, receiver: ?u32) !?facts.SafetySummary {
        var summary = self.engine.summaryFor(implementation) orelse return null;
        const function = self.graph.function(implementation);
        const outputs = try self.allocator.alloc(facts.ValueEffect, summary.outputs.len);
        for (summary.outputs, 0..) |output, index| outputs[index] = try self.eraseScalarOwnershipTransfers(function, output);
        summary.outputs = outputs;
        summary.input_post_states = try self.normalizeContractPostStates(function, receiver, summary.input_post_states);
        const outcomes = try self.allocator.dupe(facts.OutcomePostStates, summary.outcome_post_states);
        for (outcomes) |*outcome| outcome.input_post_states = try self.normalizeContractPostStates(function, receiver, outcome.input_post_states);
        summary.outcome_post_states = outcomes;
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
        const guards = try self.allocator.dupe(facts.GuardedSafetyEffects, summary.guarded_effects);
        for (guards) |*guard| {
            if (guard.origin != .general) continue;
            const effects = try self.allocator.create(facts.SafetySummary);
            effects.* = guard.effects.*;
            const guarded_outputs = try self.allocator.alloc(facts.ValueEffect, effects.outputs.len);
            for (effects.outputs, guarded_outputs) |output, *target| target.* = try self.eraseScalarOwnershipTransfers(function, output);
            effects.outputs = guarded_outputs;
            effects.input_post_states = try self.normalizeContractPostStates(function, receiver, effects.input_post_states);
            guard.effects = effects;
        }
        summary.guarded_effects = guards;
        // Derived outcome records must use the normalized concrete view too.
        return try summaries.refreshOutcomeGuards(self.allocator, summary);
    }

    fn normalizeContractPostStates(self: *Infer, function: graph_mod.Function, receiver: ?u32, post_states: []const facts.PlacePostState) ![]const facts.PlacePostState {
        var states = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        for (post_states) |original_state| {
            var state = original_state;
            var ty = self.graph.fields.items[function.input.start + state.target.input_index].ty;
            var scalar_field = receiver != null and state.target.input_index == receiver.? and state.target.projections.len != 0;
            for (state.target.projections) |projection| {
                if (projection != .dereference and self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
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
                    .dereference => {
                        const current = self.graph.semanticType(ty);
                        if (current != .pointer) {
                            scalar_field = false;
                            break;
                        }
                        ty = current.pointer.child;
                    },
                    .static_index, .dynamic_index => {
                        ty = types.arrayElement(self.graph, ty) orelse {
                            scalar_field = false;
                            break;
                        };
                    },
                    else => {
                        scalar_field = false;
                        break;
                    },
                }
            }
            // A numeric content write cannot introduce hidden dependencies
            // when its value has no capability or lifetime facts. Conservative
            // opaque-access markers are not additional storage permissions.
            const numeric_contents = switch (self.graph.semanticType(ty)) {
                .builtin => |builtin| switch (builtin) {
                    .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64, .Char, .Bool => true,
                    else => false,
                },
                else => false,
            };
            // Numeric place origins retain selector evidence, not hidden
            // lifetime or acquisition permissions. Keep them on the post-value
            // for identity checking, but exclude them from this occupancy test.
            var content_permissions = state.value;
            content_permissions.input_place_values = &.{};
            if (numeric_contents and facts.isEmptyValue(content_permissions))
                state.may_repopulate_opaque_storage = false;
            // Scalar receiver fields are implementation details, not fields of
            // the erased Virtual handle. They carry no published borrow state.
            if (scalar_field and !self.typeContainsPointer(ty) and
                state.initializedness == .initialized and state.opaque_ownership == .none and
                !state.ends_previous_roots and !state.refreshes_storage_generation and
                !state.requires_available_destination and !state.value.explicit_dependency and
                !state.value.fresh_cleanup_obligation and state.value.fresh_owned_roots.len == 0 and state.value.fresh_dependencies.len == 0 and
                state.value.fresh_storage_capabilities.len == 0) continue;
            try states.append(state);
        }
        return states.toOwnedSlice();
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
            .required_opaque_inputs = previous.required_opaque_inputs,
            .storage_capability_uses = previous.storage_capability_uses,
            .storage_capability_conflicts = previous.storage_capability_conflicts,
            .input_post_states = previous.input_post_states,
            .outcome_post_states = previous.outcome_post_states,
            .opaque_storage_effects = previous.opaque_storage_effects,
            .opaque_storage_empties = previous.opaque_storage_empties,
        };

        // Drop activation depends only on the finalized GlobalSG. Cache it
        // across fixed-point reevaluations, independently of inferred effects.
        if (!self.cleanup_activations.contains(function_id)) {
            var activation = try cleanup_activation.collect(self.allocator, self.graph, function_id);
            errdefer activation.deinit();
            try self.cleanup_activations.put(function_id, activation);
        }
        self.cleanup = self.cleanup_activations.getPtr(function_id).?;
        defer self.cleanup = null;

        self.bindings.clearRetainingCapacity();
        self.place_bindings.clearRetainingCapacity();
        self.local_address_bindings.clearRetainingCapacity();
        self.addressed_outputs.clearRetainingCapacity();
        self.domain_invalidations.clearRetainingCapacity();
        self.unbound_opaque_dependencies = .{};
        var start = profile.timestamp(self.profile_io);
        try self.inferBlock(function_id, function.body.?, outputs);
        profile.accumulate(self.profile_io, start, &self.output_ns);

        var required_live_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
        start = profile.timestamp(self.profile_io);
        try self.inferRequiredLiveInputsBlock(function_id, function.body.?, &required_live_inputs);
        var required_opaque_inputs = std.array_list.Managed(facts.InputPath).init(self.allocator);
        {
            self.collecting_opaque_requirements = true;
            defer self.collecting_opaque_requirements = false;
            try self.inferRequiredLiveInputsBlock(function_id, function.body.?, &required_opaque_inputs);
        }
        profile.accumulate(self.profile_io, start, &self.required_live_ns);

        var post_flow = InputPostStateFlow.init(self.allocator);
        defer post_flow.deinit();
        var post_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
        defer if (post_exits) |*exits| exits.deinit();
        start = profile.timestamp(self.profile_io);
        try self.inferInputPostStates(function_id, function.body.?, &post_flow, &post_exits);
        if (post_flow.reachable) try self.recordOutcomeExit(&post_exits, &post_flow);

        var post_states = if (post_exits) |*exits|
            try self.cloneInputPostStates(exits)
        else
            std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer post_states.deinit();

        profile.accumulate(self.profile_io, start, &self.post_state_ns);
        start = profile.timestamp(self.profile_io);
        var opaque_storage_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator);
        defer opaque_storage_effects.deinit();
        self.opaque_empty_seen = false;
        const opaque_storage_empties = try self.inferOpaqueStorageEffects(
            function_id,
            function.body.?,
            &opaque_storage_effects,
        );
        const has_opaque_empty_effect = self.opaque_empty_seen;
        profile.accumulate(self.profile_io, start, &self.opaque_ns);
        start = profile.timestamp(self.profile_io);
        // Each choice is considered independently. We never construct a product
        // of unrelated discriminants; unknown tags retain the common may-effects.
        var outcomes = std.array_list.Managed(facts.OutcomePostStates).init(self.allocator);
        defer outcomes.deinit();
        const common_domains = try self.allocator.dupe(facts.InputDomain, self.domain_invalidations.items);
        const requested_outcomes = if (self.requested_selectors.get(function_id)) |requested| requested.len != 0 else false;
        var forwarded_selectors = std.array_list.Managed(outcome_selectors.Selector).init(self.allocator);
        defer forwarded_selectors.deinit();
        try self.forwardingSelectors(function_id, function.body.?, &forwarded_selectors);
        if (post_states.items.len != 0 or common_domains.len != 0 or requested_outcomes or has_opaque_empty_effect or forwarded_selectors.items.len != 0) {
            for (0..function.output.len) |output_index| {
                const output_ty = self.graph.fields.items[function.output.start + @as(u32, @intCast(output_index))].ty;
                var wanted = std.array_list.Managed(outcome_selectors.Selector).init(self.allocator);
                defer wanted.deinit();
                try wanted.appendSlice(self.requested_selectors.get(function_id) orelse &.{});
                for (previous.outcome_post_states) |outcome| try wanted.append(.{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index });
                try wanted.appendSlice(forwarded_selectors.items);
                for (try outcome_selectors.partition(self.allocator, self.graph, @intCast(output_index), output_ty, wanted.items)) |selector| {
                    self.selected_outcome = .{ .output_index = @intCast(output_index), .parent_variants = selector.parent_variants, .variant_index = selector.variant_index, .binding = self.graph.binding_refs.items[function.output_bindings.start + @as(u32, @intCast(output_index))] };
                    defer self.selected_outcome = null;
                    self.selected_forward = null;
                    self.selected_forward_applied = false;
                    defer self.selected_forward = null;
                    try self.selectForwardedCall(function_id, function.body.?);
                    self.domain_invalidations.clearRetainingCapacity();
                    var outcome_flow = InputPostStateFlow.init(self.allocator);
                    defer outcome_flow.deinit();
                    var outcome_exits: ?std.array_list.Managed(facts.PlacePostState) = null;
                    defer if (outcome_exits) |*exits| exits.deinit();
                    try self.inferInputPostStates(function_id, function.body.?, &outcome_flow, &outcome_exits);
                    if (outcome_flow.reachable) try self.recordOutcomeExit(&outcome_exits, &outcome_flow);
                    // The same selected call is interpreted at its original position.
                    // Empty-state guarantees intersect returning exits independently
                    // of generation may-effects and never recover caller snapshots.
                    const selected_domains = try self.allocator.dupe(facts.InputDomain, self.domain_invalidations.items);
                    self.selected_forward_applied = false;
                    var selected_opaque_effects = std.array_list.Managed(facts.OpaqueStorageEffect).init(self.allocator);
                    defer selected_opaque_effects.deinit();
                    const selected_empties = if (has_opaque_empty_effect)
                        try self.inferOpaqueStorageEffects(function_id, function.body.?, &selected_opaque_effects)
                    else
                        opaque_storage_empties;
                    try outcomes.append(.{
                        .reachable = outcome_exits != null,
                        .output_index = @intCast(output_index),
                        .parent_variants = selector.parent_variants,
                        .variant_index = selector.variant_index,
                        .input_post_states = if (outcome_exits) |exits| try self.allocator.dupe(facts.PlacePostState, exits.items) else &.{},
                        .invalidated_domains = selected_domains,
                        .opaque_storage_empties = selected_empties,
                    });
                }
            }
        }
        self.domain_invalidations.clearRetainingCapacity();
        try self.domain_invalidations.appendSlice(common_domains);
        const outcome_post_states = try outcomes.toOwnedSlice();

        profile.accumulate(self.profile_io, start, &self.outcome_ns);
        start = profile.timestamp(self.profile_io);
        // Local hidden domains have no input path. Until exact returned-domain
        // identity is represented, retain their possible input provenance on
        // owning or reference-containing outputs. Cleanup obligations alone
        // cannot identify hidden borrows: plain records can carry them too.
        // This is a conservative union, never fresh ownership.
        // Effects are indexed by lexical output bindings, so their types are
        // the corresponding source of output shape information.
        const output_binding_ids = self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
        const has_hidden_dependencies = !facts.isEmptyValue(self.unbound_opaque_dependencies);
        for (outputs, output_binding_ids) |*output, binding| if (effectOwnsValue(output.*) or
            (has_hidden_dependencies and self.typeContainsPointer(self.graph.binding(binding).ty)))
        {
            output.* = try self.mergeValueEffects(output.*, self.unbound_opaque_dependencies);
        };

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
                // The final whole-receiver destruction supersedes post-values
                // of its owned fields. Keep effects through borrowed references:
                // those address other storage, which this destructor cannot end.
                var post_index: usize = 0;
                while (post_index < post_states.items.len) {
                    const path = post_states.items[post_index].target;
                    const owned_field = path.input_index == index and path.storage_domain == null and
                        path.projections.len != 0 and for (path.projections) |projection|
                    {
                        if (projection == .dereference) break false;
                    } else true;
                    if (owned_field) {
                        _ = post_states.orderedRemove(post_index);
                    } else post_index += 1;
                }
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

        var summary: facts.SafetySummary = .{
            .outputs = outputs,
            .storage_capability_uses = try capability_uses.toOwnedSlice(),
            .storage_capability_conflicts = try capability_conflicts.toOwnedSlice(),
            .required_live_inputs = try required_live_inputs.toOwnedSlice(),
            .required_opaque_inputs = try required_opaque_inputs.toOwnedSlice(),
            .input_post_states = try post_states.toOwnedSlice(),
            .outcome_post_states = outcome_post_states,
            .opaque_storage_effects = try opaque_storage_effects.toOwnedSlice(),
            .opaque_storage_empties = opaque_storage_empties,
            .invalidated_domains = try self.domain_invalidations.toOwnedSlice(),
        };
        summary.guarded_effects = try self.inferEntryChoiceOutputGuards(function_id, summary, &summary.guarded_returns_complete);
        if (summary.guarded_effects.len == 0) summary.guarded_effects = try self.inferForwardedGeneralGuards(function_id, summary, &summary.guarded_returns_complete);
        return summaries.refreshOutcomeGuards(self.allocator, summary);
    }

    /// Forward exact outputs of one call through a straight-line wrapper.
    /// Reject additional effects: entry selectors describe the original call,
    /// and cannot be reconstructed from a mutable argument at a later use.
    fn inferForwardedGeneralGuards(self: *Infer, function_id: graph_mod.GlobalFunctionId, summary: facts.SafetySummary, complete: *bool) ![]const facts.GuardedSafetyEffects {
        const function = self.graph.function(function_id);
        if (function.body == null or summary.outputs.len == 0) return &.{};
        const block = self.graph.blocks.items[@intFromEnum(function.body.?)];
        const origins = try self.allocator.alloc(?ForwardOrigin, summary.outputs.len);
        @memset(origins, null);
        var source_call: ?graph_mod.GlobalNodeId = null;
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| switch (self.graph.node(node).content) {
            .binding_declaration => |binding| {
                const declaration = self.graph.binding(binding);
                if (declaration.deferred_initialization or declaration.initialization == null) continue;
                const initializer = declaration.initialization.?;
                const origin = try self.expressionForwardOrigin(initializer) orelse {
                    if (!self.entryOutputExpressionSafe(initializer)) return &.{};
                    continue;
                };
                if (source_call != null and source_call.? != origin.call) return &.{};
                source_call = origin.call;
            },
            .assignment => |assignment| {
                const index = self.outputIndex(function_id, assignment.binding) orelse return &.{};
                if (origins[index] != null) return &.{};
                const origin = try self.expressionForwardOrigin(assignment.value) orelse return &.{};
                if (origin.output_index == null or origin.parent_variants.len != 0) return &.{};
                if (source_call != null and source_call.? != origin.call) return &.{};
                source_call = origin.call;
                origins[index] = origin;
            },
            .auto_deinit_binding => |id| {
                const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
                if (cleanup.deinit_fn != null or cleanup.fields.len != 0) return &.{};
            },
            .return_statement => |ret| if (ret.expression != null or ret.cleanup.len != 0) return &.{},
            else => return &.{},
        };
        for (origins) |origin| if (origin == null) return &.{};
        const call_node = source_call orelse return &.{};
        const called = switch (self.graph.node(call_node).content) {
            .function_call => |call| .{ self.engine.summaryFor(call.callee) orelse return &.{}, call.input },
            .virtual_call => |id| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                break :blk .{ try self.virtualSummary(call.safety_methods) orelse return &.{}, call.input };
            },
            else => return &.{},
        };
        const arguments = self.structArguments(called[1]) orelse return &.{};
        for (arguments) |argument| if (!self.entryOutputExpressionSafe(argument.value)) return &.{};
        var guards: std.ArrayList(facts.GuardedSafetyEffects) = .empty;
        for (called[0].guarded_effects) |guarded| {
            if (guarded.origin != .general or guarded.conditions.impossible) continue;
            var terms: std.ArrayList(facts.ChoiceCondition) = .empty;
            var supported = true;
            for (guarded.conditions.terms) |condition| {
                if (condition.subject == .output) {
                    var mapped = false;
                    for (origins, 0..) |origin, index| if (origin.?.output_index.? == condition.index) {
                        var term = condition;
                        term.index = @intCast(index);
                        try terms.append(self.allocator, term);
                        mapped = true;
                    };
                    if (!mapped) {
                        supported = false;
                        break;
                    }
                } else {
                    if (condition.index >= arguments.len) {
                        supported = false;
                        break;
                    }
                    const argument = arguments[condition.index].value;
                    const paths = try self.inferInputPaths(function_id, argument);
                    if (paths.len != 1 or paths[0].storage_domain != null) {
                        supported = false;
                        break;
                    }
                    var term = condition;
                    term.index = paths[0].input_index;
                    term.projections = try std.mem.concat(self.allocator, facts.Projection, &.{ paths[0].projections, condition.projections });
                    try terms.append(self.allocator, term);
                }
            }
            if (!supported) return &.{};
            const outputs = try self.allocator.alloc(facts.ValueEffect, origins.len);
            for (origins, outputs) |origin, *output| {
                const effect = guarded.effects.outputs[origin.?.output_index.?];
                output.* = try self.rebaseFreshSources(try self.substituteOutput(function_id, effect, arguments), call_node);
            }
            const effects = try self.allocator.create(facts.SafetySummary);
            effects.* = summary;
            effects.outputs = outputs;
            effects.guarded_effects = &.{};
            try guards.append(self.allocator, .{ .conditions = try @import("choice_conditions.zig").normalize(self.allocator, terms.items), .effects = effects });
        }
        complete.* = called[0].guarded_returns_complete;
        return try guards.toOwnedSlice(self.allocator);
    }

    const EntryOutputFlow = struct {
        conditions: facts.ChoiceConditions = .{},
        outputs: []facts.ValueEffect,
        initialized: []bool,
        reachable: bool = true,

        fn clone(self: EntryOutputFlow, allocator: std.mem.Allocator) !EntryOutputFlow {
            var result = self;
            result.outputs = try allocator.dupe(facts.ValueEffect, self.outputs);
            result.initialized = try allocator.dupe(bool, self.initialized);
            return result;
        }
    };

    /// Stable selection bodies can publish entry guards without symbolic
    /// execution of arbitrary operations. Other dimensions retain the ordinary
    /// conservative summary; unsupported control flow discards this precision.
    fn inferEntryChoiceOutputGuards(self: *Infer, function_id: graph_mod.GlobalFunctionId, summary: facts.SafetySummary, complete: *bool) ![]const facts.GuardedSafetyEffects {
        const function = self.graph.function(function_id);
        if (summary.outputs.len == 0 or function.input.start + function.input.len > self.graph.fields.items.len) return &.{};
        const output_facts = try self.allocator.alloc(facts.ValueEffect, summary.outputs.len);
        @memset(output_facts, .{});
        const initialized = try self.allocator.alloc(bool, summary.outputs.len);
        @memset(initialized, false);
        var flow = EntryOutputFlow{ .outputs = output_facts, .initialized = initialized };
        var guards: std.ArrayList(facts.GuardedSafetyEffects) = .empty;
        defer guards.deinit(self.allocator);
        if (!try self.inferEntryOutputBlock(function_id, function.body.?, &flow, summary, &guards)) return &.{};
        if (flow.reachable) try self.recordEntryOutputGuard(flow, summary, &guards);
        // Avoid publishing a duplicate unconditional record for simple bodies.
        var conditional = false;
        for (guards.items) |guard| conditional = conditional or guard.conditions.terms.len != 0;
        if (!conditional) return &.{};
        complete.* = true;
        return guards.toOwnedSlice(self.allocator);
    }

    fn recordEntryOutputGuard(self: *Infer, flow: EntryOutputFlow, summary: facts.SafetySummary, guards: *std.ArrayList(facts.GuardedSafetyEffects)) !void {
        if (flow.conditions.impossible) return;
        for (flow.initialized) |initialized| if (!initialized) return;
        const conditions = try @import("choice_conditions.zig").conjoin(self.allocator, flow.conditions, try contracts.knownOutputConditions(self.allocator, flow.outputs));
        // Keep one complete approximation for each established entry relation.
        // Multiple exits with the same relation must join their output facts.
        for (guards.items) |guarded| if (guarded.conditions.eql(conditions)) {
            const effects = @constCast(guarded.effects);
            const outputs = try self.allocator.dupe(facts.ValueEffect, effects.outputs);
            for (outputs, flow.outputs) |*output, other| output.* = try self.mergeValueEffects(output.*, other);
            effects.outputs = outputs;
            return;
        };
        const effects = try self.allocator.create(facts.SafetySummary);
        effects.* = summary;
        effects.guarded_effects = &.{};
        effects.outputs = try self.allocator.dupe(facts.ValueEffect, flow.outputs);
        try guards.append(self.allocator, .{ .conditions = conditions, .effects = effects });
    }

    fn entryOutputExpressionSafe(self: *Infer, value: graph_mod.GlobalNodeId) bool {
        return switch (self.graph.node(value).content) {
            .binding_use, .int_literal, .float_literal, .char_literal, .bool_literal => true,
            .dereference => |read| self.entryOutputExpressionSafe(read.pointer),
            .denied_implicit_copy => |child| self.entryOutputExpressionSafe(child),
            .choice_literal => |literal| if (literal.payload) |child| self.entryOutputExpressionSafe(child) else true,
            .struct_value_literal => |literal| blk: {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    if (!self.entryOutputExpressionSafe(field.value)) break :blk false;
                break :blk true;
            },
            else => false,
        };
    }

    fn entryConditionExpressionSafe(self: *Infer, node_id: graph_mod.GlobalNodeId) bool {
        if (self.entryOutputExpressionSafe(node_id)) return true;
        return switch (self.graph.node(node_id).content) {
            .comparison => |op| self.entryConditionExpressionSafe(op.left) and self.entryConditionExpressionSafe(op.right),
            .logical_operation => |op| self.entryConditionExpressionSafe(op.left) and self.entryConditionExpressionSafe(op.right),
            else => false,
        };
    }

    fn entryOutputSuffixSafe(self: *Infer, node_id: graph_mod.GlobalNodeId) bool {
        return switch (self.graph.node(node_id).content) {
            .return_statement => |ret| ret.expression == null and ret.cleanup.len == 0,
            .auto_deinit_binding => |id| blk: {
                const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
                break :blk cleanup.deinit_fn == null and cleanup.fields.len == 0;
            },
            else => false,
        };
    }

    fn inferEntryOutputBlock(self: *Infer, function_id: graph_mod.GlobalFunctionId, block_id: graph_mod.GlobalBlockId, flow: *EntryOutputFlow, summary: facts.SafetySummary, guards: *std.ArrayList(facts.GuardedSafetyEffects)) anyerror!bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        const nodes = self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len];
        // Source blocks identify their last statement as ret_val too. Its
        // ordered effects are handled below; an independent expression result
        // would require a separate proof before this precision can apply.
        if (block.ret_val) |value| if (std.mem.indexOfScalar(graph_mod.GlobalNodeId, nodes, value) == null) return false;
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (!flow.reachable) {
                if (!self.entryOutputSuffixSafe(node_id)) return false;
                continue;
            }
            switch (self.graph.node(node_id).content) {
                .binding_declaration => |binding| {
                    const record = self.graph.binding(binding);
                    if (record.initialization) |value| if (!record.deferred_initialization and !self.entryOutputExpressionSafe(value)) return false;
                },
                .assignment => |assignment| {
                    const output = self.outputIndex(function_id, assignment.binding) orelse return false;
                    if (!self.entryOutputExpressionSafe(assignment.value)) return false;
                    // Reassigning an output remains conservative: another
                    // branch may already have established a different value.
                    if (flow.initialized[output]) return false;
                    flow.outputs[output] = try self.inferExpression(function_id, assignment.value);
                    flow.initialized[output] = true;
                },
                .if_statement => |statement| {
                    if (!self.entryConditionExpressionSafe(statement.condition)) return false;
                    var left = try flow.clone(self.allocator);
                    if (!try self.inferEntryOutputBlock(function_id, statement.then_block, &left, summary, guards)) return false;
                    var right = try flow.clone(self.allocator);
                    if (statement.else_block) |child| {
                        if (!try self.inferEntryOutputBlock(function_id, child, &right, summary, guards)) return false;
                    }
                    for ([_]EntryOutputFlow{ left, right }) |branch| if (branch.reachable) {
                        for (branch.initialized) |initialized| if (!initialized) return false;
                        try self.recordEntryOutputGuard(branch, summary, guards);
                    };
                    flow.reachable = false;
                },
                .switch_statement => |switch_id| {
                    const statement = self.graph.switches.items[@intFromEnum(switch_id)];
                    const paths = try self.inferInputPaths(function_id, statement.expression);
                    if (paths.len != 1 or paths[0].storage_domain != null) return false;
                    for (paths[0].projections) |projection| if (projection == .dynamic_index) return false;
                    const ty = self.inputPathType(function_id, paths[0]) orelse return false;
                    if (types.variants(self.graph, ty) == null or !statement.exhaustive or statement.default_block != null) return false;
                    for (self.graph.switch_cases.items[statement.cases.start..][0..statement.cases.len]) |case| {
                        const variant = self.variantIndex(ty, case.variant) orelse return false;
                        var branch = try flow.clone(self.allocator);
                        // Summary input paths address a reference's referent;
                        // selector coordinates explicitly distinguish its slot.
                        const input_type = self.graph.fields.items[self.graph.function(function_id).input.start + paths[0].input_index].ty;
                        const selector_path = if (self.graph.semanticType(input_type) == .pointer)
                            try std.mem.concat(self.allocator, facts.Projection, &.{ &.{.dereference}, paths[0].projections })
                        else
                            paths[0].projections;
                        branch.conditions = try @import("choice_conditions.zig").conjoin(self.allocator, flow.conditions, try @import("choice_conditions.zig").normalize(self.allocator, &.{.{ .subject = .entry_input, .index = paths[0].input_index, .projections = selector_path, .variant_index = variant }}));
                        if (!try self.inferEntryOutputBlock(function_id, case.body, &branch, summary, guards)) return false;
                        if (branch.reachable) {
                            // A suffix after the switch needs a general
                            // control-flow join; retain only terminal selections.
                            var terminal = true;
                            for (branch.initialized) |initialized| terminal = terminal and initialized;
                            if (!terminal) return false;
                            try self.recordEntryOutputGuard(branch, summary, guards);
                        }
                    }
                    // Only final cleanup or bare returns may follow this
                    // selection. An intervening effect loses the relation.
                    flow.reachable = false;
                },
                .code_block => |child| if (!try self.inferEntryOutputBlock(function_id, child, flow, summary, guards)) return false,
                .return_statement => |ret| {
                    if (ret.expression != null or ret.cleanup.len != 0) return false;
                    try self.recordEntryOutputGuard(flow.*, summary, guards);
                    flow.reachable = false;
                },
                .auto_deinit_binding => |id| {
                    const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
                    if (cleanup.deinit_fn != null or cleanup.fields.len != 0) return false;
                },
                else => return false,
            }
        }
        return true;
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
                .struct_field_store => |store| {
                    const targets = try self.localAddressTargets(store.struct_ptr);
                    if (targets.len != 0) for (targets) |target| {
                        try self.storeOutputProjection(function_id, target, &.{.{ .field = store.field_index }}, store.value, outputs);
                    } else try self.storeOutputProjection(function_id, store.struct_ptr, &.{.{ .field = store.field_index }}, store.value, outputs);
                },
                .pointer_assignment => |store| {
                    for (try self.localAddressTargets(store.pointer)) |target|
                        try self.storeOutputProjection(function_id, target, &.{}, store.value, outputs);
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
                .code_block, .value_sequence => |child| try self.inferBlock(function_id, child, outputs),
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
            .value_sequence => |block| blk: {
                const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse break :blk &.{};
                break :blk try self.capability_address_targets(value, flow);
            },
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
            .value_sequence => |block| blk: {
                const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse break :blk .{};
                break :blk try self.capability_value(function, value, flow);
            },
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
        if (content == .function_call or content == .virtual_call) {
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
                if (call.callee_value) |value| try self.infer_capability_node(function, value, flow, exits);
                try self.infer_capability_node(function, call.input, flow, exits);
                if (self.structArguments(call.input)) |arguments| try self.infer_capability_call(function, call.callee, arguments, flow);
            },
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.infer_capability_node(function, call.input, flow, exits);
                const summary = try self.virtualSummary(call.safety_methods) orelse return;
                if (self.structArguments(call.input)) |arguments| try self.substitute_capability_uses(function, summary, arguments, flow);
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
                if (self.cleanup) |active| if (!active.roots.contains(id)) return;
                const cleanup = self.graph.auto_deinits.items[@intFromEnum(id)];
                if (cleanup.input) |input| {
                    try self.infer_capability_node(function, input, flow, exits);
                    if (cleanup.deinit_fn) |callee| if (self.structArguments(input)) |arguments| try self.infer_capability_call(function, callee, arguments, flow);
                }
                try self.infer_cleanup_capabilities(function, cleanup.fields, flow, exits);
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
            .code_block, .value_sequence => |block| try self.infer_capability_block(function, block, flow, exits),
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

    fn infer_cleanup_capabilities(self: *Infer, function: graph_mod.GlobalFunctionId, fields: primitives.Range(graph_mod.GlobalAutoDeinitFieldId), flow: *CapabilityFlow, exits: *?CapabilityFlow) anyerror!void {
        const children = self.graph.auto_deinit_fields.items[fields.start..][0..fields.len];
        if (children.len != 0 and children[0].is_variant) {
            var joined = try flow.clone(self.allocator);
            defer joined.deinit();
            for (children, 0..) |field, index| {
                if (self.cleanup) |active| if (!active.fields.contains(@enumFromInt(fields.start + @as(u32, @intCast(index))))) continue;
                var branch = try flow.clone(self.allocator);
                defer branch.deinit();
                try self.infer_cleanup_capability_field(function, field, &branch, exits);
                // Payload alternatives are mutually exclusive. Taking the
                // maximum use count must not add their consumptions together.
                try self.join_capability_flows(&joined, &joined, &branch);
            }
            try self.join_capability_flows(flow, &joined, &joined);
            return;
        }
        for (children, 0..) |field, index| {
            if (self.cleanup) |active| if (!active.fields.contains(@enumFromInt(fields.start + @as(u32, @intCast(index))))) continue;
            try self.infer_cleanup_capability_field(function, field, flow, exits);
        }
    }

    fn infer_cleanup_capability_field(self: *Infer, function: graph_mod.GlobalFunctionId, field: graph_mod.AutoDeinitField, flow: *CapabilityFlow, exits: *?CapabilityFlow) anyerror!void {
        if (field.input) |input| {
            try self.infer_capability_node(function, input, flow, exits);
            if (field.deinit_fn) |callee| if (self.structArguments(input)) |arguments| try self.infer_capability_call(function, callee, arguments, flow);
        }
        try self.infer_cleanup_capabilities(function, field.fields, flow, exits);
    }

    const SymbolicInputOverride = struct {
        input_index: u32,
        effect: facts.ValueEffect,
    };

    const InputPostStateFlow = struct {
        states: std.array_list.Managed(facts.PlacePostState),
        reachable: bool = true,
        outcome_variant: ?u32 = null,
        outcome_parent_mismatch: bool = false,
        domains: std.array_list.Managed(facts.InputDomain),

        fn init(allocator: std.mem.Allocator) InputPostStateFlow {
            return .{ .states = std.array_list.Managed(facts.PlacePostState).init(allocator), .domains = std.array_list.Managed(facts.InputDomain).init(allocator) };
        }

        fn deinit(self: *InputPostStateFlow) void {
            self.states.deinit();
            self.domains.deinit();
        }

        fn clone(self: *const InputPostStateFlow, allocator: std.mem.Allocator) !InputPostStateFlow {
            var states = std.array_list.Managed(facts.PlacePostState).init(allocator);
            try states.appendSlice(self.states.items);
            var domains = std.array_list.Managed(facts.InputDomain).init(allocator);
            try domains.appendSlice(self.domains.items);
            return .{ .states = states, .domains = domains, .reachable = self.reachable, .outcome_variant = self.outcome_variant, .outcome_parent_mismatch = self.outcome_parent_mismatch };
        }
    };

    const OpaqueEmptyState = struct {
        emptied: std.array_list.Managed(facts.InputPath),
        reachable: bool = true,
        outcome_variant: ?u32 = null,
        outcome_parent_mismatch: bool = false,

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
            result.outcome_variant = self.outcome_variant;
            result.outcome_parent_mismatch = self.outcome_parent_mismatch;
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
        const previous_sink = self.post_domain_sink;
        self.post_domain_sink = &flow.domains;
        defer self.post_domain_sink = previous_sink;
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
            .assignment => |assignment| {
                const previous_forwarded = self.forwarded_outcome;
                const previous_leaf = self.forwarded_leaf_selected;
                defer self.forwarded_outcome = previous_forwarded;
                defer self.forwarded_leaf_selected = previous_leaf;
                self.forwarded_outcome = null;
                self.forwarded_leaf_selected = false;
                try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits);
                if (self.selected_outcome) |selected| if (self.outputIndex(function_id, assignment.binding)) |index| {
                    if (index == selected.output_index) {
                        const known = try self.knownOutcome(try self.inferExpression(function_id, assignment.value), selected.parent_variants);
                        flow.outcome_parent_mismatch = known.mismatch;
                        const origin = try self.expressionForwardOrigin(assignment.value);
                        const selected_origin = if (self.selected_forward) |forwarded| if (origin) |actual| actual.call == forwarded.call and actual.output_index == forwarded.selector.output_index else false else false;
                        flow.outcome_variant = if (selected_origin and self.selected_forward_applied and !known.mismatch) selected.variant_index else known.variant;
                    }
                };
            },
            .function_call, .virtual_call => try self.inferInputPostStatesExpression(function_id, node_id, states, exits),
            .pointer_assignment => |assignment| {
                try self.inferInputPostStatesExpression(function_id, assignment.pointer, states, exits);
                try self.inferInputPostStatesExpression(function_id, assignment.value, states, exits);
                try self.recordInputPostState(
                    states,
                    try self.inferPointeePaths(function_id, assignment.pointer),
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
                var transfers = InputPostStateFlow.init(self.allocator);
                defer transfers.deinit();
                const previous_loop = self.loop_post_effects;
                self.loop_post_effects = &transfers;
                defer self.loop_post_effects = previous_loop;
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                try self.joinInputPostStates(&body_flow.states, &body_flow.states, &transfers.states);
                try self.joinInputPostStates(states, states, &body_flow.states);
                for (body_flow.domains.items) |domain| try appendDomain(&flow.domains, domain);
                for (transfers.domains.items) |domain| try appendDomain(&flow.domains, domain);
                flow.outcome_variant = null;
                flow.outcome_parent_mismatch = false;
            },
            .for_statement => |statement| {
                if (statement.init) |initialization|
                    try self.inferInputPostStatesNode(function_id, initialization, flow, exits);
                if (!flow.reachable) return;
                try self.inferInputPostStatesExpression(function_id, statement.condition, states, exits);
                var transfers = InputPostStateFlow.init(self.allocator);
                defer transfers.deinit();
                const previous_loop = self.loop_post_effects;
                self.loop_post_effects = &transfers;
                defer self.loop_post_effects = previous_loop;
                var body_flow = try flow.clone(self.allocator);
                defer body_flow.deinit();
                try self.inferInputPostStates(function_id, statement.body, &body_flow, exits);
                if (statement.increment) |increment| {
                    // A continue still executes the increment. Joining it for
                    // every loop alternative is conservative for break paths.
                    const previous_sink = self.post_domain_sink;
                    self.post_domain_sink = &body_flow.domains;
                    defer self.post_domain_sink = previous_sink;
                    try self.inferInputPostStatesNode(function_id, increment, &body_flow, exits);
                }
                try self.joinInputPostStates(&body_flow.states, &body_flow.states, &transfers.states);
                try self.joinInputPostStates(states, states, &body_flow.states);
                for (body_flow.domains.items) |domain| try appendDomain(&flow.domains, domain);
                for (transfers.domains.items) |domain| try appendDomain(&flow.domains, domain);
                flow.outcome_variant = null;
                flow.outcome_parent_mismatch = false;
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
                if (flow.reachable) try self.recordOutcomeExit(exits, flow);
                flow.reachable = false;
            },
            .code_block, .value_sequence => |child| try self.inferInputPostStates(function_id, child, flow, exits),
            .break_statement, .continue_statement => {
                if (self.loop_post_effects) |transfers| {
                    try self.joinInputPostStates(&transfers.states, &transfers.states, states);
                    for (flow.domains.items) |domain| try appendDomain(&transfers.domains, domain);
                }
                flow.reachable = false;
            },
            .abort_statement => flow.reachable = false,
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
        const previous_sink = self.post_domain_sink;
        self.post_domain_sink = &flow.domains;
        defer self.post_domain_sink = previous_sink;
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
            .value_sequence => |block| {
                var flow = InputPostStateFlow.init(self.allocator);
                flow.states.deinit();
                flow.states = states.*;
                defer states.* = flow.states;
                defer flow.domains.deinit();
                if (self.post_domain_sink) |sink| try flow.domains.appendSlice(sink.items);
                try self.inferInputPostStates(function_id, block, &flow, exits);
                if (self.post_domain_sink) |sink| for (flow.domains.items) |domain| try appendDomain(sink, domain);
            },
            .move_value, .denied_implicit_copy => |value| try self.inferInputPostStatesExpression(function_id, value, states, exits),
            .address_of => |value| {
                try self.markAddressedOutput(function_id, value);
                try self.inferInputPostStatesExpression(function_id, value, states, exits);
            },
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
                const forwarded = self.forwarded_outcome;
                defer self.forwarded_outcome = forwarded;
                self.forwarded_outcome = null;
                if (forwarded) |selector| if (selector.parent_variants.len != 0) {
                    if ((self.variantIndex(literal.choice_type, literal.variant) orelse 0) == selector.parent_variants[0]) {
                        var inner = selector;
                        inner.parent_variants = inner.parent_variants[1..];
                        self.forwarded_outcome = inner;
                    }
                };
                if (literal.payload) |payload| try self.inferInputPostStatesExpression(function_id, payload, states, exits);
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
                if (self.post_domain_sink) |sink| try error_flow.domains.appendSlice(sink.items);
                try self.inferInputPostStatesRange(function_id, propagation.cleanup_nodes, &error_flow, exits);
                if (error_flow.reachable) try self.recordOutcomeExit(exits, &error_flow);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferInputPostStatesExpression(function_id, context.errable_value, states, exits);
                var error_flow = InputPostStateFlow.init(self.allocator);
                defer error_flow.deinit();
                try error_flow.states.appendSlice(states.items);
                if (self.post_domain_sink) |sink| try error_flow.domains.appendSlice(sink.items);
                try self.inferInputPostStatesExpression(function_id, context.context, &error_flow.states, exits);
                try self.inferInputPostStatesRange(function_id, context.cleanup_nodes, &error_flow, exits);
                if (error_flow.reachable) try self.recordOutcomeExit(exits, &error_flow);
            },
            .function_call => |call| {
                const forwarded = self.forwarded_outcome;
                self.forwarded_outcome = null;
                if (call.callee_value) |value| try self.inferInputPostStatesExpression(function_id, value, states, exits);
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
                self.forwarded_outcome = if (self.selected_forward) |origin| if (origin.call == node_id) origin.selector else forwarded else forwarded;
                const previous_leaf = self.forwarded_leaf_selected;
                self.forwarded_leaf_selected = false;
                try self.applyInputPostStatesFromFunctionCall(function_id, call.callee, call.input, states);
                if (self.selected_forward) |origin| if (origin.call == node_id and self.forwarded_leaf_selected) {
                    self.selected_forward_applied = true;
                };
                self.forwarded_leaf_selected = previous_leaf;
                self.forwarded_outcome = forwarded;
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                const forwarded = self.forwarded_outcome;
                self.forwarded_outcome = null;
                try self.inferInputPostStatesExpression(function_id, call.handle, states, exits);
                try self.inferInputPostStatesExpression(function_id, call.input, states, exits);
                self.forwarded_outcome = if (self.selected_forward) |origin| if (origin.call == node_id) origin.selector else forwarded else forwarded;
                const previous_leaf = self.forwarded_leaf_selected;
                self.forwarded_leaf_selected = false;
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.applyInputPostStatesFromSummary(function_id, summary, call.input, states, null);
                if (self.selected_forward) |origin| if (origin.call == node_id and self.forwarded_leaf_selected) {
                    self.selected_forward_applied = true;
                };
                self.forwarded_leaf_selected = previous_leaf;
                self.forwarded_outcome = forwarded;
            },
            .virtualize => |virtualize_id| try self.inferInputPostStatesExpression(
                function_id,
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                states,
                exits,
            ),

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

    fn selectForwardedEffects(self: *Infer, summary: facts.SafetySummary, selected: facts.OutcomePostStates) !facts.SafetySummary {
        var result = summary;
        result.opaque_storage_empties = try std.mem.concat(self.allocator, facts.InputPath, &.{ summary.opaque_storage_empties, selected.opaque_storage_empties });
        if (summary.outputs.len == 1) {
            result.input_post_states = selected.input_post_states;
            result.invalidated_domains = selected.invalidated_domains;
            return result;
        }
        // One output can refine only its own effects. Retain the may-union for
        // unrelated outputs and shared targets instead of inventing correlation.
        var states = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        for (summary.input_post_states) |state| {
            var governed = false;
            var shared = false;
            for (summary.outcome_post_states) |outcome| {
                if (self.findInputPostState(outcome.input_post_states, state.target) == null) continue;
                if (outcome.output_index == selected.output_index) governed = true else shared = true;
            }
            if (!governed or shared) try states.append(state);
        }
        for (selected.input_post_states) |state| {
            if (self.findInputPostState(states.items, state.target) == null) try states.append(state);
        }
        var domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
        for (summary.invalidated_domains) |domain| {
            var governed = false;
            var shared = false;
            for (summary.outcome_post_states) |outcome| for (outcome.invalidated_domains) |effect| {
                if (effect.domain_index != domain.domain_index or !self.inputPathEqual(effect.path, domain.path)) continue;
                if (outcome.output_index == selected.output_index) governed = true else shared = true;
            };
            if (!governed or shared) try appendDomain(&domains, domain);
        }
        for (selected.invalidated_domains) |domain| try appendDomain(&domains, domain);
        result.input_post_states = try states.toOwnedSlice();
        result.invalidated_domains = try domains.toOwnedSlice();
        return result;
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
        var selected = summary;
        if (self.forwarded_outcome) |selector| {
            // Forwarding a single choice keeps one selector. No correlation is
            // inferred merely because unrelated outputs use the same tag names.
            for (summary.outcome_post_states) |outcome| {
                if (outcome.output_index == selector.output_index and outcome.variant_index == selector.variant_index and std.mem.eql(u32, outcome.parent_variants, selector.parent_variants)) {
                    self.forwarded_leaf_selected = true;
                    selected = try self.selectForwardedEffects(summary, outcome);
                    break;
                }
            }
        }
        try self.applyInputPostStatesFromArguments(function_id, selected, arguments, states, override);
    }

    fn applyInputPostStatesFromArguments(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        summary: facts.SafetySummary,
        arguments: []const graph_mod.ValueField,
        states: *std.array_list.Managed(facts.PlacePostState),
        override: ?SymbolicInputOverride,
    ) !void {
        for (summary.invalidated_domains) |domain| {
            var resolved = false;
            if (domain.path.input_index < arguments.len) {
                const argument = arguments[domain.path.input_index].value;
                const value = (try self.localPointeeEffect(function_id, argument)) orelse try self.inferExpression(function_id, argument);
                for (value.domain_values) |mapped| if (mapped.domain_index == domain.domain_index) {
                    try self.recordInputPostState(states, mapped.value.input_generation_dependencies, .initialized, .{}, false, true, false, false);
                    for (mapped.value.input_domains) |input| try appendDomain(self.post_domain_sink orelse &self.domain_invalidations, input);
                    resolved = true;
                };
            }
            if (!resolved) {
                const paths = try self.substituteRequiredInputPath(function_id, domain.path, arguments, override);
                for (paths) |path| try appendDomain(self.post_domain_sink orelse &self.domain_invalidations, .{ .path = path, .domain_index = domain.domain_index });
            }
        }
        for (summary.input_post_states) |post_state| {
            if (post_state.target.input_index >= arguments.len) continue;
            const targets = try self.substituteInputPath(
                function_id,
                post_state.target,
                arguments,
                override,
                .place,
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
        if (self.cleanup) |active| if (!active.roots.contains(auto_id)) return;
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
        for (self.graph.auto_deinit_fields.items[field_range.start..][0..field_range.len], 0..) |field, index| {
            if (self.cleanup) |active| if (!active.fields.contains(@enumFromInt(field_range.start + @as(u32, @intCast(index))))) continue;
            if (field.is_variant) if (parent_effect.known_choice_variant) |active| {
                if (active != field.field_index) continue;
            };
            const field_effect = try self.projectValueEffect(parent_effect, if (field.is_variant)
                .{ .variant = field.field_index }
            else
                .{ .field = field.field_index });
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
                // An untouched relocation destination remains available. It
                // contributes no initialized value to the joined post-state.
                if (left_state.initializedness != .initialized or left_state.requires_available_destination) {
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
            if (right_state.initializedness != .initialized or right_state.requires_available_destination) {
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
            var domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
            defer domains.deinit();
            for (left.domains.items) |domain| try appendDomain(&domains, domain);
            for (right.domains.items) |domain| try appendDomain(&domains, domain);
            destination.domains.clearRetainingCapacity();
            try destination.domains.appendSlice(domains.items);
            destination.reachable = true;
            destination.outcome_variant = if (left.outcome_variant == right.outcome_variant) left.outcome_variant else null;
            destination.outcome_parent_mismatch = left.outcome_parent_mismatch and right.outcome_parent_mismatch;
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
        destination.domains.clearRetainingCapacity();
        try destination.domains.appendSlice(source.domains.items);
        destination.reachable = source.reachable;
        destination.outcome_variant = source.outcome_variant;
        destination.outcome_parent_mismatch = source.outcome_parent_mismatch;
    }

    fn markAddressedOutput(self: *Infer, function: graph_mod.GlobalFunctionId, node: graph_mod.GlobalNodeId) anyerror!void {
        switch (self.graph.node(node).content) {
            .binding_use => |binding| if (self.outputIndex(function, binding) != null) {
                try self.addressed_outputs.put(binding, {});
            },
            .struct_field_access => |access| try self.markAddressedOutput(function, access.value),
            .choice_payload_access => |access| try self.markAddressedOutput(function, access.value),
            else => {},
        }
    }

    fn recordOutcomeExit(self: *Infer, exits: *?std.array_list.Managed(facts.PlacePostState), flow: *const InputPostStateFlow) !void {
        if (self.selected_outcome) |selected| {
            // Once an output slot is exposed through a reference, an alias may
            // change its tag. Keep every exit in that selector's may-effects
            // until indirect writes have a branch-local discriminant model.
            if (!self.addressed_outputs.contains(selected.binding)) {
                if (flow.outcome_parent_mismatch) return;
                if (flow.outcome_variant) |variant| if (variant != selected.variant_index) return;
            }
        }
        for (flow.domains.items) |domain| try appendDomain(&self.domain_invalidations, domain);
        try self.recordInputPostStateExit(exits, &flow.states);
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
        if (left.input_index != right.input_index or left.storage_domain != right.storage_domain or left.projections.len != right.projections.len) return false;
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
        if (state.reachable) try self.recordOpaqueEmptyExit(&exits, &state);

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
            .assignment => |assignment| {
                try self.inferOpaqueEmptyExpression(function_id, assignment.value, effects, state, exits);
                if (self.selected_outcome) |selected| if (assignment.binding == selected.binding) {
                    const known = try self.knownOutcome(try self.inferExpression(function_id, assignment.value), selected.parent_variants);
                    state.outcome_parent_mismatch = known.mismatch;
                    const origin = try self.expressionForwardOrigin(assignment.value);
                    const selected_origin = if (self.selected_forward) |forwarded| if (origin) |actual| actual.call == forwarded.call and actual.output_index == forwarded.selector.output_index else false else false;
                    state.outcome_variant = if (selected_origin and self.selected_forward_applied and !known.mismatch) selected.variant_index else known.variant;
                };
            },
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
                state.outcome_variant = null;
                state.outcome_parent_mismatch = false;
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
                state.outcome_variant = null;
                state.outcome_parent_mismatch = false;
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
                if (state.reachable) try self.recordOpaqueEmptyExit(exits, state);
                state.reachable = false;
            },
            .struct_field_store => |store| {
                try self.inferOpaqueEmptyExpression(function_id, store.struct_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
                state.outcome_variant = null;
                state.outcome_parent_mismatch = false;
            },
            .array_store => |store| {
                try self.inferOpaqueEmptyExpression(function_id, store.array_ptr, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.index, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, store.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
                state.outcome_variant = null;
                state.outcome_parent_mismatch = false;
            },
            .pointer_assignment => |assignment| {
                try self.inferOpaqueEmptyExpression(function_id, assignment.pointer, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, assignment.value, effects, state, exits);
                state.emptied.clearRetainingCapacity();
                state.outcome_variant = null;
                state.outcome_parent_mismatch = false;
            },
            .code_block, .value_sequence => |child| try self.inferOpaqueEmptyBlock(function_id, child, effects, state, exits),
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
        if (self.cleanup) |active| if (!active.roots.contains(auto_id)) return;
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
        for (self.graph.auto_deinit_fields.items[field_range.start..][0..field_range.len], 0..) |field, index| {
            if (self.cleanup) |active| if (!active.fields.contains(@enumFromInt(field_range.start + @as(u32, @intCast(index))))) continue;
            if (field.is_variant) if (parent_effect.known_choice_variant) |active| {
                if (active != field.field_index) continue;
            };
            const field_effect = try self.projectValueEffect(parent_effect, if (field.is_variant)
                .{ .variant = field.field_index }
            else
                .{ .field = field.field_index });
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
            .value_sequence => |block| try self.inferOpaqueEmptyBlock(function_id, block, effects, state, exits),
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
                error_state.outcome_variant = null;
                error_state.outcome_parent_mismatch = false;
                try self.inferOpaqueEmptyRange(function_id, propagation.cleanup_nodes, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, &error_state);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.inferOpaqueEmptyExpression(function_id, context.errable_value, effects, state, exits);
                var error_state = try state.clone(self.allocator);
                defer error_state.deinit();
                error_state.outcome_variant = null;
                error_state.outcome_parent_mismatch = false;
                try self.inferOpaqueEmptyExpression(function_id, context.context, effects, &error_state, exits);
                try self.inferOpaqueEmptyRange(function_id, context.cleanup_nodes, effects, &error_state, exits);
                if (error_state.reachable) try self.recordOpaqueEmptyExit(exits, &error_state);
            },
            .function_call => |call| {
                if (call.callee_value) |value| try self.inferOpaqueEmptyExpression(function_id, value, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, call.input, effects, state, exits);
                const previous_forwarded = self.forwarded_outcome;
                self.forwarded_outcome = if (self.selected_forward) |origin| if (origin.call == node_id) origin.selector else null else null;
                defer self.forwarded_outcome = previous_forwarded;
                try self.applyOpaqueEmptyFunctionCall(function_id, call.callee, call.input, effects, state);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferOpaqueEmptyExpression(function_id, call.handle, effects, state, exits);
                try self.inferOpaqueEmptyExpression(function_id, call.input, effects, state, exits);
                const previous_forwarded = self.forwarded_outcome;
                self.forwarded_outcome = if (self.selected_forward) |origin| if (origin.call == node_id) origin.selector else null else null;
                defer self.forwarded_outcome = previous_forwarded;
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
        var selected = summary;
        if (self.forwarded_outcome) |selector| for (summary.outcome_post_states) |outcome| {
            if (outcome.output_index == selector.output_index and outcome.variant_index == selector.variant_index and std.mem.eql(u32, outcome.parent_variants, selector.parent_variants)) {
                selected = try self.selectForwardedEffects(summary, outcome);
                self.selected_forward_applied = true;
                break;
            }
        };
        try self.applyOpaqueEmptySummaryArguments(function_id, selected, arguments, effects, state, override);
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
        for (summary.outcome_post_states) |outcome| if (outcome.opaque_storage_empties.len != 0) {
            self.opaque_empty_seen = true;
            break;
        };
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
        if (storages.len == 0) self.unbound_opaque_dependencies = try self.mergeValueEffects(self.unbound_opaque_dependencies, try self.flattenHiddenDependencies(hidden));
        for (storages) |storage| {
            self.removeOpaqueStorageRelease(&state.emptied, storage);
            try self.recordOpaqueStorageEffect(effects, storage, hidden);
        }
    }

    fn effectOwnsValue(effect: facts.ValueEffect) bool {
        if (effect.fresh_cleanup_obligation or effect.fresh_owned_roots.len != 0) return true;
        for (effect.input_dependencies) |dependency| if (dependency.transfers_ownership) return true;
        for (effect.fields) |field| if (effectOwnsValue(field.value.*)) return true;
        for (effect.variants) |variant| if (effectOwnsValue(variant.value.*)) return true;
        return false;
    }

    fn flattenHiddenDependencies(self: *Infer, effect: facts.ValueEffect) anyerror!facts.ValueEffect {
        const dependencies = try self.dependencyOnlyEffect(effect);
        var result = try self.validityOnlyEffect(dependencies);
        result.fields = &.{};
        result.variants = &.{};
        for (dependencies.fields) |field| result = try self.mergeValueEffects(result, try self.flattenHiddenDependencies(field.value.*));
        for (dependencies.variants) |variant| result = try self.mergeValueEffects(result, try self.flattenHiddenDependencies(variant.value.*));
        return result;
    }

    fn recordOpaqueStorageEmpties(
        self: *Infer,
        state: *OpaqueEmptyState,
        storages: []const facts.InputPath,
    ) !void {
        if (storages.len != 0) self.opaque_empty_seen = true;
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
        destination.outcome_variant = if (left.outcome_variant == right.outcome_variant) left.outcome_variant else null;
        destination.outcome_parent_mismatch = left.outcome_parent_mismatch and right.outcome_parent_mismatch;
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
        destination.outcome_variant = source.outcome_variant;
        destination.outcome_parent_mismatch = source.outcome_parent_mismatch;
    }

    fn recordOpaqueEmptyExit(
        self: *Infer,
        exits: *?std.array_list.Managed(facts.InputPath),
        state: *const OpaqueEmptyState,
    ) !void {
        if (self.selected_outcome) |selected| if (!self.addressed_outputs.contains(selected.binding)) {
            if (state.outcome_parent_mismatch) return;
            if (state.outcome_variant) |variant| if (variant != selected.variant_index) return;
        };
        const emptied = state.emptied.items;
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
        if (prefix.input_index != path.input_index or prefix.storage_domain != path.storage_domain or prefix.projections.len > path.projections.len) return false;
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
            .input_captured_storages = effect.input_captured_storages,
            .input_receiver_values = effect.input_receiver_values,
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
                if (call.callee_value) |value| try self.inferRequiredLiveInputsNode(function_id, value, required);
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                if (self.engine.summaryFor(call.callee)) |summary|
                    try self.substituteRequiredLiveInputs(function_id, self.requiredInputPaths(summary), call.input, required);
            },
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.inferRequiredLiveInputsNode(function_id, call.handle, required);
                try self.inferRequiredLiveInputsNode(function_id, call.input, required);
                if (try self.virtualSummary(call.safety_methods)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(
                        function_id,
                        self.requiredInputPaths(summary),
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
            .code_block, .value_sequence => |child| try self.inferRequiredLiveInputsBlock(function_id, child, required),

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
        if (self.collecting_opaque_requirements) {
            // Backing-owner identities originate in trusted slot establishment.
            // Reading a region anchor validates storage, not stored elements.
            for (effect.input_owned_roots) |path| try appendInputPath(required, path);
            return;
        }
        const paths = try self.symbolicSourcePaths(function_id, pointer, effect);
        for (paths) |path| try appendInputPath(required, path);
        // Using a pointer loaded through another pointer requires the loaded
        // reference's lifetime, independently of its containing slot's storage.
        if (self.graph.node(pointer).content == .dereference) {
            for (try self.projectInputPaths(paths, .dereference)) |path|
                try appendInputPath(required, path);
        }
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

    fn requiredInputPaths(self: *Infer, summary: facts.SafetySummary) []const facts.InputPath {
        return if (self.collecting_opaque_requirements) summary.required_opaque_inputs else summary.required_live_inputs;
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
            if (self.collecting_opaque_requirements and path.projections.len == 0) {
                const effect = try self.inferExpression(function_id, arguments[path.input_index].value);
                for (effect.input_owned_roots) |owner| try appendInputPath(required, owner);
            }
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
            .value_sequence => |block| blk: {
                const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse break :blk &.{};
                break :blk try self.localAddressTargets(value);
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
        if (path.storage_domain) |domain_index| {
            if (path.input_index >= arguments.len) return &.{};
            const argument = arguments[path.input_index].value;
            var value = (try self.localPointeeEffect(function_id, argument)) orelse try self.inferExpression(function_id, argument);
            for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
            for (value.domain_values) |mapped| if (mapped.domain_index == domain_index) {
                var sources = std.array_list.Managed(facts.InputPath).init(self.allocator);
                for (mapped.value.input_generation_dependencies) |source| try appendInputPath(&sources, source);
                for (mapped.value.input_domains) |source| try appendInputPath(&sources, .{ .input_index = source.path.input_index, .projections = source.path.projections, .storage_domain = source.domain_index });
                return sources.toOwnedSlice();
            };
            var receiver = path;
            receiver.storage_domain = null;
            const paths = try self.substituteInputPath(function_id, receiver, arguments, override, .validity);
            const result = try self.allocator.dupe(facts.InputPath, paths);
            for (result) |*source| source.storage_domain = domain_index;
            return result;
        }
        return self.substituteInputPath(function_id, path, arguments, override, .validity);
    }

    fn substituteInputPath(
        self: *Infer,
        function_id: graph_mod.GlobalFunctionId,
        path: facts.InputPath,
        arguments: []const graph_mod.ValueField,
        override: ?SymbolicInputOverride,
        purpose: enum { validity, place },
    ) ![]const facts.InputPath {
        if (path.input_index >= arguments.len) return &.{};
        if (override) |symbolic| if (symbolic.input_index == path.input_index) {
            if (path.projections.len == 0) return &.{};
            var effect = symbolic.effect;
            for (path.projections, 0..) |projection, projection_index| {
                if (purpose == .place and projection == .dereference) {
                    // A symbolic receiver field can already name a caller's
                    // pointer input referent. Only references stored inside
                    // that referent need another dereference coordinate.
                    var sources = try self.opaqueGenerationSourcePaths(effect);
                    var referents = std.array_list.Managed(facts.InputPath).init(self.allocator);
                    for (sources) |source| {
                        const ty = self.inputPathType(function_id, source) orelse continue;
                        try appendInputPath(&referents, if (self.graph.semanticType(ty) == .pointer)
                            .{ .input_index = source.input_index, .projections = try self.appendProjection(source.projections, .dereference) }
                        else
                            source);
                    }
                    sources = try referents.toOwnedSlice();
                    for (path.projections[projection_index + 1 ..]) |remaining| sources = try self.projectInputPaths(sources, remaining);
                    return sources;
                }
                effect = try self.projectValueEffect(effect, projection);
            }
            return self.opaqueGenerationSourcePaths(effect);
        };

        const argument = arguments[path.input_index].value;
        var direct = if (purpose == .place)
            try self.inferPointeePaths(function_id, argument)
        else
            try self.inferInputPaths(function_id, argument);
        if (direct.len != 0) {
            for (path.projections) |projection| direct = try self.projectInputPaths(direct, projection);
            return direct;
        }

        // A local by-value argument has its own place. Its borrowed lifetime
        // dependencies can require caller inputs to remain live, but cannot
        // identify caller places changed or consumed by the callee. Pointer
        // arguments may still carry the provenance of a caller's place.
        if (purpose == .place) {
            const ty = self.graph.node(argument).ty orelse return &.{};
            if (self.graph.semanticType(ty) != .pointer) return &.{};
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
        if (self.cleanup) |active| if (!active.roots.contains(auto_id)) return;
        const cleanup = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const binding_effect = self.bindings.get(cleanup.binding);
        if (cleanup.input) |input| {
            try self.inferRequiredLiveInputsNode(function_id, input, required);
            if (cleanup.deinit_fn) |deinit_fn| {
                if (self.engine.summaryFor(deinit_fn)) |summary|
                    try self.substituteRequiredLiveInputsWithOverride(
                        function_id,
                        self.requiredInputPaths(summary),
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
        for (self.graph.auto_deinit_fields.items[fields_range.start..][0..fields_range.len], 0..) |field, index| {
            if (self.cleanup) |active| if (!active.fields.contains(@enumFromInt(fields_range.start + @as(u32, @intCast(index))))) continue;
            if (field.is_variant) if (parent_effect.known_choice_variant) |active| {
                if (active != field.field_index) continue;
            };
            const field_effect = try self.projectValueEffect(parent_effect, if (field.is_variant)
                .{ .variant = field.field_index }
            else
                .{ .field = field.field_index });
            if (field.input) |input| {
                try self.inferRequiredLiveInputsNode(function_id, input, required);
                if (field.deinit_fn) |deinit_fn| {
                    if (self.engine.summaryFor(deinit_fn)) |summary|
                        try self.substituteRequiredLiveInputsWithOverride(
                            function_id,
                            self.requiredInputPaths(summary),
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
            .value_sequence => |block| blk: {
                const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse break :blk .{};
                break :blk try self.inferExpression(function_id, value);
            },
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

            .testing_expect_error => |id| blk: {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                const input = expect.test_fail_input orelse break :blk .{};
                break :blk try self.inferCall(function_id, node_id, expect.test_fail_function, input);
            },
            .function_call => |call| blk: {
                if (call.callee_value) |value| _ = try self.inferExpression(function_id, value);
                break :blk try self.inferCall(function_id, node_id, call.callee, call.input);
            },
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
        var outputs = summary.outputs;
        var selected: ?facts.ChoiceConditions = null;
        for (summary.guarded_effects) |guarded| {
            if (guarded.conditions.impossible) continue;
            var established = true;
            for (guarded.conditions.terms) |condition| {
                if (condition.subject != .entry_input or condition.projections.len != 0 or condition.index >= arguments.len) {
                    established = false;
                    break;
                }
                var node = arguments[condition.index].value;
                while (self.graph.node(node).content == .denied_implicit_copy) node = self.graph.node(node).content.denied_implicit_copy;
                const literal = switch (self.graph.node(node).content) {
                    .choice_literal => |value| value,
                    else => {
                        established = false;
                        break;
                    },
                };
                if (self.variantIndex(literal.choice_type, literal.variant) != condition.variant_index) {
                    established = false;
                    break;
                }
            }
            if (established and (selected == null or guarded.conditions.implies(selected.?))) {
                outputs = guarded.effects.outputs;
                selected = guarded.conditions;
            }
        }
        return self.substitute_summary_outputs(function_id, outputs, arguments, call_node);
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

    // Field-wise construction is ordinary output construction. Preserve the
    // dependencies of projected writes just as whole-binding assignments do.
    fn storeOutputProjection(self: *Infer, function: graph_mod.GlobalFunctionId, target: graph_mod.GlobalNodeId, path: []const facts.Projection, value: graph_mod.GlobalNodeId, outputs: []facts.ValueEffect) anyerror!void {
        switch (self.graph.node(target).content) {
            .binding_use => |binding| {
                // Input-pointer writes belong to input post-states. Updating
                // the pointer binding here would replace its reference effect
                // with the pointee's fields and lose the caller's root identity.
                if (self.inputIndex(function, binding) != null) return;
                const ty = self.graph.resolvedSemanticType(self.graph.binding(binding).ty) orelse return;
                if (ty == .pointer) return;
                if (self.outputIndex(function, binding)) |index| {
                    // TODO: Unify ordinary projected output writes with the
                    // existing input post-state flow before broadening this
                    // path. Replaying their RHS can duplicate opaque effects.
                    if (self.graph.declaration(self.graph.function(function).declaration).constructor_type == null and lifecycle_contracts.initializedType(self.graph, function) == null) return;
                    outputs[index] = try self.storeEffectProjection(outputs[index], path, try self.inferExpression(function, value));
                }
            },
            .struct_field_access => |field| {
                const nested = try self.allocator.alloc(facts.Projection, path.len + 1);
                nested[0] = .{ .field = field.field_index };
                @memcpy(nested[1..], path);
                try self.storeOutputProjection(function, field.value, nested, value, outputs);
            },
            .dereference => |read| {
                for (try self.localAddressTargets(read.pointer)) |place|
                    try self.storeOutputProjection(function, place, path, value, outputs);
            },
            .address_of => |place| try self.storeOutputProjection(function, place, path, value, outputs),
            else => {},
        }
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
        var result: facts.ValueEffect = .{};
        for (fields.items) |field| {
            result = try self.mergeValueEffects(result, field.value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = try fields.toOwnedSlice();
        return result;
    }

    fn inferVirtualize(self: *Infer, function_id: graph_mod.GlobalFunctionId, id: graph_mod.GlobalVirtualizeId) !facts.ValueEffect {
        const virtualize = self.graph.virtualizes.items[@intFromEnum(id)];
        var result = try self.inferExpression(function_id, virtualize.value);
        const receiver_paths = try self.inferInputPaths(function_id, virtualize.value);
        if (virtualize.domains.len != 0) {
            const domain_values = try self.allocator.alloc(facts.OutputDomainEffect, virtualize.domains.len);
            for (virtualize.domains, domain_values) |mapping, *domain| {
                var paths = std.array_list.Managed(facts.InputPath).init(self.allocator);
                for (receiver_paths) |receiver| for (mapping.paths) |path| {
                    var projections = receiver.projections;
                    for (path.fields) |field| projections = try self.appendProjection(projections, .{ .field = field });
                    try appendInputPath(&paths, .{ .input_index = receiver.input_index, .projections = projections });
                };
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = .{ .input_generation_dependencies = try paths.toOwnedSlice() };
                domain.* = .{ .domain_index = mapping.domain_index, .value = value };
            }
            result.domain_values = domain_values;
            return result;
        }
        // A receiver without named domains captures its reachable storage.
        // Callers resolve these paths to actual generations; concrete method
        // summaries never determine the shape or liveness of the handle.
        result.input_captured_storages = receiver_paths;
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
        // A destructor creates a cleanup obligation, not necessarily a fresh
        // storage lifetime. Shape anchors and scalar owners must not introduce
        // extra roots that couple independently replaced backing allocations.
        if (types.hasDestructor(self.graph, self.graph.node(node_id).ty.?))
            result.fresh_cleanup_obligation = true;
        return result;
    }

    fn inferElements(self: *Infer, function_id: graph_mod.GlobalFunctionId, range: graph_mod.NodeRange) !facts.ValueEffect {
        var result: facts.ValueEffect = .{};
        // Share the checker's empty aggregate representation. A single
        // nonempty child restores all projections, including empty neighbors.
        var output_fields: ?[]facts.OutputFieldEffect = null;
        for (self.graph.node_refs.items[range.start..][0..range.len], 0..) |element, index| {
            const effect = try self.inferExpression(function_id, element);
            if (facts.isEmptyValue(effect)) {
                if (output_fields) |stored| stored[index] = .{ .index = @intCast(index), .value = &facts.empty_value_effect };
                continue;
            }
            if (output_fields == null) {
                output_fields = try self.allocator.alloc(facts.OutputFieldEffect, range.len);
                for (output_fields.?[0..index], 0..) |*field, prior| field.* = .{ .index = @intCast(prior), .value = &facts.empty_value_effect };
            }
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = effect;
            output_fields.?[index] = .{ .index = @intCast(index), .value = value };
            result = try self.mergeValueEffects(result, value.*);
            result.variants = &.{};
            result.known_choice_variant = null;
        }
        result.fields = output_fields orelse &.{};
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
        if (!self.typeContainsPointer(ty)) return self.scalar_read_effect(effect);
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

    fn inputPathType(self: *Infer, function_id: graph_mod.GlobalFunctionId, path: facts.InputPath) ?graph_mod.GlobalTypeId {
        const function = self.graph.function(function_id);
        if (path.input_index >= function.input.len) return null;
        var ty = self.graph.fields.items[function.input.start + path.input_index].ty;
        if (self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
        for (path.projections) |projection| {
            ty = switch (projection) {
                .field => |index| blk: {
                    const fields = types.fields(self.graph, ty) orelse return null;
                    if (index >= fields.len) return null;
                    break :blk types.effectiveFieldType(self.graph.fields.items[fields.start + index]);
                },
                .variant => |index| blk: {
                    const variants = types.variants(self.graph, ty) orelse return null;
                    if (index >= variants.len) return null;
                    break :blk self.graph.variants.items[variants.start + index].payload_type orelse return null;
                },
                .static_index, .dynamic_index => types.arrayElement(self.graph, ty) orelse return null,
                .dereference => if (self.graph.semanticType(ty) == .pointer) self.graph.semanticType(ty).pointer.child else return null,
            };
        }
        return ty;
    }

    fn inferPointeePaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, pointer: graph_mod.GlobalNodeId) ![]const facts.InputPath {
        const paths = try self.inferInputPaths(function_id, pointer);
        const pointer_ty = self.graph.node(pointer).ty orelse return paths;
        const pointer_type = self.graph.semanticType(pointer_ty);
        if (pointer_type != .pointer) return paths;
        var result = std.array_list.Managed(facts.InputPath).init(self.allocator);
        const function = self.graph.function(function_id);
        for (paths) |path| {
            if (path.input_index >= function.input.len) continue;
            var ty = self.graph.fields.items[function.input.start + path.input_index].ty;
            // Input pointer coordinates already denote their referent. A
            // pointer stored inside it needs an explicit dereference instead
            // of describing a write to the field holding that pointer.
            if (self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
            var projections = std.array_list.Managed(facts.Projection).init(self.allocator);
            for (path.projections) |projection| {
                if (projection != .dereference and self.graph.semanticType(ty) == .pointer) {
                    try projections.append(.dereference);
                    ty = self.graph.semanticType(ty).pointer.child;
                }
                try projections.append(projection);
                ty = switch (projection) {
                    .field => |index| blk: {
                        const fields = types.fields(self.graph, ty) orelse break :blk ty;
                        if (index >= fields.len) break :blk ty;
                        break :blk types.effectiveFieldType(self.graph.fields.items[fields.start + index]);
                    },
                    .variant => |index| blk: {
                        const variants = types.variants(self.graph, ty) orelse break :blk ty;
                        if (index >= variants.len) break :blk ty;
                        break :blk self.graph.variants.items[variants.start + index].payload_type orelse ty;
                    },
                    .static_index, .dynamic_index => types.arrayElement(self.graph, ty) orelse ty,
                    .dereference => if (self.graph.semanticType(ty) == .pointer) self.graph.semanticType(ty).pointer.child else ty,
                };
            }
            if (self.graph.semanticType(ty) == .pointer and !types.equal(self.graph, ty, pointer_type.pointer.child))
                try projections.append(.dereference);
            try appendInputPath(&result, .{ .input_index = path.input_index, .projections = try projections.toOwnedSlice() });
        }
        return result.toOwnedSlice();
    }

    fn inferInputPaths(self: *Infer, function_id: graph_mod.GlobalFunctionId, node_id: graph_mod.GlobalNodeId) anyerror![]const facts.InputPath {
        return switch (self.graph.node(node_id).content) {
            .value_sequence => |block| blk: {
                const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse break :blk &.{};
                break :blk try self.inferInputPaths(function_id, value);
            },
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
            .fresh_cleanup_obligation = effect.fresh_cleanup_obligation,
            .fresh_owned_roots = effect.fresh_owned_roots,
            .fresh_storage_capabilities = effect.fresh_storage_capabilities,
            .unavailable_fresh_storage = effect.unavailable_fresh_storage,
            .integer_address = effect.integer_address,
            .foreign_storage = effect.foreign_storage,
            .known_choice_variant = effect.known_choice_variant,
        };

        var input_domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
        for (effect.input_domains) |domain| {
            var resolved = false;
            if (domain.path.input_index < arguments.len) {
                const argument = arguments[domain.path.input_index].value;
                var value = (try self.localPointeeEffect(function_id, argument)) orelse try self.inferExpression(function_id, argument);
                for (domain.path.projections) |projection| value = try self.projectValueEffect(value, projection);
                for (value.domain_values) |mapped| if (mapped.domain_index == domain.domain_index) {
                    result = try self.mergeValueEffects(result, mapped.value.*);
                    resolved = true;
                };
            }
            if (!resolved) {
                const paths = try self.substituteRequiredInputPath(function_id, domain.path, arguments, override);
                for (paths) |path| try appendDomain(&input_domains, .{ .path = path, .domain_index = domain.domain_index });
            }
        }
        result.input_domains = try input_domains.toOwnedSlice();
        const domain_values = try self.allocator.alloc(facts.OutputDomainEffect, effect.domain_values.len);
        for (effect.domain_values, domain_values) |domain, *mapped| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.substituteOutputWithOverride(function_id, domain.value.*, arguments, override);
            mapped.* = .{ .domain_index = domain.domain_index, .value = value };
        }
        result.domain_values = domain_values;

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
        var captured_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_captured_storages) |path| {
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&captured_storages, candidate);
        }
        result.input_captured_storages = try captured_storages.toOwnedSlice();

        var receiver_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (effect.input_receiver_values) |path| {
            if (path.input_index >= arguments.len) continue;
            const argument = arguments[path.input_index].value;
            if ((try self.inferInputPaths(function_id, argument)).len == 0) {
                if (try self.localPointeeEffect(function_id, argument)) |pointee| {
                    var value = pointee;
                    for (path.projections) |projection| value = try self.projectValueEffect(value, projection);
                    result = try self.mergeValueEffects(result, try self.validityOnlyEffect(value));
                    continue;
                }
            }
            const mapped = try self.substituteRequiredInputPath(function_id, path, arguments, override);
            for (mapped) |candidate| try appendInputPath(&receiver_values, candidate);
        }
        result.input_receiver_values = try receiver_values.toOwnedSlice();

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
            .static_index => |element_index| {
                for (effect.fields) |field| if (field.index == element_index) return field.value.*;
            },
            .dynamic_index => {
                if (effect.fields.len != 0) {
                    var merged: facts.ValueEffect = .{ .foreign_storage = effect.foreign_storage };
                    for (effect.fields) |field| merged = try self.mergeValueEffects(merged, field.value.*);
                    return merged;
                }
            },
            .dereference => {},
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
            .storage_domain = path.storage_domain,
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
        var input_domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
        for (left.input_domains) |domain| try appendDomain(&input_domains, domain);
        for (right.input_domains) |domain| try appendDomain(&input_domains, domain);
        var domain_values = std.array_list.Managed(facts.OutputDomainEffect).init(self.allocator);
        for (left.domain_values) |domain| try domain_values.append(domain);
        for (right.domain_values) |domain| {
            var found = false;
            for (domain_values.items) |*existing| if (existing.domain_index == domain.domain_index) {
                const value = try self.allocator.create(facts.ValueEffect);
                value.* = try self.mergeValueEffects(existing.value.*, domain.value.*);
                existing.value = value;
                found = true;
                break;
            };
            if (!found) try domain_values.append(domain);
        }
        var dependencies = std.array_list.Managed(facts.InputDependency).init(self.allocator);
        for (left.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        for (right.input_dependencies) |value| try appendInputDependency(&dependencies, value);
        var input_places = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_places) |value| try appendInputPath(&input_places, value);
        for (right.input_places) |value| try appendInputPath(&input_places, value);
        var input_generations = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_generation_dependencies) |value| try appendInputPath(&input_generations, value);
        for (right.input_generation_dependencies) |value| try appendInputPath(&input_generations, value);
        var receiver_values = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_receiver_values) |value| try appendInputPath(&receiver_values, value);
        for (right.input_receiver_values) |value| try appendInputPath(&receiver_values, value);
        var captured_storages = std.array_list.Managed(facts.InputPath).init(self.allocator);
        for (left.input_captured_storages) |value| try appendInputPath(&captured_storages, value);
        for (right.input_captured_storages) |value| try appendInputPath(&captured_storages, value);
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
            .input_captured_storages = try captured_storages.toOwnedSlice(),
            .input_receiver_values = try receiver_values.toOwnedSlice(),
            .input_place_values = try input_place_values.toOwnedSlice(),
            .input_owned_roots = try input_owned_roots.toOwnedSlice(),
            .input_domains = try input_domains.toOwnedSlice(),
            .domain_values = try domain_values.toOwnedSlice(),
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
            .fresh_cleanup_obligation = left.fresh_cleanup_obligation or right.fresh_cleanup_obligation,
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
            .input_domains = effect.input_domains,
            .explicit_dependency = effect.explicit_dependency,
            .input_dependencies = try dependencies.toOwnedSlice(),
            .input_generation_dependencies = try generations.toOwnedSlice(),
            .input_captured_storages = effect.input_captured_storages,
            .input_receiver_values = effect.input_receiver_values,
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

    fn scalar_read_effect(self: *Infer, effect: facts.ValueEffect) anyerror!facts.ValueEffect {
        var result = try self.scalar_storage_effect(effect);
        // Reading numeric contents grants no ownership or validity relation,
        // but retains the copied discriminant and the paths to nested choices.
        result.known_choice_variant = effect.known_choice_variant;
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, fields) |field, *projected| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.scalar_read_effect(field.value.*);
            projected.* = .{ .index = field.index, .value = value };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, variants) |variant, *projected| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.scalar_read_effect(variant.value.*);
            projected.* = .{ .index = variant.index, .value = value };
        }
        result.variants = variants;
        return result;
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

fn containsInputDependency(haystack: []const facts.InputDependency, needle: facts.InputDependency) bool {
    for (haystack) |candidate| {
        if (candidate.path.input_index != needle.path.input_index or
            candidate.path.storage_domain != needle.path.storage_domain or
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
        if (existing.input_index != path.input_index or existing.storage_domain != path.storage_domain or existing.projections.len != path.projections.len) continue;
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

test "numeric projected values retain choices without ownership or validity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, undefined, &engine);
    defer infer.deinit();
    const payload = facts.ValueEffect{
        .fresh_cleanup_obligation = true,
        .input_owned_roots = &.{.{ .input_index = 0 }},
        .input_dependencies = &.{.{ .path = .{ .input_index = 0 }, .validity_only = true }},
        .input_storage_capabilities = &.{.{ .input_index = 1 }},
    };
    const choice = facts.ValueEffect{
        .known_choice_variant = 1,
        .variants = &.{.{ .index = 1, .value = &payload }},
    };
    const effect = try infer.scalar_read_effect(.{ .fields = &.{.{ .index = 2, .value = &choice }} });
    const projected = effect.fields[0].value.*;
    try std.testing.expectEqual(@as(u32, 2), effect.fields[0].index);
    try std.testing.expectEqual(@as(?u32, 1), projected.known_choice_variant);
    try std.testing.expectEqual(@as(usize, 1), projected.variants.len);
    const read = projected.variants[0].value.*;
    try std.testing.expect(!read.fresh_cleanup_obligation);
    try std.testing.expectEqual(@as(usize, 0), read.input_owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), read.input_dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), read.input_storage_capabilities.len);
}

test "forwarded output preserves unrelated and shared may effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, undefined, &engine);
    defer infer.deinit();
    const summary = facts.SafetySummary{
        .outputs = &.{ .{}, .{} },
        .input_post_states = &.{
            .{ .target = .{ .input_index = 0 }, .initializedness = .maybe_initialized },
            .{ .target = .{ .input_index = 1 }, .initializedness = .maybe_initialized },
            .{ .target = .{ .input_index = 2 }, .initializedness = .maybe_initialized },
            .{ .target = .{ .input_index = 3 }, .initializedness = .initialized },
        },
        .invalidated_domains = &.{
            .{ .path = .{ .input_index = 0 }, .domain_index = 0 },
            .{ .path = .{ .input_index = 1 }, .domain_index = 0 },
            .{ .path = .{ .input_index = 2 }, .domain_index = 0 },
        },
        .outcome_post_states = &.{
            .{ .output_index = 0, .variant_index = 1, .input_post_states = &.{
                .{ .target = .{ .input_index = 0 }, .initializedness = .moved },
                .{ .target = .{ .input_index = 2 }, .initializedness = .initialized },
            }, .invalidated_domains = &.{
                .{ .path = .{ .input_index = 0 }, .domain_index = 0 },
                .{ .path = .{ .input_index = 2 }, .domain_index = 0 },
            } },
            .{ .output_index = 0, .variant_index = 0, .input_post_states = &.{} },
            .{ .output_index = 1, .variant_index = 1, .input_post_states = &.{
                .{ .target = .{ .input_index = 1 }, .initializedness = .moved },
                .{ .target = .{ .input_index = 2 }, .initializedness = .initialized },
            }, .invalidated_domains = &.{
                .{ .path = .{ .input_index = 1 }, .domain_index = 0 },
                .{ .path = .{ .input_index = 2 }, .domain_index = 0 },
            } },
        },
    };
    const preserving = try infer.selectForwardedEffects(summary, summary.outcome_post_states[1]);
    try std.testing.expectEqual(@as(usize, 3), preserving.input_post_states.len);
    try std.testing.expect(infer.findInputPostState(preserving.input_post_states, .{ .input_index = 0 }) == null);
    try std.testing.expectEqual(.maybe_initialized, infer.findInputPostState(preserving.input_post_states, .{ .input_index = 1 }).?.initializedness);
    try std.testing.expectEqual(.maybe_initialized, infer.findInputPostState(preserving.input_post_states, .{ .input_index = 2 }).?.initializedness);
    try std.testing.expectEqual(@as(usize, 2), preserving.invalidated_domains.len);
    const moving = try infer.selectForwardedEffects(summary, summary.outcome_post_states[0]);
    try std.testing.expectEqual(.moved, infer.findInputPostState(moving.input_post_states, .{ .input_index = 0 }).?.initializedness);
    try std.testing.expectEqual(.maybe_initialized, infer.findInputPostState(moving.input_post_states, .{ .input_index = 2 }).?.initializedness);
}

test "virtual safety contract scalar summaries do not read implementations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var infer = Infer.init(allocator, &graph, &engine);
    defer infer.deinit();
    try graph.virtual_registries.append(allocator, .{
        .implementations = .{ .start = 0, .len = 0 },
        .receiver_input_index = 1,
        .contract_input_count = 2,
        .safety_contract = .{ .output_count = 1, .source = .{ .file_index = 0, .offset = 0 }, .dependencies = &.{.{ .output_index = 0, .input_index = 1 }} },
    });
    const first = (try infer.virtualSummary(@enumFromInt(0))).?;
    try std.testing.expectEqual(@as(usize, 2), first.required_live_inputs.len);
    try std.testing.expectEqual(@as(u32, 1), first.outputs[0].input_receiver_values[0].input_index);
    try std.testing.expectEqual(@as(usize, 0), first.outputs[0].input_dependencies.len);
    // No concrete summaries exist. Changing the implementation list must not
    // introduce a read of a concrete body or change the published call effects.
    try graph.function_refs.appendSlice(allocator, &.{ @enumFromInt(0), @enumFromInt(1) });
    graph.virtual_registries.items[0].implementations.len = 2;
    infer.virtual_summaries.clearRetainingCapacity();
    const second = (try infer.virtualSummary(@enumFromInt(0))).?;
    try std.testing.expect(summaries.summaryEql(first, second));
    var declaration = graph.virtual_registries.items[0].safety_contract.?;
    declaration.output_count = 0;
    declaration.dependencies = &.{};
    declaration.invalidates = &.{0};
    graph.virtual_registries.items[0].safety_contract = declaration;
    infer.virtual_summaries.clearRetainingCapacity();
    const invalidating = (try infer.virtualSummary(@enumFromInt(0))).?;
    try std.testing.expectEqual(@as(usize, 1), invalidating.input_post_states.len);
    try std.testing.expectEqual(@as(u32, 0), invalidating.input_post_states[0].target.input_index);
    try std.testing.expect(invalidating.input_post_states[0].refreshes_storage_generation);
    try std.testing.expect(!invalidating.input_post_states[0].ends_previous_roots);
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

test "array summary projections select and merge element effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, undefined, &engine);
    defer inference.deinit();

    const foreign = facts.ValueEffect{ .foreign_storage = true };
    const local = facts.ValueEffect{ .input_dependencies = &.{.{ .path = .{ .input_index = 2 } }} };
    const array = facts.ValueEffect{ .fields = &.{
        .{ .index = 0, .value = &foreign },
        .{ .index = 1, .value = &local },
    } };
    const first = try inference.projectValueEffect(array, .{ .static_index = 0 });
    try std.testing.expect(first.foreign_storage);
    try std.testing.expectEqual(@as(usize, 0), first.input_dependencies.len);
    const second = try inference.projectValueEffect(array, .{ .static_index = 1 });
    try std.testing.expect(!second.foreign_storage);
    try std.testing.expectEqualDeep(local.input_dependencies, second.input_dependencies);
    const dynamic = try inference.projectValueEffect(array, .dynamic_index);
    try std.testing.expect(dynamic.foreign_storage);
    try std.testing.expectEqualDeep(local.input_dependencies, dynamic.input_dependencies);
    try std.testing.expectEqual(@as(usize, 0), dynamic.fresh_storage_capabilities.len);

    // A uniform foreign array can keep its marker on the aggregate instead
    // of allocating metadata for every element. Individual writes add fields.
    const uniform = facts.ValueEffect{ .foreign_storage = true, .fields = &.{.{ .index = 1, .value = &local }} };
    try std.testing.expect((try inference.projectValueEffect(uniform, .dynamic_index)).foreign_storage);
    try std.testing.expect((try inference.projectValueEffect(.{ .foreign_storage = true }, .{ .static_index = 5 })).foreign_storage);
}

test "large numeric literals keep no per-element summary records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .int_literal = 0 } });
    try graph.node_refs.resize(allocator, 65536);
    @memset(graph.node_refs.items, @enumFromInt(0));
    var engine = summaries.Engine.init(allocator);
    defer engine.deinit();
    var inference = Infer.init(allocator, &graph, &engine);
    defer inference.deinit();
    const value = try inference.inferElements(@enumFromInt(0), .{ .start = 0, .len = 65536 });
    try std.testing.expect(facts.isEmptyValue(value));
    try std.testing.expect(facts.isEmptyValue(try inference.mergeValueEffects(value, value)));
}

fn appendDomain(list: *std.array_list.Managed(facts.InputDomain), domain: facts.InputDomain) !void {
    for (list.items) |existing| {
        if (existing.domain_index != domain.domain_index or existing.path.input_index != domain.path.input_index or existing.path.storage_domain != domain.path.storage_domain or existing.path.projections.len != domain.path.projections.len) continue;
        var same = true;
        for (existing.path.projections, domain.path.projections) |x, y| if (!x.eql(y)) {
            same = false;
            break;
        };
        if (same) return;
    }
    try list.append(domain);
}
