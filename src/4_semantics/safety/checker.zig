const lifecycle_contracts = @import("../global/lifecycle_contracts.zig");
const std = @import("std");
const profile = @import("../../1_base/profile.zig");
const diagnostics = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const facts = @import("facts.zig");
const summary_engine = @import("summaries.zig");
const summary_infer = @import("summary_infer.zig");
const value_state = @import("value_state.zig");
const primitive_transfer = @import("../primitives/registry.zig");
const initializer_contract = @import("../global/initializer_contract.zig");
const primitives = @import("../primitives/schema.zig");

/// Indexed temporal checker. Program identity is exclusively Global*Id; no
/// pointer identity or pointer-based semantic object participates in state.
///
/// Calls execute transactionally against a cloned caller state. Because
/// GlobalBindingId is unique program-wide, pointee Places survive the call and
/// mutations are committed directly without reconstructing symbolic pointer
/// identities. Recursive calls apply summaries converged before concrete
/// validation; inference records dependencies between GlobalFunctionIds.
pub const SafetyChecker = struct {
    pub const Stats = struct {
        timing_io: ?std.Io = null,
        summary_inference_ns: u64 = 0,
        state_copy_ns: u64 = 0,
        summary_allocated_bytes: u64 = 0,
        summary_worklist_bytes: u64 = 0,
        output_inference_ns: u64 = 0,
        required_live_inference_ns: u64 = 0,
        post_state_inference_ns: u64 = 0,
        outcome_inference_ns: u64 = 0,
        opaque_inference_ns: u64 = 0,
        virtual_summary_ns: u64 = 0,
        summary_evaluations: u64 = 0,
        summary_changes: u64 = 0,
        functions: usize = 0,
        calls: usize = 0,
        state_clones: u64 = 0,
        state_elements_copied: u64 = 0,
        primitive_calls: usize = 0,
        recursive_edges: usize = 0,
    };

    const StorageCapabilityState = enum { available, conditional, maybe_consumed, consumed };
    const OwnershipEdge = struct { owner: facts.ValidityRootId, owned: facts.ValidityRootId };
    const StorageGeneration = struct {
        storage: facts.Place,
        generation: facts.ValidityRootId,
        needs_current_generation: bool = false,
    };
    const OpaqueStorage = struct {
        storage: facts.Place,
        hidden_dependencies: []const facts.ValidityRootId,
        outcome_guard: u64 = 0,
        // Identity only: a moved owner's slot can disappear before output
        // checks. These roots associate hidden contents without keeping any
        // resource or lexical generation alive.
        owner_roots: []const facts.ValidityRootId = &.{},
    };
    const ChoiceActive = struct { storage: facts.Place, variant_index: u32 };
    const ChoiceRejected = struct { storage: facts.Place, variant_index: u32 };
    const ChoiceTemporaryActive = struct { expression: graph_mod.GlobalNodeId, variant_index: u32 };

    const SymbolicPointeeState = struct { identity: graph_mod.GlobalBindingId, initializedness: value_state.Initializedness };

    const FunctionState = struct {
        tracker: facts.Tracker,
        places: std.array_list.Managed(facts.PlaceFacts),
        symbolic_pointees: std.array_list.Managed(SymbolicPointeeState),
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
                .symbolic_pointees = std.array_list.Managed(SymbolicPointeeState).init(allocator),
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
            self.symbolic_pointees.deinit();
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
            const io = if (stats) |s| s.timing_io else null;
            const start = profile.timestamp(io);
            defer if (stats) |s| profile.accumulate(io, start, &s.state_copy_ns);
            var out = FunctionState.init(allocator);
            errdefer out.deinit();
            try out.tracker.roots.appendSlice(self.tracker.roots.items);
            try out.places.appendSlice(self.places.items);
            try out.symbolic_pointees.appendSlice(self.symbolic_pointees.items);
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
                s.state_elements_copied += @intCast(self.tracker.roots.items.len + self.places.items.len + self.symbolic_pointees.items.len + self.storage_capabilities.items.len + self.ownership_edges.items.len + self.storage_generations.items.len + self.lexical_storage_generations.items.len + self.opaque_storages.items.len + self.choice_active.items.len + self.choice_rejected.items.len + self.choice_temporary_active.items.len);
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
    // Outputs and input post-states of one call share acquisition identities.
    // Nested calls install their own map so repeated acquisitions stay distinct.
    next_outcome_guard: u64 = 1,
    active_fresh_capabilities: ?*std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId) = null,
    active_summary_inference: ?*summary_infer.Infer = null,
    collect_stats: bool = false,
    profile_io: ?std.Io = null,
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

    pub fn enableStats(self: *SafetyChecker, io: std.Io) void {
        self.collect_stats = true;
        self.profile_io = io;
    }

    pub fn analyze(self: *SafetyChecker) !void {
        self.stats = .{ .timing_io = self.profile_io };
        const before = self.diagnostics.list.items.len;
        try self.validateNominalChoiceLayouts();
        try self.validateForeignSignatures();

        var allocations = profile.AllocationCounter{ .child = self.allocator, .requested_bytes = &self.stats.summary_allocated_bytes };
        const inference_allocator = if (self.collect_stats) allocations.allocator() else self.allocator;
        var engine = summary_engine.Engine.init(inference_allocator);
        defer engine.deinit();
        var inference = summary_infer.Infer.init(inference_allocator, self.graph, &engine);
        defer inference.deinit();
        inference.profile_io = self.profile_io;
        const inference_start = profile.timestamp(self.profile_io);
        try inference.inferSafetySummariesFixedPoint();
        profile.accumulate(self.profile_io, inference_start, &self.stats.summary_inference_ns);
        if (self.collect_stats) {
            self.stats.summary_evaluations = inference.evaluations;
            self.stats.summary_changes = inference.summary_changes;
            self.stats.summary_worklist_bytes = @intCast(engine.worklist.capacity * @sizeOf(graph_mod.GlobalFunctionId));
            self.stats.output_inference_ns = inference.output_ns;
            self.stats.required_live_inference_ns = inference.required_live_ns;
            self.stats.post_state_inference_ns = inference.post_state_ns;
            self.stats.outcome_inference_ns = inference.outcome_ns;
            self.stats.opaque_inference_ns = inference.opaque_ns;
        }
        try self.validateInitializerContracts(&engine);
        try self.validateVirtualSafetyContracts(&inference);
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
        if (self.collect_stats) {
            self.stats.virtual_summary_ns = inference.virtual_summary_ns;
        }
        if (self.diagnostics.list.items.len != before) return error.Reported;
    }

    fn validateVirtualSafetyContracts(self: *SafetyChecker, inference: *summary_infer.Infer) !void {
        // Conformance uses converged concrete summaries. Static selections and
        // virtual table slots share the same proof obligations; neither can
        // weaken a declaration by choosing a different dispatch mechanism.
        for (self.graph.abstract_safety_conformances.items) |conformance| {
            try self.validateAbstractSafetyContract(inference, conformance.contract, conformance.method, conformance.receiver_input_index, conformance.domains, conformance.source);
        }
        for (self.graph.virtualizes.items) |virtualize| {
            for (self.graph.virtual_registry_refs.items[virtualize.safety_methods.start..][0..virtualize.safety_methods.len], 0..) |registry_id, index| {
                const registry = self.graph.virtual_registries.items[@intFromEnum(registry_id)];
                const declared = registry.safety_contract orelse continue;
                const method = self.graph.function_refs.items[virtualize.methods.start + index];
                try self.validateAbstractSafetyContract(inference, declared, method, registry.receiver_input_index, virtualize.domains, virtualize.source);
            }
        }
    }

    fn validateAbstractSafetyContract(self: *SafetyChecker, inference: *summary_infer.Infer, declared: primitives.MethodSafetyContract, method: graph_mod.GlobalFunctionId, receiver: ?u32, domains: []const primitives.StorageDomainMapping, source: primitives.SourceRef) !void {
        const contracts = @import("contracts.zig");
        var contract = try contracts.fromDeclaration(self.allocator, declared);
        if (!try self.resolveContractOpaqueStorage(&contract, domains, method, source)) return;
        for (@constCast(contract.outputs)) |*output| try self.resolveContractDomains(output, domains);
        for (contract.guarded_effects) |guarded| for (@constCast(guarded.effects.outputs)) |*output| try self.resolveContractDomains(output, domains);
        try self.resolveContractInvalidations(&contract, domains);
        const function = self.graph.function(method);
        for (declared.referents) |referent| {
            if (!try self.provesDirectContractReferent(function, referent)) {
                try self.report(source, "method '{s}' cannot prove refers_to: forward the declared reference input directly or through unchanged lexical bindings", .{self.graph.text(self.graph.declaration(function.declaration).name)});
            }
        }
        for (declared.transfers) |transfer| {
            if (!try self.provesDirectContractTransfer(function, transfer))
                try self.report(source, "method '{s}' cannot prove transfers: move the declared input to the output directly or through lexical owners", .{self.graph.text(self.graph.declaration(function.declaration).name)});
        }
        var summary = (try inference.contractImplementationSummary(method, receiver)) orelse {
            try self.report(source, "cannot verify safety contract for this implementation", .{});
            return;
        };
        var scalar_invalidates: std.ArrayList(u32) = .empty;
        try scalar_invalidates.appendSlice(self.allocator, declared.invalidates);
        try self.collectOutcomeInvalidations(declared.outcomes, &scalar_invalidates);
        if (scalar_invalidates.items.len != 0) {
            const states = try self.allocator.dupe(facts.PlacePostState, summary.input_post_states);
            for (states) |*post| for (scalar_invalidates.items) |index| {
                if (post.target.input_index == index and post.target.projections.len == 0) post.may_repopulate_opaque_storage = false;
            };
            summary.input_post_states = states;
            const outcomes = try self.allocator.dupe(facts.OutcomePostStates, summary.outcome_post_states);
            for (outcomes) |*outcome| {
                const states_in_outcome = try self.allocator.dupe(facts.PlacePostState, outcome.input_post_states);
                for (states_in_outcome) |*post| for (scalar_invalidates.items) |index| {
                    if (post.target.input_index == index and post.target.projections.len == 0) post.may_repopulate_opaque_storage = false;
                };
                outcome.input_post_states = states_in_outcome;
            }
            summary.outcome_post_states = outcomes;
        }
        // Domain paths and scalar invalidation normalization precede the
        // general proof conversion. Raw payload views are not interchangeable
        // with complete conditional contracts.
        contract = try contracts.withOutcomeGuards(self.allocator, contract);
        summary = try summary_engine.refreshOutcomeGuards(self.allocator, summary);
        if (contracts.check(contract, summary)) |failure| {
            const method_name = self.graph.text(self.graph.declarationSourceName(function.declaration));
            if (failure.input) |path| {
                const input_name = if (path.input_index < function.input.len) self.graph.text(self.graph.fields.items[function.input.start + path.input_index].name) else "implicit input";
                try self.report(source, "method '{s}' violates its safety contract: {s} involving input '{s}'", .{ method_name, failure.description(), input_name });
            } else try self.report(source, "method '{s}' violates its safety contract: {s}", .{ method_name, failure.description() });
            if (failure.outcome) |outcome| {
                if (outcome.output_index < function.output.len) {
                    const output = self.graph.fields.items[function.output.start + outcome.output_index];
                    var selected_ty = output.ty;
                    for (outcome.parent_variants) |parent| {
                        const enclosing = types.variants(self.graph, selected_ty) orelse break;
                        if (parent >= enclosing.len) break;
                        selected_ty = self.graph.variants.items[enclosing.start + parent].payload_type orelse break;
                    }
                    if (types.variants(self.graph, selected_ty)) |variants| if (outcome.variant_index < variants.len) {
                        const variant = self.graph.variants.items[variants.start + outcome.variant_index];
                        if (failure.kind == .missing_consumption) {
                            try self.report(declared.source, "cannot prove consumes for on {s} ..{s}; deinitialize the input on every path returning this variant", .{ self.graph.text(output.name), self.graph.text(variant.name) });
                        } else try self.report(declared.source, "cannot prove preservation for on {s} ..{s}; declare its generation effects or preserve the input on every continuing path", .{ self.graph.text(output.name), self.graph.text(variant.name) });
                    };
                }
            }
            try self.report(declared.source, "the safety contract is declared here", .{});
        }
    }

    fn collectOutcomeInvalidations(self: *SafetyChecker, outcomes: []const primitives.MethodSafetyContract.Outcome, result: *std.ArrayList(u32)) anyerror!void {
        for (outcomes) |outcome| {
            try result.appendSlice(self.allocator, outcome.invalidates);
            try self.collectOutcomeInvalidations(outcome.outcomes, result);
        }
    }

    fn resolveContractInvalidations(self: *SafetyChecker, contract: *@import("contracts.zig").Contract, mappings: []const primitives.StorageDomainMapping) anyerror!void {
        var invalidates: std.ArrayList(facts.InputPath) = .empty;
        try invalidates.appendSlice(self.allocator, contract.invalidates);
        for (contract.invalidated_domains) |domain| for (mappings) |mapping| {
            if (mapping.domain_index != domain.domain_index) continue;
            for (mapping.paths) |path| {
                const projections = try self.allocator.alloc(facts.Projection, path.fields.len);
                for (path.fields, projections) |field, *projection| projection.* = .{ .field = field };
                try invalidates.append(self.allocator, .{ .input_index = domain.path.input_index, .projections = projections });
            }
        };
        contract.invalidates = try invalidates.toOwnedSlice(self.allocator);
        for (contract.outcomes) |outcome| try self.resolveContractInvalidations(@constCast(outcome.effects), mappings);
        for (contract.guarded_effects) |guarded| try self.resolveContractInvalidations(@constCast(guarded.effects), mappings);
    }

    fn resolveOpaqueContractPath(self: *SafetyChecker, path: facts.InputPath, mappings: []const primitives.StorageDomainMapping, method: graph_mod.GlobalFunctionId, source: primitives.SourceRef) !?facts.InputPath {
        const domain = path.storage_domain orelse return path;
        for (mappings) |mapping| if (mapping.domain_index == domain) {
            if (mapping.paths.len != 1) {
                try self.report(source, "opaque storage effects require one mapped storage identity per domain; grouped domains require exact hidden transfer proofs", .{});
                return null;
            }
            const fields = mapping.paths[0].fields;
            const function = self.graph.function(method);
            var ty = self.graph.semanticType(self.graph.fields.items[function.input.start + path.input_index].ty).pointer.child;
            for (fields) |field| {
                if (self.graph.semanticType(ty) == .pointer) {
                    try self.report(source, "opaque storage domain mappings cannot cross reference fields; use a known storage input until referent identities are represented", .{});
                    return null;
                }
                ty = self.fieldTypeAt(ty, field) orelse return error.MissingVirtualStorageDomain;
            }
            if (self.graph.semanticType(ty) == .pointer) {
                try self.report(source, "opaque storage domain mappings cannot select reference fields; map an owned storage field instead", .{});
                return null;
            }
            const projections = try self.allocator.alloc(facts.Projection, fields.len);
            for (fields, projections) |field, *projection| projection.* = .{ .field = field };
            return .{ .input_index = path.input_index, .projections = projections };
        };
        try self.report(source, "opaque storage effect has no concrete domain mapping", .{});
        return null;
    }

    fn resolveContractOpaqueStorage(self: *SafetyChecker, contract: *@import("contracts.zig").Contract, mappings: []const primitives.StorageDomainMapping, method: graph_mod.GlobalFunctionId, source: primitives.SourceRef) anyerror!bool {
        for (@constCast(contract.retained_inputs)) |*retained| retained.storage = try self.resolveOpaqueContractPath(retained.storage, mappings, method, source) orelse return false;
        for (@constCast(contract.emptied_inputs)) |*empty| empty.* = try self.resolveOpaqueContractPath(empty.*, mappings, method, source) orelse return false;
        for (@constCast(contract.outputs)) |*output| if (!try self.resolveOpaqueOutputStorage(output, mappings, method, source)) return false;
        for (contract.outcomes) |outcome| if (!try self.resolveContractOpaqueStorage(@constCast(outcome.effects), mappings, method, source)) return false;
        for (contract.guarded_effects) |guarded| if (!try self.resolveContractOpaqueStorage(@constCast(guarded.effects), mappings, method, source)) return false;
        return true;
    }

    fn resolveOpaqueOutputStorage(self: *SafetyChecker, output: *@import("contracts.zig").Output, mappings: []const primitives.StorageDomainMapping, method: graph_mod.GlobalFunctionId, source: primitives.SourceRef) anyerror!bool {
        for (@constCast(output.storage_sources)) |*path| path.* = try self.resolveOpaqueContractPath(path.*, mappings, method, source) orelse return false;
        for (output.outcomes) |outcome| if (!try self.resolveOpaqueOutputStorage(@constCast(outcome.value), mappings, method, source)) return false;
        return true;
    }

    fn resolveContractDomains(self: *SafetyChecker, output: *@import("contracts.zig").Output, domains: []const primitives.StorageDomainMapping) anyerror!void {
        var paths: std.ArrayList(facts.InputPath) = .empty;
        try paths.appendSlice(self.allocator, output.dependencies);
        for (output.domains) |domain| for (domains) |mapping| {
            if (mapping.domain_index != domain.domain_index) continue;
            for (mapping.paths) |path| {
                const projections = try self.allocator.alloc(facts.Projection, path.fields.len);
                for (path.fields, projections) |field, *projection| projection.* = .{ .field = field };
                try paths.append(self.allocator, .{ .input_index = domain.path.input_index, .projections = projections });
            }
        };
        output.dependencies = try paths.toOwnedSlice(self.allocator);
        for (output.outcomes) |outcome| try self.resolveContractDomains(@constCast(outcome.value), domains);
    }

    fn provesDirectContractTransfer(self: *SafetyChecker, function: graph_mod.Function, transfer: primitives.MethodSafetyContract.Dependency) !bool {
        return self.provesLexicalContractForwarding(function, transfer, true);
    }

    fn provesDirectContractReferent(self: *SafetyChecker, function: graph_mod.Function, referent: primitives.MethodSafetyContract.Dependency) !bool {
        return self.provesLexicalContractForwarding(function, referent, false);
    }

    /// A may-dependency summary cannot establish exact identity. Follow only
    /// ordered lexical links, independently of the converged effect check.
    /// Every ownership link moves the value; unknown effects or control flow
    /// cannot certify that a later result retains the declared identity.
    fn provesLexicalContractForwarding(self: *SafetyChecker, function: graph_mod.Function, relation: primitives.MethodSafetyContract.Dependency, owning: bool) !bool {
        const block = self.graph.blocks.items[@intFromEnum(function.body orelse return false)];
        if (relation.input_index >= function.input_bindings.len or relation.output_index >= function.output_bindings.len) return false;
        const input = self.graph.binding_refs.items[function.input_bindings.start + relation.input_index];
        const output = self.graph.binding_refs.items[function.output_bindings.start + relation.output_index];
        var links = std.array_list.Managed(graph_mod.GlobalBindingId).init(self.allocator);
        defer links.deinit();
        try links.append(input);
        var assigned = false;
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |id| switch (self.graph.node(id).content) {
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (record.deferred_initialization or binding == output or linksContains(links.items, binding)) return false;
                const initializer = record.initialization orelse return false;
                if (!self.isForwardingLink(initializer, links.items, owning)) return false;
                try links.append(binding);
            },
            .assignment => |assignment| {
                if (assignment.binding != output or assigned) return false;
                if (!self.isForwardingLink(assignment.value, links.items, owning)) return false;
                assigned = true;
            },
            .auto_deinit_binding => {},
            .return_statement => |ret| return ret.expression == null and assigned,
            else => return false,
        };
        return assigned;
    }

    fn linksContains(links: []const graph_mod.GlobalBindingId, binding: graph_mod.GlobalBindingId) bool {
        return std.mem.indexOfScalar(graph_mod.GlobalBindingId, links, binding) != null;
    }

    fn isForwardingLink(self: *SafetyChecker, id: graph_mod.GlobalNodeId, links: []const graph_mod.GlobalBindingId, owning: bool) bool {
        var expression = self.graph.node(id).content;
        if (owning) {
            if (expression != .move_value) return false;
            expression = self.graph.node(expression.move_value).content;
        }
        return expression == .binding_use and linksContains(links, expression.binding_use);
    }

    fn validateInitializerContracts(self: *SafetyChecker, engine: *summary_engine.Engine) !void {
        _ = engine;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null) continue;
            const declaration = self.graph.declaration(function.declaration);

            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (lifecycle_contracts.initializedType(self.graph, id) == null) continue;
            if (initializer_contract.classify(self.graph, id) == .invalid)
                try self.report(declaration.source, "initializer must return its constructed type or one Errable of that type", .{});
        }
    }

    fn findInputPostState(self: *SafetyChecker, states: []const facts.PlacePostState, path: facts.InputPath) ?facts.PlacePostState {
        _ = self;
        for (states) |state| {
            if (state.target.input_index != path.input_index or state.target.projections.len != path.projections.len) continue;
            var same = true;
            for (state.target.projections, path.projections) |left, right| if (!left.eql(right)) {
                same = false;
                break;
            };
            if (same) return state;
        }
        return null;
    }

    fn appendInputProjection(self: *SafetyChecker, path: facts.InputPath, projection: facts.Projection) !facts.InputPath {
        const projections = try self.allocator.alloc(facts.Projection, path.projections.len + 1);
        @memcpy(projections[0..path.projections.len], path.projections);
        projections[path.projections.len] = projection;
        return .{ .input_index = path.input_index, .projections = projections };
    }

    fn validateForeignSignatures(self: *SafetyChecker) !void {
        const c_abi = @import("../global/c_abi.zig");
        for (self.graph.bindings.items) |binding| {
            if (types.incompleteDeclaration(self.graph, binding.ty)) |id|
                try self.report(binding.source, "CIncomplete type '{s}' has no value representation; use RawPointer for foreign handles", .{self.graph.text(self.graph.declaration(id).name)});
            if (self.graph.resolvedSemanticType(binding.ty)) |semantic| {
                if (semantic == .pointer) {
                    if (types.incompleteDeclaration(self.graph, semantic.pointer.child)) |id|
                        try self.report(binding.source, "cannot form a safe reference to CIncomplete type '{s}'; use RawPointer for foreign handles", .{self.graph.text(self.graph.declaration(id).name)});
                }
            }
        }
        for (self.graph.declarations.items) |declaration| {
            if (declaration.struct_layout != .c_struct) continue;
            const fields = declaration.struct_fields orelse continue;
            if (fields.len == 0) try self.report(declaration.source, "CStruct '{s}' must contain at least one field", .{self.graph.text(declaration.name)});
            for (self.graph.fields.items[fields.start..][0..fields.len]) |field| {
                if (!c_abi.supportsRepresentation(self.graph, field.ty))
                    try self.report(field.source, "CStruct '{s}' field '{s}' has no supported C representation", .{ self.graph.text(declaration.name), self.graph.text(field.name) });
            }
        }
        for (self.graph.generic_instances.items) |instance| {
            const shape = switch (instance.shape) {
                .structure => |value| value,
                else => continue,
            };
            if (shape.layout != .c_struct) continue;
            if (shape.fields.len == 0) try self.report(self.graph.declaration(self.graph.types.items[@intFromEnum(instance.type_id)].generic.base).source, "CStruct must contain at least one field", .{});
            for (self.graph.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                if (!c_abi.supportsRepresentation(self.graph, field.ty))
                    try self.report(field.source, "CStruct field '{s}' has no supported C representation", .{self.graph.text(field.name)});
            }
        }
        for (self.graph.functions.items) |function| {
            if (function.flags.is_abstract_dispatch) continue;
            if (!function.flags.is_c_abi and (function.body != null or function.flags.has_declared_body)) continue;
            const declaration = self.graph.declaration(function.declaration);
            const name = self.graph.text(declaration.name);
            if (function.output.len > 1) {
                try self.report(declaration.source, "C function '{s}' must have zero or one output; use explicit pointer parameters for additional results", .{name});
            }
            for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
                if (function.flags.is_c_function_pointer and index < c_abi.physicalInputCount(function) and c_abi.isSafeReferenceValue(self.graph, field.ty))
                    try self.report(field.source, "CFunctionPointer parameters require RawPointer instead of safe references", .{});
                if (!c_abi.supportsCValue(self.graph, field.ty))
                    try self.report(field.source, "C function '{s}' input '{s}' has an unsupported C ABI type; aggregate arguments require target-specific lowering", .{ name, self.graph.text(field.name) });
            }
            for (self.graph.fields.items[function.output.start..][0..function.output.len]) |field| {
                if (function.flags.is_c_function_pointer and c_abi.isSafeReferenceValue(self.graph, field.ty))
                    try self.report(field.source, "CFunctionPointer results require RawPointer instead of safe references", .{});
                if (!c_abi.supportsCValue(self.graph, field.ty))
                    try self.report(field.source, "C function '{s}' output '{s}' has an unsupported C ABI type; aggregate results require target-specific lowering", .{ name, self.graph.text(field.name) });
            }
        }
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
            var value: facts.ValueFacts = if (isPointer(self.graph, record.ty)) blk: {
                const root = shared_pointer_root orelse root_blk: {
                    const created = try state.tracker.establish(.fresh);
                    shared_pointer_root = created;
                    break :root_blk created;
                };
                try state.symbolic_pointees.append(.{ .identity = binding, .initializedness = .initialized });
                break :blk .{ .dependencies = try self.oneDependency(root), .symbolic_pointees = try self.allocator.dupe(graph_mod.GlobalBindingId, &.{binding}) };
            } else .{};
            const ty = if (isPointer(self.graph, record.ty)) self.graph.semanticType(record.ty).pointer.child else record.ty;
            if (self.graph.semanticType(ty) == .virtual) {
                for (self.graph.virtualizes.items) |virtualize| {
                    if (!types.equal(self.graph, ty, virtualize.virtual_type) or virtualize.domains.len == 0) continue;
                    const domains = try self.allocator.alloc(facts.DomainFacts, virtualize.domains.len);
                    for (virtualize.domains, domains) |mapping, *domain| {
                        const storage = try self.project(.{ .root = binding }, .{ .field = mapping.domain_index });
                        _ = try self.storageGeneration(state, storage);
                        const places = try self.allocator.alloc(facts.Place, 1);
                        places[0] = storage;
                        domain.* = .{ .domain_index = mapping.domain_index, .storages = places };
                    }
                    value.domains = domains;
                    break;
                }
            }
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
        try self.validateBlockWithResult(function, block_id, state, loop_transfers, null);
    }

    fn validateBlockWithResult(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        block_id: graph_mod.GlobalBlockId,
        state: *FunctionState,
        loop_transfers: ?*LoopTransfers,
        result: ?*facts.ValueFacts,
    ) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        const nodes = self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len];
        for (nodes, 0..) |node_id, node_index| {
            if (!state.reachable) break;
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .binding_declaration => |binding| {
                    const record = self.graph.bindings.items[@intFromEnum(binding)];
                    const storage = facts.Place{ .root = binding };
                    try self.beginLexicalStorage(state, storage);
                    const value = if (!record.deferred_initialization) if (record.initialization) |initialization| blk: {
                        try self.validateContextualIntegerLiteral(initialization, record.ty);
                        break :blk try self.evaluate(function, initialization, state);
                    } else facts.ValueFacts{} else facts.ValueFacts{};
                    try self.setPlace(state, .{ .root = binding }, if (record.initialization != null and !record.deferred_initialization) .initialized else .deinitialized, value);
                },
                .assignment => |assignment| {
                    const binding = self.graph.binding(assignment.binding);
                    const storage = facts.Place{ .root = assignment.binding };
                    const previous_state = self.initializednessAtPlace(state, storage);
                    if (previous_state == .moved)
                        try self.reportMovedReassignment(node.source, storage, state);
                    if (binding.mutability == .constant and previous_state == .initialized)
                        try self.report(node.source, "binding '{s}' is constant and cannot be reassigned after initialization", .{self.graph.text(binding.name)});
                    if (previous_state == .deinitialized)
                        try self.refreshStorageGenerationChecked(node.source, state, storage);
                    try self.validateContextualIntegerLiteral(assignment.value, self.graph.binding(assignment.binding).ty);
                    const value = try self.evaluate(function, assignment.value, state);
                    try self.setPlace(state, .{ .root = assignment.binding }, .initialized, value);
                },
                .auto_deinit_binding => |auto_id| {
                    if (self.graph.function(function).body == block_id) {
                        const final_cleanup = for (nodes[node_index..]) |remaining| {
                            if (self.graph.node(remaining).content != .auto_deinit_binding) break false;
                        } else true;
                        // Fallthrough has the same escape rule as an explicit
                        // return. Check before cleanup erases local owners.
                        if (final_cleanup) try self.rejectEscapingOutputBindings(function, state);
                    }
                    try self.applyAutoDeinit(function, auto_id, state);
                },
                .struct_field_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, node.source, store.struct_ptr, state) orelse continue;
                    const value = try self.evaluate(function, store.value, state);
                    try self.recordOpaqueWrite(node.source, state, pointer, value);
                    if (try self.resolvePlace(store.struct_ptr, state)) |base|
                        try self.setPlace(state, try self.project(base, .{ .field = store.field_index }), .initialized, value);
                },
                .array_store => |store| {
                    const pointer = try self.evaluatePointerUse(function, node.source, store.array_ptr, state) orelse continue;
                    _ = try self.evaluate(function, store.index, state);
                    const value = try self.evaluate(function, store.value, state);
                    try self.recordOpaqueWrite(node.source, state, pointer, value);
                    if (try self.resolvePlace(store.array_ptr, state)) |base| {
                        const projection: facts.Projection = if (self.staticIndex(store.index)) |index| .{ .static_index = index } else .dynamic_index;
                        try self.setPlace(state, try self.project(base, projection), .initialized, value);
                    }
                },
                .pointer_assignment => |assignment| {
                    const pointer_node = self.graph.node(assignment.pointer);
                    var pointer = switch (pointer_node.content) {
                        .address_of => |child| try self.evaluateAddress(function, pointer_node.source, child, state, true),
                        else => try self.evaluate(function, assignment.pointer, state),
                    };
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
                    try self.recordOpaqueWrite(node.source, state, pointer, value);
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
                .abort_statement => state.reachable = false,
                .code_block => |nested| try self.validateBlock(function, nested, state, loop_transfers),
                else => {
                    const value = try self.evaluate(function, node_id, state);
                    if (block.ret_val != null and block.ret_val.? == node_id) if (result) |out| {
                        out.* = value;
                    };
                },
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
                try self.activate_conditional_resources(&branch, payload);
                try self.beginLexicalStorage(&branch, .{ .root = binding });
                try self.setPlace(&branch, .{ .root = binding }, .initialized, switch (case.payload_mode) {
                    .value, .move => payload,
                    .borrow, .mut_borrow => payload.referenceCopy(),
                });
                if (case.payload_mode == .move) if (try self.resolvePlace(sw.expression, &branch)) |storage| {
                    // Moving a choice payload consumes the discriminated value.
                    // Keeping the aggregate initialized would allow another
                    // branch-sensitive read to observe the transferred payload.
                    try self.markMoved(&branch, storage, .{}, self.graph.node(sw.expression).source);
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
                const storage = facts.Place{ .root = binding };
                const place = self.getPlace(state, storage) orelse break :blk .{};
                try self.requirePlaceInitialized(function, node.source, storage, place.initializedness, state);
                try self.requireDescendantsInitialized(function, node.source, storage, state);
                var value = try self.refineGeneralValue(try self.reconstructPlaceValue(state, storage, place.value), state);
                value.known_choice_variant = self.activeVariant(state, storage) orelse value.known_choice_variant;
                if (valueHasDeadExplicitDependencyForUse(value, state, isPointer(self.graph, self.graph.binding(binding).ty)))
                    try self.report(node.source, "{s} depends on a root that has ended", .{if (isPointer(self.graph, self.graph.binding(binding).ty)) "reference" else "value"});
                break :blk value;
            },
            .move_value => |child| blk: {
                const value = try self.evaluate(function, child, state);
                if (try self.resolvePlace(child, state)) |storage| {
                    try self.requirePlaceInitialized(function, node.source, storage, self.initializednessAtPlace(state, storage), state);
                    try self.markMoved(state, storage, value, node.source);
                }
                break :blk value;
            },
            .denied_implicit_copy => |child| blk: {
                const diagnostic_count = self.diagnostics.list.items.len;
                const value = try self.evaluate(function, child, state);
                if (self.diagnostics.list.items.len == diagnostic_count) {
                    var type_name = std.array_list.Managed(u8).init(self.allocator);
                    defer type_name.deinit();
                    try appendSafetyTypeName(&type_name, self.graph, node.ty orelse self.graph.node(child).ty.?);
                    try self.report(node.source, "type '{s}' cannot be copied implicitly; use '~value' to transfer ownership", .{type_name.items});
                }
                break :blk value;
            },
            .address_of => |child| try self.evaluateAddress(function, node.source, child, state, false),
            .dereference => |deref| blk: {
                const pointer = try self.evaluatePointerUse(function, node.source, deref.pointer, state) orelse break :blk .{};
                var value: facts.ValueFacts = .{};
                if (pointer.referenced_place) |storage| {
                    const initializedness = self.initializednessAtPlace(state, storage);
                    try self.requireInitialized(function, node.source, initializedness);
                    try self.requireDescendantsInitialized(function, node.source, storage, state);
                    value = try self.reconstructPlaceValue(state, storage, self.valueAtPlace(state, storage) orelse .{});
                }
                break :blk try self.envelopeOpaqueRead(state, value, node.ty, pointer);
            },
            .struct_field_access => |access| blk: {
                const diagnostic_count = self.diagnostics.list.items.len;
                try self.validateAddressAccess(function, node.source, access.value, state);
                if (self.diagnostics.list.items.len != diagnostic_count) break :blk .{};
                if (try self.resolvePlace(node_id, state)) |storage| {
                    const initializedness = self.initializednessAtPlace(state, storage);
                    try self.requirePlaceInitialized(function, node.source, storage, initializedness, state);
                    if (self.valueAtPlace(state, storage)) |value| {
                        try self.requireDescendantsInitialized(function, node.source, storage, state);
                        const provenance = try self.opaqueProvenanceCarriedByAccess(access.value, state);
                        break :blk try self.addOpaqueReadEnvelope(try self.refineGeneralValue(try self.reconstructPlaceValue(state, storage, value), state), node.ty, provenance);
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
                    try self.requirePlaceInitialized(function, node.source, storage, initializedness, state);
                    try self.requireDescendantsInitialized(function, node.source, storage, state);
                    value = try self.reconstructPlaceValue(state, storage, self.valueAtPlace(state, storage) orelse .{});
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
                var value = (try self.evaluate(function, virtualize.value, state)).referenceCopy();
                if (virtualize.domains.len != 0 and value.referenced_place == null) {
                    var pointer = virtualize.value;
                    const address = self.graph.node(pointer).content;
                    if (address == .address_of) {
                        const child = self.graph.node(address.address_of).content;
                        if (child == .dereference) pointer = child.dereference.pointer;
                    }
                    if (try self.resolvePlace(pointer, state)) |slot| {
                        if (self.functionInputIndex(function, slot.root) != null) {
                            // Symbolic input referents are caller storage, not
                            // this function's argument slot. Keep a distinct
                            // dereference path for their domain generations.
                            const receiver = try self.project(slot, .dereference);
                            const contents = try self.initializedValueAtPlace(state, receiver, virtualize.concrete_type);
                            try self.setPlace(state, receiver, .initialized, contents);
                            value.referenced_place = receiver;
                        }
                    }
                }
                if (value.referenced_place) |receiver| if (virtualize.domains.len != 0) {
                    var domains: std.ArrayList(facts.DomainFacts) = .empty;
                    var captured: std.ArrayList(@import("domains.zig").Captured) = .empty;
                    defer captured.deinit(self.allocator);
                    for (virtualize.domains) |mapping| {
                        var storages: std.ArrayList(facts.Place) = .empty;
                        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                        defer dependencies.deinit();
                        var visited = std.array_list.Managed(facts.Place).init(self.allocator);
                        defer visited.deinit();
                        for (mapping.paths) |path| {
                            var storage = receiver;
                            var ty = virtualize.concrete_type;
                            for (path.fields) |field| {
                                if (self.graph.semanticType(ty) == .pointer) {
                                    const stored: facts.ValueFacts = self.valueAtPlace(state, storage) orelse .{};
                                    storage = stored.referenced_place orelse storage;
                                    ty = self.graph.semanticType(ty).pointer.child;
                                }
                                storage = try self.project(storage, .{ .field = field });
                                ty = self.fieldTypeAt(ty, field) orelse return error.InvalidDomainMapping;
                            }
                            try storages.append(self.allocator, storage);
                            try self.captureContractStorage(function, virtualize.source, state, storage, ty, &dependencies, &visited);
                        }
                        const roots = try self.allocator.alloc(facts.ValidityRootId, visited.items.len);
                        for (visited.items, roots) |storage, *root| root.* = try self.storageGeneration(state, storage);
                        try captured.append(self.allocator, .{ .domain = @enumFromInt(mapping.domain_index), .generations = roots });
                        try domains.append(self.allocator, .{ .domain_index = mapping.domain_index, .storages = try storages.toOwnedSlice(self.allocator) });
                    }
                    if (@import("domains.zig").validateCaptured(captured.items)) |_| try self.report(virtualize.source, "Abstract storage domains share a storage generation and cannot be invalidated independently", .{});
                    value.domains = try domains.toOwnedSlice(self.allocator);
                };
                if (value.referenced_place) |receiver_place| if (virtualize.domains.len == 0) {
                    var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                    try dependencies.appendSlice(value.dependencies);
                    var visited = std.array_list.Managed(facts.Place).init(self.allocator);
                    defer visited.deinit();
                    try self.captureContractStorage(function, virtualize.source, state, receiver_place, virtualize.concrete_type, &dependencies, &visited);
                    value.dependencies = try dependencies.toOwnedSlice();
                };
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
                // Cleanup belongs to the propagation's error exit. Validate it
                // on a branch state so its mutations cannot affect the success
                // continuation that receives the unwrapped value.
                var error_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                defer error_state.deinit();
                try self.rejectPropagatedLocalError(function, node.source, prop.errable_value, prop.error_variant, value, &error_state);
                for (self.graph.node_refs.items[prop.cleanup_nodes.start..][0..prop.cleanup_nodes.len]) |cleanup|
                    _ = try self.evaluate(function, cleanup, &error_state);
                break :blk try self.error_success_facts(prop.errable_value, prop.ok_variant, prop.ok_value_field_index, value, state);
            },
            .error_context => |ctx_id| blk: {
                const ctx = self.graph.error_contexts.items[@intFromEnum(ctx_id)];
                const value = try self.evaluate(function, ctx.errable_value, state);
                var error_state = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                defer error_state.deinit();
                try self.rejectPropagatedLocalError(function, node.source, ctx.errable_value, ctx.error_variant, value, &error_state);
                _ = try self.evaluate(function, ctx.context, &error_state);
                for (self.graph.node_refs.items[ctx.cleanup_nodes.start..][0..ctx.cleanup_nodes.len]) |cleanup|
                    _ = try self.evaluate(function, cleanup, &error_state);
                break :blk try self.error_success_facts(ctx.errable_value, ctx.ok_variant, ctx.ok_value_field_index, value, state);
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
                // Converting a live reference to its numeric address observes
                // the reference but the resulting integer carries no temporal
                // dependency on the referenced root.
                if (!isPointer(self.graph, cast.target_type)) break :blk .{};
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
            .value_sequence => |block| blk: {
                var value: facts.ValueFacts = .{};
                try self.validateBlockWithResult(function, block, state, null, &value);
                break :blk value;
            },
            .code_block => |block| blk: {
                try self.validateBlock(function, block, state, null);
                break :blk .{};
            },
            .int_literal => |value| blk: {
                try self.validateIntegerLiteral(node.source, node.ty, value);
                break :blk .{};
            },
            .testing_expect_error => |id| blk: {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                _ = try self.evaluate(function, expect.expected_reason, state);
                _ = try self.evaluate(function, expect.actual_result, state);
                const input = expect.test_fail_input orelse break :blk .{};
                break :blk try self.evaluateCall(function, node_id, .{ .callee = expect.test_fail_function, .input = input }, state);
            },

            .float_literal, .char_literal, .string_literal, .bool_literal, .declaration, .reach_directive, .break_statement, .continue_statement, .abort_statement => .{},
            else => .{},
        };
    }

    fn rejectPropagatedLocalError(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        errable: graph_mod.GlobalNodeId,
        error_variant: graph_mod.GlobalVariantId,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        const ty = self.graph.node(errable).ty orelse return;
        const index = variantIndex(self.graph, ty, error_variant) orelse return;
        if (value.known_choice_variant) |known| if (known != index) return;
        // ! and !! return the error payload before ordinary success resumes.
        // Its tracer and other dependencies obey the same output lifetime
        // rule as an explicit return, before branch cleanup destroys locals.
        const failure = try self.projectValueFacts(value, &.{.{ .variant = index }});
        try self.rejectEscapingLocalRoots(function, source, failure, state);
    }

    // Propagation continues only on success. Its runtime value is the selected
    // payload, with any wrapper field selected by semantizing, not the Errable.
    fn error_success_facts(
        self: *SafetyChecker,
        errable: graph_mod.GlobalNodeId,
        ok_variant: graph_mod.GlobalVariantId,
        value_field: ?u32,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) !facts.ValueFacts {
        const ty = self.graph.node(errable).ty orelse return .{};
        const index = variantIndex(self.graph, ty, ok_variant) orelse return .{};
        var success = try self.projectValueFacts(value, &.{.{ .variant = index }});
        if (value_field) |field| success = try self.projectValueFacts(success, &.{.{ .field = field }});
        try self.activate_conditional_resources(state, success);
        return success;
    }

    fn initializedValueAtPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, ty: graph_mod.GlobalTypeId) anyerror!facts.ValueFacts {
        var result = self.valueAtPlace(state, storage) orelse facts.ValueFacts{};
        const range = types.fields(self.graph, ty) orelse return result;
        const fields = try self.allocator.alloc(facts.FieldFacts, range.len);
        for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = try self.initializedValueAtPlace(state, try self.project(storage, .{ .field = @intCast(index) }), types.effectiveFieldType(field));
            fields[index] = .{ .index = @intCast(index), .value = child };
            result = try self.mergeValueFacts(result, child.*);
        }
        result.fields = fields;
        return result;
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
        if (@hasField(@TypeOf(call), "callee_value")) {
            if (call.callee_value) |value| _ = try self.evaluate(caller, value, &candidate);
        }
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
            const summary = if (self.active_summaries) |engine| engine.summaryFor(call.callee) else null;
            const destination = if (callee.safety_primitive == .relocate) index == 1 else if (summary) |effects| initializesInput(effects, index) else false;
            const node = self.graph.node(field.value);
            values[index] = if (destination and node.content == .address_of)
                try self.evaluateAddress(caller, node.source, node.content.address_of, state, true)
            else
                try self.evaluate(caller, field.value, state);
        }

        if (callee.flags.has_foreign_capability) {
            const summary = (self.active_summaries orelse return error.MissingSafetySummary).summaryFor(call.callee) orelse return error.MissingSafetySummary;
            if (!try self.validateSummaryRequiredLive(input_node.source, summary, values, state)) return .{};
        }

        if (callee.safety_primitive != .none) {
            if (self.active_summaries) |engine| if (engine.summaryFor(call.callee)) |summary| {
                if (!try self.validateSummaryRequiredOpaque(input_node.source, summary, values, state)) return .{};
            };
            if (self.collect_stats) self.stats.primitive_calls += 1;
            return self.evaluatePrimitive(caller, callee.safety_primitive, argument_nodes, values, state, input_node.source);
        }
        if (callee.body == null) {
            // Argument evaluation is still part of the successful call and is
            // committed by the outer transaction. Foreign pointers themselves
            // do not become safe references implicitly.
            if (callee.output.len == 1)
                return @import("foreign_result.zig").value(facts.ValueFacts, self.allocator, self.graph, self.graph.fields.items[callee.output.start].ty);
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
        const summary = try self.selectEntryGuardedSummary(engine.summaryFor(callee) orelse return null, values, state);
        var call_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator);
        defer call_capabilities.deinit();
        const previous_capabilities = self.active_fresh_capabilities;
        self.active_fresh_capabilities = &call_capabilities;
        defer self.active_fresh_capabilities = previous_capabilities;
        if (!try self.validateSummaryRequiredLive(source, summary, values, state)) return facts.ValueFacts{};
        if (!try self.validateConsumedInputAliasing(source, summary, argument_nodes, values, state)) return facts.ValueFacts{};
        if (call_node) |node| try self.recordFunctionCallAutoDeinit(node, summary, argument_nodes, values, state);
        const prepared = try self.prepareGeneralValueGuards(summary, values, state);
        const result = try self.applyOutcomeSummary(source, summary, argument_nodes, values, state);
        return try self.attachGeneralValueGuards(summary, prepared, result);
    }

    /// Input conditions are evaluated before applying any call effect. Reading
    /// the same mutable input after the call cannot establish an entry tag.
    fn selectEntryGuardedSummary(self: *SafetyChecker, summary: facts.SafetySummary, arguments: []const facts.ValueFacts, state: *FunctionState) !facts.SafetySummary {
        var selected: ?facts.GuardedSafetyEffects = null;
        for (summary.guarded_effects) |guarded| {
            if (guarded.conditions.impossible) continue;
            var satisfied = true;
            for (guarded.conditions.terms) |condition| {
                if (condition.subject != .entry_input or condition.index >= arguments.len) {
                    satisfied = false;
                    break;
                }
                const value = try self.entryConditionValue(arguments[condition.index], condition.projections, state) orelse {
                    satisfied = false;
                    break;
                };
                if (value.known_choice_variant == null or value.known_choice_variant.? != condition.variant_index) {
                    satisfied = false;
                    break;
                }
            }
            if (!satisfied) continue;
            // Each record is a complete sound approximation. Prefer a proven
            // stronger guard without constructing combinations of effect sets.
            if (selected == null or guarded.conditions.implies(selected.?.conditions)) selected = guarded;
        }
        return if (selected) |guarded| guarded.effects.* else summary;
    }

    fn entryConditionValue(self: *SafetyChecker, initial: facts.ValueFacts, projections: []const facts.Projection, state: *FunctionState) !?facts.ValueFacts {
        var value = initial;
        for (projections) |projection| switch (projection) {
            .dereference => {
                if (!state.tracker.dependenciesAreAlive(value)) return null;
                const target = value.referenced_place orelse return null;
                if (self.initializednessAtPlace(state, target) != .initialized) return null;
                const stored = self.valueAtPlace(state, target) orelse return null;
                value = try self.reconstructPlaceValue(state, target, stored);
                value.known_choice_variant = self.activeVariant(state, target) orelse value.known_choice_variant;
            },
            .field, .static_index => {
                const index: usize = if (projection == .field) projection.field else projection.static_index;
                var next: ?facts.ValueFacts = null;
                for (value.fields) |field| if (field.index == index) {
                    next = field.value.*;
                    break;
                };
                value = next orelse return null;
            },
            .variant => |index| {
                if (value.known_choice_variant == null or value.known_choice_variant.? != index) return null;
                var next: ?facts.ValueFacts = null;
                for (value.variants) |variant| if (variant.index == index) {
                    next = variant.value.*;
                    break;
                };
                value = next orelse return null;
            },
            .dynamic_index => return null,
        };
        return value;
    }

    const PreparedValueGuard = struct { output_index: u32, proof: facts.GuardedValueFacts };

    /// Capture historical entry tags and payload provenance before the call can
    /// replace any input. Later tag tests only provide output evidence.
    fn prepareGeneralValueGuards(self: *SafetyChecker, summary: facts.SafetySummary, arguments: []const facts.ValueFacts, state: *FunctionState) ![]const PreparedValueGuard {
        var prepared: std.ArrayList(PreparedValueGuard) = .empty;
        const call = self.next_outcome_guard;
        self.next_outcome_guard += 1;
        for (summary.guarded_effects) |guarded| {
            if (guarded.origin != .general or guarded.conditions.impossible) continue;
            var known: std.ArrayList(facts.ChoiceCondition) = .empty;
            defer known.deinit(self.allocator);
            for (guarded.conditions.terms) |condition| {
                if (condition.subject != .entry_input or condition.index >= arguments.len) continue;
                if (try self.entryConditionValue(arguments[condition.index], condition.projections, state)) |value| if (value.known_choice_variant) |variant| {
                    var observed = condition;
                    observed.variant_index = variant;
                    try known.append(self.allocator, observed);
                };
            }
            const entry = try @import("choice_conditions.zig").normalize(self.allocator, known.items);
            for (guarded.effects.outputs, 0..) |effect, index| {
                if (effectHasFreshRoles(effect)) continue;
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutput(effect, arguments, state);
                try prepared.append(self.allocator, .{ .output_index = @intCast(index), .proof = .{ .call = call, .conditions = guarded.conditions, .entry_facts = entry, .value = value } });
            }
        }
        return try prepared.toOwnedSlice(self.allocator);
    }

    fn attachGeneralValueGuards(self: *SafetyChecker, summary: facts.SafetySummary, prepared: []const PreparedValueGuard, initial: facts.ValueFacts) !facts.ValueFacts {
        if (prepared.len == 0) return initial;
        const call = prepared[0].proof.call;
        var result = initial;
        if (summary.outputs.len == 1) {
            try self.attachCallSelectors(&result, call, 0, &.{});
        } else {
            const fields = try self.allocator.dupe(facts.FieldFacts, result.fields);
            result.fields = fields;
            for (fields) |*field| {
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = field.value.*;
                field.value = value;
                try self.attachCallSelectors(value, call, field.index, &.{});
            }
        }
        for (prepared) |item| {
            if (summary.outputs.len == 1) {
                result.guarded_values = try std.mem.concat(self.allocator, facts.GuardedValueFacts, &.{ result.guarded_values, &.{item.proof} });
            } else {
                for (@constCast(result.fields)) |*field| if (field.index == item.output_index) {
                    const target = @constCast(field.value);
                    target.guarded_values = try std.mem.concat(self.allocator, facts.GuardedValueFacts, &.{ target.guarded_values, &.{item.proof} });
                };
            }
        }
        return result;
    }

    fn effectHasFreshRoles(effect: facts.ValueEffect) bool {
        if (effect.fresh_owned_roots.len != 0 or effect.fresh_dependencies.len != 0 or effect.fresh_storage_capabilities.len != 0 or effect.fresh_cleanup_obligation) return true;
        for (effect.fields) |field| if (effectHasFreshRoles(field.value.*)) return true;
        for (effect.variants) |variant| if (effectHasFreshRoles(variant.value.*)) return true;
        return false;
    }

    fn attachCallSelectors(self: *SafetyChecker, value: *facts.ValueFacts, call: u64, index: u32, projections: []const facts.Projection) anyerror!void {
        if (value.variants.len != 0) {
            const selector: facts.CallChoiceSelector = .{ .call = call, .selector = .{ .subject = .output, .index = index, .projections = projections, .variant_index = 0 } };
            value.choice_selectors = try std.mem.concat(self.allocator, facts.CallChoiceSelector, &.{ value.choice_selectors, &.{selector} });
            const variants = try self.allocator.dupe(facts.VariantFacts, value.variants);
            value.variants = variants;
            for (variants) |*variant| {
                const child = try self.allocator.create(facts.ValueFacts);
                child.* = variant.value.*;
                variant.value = child;
                var observation = selector;
                observation.selector.variant_index = variant.index;
                child.choice_observations = try std.mem.concat(self.allocator, facts.CallChoiceSelector, &.{ child.choice_observations, &.{observation} });
                try self.attachCallSelectors(child, call, index, try std.mem.concat(self.allocator, facts.Projection, &.{ projections, &.{.{ .variant = variant.index }} }));
            }
        }
        const fields = try self.allocator.dupe(facts.FieldFacts, value.fields);
        value.fields = fields;
        for (fields) |*field| {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = field.value.*;
            field.value = child;
            try self.attachCallSelectors(child, call, index, try std.mem.concat(self.allocator, facts.Projection, &.{ projections, &.{.{ .field = field.index }} }));
        }
    }

    fn collectCallChoiceFacts(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, value: facts.ValueFacts, call: u64, terms: *std.ArrayList(facts.ChoiceCondition)) anyerror!void {
        if (self.initializednessAtPlace(state, storage) != .initialized) return;
        for (value.choice_observations) |observation| if (observation.call == call) try terms.append(self.allocator, observation.selector);
        const active = self.activeVariant(state, storage) orelse value.known_choice_variant;
        if (active) |variant| {
            for (value.choice_selectors) |selector| if (selector.call == call) {
                var observed = selector.selector;
                observed.variant_index = variant;
                try terms.append(self.allocator, observed);
            };
            for (value.variants) |payload| if (payload.index == variant) try self.collectCallChoiceFacts(state, try self.project(storage, .{ .variant = variant }), payload.value.*, call, terms);
        }
        for (value.fields) |field| try self.collectCallChoiceFacts(state, try self.project(storage, .{ .field = field.index }), field.value.*, call, terms);
    }

    fn refineGeneralValue(self: *SafetyChecker, initial: facts.ValueFacts, state: *FunctionState) anyerror!facts.ValueFacts {
        var selected: ?facts.GuardedValueFacts = null;
        for (initial.guarded_values) |guarded| {
            var terms: std.ArrayList(facts.ChoiceCondition) = .empty;
            defer terms.deinit(self.allocator);
            try terms.appendSlice(self.allocator, guarded.entry_facts.terms);
            // Root places are reconstructed so an overwritten field cannot
            // contribute a discriminant retained in an older aggregate fact.
            for (state.places.items) |place| {
                if (place.storage.projections.len != 0 or place.initializedness != .initialized) continue;
                try self.collectCallChoiceFacts(state, place.storage, try self.reconstructPlaceValue(state, place.storage, place.value), guarded.call, &terms);
            }
            const known = try @import("choice_conditions.zig").normalize(self.allocator, terms.items);
            if (guarded.conditions.evaluate(known) != .satisfied) continue;
            if (selected == null or guarded.conditions.implies(selected.?.conditions)) selected = guarded;
        }
        if (selected) |guarded| return self.refineValidityEnvelope(initial, guarded.value.*);
        return initial;
    }

    fn refineValidityEnvelope(self: *SafetyChecker, initial: facts.ValueFacts, precise: facts.ValueFacts) anyerror!facts.ValueFacts {
        var result = initial;
        result.dependencies = precise.dependencies;
        result.explicit_dependency = precise.explicit_dependency;
        const fields = try self.allocator.dupe(facts.FieldFacts, initial.fields);
        result.fields = fields;
        for (fields) |*field| for (precise.fields) |other| if (field.index == other.index) {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = try self.refineValidityEnvelope(field.value.*, other.value.*);
            field.value = child;
            break;
        };
        const variants = try self.allocator.dupe(facts.VariantFacts, initial.variants);
        result.variants = variants;
        for (variants) |*variant| for (precise.variants) |other| if (variant.index == other.index) {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = try self.refineValidityEnvelope(variant.value.*, other.value.*);
            variant.value = child;
            break;
        };
        return result;
    }

    fn recordFunctionCallAutoDeinit(
        self: *SafetyChecker,
        call_node: graph_mod.GlobalNodeId,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        const consumed = try self.callCleanupNodes(summary, argument_ids, arguments, state, false);
        const initialized = try self.callCleanupNodes(summary, argument_ids, arguments, state, true);
        const outcomes = try self.callOutcomeCleanups(summary, argument_ids, arguments, state);
        const node = &self.graph.nodes.items[@intFromEnum(call_node)];
        if (node.content != .function_call) return;
        node.content.function_call.consumed_auto_deinits = consumed;
        node.content.function_call.initialized_auto_deinits = initialized;
        node.content.function_call.outcome_cleanups = outcomes;
        for (summary.input_post_states) |post_state| {
            if (post_state.target.projections.len != 0 or post_state.target.input_index >= argument_ids.len) continue;
            const field = self.graph.value_fields.items[@intFromEnum(argument_ids[post_state.target.input_index])];
            if (self.graph.nodes.items[@intFromEnum(field.value)].content != .address_of or self.rootBinding(field.value) == null) continue;
            if (post_state.requires_available_destination and post_state.initializedness == .initialized)
                node.content.function_call.initializes_auto_deinit = field.value;
            if (post_state.initializedness == .deinitialized or post_state.initializedness == .moved)
                node.content.function_call.consumes_auto_deinit = field.value;
        }
    }

    fn initializesInput(summary: facts.SafetySummary, index: usize) bool {
        for (summary.input_post_states) |post| if (post.target.input_index == index and
            post.target.projections.len == 0 and post.requires_available_destination) return true;
        return false;
    }

    /// A represented exit can disable source cleanup or enable destination
    /// cleanup. Possible transitions in the fallback cannot select either flag.
    fn callOutcomeCleanups(self: *SafetyChecker, summary: facts.SafetySummary, ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState) ![]const primitives.OutcomeCleanup(graph_mod.Ids) {
        var result = std.array_list.Managed(primitives.OutcomeCleanup(graph_mod.Ids)).init(self.allocator);
        // A possible consumption without an exact result partition cannot be
        // implemented by either always keeping or always disabling cleanup.
        // Projected may-states also describe opaque backing-storage replacement;
        // they do not establish consumption of the whole input owner.
        for (summary.input_post_states) |post| {
            if (post.initializedness != .maybe_initialized or post.target.projections.len != 0) continue;
            var relocation_source = false;
            for (summary.outcome_post_states) |outcome| for (outcome.input_post_states) |selected| {
                if (sameInputPath(selected.target, post.target) and selected.initializedness == .moved) relocation_source = true;
            };
            if (!post.ends_previous_roots and !post.requires_available_destination and !relocation_source) continue;
            const target = try self.resolveSummaryInputPath(post.target, ids, arguments, state) orelse continue;
            var owns_cleanup = false;
            for (self.graph.auto_deinits.items) |cleanup| if (cleanup.binding == target.root) {
                owns_cleanup = true;
                break;
            };
            if (!owns_cleanup) continue;
            var represented = false;
            for (summary.outcome_post_states) |candidate| {
                var definite = false;
                var ambiguous = false;
                for (summary.outcome_post_states) |outcome| {
                    if (outcome.output_index != candidate.output_index) continue;
                    for (outcome.input_post_states) |selected| {
                        if (!sameInputPath(selected.target, post.target)) continue;
                        ambiguous = ambiguous or selected.initializedness == .maybe_initialized;
                        definite = definite or selected.initializedness == .moved or
                            (selected.initializedness == .initialized and selected.requires_available_destination) or
                            (selected.initializedness == .deinitialized and selected.ends_previous_roots);
                    }
                }
                if (definite and !ambiguous) {
                    represented = true;
                    break;
                }
            }
            if (!represented) {
                if (post.requires_available_destination or relocation_source) {
                    try self.report(self.graph.binding(target.root).source, "cannot select cleanup for conditional relocation; return a distinct result variant on each relocating or preserving path", .{});
                } else try self.report(self.graph.binding(target.root).source, "cannot select cleanup for conditional consumption; return a distinct result variant on each consuming or preserving path, or consume a moved lexical owner", .{});
            }
        }
        for (summary.outcome_post_states) |outcome| {
            for (outcome.input_post_states) |post| {
                const initializing = post.requires_available_destination and post.initializedness == .initialized;
                const relinquishing = post.initializedness == .moved or
                    (post.initializedness == .deinitialized and post.ends_previous_roots);
                if (!initializing and !relinquishing) continue;
                var unconditional = false;
                for (summary.input_post_states) |common| if (sameInputPath(common.target, post.target) and
                    common.initializedness == post.initializedness and
                    common.requires_available_destination == post.requires_available_destination and
                    common.ends_previous_roots == post.ends_previous_roots)
                {
                    unconditional = true;
                    break;
                };
                if (unconditional) continue;
                const target = try self.resolveSummaryInputPath(post.target, ids, arguments, state) orelse continue;
                const node = try self.cleanupNodeForPlace(target) orelse {
                    for (self.graph.auto_deinits.items) |cleanup| if (cleanup.binding == target.root) {
                        try self.report(self.graph.binding(target.root).source, "conditional consumption needs a lexical cleanup place; move the indexed or indirect owner into a local value first", .{});
                        break;
                    };
                    continue;
                };
                try result.append(.{ .place = node, .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index, .enabled = initializing });
            }
        }
        return result.toOwnedSlice();
    }

    fn mayMoveInput(summary: facts.SafetySummary, post: facts.PlacePostState) bool {
        if (post.initializedness == .moved) return true;
        for (summary.outcome_post_states) |outcome| for (outcome.input_post_states) |selected| {
            if (sameInputPath(selected.target, post.target) and selected.initializedness == .moved) return true;
        };
        return false;
    }

    fn cleanupTransition(summary: facts.SafetySummary, post: facts.PlacePostState) bool {
        return post.requires_available_destination or post.initializedness == .moved or
            mayMoveInput(summary, post) or
            ((post.initializedness == .deinitialized or post.initializedness == .maybe_initialized) and post.ends_previous_roots);
    }

    fn symbolicConsumptionInputs(self: *SafetyChecker, path: facts.InputPath, ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts) ![]const graph_mod.GlobalBindingId {
        if (path.storage_domain != null or path.input_index >= arguments.len or path.input_index >= ids.len) return &.{};
        var argument = arguments[path.input_index];
        const node = self.graph.value_fields.items[@intFromEnum(ids[path.input_index])].value;
        var ty = self.graph.node(node).ty orelse return &.{};
        if (path.projections.len != 0) {
            if (path.projections[path.projections.len - 1] != .dereference or isPointer(self.graph, ty)) return &.{};
            for (path.projections[0 .. path.projections.len - 1]) |projection| {
                ty = switch (projection) {
                    .field => |index| blk: {
                        const fields = types.fields(self.graph, ty) orelse return &.{};
                        if (index >= fields.len) return &.{};
                        break :blk types.effectiveFieldType(self.graph.fields.items[fields.start + index]);
                    },
                    .variant => |index| blk: {
                        const variants = types.variants(self.graph, ty) orelse return &.{};
                        if (index >= variants.len) return &.{};
                        break :blk self.graph.variants.items[variants.start + index].payload_type orelse return &.{};
                    },
                    .static_index, .dynamic_index => types.arrayElement(self.graph, ty) orelse return &.{},
                    .dereference => return &.{},
                };
                argument = try self.projectValueFacts(argument, &.{projection});
            }
        }
        // Only a whole unknown pointer carries a consumption identity. The
        // surrounding copied record and borrowed dependency envelopes do not.
        if (!isPointer(self.graph, ty) or argument.referenced_place != null) return &.{};
        return argument.symbolic_pointees;
    }

    fn validateConsumedInputAliasing(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState) !bool {
        for (summary.input_post_states, 0..) |post, index| {
            if (!cleanupTransition(summary, post)) continue;
            const target = try self.resolveSummaryInputPath(post.target, ids, arguments, state) orelse {
                if (post.target.input_index >= arguments.len or post.requires_available_destination) continue;
                const identities = try self.symbolicConsumptionInputs(post.target, ids, arguments);
                for (identities) |identity| {
                    for (state.symbolic_pointees.items) |pointee| {
                        if (pointee.identity != identity or pointee.initializedness == .initialized) continue;
                        try self.report(source, "consumption requires an initialized owner; this parameter's referent may already have been consumed", .{});
                        return false;
                    }
                }
                for (summary.input_post_states[0..index]) |previous| {
                    if (!cleanupTransition(summary, previous) or previous.requires_available_destination or
                        sameInputPath(previous.target, post.target) or previous.target.input_index >= arguments.len) continue;
                    for (try self.symbolicConsumptionInputs(previous.target, ids, arguments)) |other| {
                        if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, identities, other) == null) continue;
                        try self.report(source, "consumed inputs alias the same storage; provide distinct owners for consumption or relocation", .{});
                        return false;
                    }
                }
                continue;
            };
            if (!post.requires_available_destination and self.initializednessAtPlace(state, target) != .initialized) {
                if (mayMoveInput(summary, post)) {
                    try self.report(source, "relocation requires an initialized source; initialize it before transferring its owner", .{});
                } else {
                    try self.report(source, "consumption requires an initialized owner; initialize it before destroying its value", .{});
                }
                return false;
            }
            for (summary.input_post_states[0..index]) |previous| {
                if (!cleanupTransition(summary, previous)) continue;
                if (previous.target.input_index == post.target.input_index and
                    !(previous.target.projections.len != 0 and post.target.projections.len != 0 and
                        previous.target.projections[previous.target.projections.len - 1] == .dereference and
                        post.target.projections[post.target.projections.len - 1] == .dereference and
                        !sameInputPath(previous.target, post.target))) continue;
                const other = try self.resolveSummaryInputPath(previous.target, ids, arguments, state) orelse continue;
                if (target.isPrefixOf(other) or other.isPrefixOf(target)) {
                    try self.report(source, "consumed inputs alias the same storage; provide distinct owners for consumption or relocation", .{});
                    return false;
                }
            }
        }
        return true;
    }

    fn callCleanupNodes(self: *SafetyChecker, summary: facts.SafetySummary, ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState, initializing: bool) ![]const graph_mod.GlobalNodeId {
        var targets = std.array_list.Managed(facts.Place).init(self.allocator);
        defer targets.deinit();
        for (summary.input_post_states) |post| {
            if (initializing) {
                if (!post.requires_available_destination or post.initializedness != .initialized) continue;
            } else if (post.initializedness != .moved and (post.initializedness != .deinitialized or !post.ends_previous_roots)) continue;
            if (try self.resolveSummaryInputPath(post.target, ids, arguments, state)) |target| try appendPlaceFact(&targets, target);
        }
        var nodes = std.array_list.Managed(graph_mod.GlobalNodeId).init(self.allocator);
        for (targets.items) |target| {
            var covered = false;
            for (targets.items) |other| if (!target.eql(other) and other.isPrefixOf(target)) {
                covered = true;
                break;
            };
            if (covered) continue;
            if (try self.cleanupNodeForPlace(target)) |node| {
                try nodes.append(node);
            } else {
                for (self.graph.auto_deinits.items) |cleanup| if (cleanup.binding == target.root) {
                    try self.report(self.graph.binding(target.root).source, "cannot consume this indexed or indirect owner through a borrow; move it into a lexical owner before consuming it", .{});
                    break;
                };
            }
        }
        return nodes.toOwnedSlice();
    }

    /// Cleanup flags belong to caller storage, not to a reference-valued alias
    /// slot passed as an argument. Reconstruct only projections represented by
    /// structural cleanup; borrowed pointer fields never own their pointees.
    fn cleanupNodeForPlace(self: *SafetyChecker, storage: facts.Place) !?graph_mod.GlobalNodeId {
        const binding = self.graph.binding(storage.root);
        var ty = binding.ty;
        var node: graph_mod.GlobalNodeId = @enumFromInt(self.graph.nodes.items.len);
        try self.graph.nodes.append(self.allocator, .{ .source = binding.source, .ty = ty, .content = .{ .binding_use = storage.root } });
        for (storage.projections) |projection| switch (projection) {
            .field => |index| {
                const fields = types.fields(self.graph, ty) orelse return null;
                if (index >= fields.len) return null;
                const field = self.graph.fields.items[fields.start + index];
                const projected: graph_mod.GlobalNodeId = @enumFromInt(self.graph.nodes.items.len);
                try self.graph.nodes.append(self.allocator, .{ .source = binding.source, .ty = field.ty, .content = .{ .struct_field_access = .{ .value = node, .field_name = field.name, .field_index = index } } });
                node = projected;
                ty = field.ty;
            },
            .variant => |index| {
                const variants = types.variants(self.graph, ty) orelse return null;
                if (index >= variants.len) return null;
                const variant_id: graph_mod.GlobalVariantId = @enumFromInt(variants.start + index);
                const payload = self.graph.variants.items[@intFromEnum(variant_id)].payload_type orelse return null;
                const projected: graph_mod.GlobalNodeId = @enumFromInt(self.graph.nodes.items.len);
                try self.graph.nodes.append(self.allocator, .{ .source = binding.source, .ty = payload, .content = .{ .choice_payload_access = .{ .value = node, .variant = variant_id, .payload_type = payload } } });
                node = projected;
                ty = payload;
            },
            .dereference, .static_index, .dynamic_index => return null,
        };
        return node;
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
        if (primitive_transfer.forPrimitive(primitive).consumes_storage_input) |index| {
            if (index < values.len) try self.consume_storage_capabilities(source, values[index], 1, 1, state);
        }
        return switch (primitive_transfer.forPrimitive(primitive).value) {
            .empty => .{},
            .raw_storage => blk: {
                const id: facts.StorageCapabilityId = @enumFromInt(state.storage_capabilities.items.len);
                try state.storage_capabilities.append(.available);
                break :blk .{ .foreign_storage = true, .storage_capabilities = try self.oneCapability(id) };
            },
            .inherited_reference, .inherited_storage => blk: {
                if (values.len < 2) break :blk .{};
                // The raw address identifies storage, while the root argument
                // supplies its lifetime. It does not establish a new root.
                break :blk .{
                    .explicit_dependency = values[1].explicit_dependency,
                    .dependencies = values[1].dependencies,
                };
            },
            .allocation => blk: {
                const root = try state.tracker.establish(.fresh);
                state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
                const shape = primitive_transfer.AllocationTransfer;
                const fields = try self.allocator.alloc(facts.FieldFacts, shape.field_count);
                for (fields, 0..) |*field, index| {
                    const value = try self.allocator.create(facts.ValueFacts);
                    value.* = if (index == shape.data_field)
                        .{ .dependencies = try self.oneDependency(root) }
                    else
                        .{};
                    for (shape.borrowed_fields) |borrowed| if (index == borrowed.field) {
                        value.* = values[borrowed.input];
                        value.owned_roots = &.{};
                    };
                    field.* = .{ .index = @intCast(index), .value = value };
                }
                var result: facts.ValueFacts = .{ .owned_roots = try self.oneRoot(root) };
                for (fields) |field| result = try self.mergeValueFacts(result, field.value.*);
                result.fields = fields;
                break :blk result;
            },
            .reference_copy => if (values.len != 0) values[0].referenceCopy() else .{},
            .allocation_slot => blk: {
                if (values.len < 3) break :blk .{};
                var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                if (values[0].referenced_place) |place| {
                    if (self.valueAtPlace(state, place)) |allocation_value| {
                        for (allocation_value.owned_roots) |root| try appendDependencyFact(&dependencies, .{ .root = root });
                    }
                }
                for (values[2].dependencies) |dependency| try appendDependencyFact(&dependencies, dependency);
                break :blk .{ .dependencies = try dependencies.toOwnedSlice() };
            },
            .restrict_reference, .depend_on => |transfer| try self.dependencyPrimitive(values, transfer),
            .relocate => try self.relocatePrimitive(source, values, state),
            .opaque_move => blk: {
                try self.applyOpaqueMovePrimitive(function, source, argument_ids, values, state);
                break :blk .{};
            },
            .opaque_move_out => try self.opaqueMoveOutPrimitive(argument_ids, values, state),
            .opaque_relocate => blk: {
                if (values.len != 0) try self.rejectOpaqueRelocation(source, state, values[0]);
                break :blk .{};
            },
            .opaque_mark_empty => blk: {
                if (try self.primitiveArgumentStorage(argument_ids, values, 0, state)) |storage|
                    self.markOpaqueStorageEmpty(state, storage);
                break :blk .{};
            },
            // Slot destruction is trusted runtime behavior. Domain emptiness is
            // communicated explicitly by mark_empty and by summaries.
            .opaque_drop => .{},
        };
    }

    fn require_available_storage_capabilities(self: *SafetyChecker, source: primitives.SourceRef, value: facts.ValueFacts, maximum: u2, state: *FunctionState) !void {
        for (value.storage_capabilities) |capability| {
            const raw = @intFromEnum(capability);
            if (raw >= state.storage_capabilities.items.len or state.storage_capabilities.items[raw] != .available) {
                try self.report(source, "physical storage capability has already been consumed", .{});
            } else if (maximum > 1) {
                try self.report(source, "function may consume the same physical storage capability more than once", .{});
            }
        }
    }

    fn record_storage_consumption(self: *SafetyChecker, value: facts.ValueFacts, minimum: u2, maximum: u2, state: *FunctionState) void {
        _ = self;
        if (maximum == 0) return;
        for (value.storage_capabilities) |capability| {
            const entry = &state.storage_capabilities.items[@intFromEnum(capability)];
            if (entry.* != .consumed) entry.* = if (minimum == 0) .maybe_consumed else .consumed;
        }
    }

    fn consume_storage_capabilities(self: *SafetyChecker, source: primitives.SourceRef, value: facts.ValueFacts, minimum: u2, maximum: u2, state: *FunctionState) !void {
        if (value.storage_capabilities.len == 0) return;
        const before = self.diagnostics.list.items.len;
        try self.require_available_storage_capabilities(source, value, maximum, state);
        if (before == self.diagnostics.list.items.len) self.record_storage_consumption(value, minimum, maximum, state);
    }

    // Summary paths selecting stored fields must load the caller's pointee.
    // Both lifetime anchors and storage authorization use that same value;
    // borrowing the field's storage alone loses its referent's lifetime.
    fn load_summary_input_value(self: *SafetyChecker, path: facts.InputPath, arguments: []const facts.ValueFacts, state: *FunctionState) !facts.ValueFacts {
        if (path.input_index >= arguments.len) return .{};
        var value = arguments[path.input_index];
        var storage: ?facts.Place = null;
        if (path.projections.len == 0 or path.projections[0] != .dereference) {
            // A Virtual value retains its concrete receiver Place. Loading
            // through the wrapper must reach that receiver's scalar facts.
            var visited = std.array_list.Managed(facts.Place).init(self.allocator);
            defer visited.deinit();
            while (value.referenced_place) |place| {
                var seen = false;
                for (visited.items) |previous| if (previous.eql(place)) {
                    seen = true;
                    break;
                };
                if (seen) break;
                try visited.append(place);
                storage = place;
                value = self.valueAtPlace(state, place) orelse break;
            }
        }
        for (path.projections) |projection| {
            if (projection == .dereference) {
                if (value.referenced_place) |place| {
                    storage = place;
                    value = self.valueAtPlace(state, place) orelse .{};
                }
            } else {
                const fallback = try self.projectValueFacts(value, &.{projection});
                if (storage) |place| {
                    storage = try self.project(place, projection);
                    value = self.valueAtPlace(state, storage.?) orelse fallback;
                } else value = fallback;
            }
        }
        return value;
    }

    fn dependencyPrimitive(
        self: *SafetyChecker,
        values: []const facts.ValueFacts,
        transfer: primitive_transfer.Transfer.Value,
    ) !facts.ValueFacts {
        if (values.len == 0) return .{};
        var result = if (transfer == .restrict_reference) values[0].referenceCopy() else values[0];
        if (values.len == 1) return result;
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        for (result.dependencies) |dependency| try appendDependencyFact(&dependencies, dependency);
        for (values[1].dependencies) |dependency| try appendDependencyFact(&dependencies, dependency);
        result.dependencies = try dependencies.toOwnedSlice();
        if (transfer == .depend_on) result.explicit_dependency = true;
        return result;
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
        const destination_state = self.initializednessAtPlace(state, destination);
        if (!try self.requireAvailableRelocationDestination(source, destination_state)) return .{};
        if (destination_state == .deinitialized)
            try self.refreshStorageGenerationChecked(source, state, destination);
        const value = self.valueAtPlace(state, source_place) orelse return .{};
        try self.setPlace(state, destination, .initialized, value);
        try self.markMoved(state, source_place, .{}, source);
        return .{};
    }

    fn requireAvailableRelocationDestination(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        initializedness: value_state.Initializedness,
    ) !bool {
        switch (initializedness) {
            .initialized => try self.report(source, "relocate destination is initialized", .{}),
            .maybe_initialized => try self.report(source, "relocate destination may be initialized", .{}),
            .deinitialized, .moved => return true,
        }
        return false;
    }

    fn applyOpaqueMovePrimitive(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        const operands = primitive_transfer.opaqueMoveOperands(values.len) orelse return;
        if (operands.storage) |storage_index| {
            try self.closeOpaqueOwnedRoots(source, values[operands.owner], state, null);
            if (try self.primitiveArgumentStorage(argument_ids, values, storage_index, state)) |storage| {
                try self.markOpaqueArgumentAccess(argument_ids, 1, state, storage);
                try self.hideOpaqueDependencies(state, storage, values[operands.owner]);
                return;
            }
            const root_binding = self.primitiveArgumentRootBinding(argument_ids, storage_index);
            if (root_binding != null and self.functionInputIndex(function, root_binding.?) != null) return;
            if (valueHasDependency(values[operands.owner]))
                try self.report(source, "opaque ownership storage requires an identifiable storage domain place", .{});
            return;
        }
        const owner = values[operands.owner];
        if (hasExternalOpaqueDependency(owner, owner.owned_roots)) {
            try self.report(source, "opaque ownership storage cannot hide dependencies on external roots", .{});
            return;
        }
        try self.closeOpaqueOwnedRoots(source, owner, state, null);
        if (try self.inferOpaqueDomain(state, values[0])) |storage| {
            try self.markOpaqueArgumentAccess(argument_ids, 0, state, storage);
            try self.hideOpaqueDependencies(state, storage, owner);
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

    fn isForeignCapabilityPlace(self: *SafetyChecker, storage: facts.Place) bool {
        var ty = self.graph.binding(storage.root).ty;
        for (storage.projections) |projection| {
            ty = switch (projection) {
                .field => |index| self.fieldTypeAt(ty, index) orelse return false,
                .variant => |index| self.variantPayloadTypeAt(ty, index) orelse return false,
                .static_index, .dynamic_index => types.arrayElement(self.graph, ty) orelse return false,
                .dereference => switch (self.graph.semanticType(ty)) {
                    .pointer => |pointer| pointer.child,
                    else => return false,
                },
            };
        }
        const declaration = switch (self.graph.semanticType(ty)) {
            .declared => |id| id,
            else => return false,
        };
        if (!std.mem.eql(u8, self.graph.text(self.graph.declaration(declaration).name), "ForeignFunctionInterface")) return false;
        const module = self.graph.moduleForDeclaration(declaration) orelse return false;
        return self.graph.modules.items[@intFromEnum(module)].is_bundled_core;
    }

    fn validateSummaryRequiredLive(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        summary: facts.SafetySummary,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !bool {
        const before = self.diagnostics.list.items.len;
        _ = try self.validateSummaryRequiredOpaque(source, summary, arguments, state);
        for (summary.required_live_inputs) |path| {
            if (path.input_index >= arguments.len) continue;
            var owners = arguments[path.input_index];
            var value = try self.projectValueFacts(owners, path.projections);
            if (path.projections.len != 0) if (arguments[path.input_index].referenced_place) |base| {
                if (self.valueAtPlace(state, base)) |stored| owners = try self.reconstructPlaceValue(state, base, stored);
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                if (self.valueAtPlace(state, target)) |stored| value = try self.reconstructPlaceValue(state, target, stored);
            };
            for (path.projections) |projection| if (projection == .dereference) {
                var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
                defer provenances.deinit();
                try self.collectOpaqueProvenancesCarriedBy(state, arguments[path.input_index], &provenances);
                var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                try dependencies.appendSlice(value.dependencies);
                for (provenances.items) |provenance| for (state.opaque_storages.items) |domain| {
                    if (!domain.storage.eql(provenance.storage)) continue;
                    for (domain.hidden_dependencies) |dependency| {
                        if (!self.opaqueDependencyIsInternalToStorage(state, domain.storage, dependency))
                            try appendDependencyFact(&dependencies, .{ .root = dependency });
                    }
                };
                value.dependencies = try dependencies.toOwnedSlice();
                break;
            };
            try self.requireMappedOpaqueContentsLive(source, value, state);
            if (value.referenced_place) |storage| {
                // Referencing the wrapper checks its slot generation. Calling
                // through that reference also requires the hidden receiver
                // envelope stored inside it, including captured field roots.
                // Preserve this obligation across ordinary wrapper functions.
                // Mapped contents live separately from field facts. Reading
                // the receiver requires their external referents as well;
                // allocation metadata alone does not carry that obligation.
                if (self.valueAtPlace(state, storage)) |stored| {
                    try self.requireMappedOpaqueContentsLive(source, stored, state);
                    if (stored.virtual_methods.len != 0) try self.requireLive(@enumFromInt(0), source, stored, state);
                    for (stored.domains) |domain| for (domain.storages) |target| {
                        const generation = try self.storageGeneration(state, target);
                        if (state.tracker.roots.items[@intFromEnum(generation)].state != .alive)
                            try self.report(source, "reference depends on a root that has ended", .{});
                        try self.requirePlaceInitialized(@enumFromInt(0), source, target, self.initializednessAtPlace(state, target), state);
                        if (self.valueAtPlace(state, target)) |contents| try self.requireLive(@enumFromInt(0), source, try self.reconstructPlaceValue(state, target, contents), state);
                    };
                }
                // A capability authorizes a call only while its value remains
                // initialized. Unlike an output pointer, it is never merely a
                // destination whose live storage may hold no initialized value.
                if (self.isForeignCapabilityPlace(storage))
                    try self.requirePlaceInitialized(@enumFromInt(0), source, storage, self.initializednessAtPlace(state, storage), state);
            }
            // Summary paths select nested payloads, but ownership can live on
            // the containing choice. Keep that envelope when checking roots
            // that exist only on the selected success branch.
            if (valueDependsOnDeadRootWithOwners(value, owners, state)) {
                try self.report(source, "reference depends on a root that has ended", .{});
            }
        }
        return self.diagnostics.list.items.len == before;
    }

    fn validateSummaryRequiredOpaque(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, arguments: []const facts.ValueFacts, state: *FunctionState) !bool {
        const before = self.diagnostics.list.items.len;
        for (summary.required_opaque_inputs) |path| {
            if (path.input_index >= arguments.len) continue;
            var value = try self.projectValueFacts(arguments[path.input_index], path.projections);
            if (arguments[path.input_index].referenced_place) |base| {
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                if (self.valueAtPlace(state, target)) |stored|
                    value = try self.reconstructPlaceValue(state, target, stored);
            }
            var provenances = std.array_list.Managed(facts.OpaqueProvenance).init(self.allocator);
            defer provenances.deinit();
            try self.collectOpaqueProvenancesRecursively(state, value, &provenances);
            for (provenances.items) |provenance| for (state.opaque_storages.items) |domain| {
                if (!domain.storage.eql(provenance.storage)) continue;
                for (domain.hidden_dependencies) |dependency| {
                    if (self.opaqueDependencyIsInternalToStorage(state, domain.storage, dependency)) continue;
                    if (state.tracker.roots.items[@intFromEnum(dependency)].state != .alive) {
                        try self.report(source, "opaque contents depend on a root that has ended", .{});
                        break;
                    }
                }
            };
        }
        return self.diagnostics.list.items.len == before;
    }

    fn requireMappedOpaqueContentsLive(self: *SafetyChecker, source: primitives.SourceRef, receiver: facts.ValueFacts, state: *FunctionState) !void {
        for (receiver.domains) |domain| for (domain.storages) |target| {
            for (state.opaque_storages.items) |opaque_storage| {
                if (!target.isPrefixOf(opaque_storage.storage)) continue;
                for (opaque_storage.hidden_dependencies) |dependency| {
                    if (self.opaqueDependencyIsInternalToStorage(state, opaque_storage.storage, dependency)) continue;
                    if (state.tracker.roots.items[@intFromEnum(dependency)].state != .alive) {
                        try self.report(source, "receiver contents depend on a root that has ended", .{});
                        break;
                    }
                }
            }
        };
    }

    /// Guard only represented generation changes and whole-resource transitions.
    /// Unrepresented value writes and capabilities retain their conservative
    /// summary. A guard never restores a saved caller snapshot.
    fn applyOutcomeSummary(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, argument_ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState) !facts.ValueFacts {
        var capture = false;
        for (summary.outputs) |output| if (hasOpaqueOutputDependencies(output)) {
            capture = true;
            break;
        };
        if (!capture) {
            const result = try self.applyOutcomeSummaryEffects(source, summary, argument_ids, arguments, state);
            return self.attachSummaryOpaqueEmptyProofs(source, summary, argument_ids, arguments, state, result);
        }
        // Capture only the hidden contents' provenance before emptying them.
        // Returned owners keep these obligations; no caller place is restored.
        const effects = try self.allocator.alloc(facts.ValueEffect, summary.outputs.len);
        for (summary.outputs, effects) |output, *effect| effect.* = try self.opaqueOutputDependencies(output);
        const hidden = try self.instantiateSummaryOutputs(effects, arguments, state);
        const result = try self.applyOutcomeSummaryEffects(source, summary, argument_ids, arguments, state);
        var combined = try self.mergeValueFacts(result, hidden);
        // This adds provenance to the same result, rather than joining two
        // possible values. Keep its existing discriminant proofs intact.
        try self.preserveResultOutcomeProofs(&combined, result);
        return self.attachSummaryOpaqueEmptyProofs(source, summary, argument_ids, arguments, state, combined);
    }

    fn preserveResultOutcomeProofs(self: *SafetyChecker, value: *facts.ValueFacts, result: facts.ValueFacts) anyerror!void {
        value.generation_outcomes = result.generation_outcomes;
        const fields = try self.allocator.dupe(facts.FieldFacts, value.fields);
        value.fields = fields;
        for (fields) |*field| for (result.fields) |original| if (field.index == original.index) {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = field.value.*;
            field.value = child;
            try self.preserveResultOutcomeProofs(child, original.value.*);
            break;
        };
        const variants = try self.allocator.dupe(facts.VariantFacts, value.variants);
        value.variants = variants;
        for (variants) |*variant| for (result.variants) |original| if (variant.index == original.index) {
            const child = try self.allocator.create(facts.ValueFacts);
            child.* = variant.value.*;
            variant.value = child;
            try self.preserveResultOutcomeProofs(child, original.value.*);
            break;
        };
    }

    fn attachSummaryOpaqueEmptyProofs(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, argument_ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState, initial: facts.ValueFacts) !facts.ValueFacts {
        var result = initial;
        const guard = self.next_outcome_guard;
        self.next_outcome_guard += 1;
        for (summary.outcome_post_states) |outcome| {
            if (!outcome.reachable) continue;
            for (outcome.opaque_storage_empties) |path| {
                const storage = try self.resolveSummaryOpaqueStoragePath(path, argument_ids, arguments, state) orelse continue;
                // An unconditional guarantee has already discharged this domain.
                // Otherwise keep its current dependencies until the tag is known.
                var guarded = false;
                for (state.opaque_storages.items) |*domain| if (domain.storage.eql(storage) and domain.hidden_dependencies.len != 0) {
                    domain.outcome_guard = guard;
                    guarded = true;
                    break;
                };
                if (!guarded) continue;
                const generation = try self.storageGeneration(state, storage);
                const proof = facts.GenerationOutcome{ .storage = storage, .generation = generation, .guard = guard, .invalidates = false, .empties_opaque_storage = true, .source = source };
                if (summary.outputs.len == 1) {
                    try self.attachOutcomeGeneration(&result, outcome.parent_variants, outcome.variant_index, proof);
                } else {
                    const fields = try self.allocator.dupe(facts.FieldFacts, result.fields);
                    result.fields = fields;
                    for (fields) |*field| if (field.index == outcome.output_index) {
                        const value = try self.allocator.create(facts.ValueFacts);
                        value.* = field.value.*;
                        field.value = value;
                        try self.attachOutcomeGeneration(value, outcome.parent_variants, outcome.variant_index, proof);
                    };
                }
            }
        }
        return result;
    }

    fn hasOpaqueOutputDependencies(effect: facts.ValueEffect) bool {
        if (effect.opaque_storage_dependencies.len != 0) return true;
        for (effect.fields) |field| if (hasOpaqueOutputDependencies(field.value.*)) return true;
        for (effect.variants) |variant| if (hasOpaqueOutputDependencies(variant.value.*)) return true;
        return false;
    }

    fn opaqueOutputDependencies(self: *SafetyChecker, effect: facts.ValueEffect) anyerror!facts.ValueEffect {
        if (!hasOpaqueOutputDependencies(effect)) return .{};
        var result = facts.ValueEffect{ .opaque_storage_dependencies = effect.opaque_storage_dependencies, .known_choice_variant = effect.known_choice_variant };
        const fields = try self.allocator.alloc(facts.OutputFieldEffect, effect.fields.len);
        for (effect.fields, fields) |field, *output| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.opaqueOutputDependencies(field.value.*);
            output.* = .{ .index = field.index, .value = value };
        }
        result.fields = fields;
        const variants = try self.allocator.alloc(facts.OutputVariantEffect, effect.variants.len);
        for (effect.variants, variants) |variant, *output| {
            const value = try self.allocator.create(facts.ValueEffect);
            value.* = try self.opaqueOutputDependencies(variant.value.*);
            output.* = .{ .index = variant.index, .value = value };
        }
        result.variants = variants;
        return result;
    }

    fn applyOutcomeSummaryEffects(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, argument_ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState) !facts.ValueFacts {
        var selector: ?u32 = null;
        for (summary.outcome_post_states) |outcome| {
            var preserves = false;
            for (summary.input_post_states) |post| {
                if (consumptionSelectedBy(summary, post, outcome.output_index)) preserves = true;
                if (relocationSelectedBy(summary, post, outcome.output_index) != null) preserves = true;
                if (!post.refreshes_storage_generation) continue;
                var invalidates = false;
                for (outcome.input_post_states) |branch_post| if (sameInputPath(branch_post.target, post.target) and branch_post.refreshes_storage_generation) {
                    invalidates = true;
                    break;
                };
                if (!invalidates) preserves = true;
            }
            for (summary.invalidated_domains) |domain| {
                var invalidates = false;
                for (outcome.invalidated_domains) |branch_domain| if (domain.domain_index == branch_domain.domain_index and sameInputPath(domain.path, branch_domain.path)) {
                    invalidates = true;
                    break;
                };
                if (!invalidates) preserves = true;
            }
            if (!preserves) continue;
            if (selector != null and selector.? != outcome.output_index) {
                try self.applySummaryEffects(source, summary, argument_ids, arguments, state);
                return self.instantiateSummaryOutputs(summary.outputs, arguments, state);
            }
            selector = outcome.output_index;
        }
        const output_index = selector orelse {
            try self.applySummaryEffects(source, summary, argument_ids, arguments, state);
            return self.instantiateSummaryOutputs(summary.outputs, arguments, state);
        };
        var deferred = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer deferred.deinit();
        var common = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer common.deinit();
        var resources = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer resources.deinit();
        var relocations = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer relocations.deinit();
        for (summary.input_post_states) |post| if (relocationSelectedBy(summary, post, output_index) != null) try relocations.append(post);
        for (summary.input_post_states) |post| if (consumptionSelectedBy(summary, post, output_index)) try resources.append(post);
        for (summary.input_post_states) |post| {
            var resource_effect = false;
            for (relocations.items) |destination| {
                const moved_source = relocationSelectedBy(summary, destination, output_index).?;
                if (inputPathCovers(destination.target, post.target) or inputPathCovers(moved_source, post.target)) resource_effect = true;
            }
            for (resources.items) |resource| if (inputPathCovers(resource.target, post.target)) {
                resource_effect = true;
                break;
            };
            if (resource_effect) continue;
            // Only a pure generation change can be postponed independently of
            // input contents. Everything else retains its conservative effect.
            var pure = post;
            pure.refreshes_storage_generation = false;
            pure.may_repopulate_opaque_storage = false;
            var value = pure.value;
            var retains_input = true;
            for (value.input_place_values) |path| if (!sameInputPath(path, post.target)) {
                retains_input = false;
                break;
            };
            value.input_place_values = &.{};
            var preserves = false;
            for (summary.outcome_post_states) |outcome| {
                if (outcome.output_index != output_index) continue;
                var invalidates = false;
                for (outcome.input_post_states) |branch_post| if (sameInputPath(branch_post.target, post.target) and branch_post.refreshes_storage_generation) {
                    invalidates = true;
                    break;
                };
                if (!invalidates) preserves = true;
            }
            if (post.refreshes_storage_generation and preserves and pure.initializedness == .initialized and
                !pure.ends_previous_roots and !pure.requires_available_destination and pure.opaque_ownership == .none and
                pure.opaque_storage == null and retains_input and facts.isEmptyValue(value))
            {
                try deferred.append(post);
                if (!facts.isEmptyValue(post.value)) {
                    var contents = post;
                    contents.refreshes_storage_generation = false;
                    try common.append(contents);
                }
            } else try common.append(post);
        }
        var deferred_domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
        defer deferred_domains.deinit();
        var common_domains = std.array_list.Managed(facts.InputDomain).init(self.allocator);
        defer common_domains.deinit();
        for (summary.invalidated_domains) |domain| {
            var preserves = false;
            for (summary.outcome_post_states) |outcome| {
                if (outcome.output_index != output_index) continue;
                var invalidates = false;
                for (outcome.invalidated_domains) |branch_domain| if (domain.domain_index == branch_domain.domain_index and sameInputPath(domain.path, branch_domain.path)) {
                    invalidates = true;
                    break;
                };
                if (!invalidates) preserves = true;
            }
            if (preserves) try deferred_domains.append(domain) else try common_domains.append(domain);
        }
        var common_summary = summary;
        common_summary.input_post_states = common.items;
        common_summary.invalidated_domains = common_domains.items;
        try self.applySummaryEffects(source, common_summary, argument_ids, arguments, state);
        var result = try self.instantiateSummaryOutputs(summary.outputs, arguments, state);
        if (deferred.items.len == 0 and deferred_domains.items.len == 0 and resources.items.len == 0 and relocations.items.len == 0) return result;
        var choice: *facts.ValueFacts = &result;
        if (summary.outputs.len != 1) {
            const fields = try self.allocator.dupe(facts.FieldFacts, result.fields);
            result.fields = fields;
            for (fields) |*field| if (field.index == output_index) {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = field.value.*;
                field.value = stored;
                choice = stored;
                break;
            };
        }
        const guard = self.next_outcome_guard;
        self.next_outcome_guard += 1;
        for (relocations.items) |destination| try self.guardRelocation(source, summary, destination, output_index, argument_ids, arguments, state, choice, guard);
        for (resources.items) |post| {
            const storage = try self.resolveSummaryInputPath(post.target, argument_ids, arguments, state) orelse continue;
            if (self.initializednessAtPlace(state, storage) != .initialized) continue;
            const previous = self.valueAtPlace(state, storage) orelse continue;
            const generation = try self.storageGeneration(state, storage);
            var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer owned.deinit();
            try collectOwnedRoots(previous, &owned);
            const owned_roots = try owned.toOwnedSlice();
            var available = state.tracker.roots.items[@intFromEnum(generation)].state == .alive;
            for (owned_roots) |root| available = available and state.tracker.roots.items[@intFromEnum(root)].state == .alive;
            if (!available) {
                try self.applySummaryEffects(source, .{ .outputs = &.{}, .input_post_states = &.{post} }, argument_ids, arguments, state);
                continue;
            }
            // Retain current facts in the caller, but make availability and
            // owned generations uncertain until this call's result is selected.
            try self.setPlace(state, storage, .maybe_initialized, previous);
            state.tracker.roots.items[@intFromEnum(generation)].state = .maybe_alive;
            state.tracker.roots.items[@intFromEnum(generation)].outcome_guard = guard;
            for (owned_roots) |root| if (state.tracker.roots.items[@intFromEnum(root)].state == .alive) {
                state.tracker.roots.items[@intFromEnum(root)].state = .maybe_alive;
                state.tracker.roots.items[@intFromEnum(root)].outcome_guard = guard;
            };
            for (summary.outcome_post_states) |outcome| {
                if (outcome.output_index != output_index) continue;
                var consumes = false;
                for (outcome.input_post_states) |selected| if (sameInputPath(post.target, selected.target) and selected.initializedness == .deinitialized) {
                    consumes = true;
                    break;
                };
                try self.attachOutcomeGeneration(choice, outcome.parent_variants, outcome.variant_index, .{ .storage = storage, .generation = generation, .guard = guard, .invalidates = consumes, .resource_state = if (consumes) .deinitialized else .initialized, .owned_roots = owned_roots, .source = source });
                for (state.storage_generations.items) |child| {
                    if (child.storage.eql(storage) or !storage.isPrefixOf(child.storage)) continue;
                    const entry = &state.tracker.roots.items[@intFromEnum(child.generation)];
                    if (entry.state == .alive) {
                        entry.state = .maybe_alive;
                        entry.outcome_guard = guard;
                    }
                    if (entry.outcome_guard == guard) try self.attachOutcomeGeneration(choice, outcome.parent_variants, outcome.variant_index, .{ .storage = child.storage, .generation = child.generation, .guard = guard, .invalidates = consumes, .source = source });
                }
            }
        }
        var storages = std.array_list.Managed(facts.Place).init(self.allocator);
        defer storages.deinit();
        for (deferred.items) |post| {
            if (try self.resolveSummaryInputPath(post.target, argument_ids, arguments, state)) |storage| try appendPlaceFact(&storages, storage);
        }
        for (deferred_domains.items) |domain| {
            if (domain.path.input_index >= arguments.len) continue;
            const value = try self.projectValueFacts(arguments[domain.path.input_index], domain.path.projections);
            for (try self.domainStorage(value, domain.domain_index, state)) |storage| try appendPlaceFact(&storages, storage);
        }
        // An aggregate domain also governs references to its projected fields.
        // Capture every existing generation below it before any guard is added.
        const initial_storages = try self.allocator.dupe(facts.Place, storages.items);
        for (initial_storages) |storage| for (state.storage_generations.items) |generation| {
            if (storage.isPrefixOf(generation.storage)) try appendPlaceFact(&storages, generation.storage);
        };
        for (storages.items) |storage| {
            const root = try self.storageGeneration(state, storage);
            const entry = &state.tracker.roots.items[@intFromEnum(root)];
            if (entry.state != .alive) {
                entry.outcome_guard = 0;
                continue;
            }
            entry.state = .maybe_alive;
            entry.outcome_guard = guard;
            for (summary.outcome_post_states) |outcome| {
                if (outcome.output_index != output_index) continue;
                const invalidates = try self.outcomeInvalidatesStorage(outcome, argument_ids, arguments, state, storage);
                try self.attachOutcomeGeneration(choice, outcome.parent_variants, outcome.variant_index, .{ .storage = storage, .generation = root, .guard = guard, .invalidates = invalidates, .source = source });
            }
        }
        return result;
    }

    /// Relocation is one paired transition selected by one discriminant. The
    /// finite boundary excludes partial values and replacement effects, so a
    /// preserving exit confirms current facts instead of restoring snapshots.
    fn relocationSelectedBy(summary: facts.SafetySummary, destination: facts.PlacePostState, output_index: u32) ?facts.InputPath {
        if (summary.opaque_storage_effects.len != 0 or summary.opaque_storage_empties.len != 0 or summary.storage_capability_uses.len != 0) return null;
        if (destination.target.projections.len != 0 or destination.initializedness != .maybe_initialized or
            !destination.requires_available_destination or !destination.refreshes_storage_generation or
            destination.ends_previous_roots or destination.opaque_ownership != .none or destination.opaque_storage != null or
            destination.may_repopulate_opaque_storage or destination.value.input_place_values.len != 1) return null;
        const source = destination.value.input_place_values[0];
        if (source.projections.len != 0 or source.input_index == destination.target.input_index) return null;
        var value = destination.value;
        value.input_place_values = &.{};
        if (!facts.isEmptyValue(value)) return null;
        for (summary.input_post_states) |post| {
            if ((inputPathCovers(source, post.target) and !sameInputPath(source, post.target)) or
                (inputPathCovers(destination.target, post.target) and !sameInputPath(destination.target, post.target))) return null;
        }
        var source_found = false;
        for (summary.input_post_states) |post| if (sameInputPath(source, post.target)) {
            if (post.initializedness != .maybe_initialized or post.ends_previous_roots or post.refreshes_storage_generation or
                post.requires_available_destination or post.opaque_ownership != .none or post.opaque_storage != null or post.may_repopulate_opaque_storage) return null;
            value = post.value;
            for (value.input_place_values) |path| if (!sameInputPath(path, source)) return null;
            value.input_place_values = &.{};
            if (!facts.isEmptyValue(value)) return null;
            source_found = true;
        };
        if (!source_found) return null;
        var moves = false;
        for (summary.outcome_post_states) |outcome| {
            if (outcome.output_index != output_index) continue;
            var moved = false;
            var initialized = false;
            for (outcome.input_post_states) |post| {
                if (inputPathCovers(source, post.target)) {
                    if (!sameInputPath(source, post.target) or post.initializedness != .moved or
                        post.ends_previous_roots or post.refreshes_storage_generation or post.requires_available_destination or
                        post.opaque_ownership != .none or post.opaque_storage != null or post.may_repopulate_opaque_storage or !facts.isEmptyValue(post.value)) return null;
                    moved = true;
                }
                if (inputPathCovers(destination.target, post.target)) {
                    if (!sameInputPath(destination.target, post.target) or post.initializedness != .initialized or
                        !post.requires_available_destination or !post.refreshes_storage_generation or post.ends_previous_roots or
                        post.opaque_ownership != .none or post.opaque_storage != null or post.may_repopulate_opaque_storage or
                        post.value.input_place_values.len != 1 or !sameInputPath(post.value.input_place_values[0], source)) return null;
                    value = post.value;
                    value.input_place_values = &.{};
                    if (!facts.isEmptyValue(value)) return null;
                    initialized = true;
                }
            }
            if (moved != initialized) return null;
            moves = moves or moved;
        }
        return if (moves) source else null;
    }

    fn guardRelocation(self: *SafetyChecker, source: primitives.SourceRef, summary: facts.SafetySummary, destination: facts.PlacePostState, output_index: u32, ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState, choice: *facts.ValueFacts, guard: u64) !void {
        const moved_source = relocationSelectedBy(summary, destination, output_index).?;
        const source_place = try self.resolveSummaryInputPath(moved_source, ids, arguments, state);
        const destination_place = try self.resolveSummaryInputPath(destination.target, ids, arguments, state);
        if (source_place != null and destination_place != null) {
            const from = source_place.?;
            const to = destination_place.?;
            if (from.isPrefixOf(to) or to.isPrefixOf(from)) {
                try self.report(source, "relocation requires distinct, non-overlapping source and destination storage", .{});
                return;
            }
            if (self.initializednessAtPlace(state, from) == .initialized and self.valueAtPlace(state, from) != null) {
                const available_state = self.initializednessAtPlace(state, to);
                if (!try self.requireAvailableRelocationDestination(source, available_state)) return;
                const generation = try self.storageGeneration(state, from);
                const current = self.valueAtPlace(state, from).?;
                var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer owned.deinit();
                try collectOwnedRoots(current, &owned);
                var alive = state.tracker.isAlive(generation);
                for (owned.items) |root| alive = alive and state.tracker.isAlive(root);
                if (alive) {
                    // Materialize transferred facts while the source remains
                    // available. Both slots become pending; the owner roots
                    // themselves survive either outcome of the same transfer.
                    try self.refreshStorageGenerationChecked(source, state, to);
                    const destination_generation = try self.storageGeneration(state, to);
                    try self.setPlace(state, to, .maybe_initialized, current);
                    try self.setPlace(state, from, .maybe_initialized, current);
                    for (&[_]facts.ValidityRootId{ generation, destination_generation }) |root| {
                        state.tracker.roots.items[@intFromEnum(root)].state = .maybe_alive;
                        state.tracker.roots.items[@intFromEnum(root)].outcome_guard = guard;
                    }
                    for (summary.outcome_post_states) |outcome| {
                        if (outcome.output_index != output_index) continue;
                        var moved = false;
                        for (outcome.input_post_states) |post| {
                            if (sameInputPath(post.target, moved_source) and post.initializedness == .moved) moved = true;
                        }
                        try self.attachOutcomeGeneration(choice, outcome.parent_variants, outcome.variant_index, .{
                            .storage = from,
                            .generation = generation,
                            .guard = guard,
                            .invalidates = moved,
                            .relocation = .{ .destination = to, .generation = destination_generation, .available_state = available_state, .moved = moved },
                            .source = source,
                        });
                        for (state.storage_generations.items) |child| {
                            if (child.storage.eql(from) or !from.isPrefixOf(child.storage)) continue;
                            const entry = &state.tracker.roots.items[@intFromEnum(child.generation)];
                            if (entry.state == .alive) {
                                entry.state = .maybe_alive;
                                entry.outcome_guard = guard;
                            }
                            if (entry.outcome_guard == guard) try self.attachOutcomeGeneration(choice, outcome.parent_variants, outcome.variant_index, .{ .storage = child.storage, .generation = child.generation, .guard = guard, .invalidates = moved, .source = source });
                        }
                    }
                    return;
                }
            }
        }
        var posts = std.array_list.Managed(facts.PlacePostState).init(self.allocator);
        defer posts.deinit();
        for (summary.input_post_states) |post| if (sameInputPath(post.target, moved_source)) try posts.append(post);
        try posts.append(destination);
        try self.applySummaryEffects(source, .{ .outputs = &.{}, .input_post_states = posts.items }, ids, arguments, state);
    }

    fn inputPathCovers(parent: facts.InputPath, child: facts.InputPath) bool {
        if (parent.input_index != child.input_index or parent.storage_domain != child.storage_domain or parent.projections.len > child.projections.len) return false;
        for (parent.projections, child.projections[0..parent.projections.len]) |a, b| if (!a.eql(b)) return false;
        // Borrowed fields reach external storage; consuming their containing
        // owner must not postpone or discard effects on that referent.
        for (child.projections[parent.projections.len..]) |projection| if (projection == .dereference) return false;
        return true;
    }

    /// The finite boundary admits only definite destruction or preservation
    /// selected by one output. Replacements and unrelated predicates retain
    /// their conservative post-state rather than recovering caller snapshots.
    fn consumptionSelectedBy(summary: facts.SafetySummary, post: facts.PlacePostState, output_index: u32) bool {
        if (summary.opaque_storage_effects.len != 0 or summary.opaque_storage_empties.len != 0 or summary.storage_capability_uses.len != 0) return false;
        if (post.initializedness != .maybe_initialized or !post.ends_previous_roots or post.target.projections.len != 0) return false;
        var consumes = false;
        for (summary.outcome_post_states) |outcome| {
            if (outcome.output_index != output_index) continue;
            var destroys = false;
            for (outcome.input_post_states) |selected| if (sameInputPath(post.target, selected.target) and selected.initializedness == .deinitialized and selected.ends_previous_roots) {
                destroys = true;
                break;
            };
            for (outcome.input_post_states) |selected| {
                // Preserving availability is not a promise that the old field
                // facts survived replacement. Keep such branches conservative
                // until conditional post-values have their own checked model.
                if (!destroys and inputPathCovers(post.target, selected.target)) return false;
                if (!sameInputPath(post.target, selected.target)) continue;
                if (selected.initializedness != .deinitialized or !selected.ends_previous_roots or selected.refreshes_storage_generation or !facts.isEmptyValue(selected.value)) return false;
                consumes = true;
            }
        }
        return consumes;
    }

    fn attachOutcomeGeneration(self: *SafetyChecker, value: *facts.ValueFacts, parents: []const u32, leaf: u32, proof: facts.GenerationOutcome) anyerror!void {
        const variants = try self.allocator.dupe(facts.VariantFacts, value.variants);
        value.variants = variants;
        const selected = if (parents.len == 0) leaf else parents[0];
        for (variants) |*variant| {
            if (variant.index != selected) continue;
            const payload = try self.allocator.create(facts.ValueFacts);
            payload.* = variant.value.*;
            variant.value = payload;
            if (parents.len == 0) {
                payload.generation_outcomes = try std.mem.concat(self.allocator, facts.GenerationOutcome, &.{ payload.generation_outcomes, &.{proof} });
            } else try self.attachOutcomeGeneration(payload, parents[1..], leaf, proof);
            break;
        }
    }

    fn outcomeInvalidatesStorage(self: *SafetyChecker, outcome: facts.OutcomePostStates, argument_ids: []const graph_mod.GlobalValueFieldId, arguments: []const facts.ValueFacts, state: *FunctionState, storage: facts.Place) !bool {
        for (outcome.input_post_states) |post| {
            if (!post.refreshes_storage_generation) continue;
            if (try self.resolveSummaryInputPath(post.target, argument_ids, arguments, state)) |target| if (target.isPrefixOf(storage)) return true;
        }
        for (outcome.invalidated_domains) |domain| {
            if (domain.path.input_index >= arguments.len) continue;
            const value = try self.projectValueFacts(arguments[domain.path.input_index], domain.path.projections);
            for (try self.domainStorage(value, domain.domain_index, state)) |target| if (target.isPrefixOf(storage)) return true;
        }
        return false;
    }

    fn applySummaryEffects(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.invalidated_domains) |domain| {
            if (domain.path.input_index >= arguments.len) continue;
            const value = try self.projectValueFacts(arguments[domain.path.input_index], domain.path.projections);
            for (try self.domainStorage(value, domain.domain_index, state)) |storage|
                try self.refreshStorageGenerationChecked(source, state, storage);
        }

        const capability_diagnostics = self.diagnostics.list.items.len;
        for (summary.storage_capability_uses) |use| {
            try self.require_available_storage_capabilities(source, try self.load_summary_input_value(use.target, arguments, state), use.maximum, state);
        }
        for (summary.storage_capability_conflicts) |pair| {
            const first = try self.load_summary_input_value(pair.first, arguments, state);
            const second = try self.load_summary_input_value(pair.second, arguments, state);
            for (first.storage_capabilities) |capability| if (std.mem.indexOfScalar(facts.StorageCapabilityId, second.storage_capabilities, capability) != null) {
                try self.report(source, "function may consume the same physical storage capability more than once", .{});
                break;
            };
        }
        if (capability_diagnostics != self.diagnostics.list.items.len) return;
        for (summary.storage_capability_uses) |use| {
            const value = try self.load_summary_input_value(use.target, arguments, state);
            self.record_storage_consumption(value, use.minimum, use.maximum, state);
        }

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

        // A summary describes the post-state of all inputs at once. Materialize
        // its values before changing any place so effects may transfer a value
        // from an input that the same summary subsequently marks as moved.
        const post_values = try self.allocator.alloc(?facts.ValueFacts, summary.input_post_states.len);
        @memset(post_values, null);
        for (summary.input_post_states, 0..) |post_state, post_index| {
            if (post_state.target.input_index >= arguments.len) continue;
            if (post_state.initializedness != .initialized or post_state.opaque_ownership != .none) continue;
            post_values[post_index] = try self.instantiateOutputWithFresh(
                post_state.value,
                arguments,
                state,
                &fresh_roots,
                self.active_fresh_capabilities orelse &fresh_capabilities,
            );
        }

        for (summary.input_post_states, 0..) |post_state, post_index| {
            if (post_state.target.input_index >= arguments.len) continue;
            const index: usize = @intCast(post_state.target.input_index);
            if (cleanupTransition(summary, post_state)) {
                for (try self.symbolicConsumptionInputs(post_state.target, argument_ids, arguments)) |identity| {
                    for (state.symbolic_pointees.items) |*pointee| if (pointee.identity == identity) {
                        // Unknown input reinitialization cannot revive old aliases.
                        pointee.initializedness = if (post_state.requires_available_destination) .maybe_initialized else post_state.initializedness;
                    };
                }
            }

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
                    const storage = try self.resolveSummaryOpaqueStoragePath(opaque_path, argument_ids, arguments, state) orelse continue;
                    try self.closeOpaqueOwnedRoots(source, value, state, consumed);
                    if (consumed) |target| try self.markMoved(state, target, .{}, source);
                    try self.hideOpaqueDependencies(state, storage, value);
                } else {
                    if (hasExternalOpaqueDependency(value, value.owned_roots))
                        try self.report(source, "opaque ownership storage cannot hide dependencies on external roots", .{});
                    try self.closeOpaqueOwnedRoots(source, value, state, consumed);
                    if (consumed) |target| try self.markMoved(state, target, .{}, source);
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
                    if (!try self.requireAvailableRelocationDestination(source, current.initializedness))
                        continue;
                }
            }

            const reinitializes_dead_place = post_state.initializedness == .initialized and
                (if (self.getPlace(state, target)) |current| current.initializedness == .deinitialized else false);
            const previous_value = self.valueAtPlace(state, target);
            if (post_state.ends_previous_roots) if (previous_value) |previous| {
                var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer owned.deinit();
                try collectOwnedRoots(previous, &owned);
                _ = try self.endRoots(source, state, owned.items);
            };
            if (post_state.initializedness == .deinitialized or post_state.initializedness == .moved)
                try self.endStorageGenerationsUnder(source, state, target);
            if (post_state.refreshes_storage_generation or
                (!post_state.requires_available_destination and reinitializes_dead_place))
            {
                const old_generation = try self.storageGeneration(state, target);
                try self.refreshStorageGenerationChecked(source, state, target);
                if (reinitializes_dead_place and post_state.target.projections.len == 0 and index < argument_ids.len) {
                    const argument_node = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
                    if (try self.resolvePlace(argument_node, state)) |pointer_storage| {
                        const argument = arguments[index];
                        if (!pointer_storage.eql(target) and argument.referenced_place != null and argument.referenced_place.?.eql(target)) {
                            const generation = try self.storageGeneration(state, target);
                            const refreshed = try self.replaceValueRoots(argument, &.{old_generation}, generation);
                            // The input pointer used to reinitialize the place
                            // follows its generation; sibling aliases remain old.
                            try self.setPlace(state, pointer_storage, .initialized, refreshed);
                        }
                    }
                }
            }

            const value = post_values[post_index] orelse facts.ValueFacts{};
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
        var projections = path_value.projections;
        var target = arguments[index].referenced_place orelse blk: {
            if (index >= argument_ids.len) return null;
            const argument = self.graph.value_fields.items[@intFromEnum(argument_ids[index])].value;
            const argument_type = self.graph.nodes.items[@intFromEnum(argument)].ty orelse return null;
            // A by-value parameter owns its local slot. Its summary state must
            // not overwrite the caller Place that supplied the value; explicit
            // move/copy evaluation has already updated that Place. Pointer
            // arguments may still expose their own storage when provenance is
            // unavailable (for example an abstract pointer binding).
            if (!isPointer(self.graph, argument_type)) {
                // A copied argument record has its own fields, but references
                // carried inside it still identify their caller referents.
                var value = arguments[index];
                for (projections, 0..) |projection, projection_index| {
                    if (projection == .dereference) {
                        const referent = value.referenced_place orelse return null;
                        projections = projections[projection_index + 1 ..];
                        break :blk referent;
                    }
                    value = try self.projectValueFacts(value, &.{projection});
                }
                return null;
            }
            const storage = try self.resolvePlace(argument, state) orelse return null;
            // An abstract pointer input has no concrete pointee Place. Its
            // binding stores the pointer itself, so writing a pointee summary
            // there would replace the pointer's own temporal dependencies.
            if (isPointer(self.graph, self.graph.binding(storage.root).ty) and
                arguments[index].referenced_place == null) return null;
            break :blk storage;
        };
        for (projections) |projection| {
            if (projection == .dereference) {
                if (self.valueAtPlace(state, target)) |stored| {
                    if (stored.referenced_place) |referent| {
                        target = referent;
                        continue;
                    }
                }
            }
            target = try self.project(target, projection);
        }
        return target;
    }

    fn resolveSummaryOpaqueStoragePath(
        self: *SafetyChecker,
        path: facts.InputPath,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?facts.Place {
        if (path.storage_domain) |domain| {
            if (path.input_index >= arguments.len) return null;
            const receiver = try self.projectValueFacts(arguments[path.input_index], path.projections);
            const storages = try self.domainStorage(receiver, domain, state);
            // Declaration conformance requires one mapped storage identity.
            if (storages.len != 1) return error.MissingVirtualStorageDomain;
            return storages[0];
        }
        if (try self.resolveSummaryInputPath(path, argument_ids, arguments, state)) |storage| return storage;
        if (path.input_index >= argument_ids.len or path.input_index >= arguments.len) return null;
        const argument = self.graph.value_fields.items[@intFromEnum(argument_ids[path.input_index])].value;
        const pointer_slot = try self.resolvePlace(argument, state) orelse return null;
        if (!isPointer(self.graph, self.graph.binding(pointer_slot.root).ty)) return null;
        // An unknown input referent still has a symbolic opaque domain. Keep
        // its hidden contents behind a dereference, separate from the pointer
        // slot: ordinary post-state writes must not overwrite pointer facts.
        var storage = try self.project(pointer_slot, .dereference);
        for (path.projections) |projection| storage = try self.project(storage, projection);
        return storage;
    }

    fn applySummaryOpaqueStorageEffects(
        self: *SafetyChecker,
        summary: facts.SafetySummary,
        argument_ids: []const graph_mod.GlobalValueFieldId,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        for (summary.opaque_storage_effects) |effect| {
            const storage = try self.resolveSummaryOpaqueStoragePath(effect.storage, argument_ids, arguments, state) orelse continue;
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
            const storage = try self.resolveSummaryOpaqueStoragePath(empty_path, argument_ids, arguments, state) orelse continue;
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
        for (effect.input_generation_dependencies) |input_path| {
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
            const storage = try self.resolveSummaryOpaqueStoragePath(input_path, &.{}, arguments, state) orelse continue;
            try self.collectReturnedStorageDependencies(state, storage, hidden);
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
        var fresh_roots = std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId).init(self.allocator);
        defer fresh_roots.deinit();
        var fresh_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator);
        defer fresh_capabilities.deinit();
        const fields = try self.allocator.alloc(facts.FieldFacts, outputs.len);
        var aggregate: facts.ValueFacts = .{};
        for (outputs, 0..) |effect, index| {
            const value = try self.allocator.create(facts.ValueFacts);
            value.* = try self.instantiateOutputWithFresh(effect, arguments, state, &fresh_roots, self.active_fresh_capabilities orelse &fresh_capabilities);
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
        return self.instantiateOutputWithFresh(effect, arguments, state, &fresh_roots, self.active_fresh_capabilities orelse &fresh_capabilities);
    }

    fn instantiateOutputWithFresh(
        self: *SafetyChecker,
        effect: facts.ValueEffect,
        arguments: []const facts.ValueFacts,
        state: *FunctionState,
        fresh_roots: *std.AutoHashMap(facts.FreshEffectSource, facts.ValidityRootId),
        fresh_capabilities: *std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId),
    ) !facts.ValueFacts {
        var result: facts.ValueFacts = .{ .explicit_dependency = effect.explicit_dependency };
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
            const storage = try self.resolveSummaryOpaqueStoragePath(input_path, &.{}, arguments, state) orelse continue;
            var returned_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer returned_dependencies.deinit();
            try self.collectReturnedStorageDependencies(state, storage, &returned_dependencies);
            for (returned_dependencies.items) |root| try appendDependencyFact(&dependencies, .{ .root = root });
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

        for (effect.input_storage_capabilities) |path| {
            const input = (try self.load_summary_input_value(path, arguments, state)).scalarOpaqueRead();
            result = try self.mergeValueFacts(result, input);
        }
        var capabilities = std.array_list.Managed(facts.StorageCapabilityId).init(self.allocator);
        for (result.storage_capabilities) |capability| try appendCapabilityFact(&capabilities, capability);
        for (effect.fresh_storage_capabilities) |fresh|
            try appendCapabilityFact(&capabilities, try self.instantiateFreshCapability(fresh, state, fresh_capabilities));
        result.storage_capabilities = try capabilities.toOwnedSlice();
        for (effect.unavailable_fresh_storage) |entry| {
            const capability = try self.instantiateFreshCapability(entry.source, state, fresh_capabilities);
            state.storage_capabilities.items[@intFromEnum(capability)] = if (entry.maybe_consumed) .maybe_consumed else .consumed;
        }

        for (effect.input_receiver_values) |path| {
            if (path.input_index >= arguments.len) continue;
            var receiver = try self.projectValueFacts(arguments[path.input_index], path.projections);
            if (receiver.referenced_place) |storage| if (self.domainStorageType(storage)) |ty| {
                if (self.graph.semanticType(ty) == .virtual) {
                    if (self.valueAtPlace(state, storage)) |stored| receiver = stored;
                }
            };
            var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer roots.deinit();
            try collectDependencyRoots(receiver, &roots);
            try collectOwnedRoots(receiver, &roots);
            for (roots.items) |root| try appendDependencyFact(&dependencies, .{ .root = root });
            var visited = std.array_list.Managed(facts.Place).init(self.allocator);
            defer visited.deinit();
            if (receiver.referenced_place) |storage| if (self.domainStorageType(storage)) |ty| {
                try self.captureContractStorage(@enumFromInt(0), self.graph.binding(storage.root).source, state, storage, ty, &dependencies, &visited);
            };
            for (receiver.domains) |domain| for (domain.storages) |storage| {
                if (self.domainStorageType(storage)) |ty| {
                    try self.captureContractStorage(@enumFromInt(0), self.graph.binding(storage.root).source, state, storage, ty, &dependencies, &visited);
                } else try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, storage) });
            };
        }
        for (effect.input_domains) |domain| {
            if (domain.path.input_index >= arguments.len) continue;
            const input = try self.projectValueFacts(arguments[domain.path.input_index], domain.path.projections);
            for (try self.domainStorage(input, domain.domain_index, state)) |storage| {
                try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, storage) });
                if (self.domainStorageType(storage)) |ty| {
                    var visited = std.array_list.Managed(facts.Place).init(self.allocator);
                    defer visited.deinit();
                    try self.captureContractStorage(@enumFromInt(0), self.graph.binding(storage.root).source, state, storage, ty, &dependencies, &visited);
                }
                if (self.valueAtPlace(state, storage)) |stored| {
                    const value = try self.reconstructPlaceValue(state, storage, stored);
                    var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer roots.deinit();
                    try collectDependencyRoots(value, &roots);
                    try collectOwnedRoots(value, &roots);
                    for (roots.items) |root| try appendDependencyFact(&dependencies, .{ .root = root });
                }
            }
        }
        var referenced_place: ?facts.Place = null;
        var has_referent = false;
        for (effect.input_places) |path| {
            if (path.input_index >= arguments.len) continue;
            if (arguments[path.input_index].referenced_place) |base| {
                var target = base;
                for (path.projections) |projection| target = try self.project(target, projection);
                try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, target) });
                referenced_place = target;
                has_referent = true;
            }
        }
        for (effect.input_captured_storages) |path| {
            if (path.input_index >= arguments.len) continue;
            const input = try self.projectValueFacts(arguments[path.input_index], path.projections);
            if (input.referenced_place) |storage| if (self.domainStorageType(storage)) |ty| {
                var visited = std.array_list.Managed(facts.Place).init(self.allocator);
                defer visited.deinit();
                try self.captureContractStorage(@enumFromInt(0), self.graph.binding(storage.root).source, state, storage, ty, &dependencies, &visited);
            };
        }
        for (effect.input_generation_dependencies) |path| {
            if (path.input_index >= arguments.len) continue;
            var target = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| target = try self.project(target, projection);
            try appendDependencyFact(&dependencies, .{ .root = try self.storageGeneration(state, target) });
        }
        for (effect.input_owned_roots) |path| {
            if (path.input_index >= arguments.len) continue;
            var place = arguments[path.input_index].referenced_place orelse continue;
            for (path.projections) |projection| place = try self.project(place, projection);
            if (self.valueAtPlace(state, place)) |value| {
                for (value.owned_roots) |root| try appendDependencyFact(&dependencies, .{ .root = root });
            }
        }
        if (effect.domain_values.len != 0) {
            var domains: std.ArrayList(facts.DomainFacts) = .empty;
            for (effect.domain_values) |domain| {
                var storages = std.array_list.Managed(facts.Place).init(self.allocator);
                for (domain.value.input_generation_dependencies) |path| {
                    if (path.input_index >= arguments.len) continue;
                    var storage = arguments[path.input_index].referenced_place orelse continue;
                    for (path.projections) |projection| {
                        if (self.valueAtPlace(state, storage)) |stored| {
                            if (stored.referenced_place) |referent| storage = referent;
                        }
                        storage = try self.project(storage, projection);
                    }
                    try appendPlaceFact(&storages, storage);
                }
                for (domain.value.input_domains) |input| {
                    if (input.path.input_index >= arguments.len) continue;
                    const value = try self.projectValueFacts(arguments[input.path.input_index], input.path.projections);
                    for (try self.domainStorage(value, input.domain_index, state)) |storage| try appendPlaceFact(&storages, storage);
                }
                try domains.append(self.allocator, .{ .domain_index = domain.domain_index, .storages = try storages.toOwnedSlice() });
            }
            result.domains = try domains.toOwnedSlice(self.allocator);
        }
        result.dependencies = try dependencies.toOwnedSlice();
        const direct_owned_roots = result.owned_roots;

        for (effect.input_dependencies) |dependency| {
            if (dependency.path.input_index >= arguments.len) continue;
            var input = if (dependency.validity_only and dependency.path.projections.len != 0)
                try self.load_summary_input_value(dependency.path, arguments, state)
            else
                try self.projectValueFacts(arguments[dependency.path.input_index], dependency.path.projections);
            if (dependency.transfers_ownership and dependency.path.projections.len != 0)
                try self.activate_conditional_resources(state, input);
            if (!dependency.transfers_ownership) input.owned_roots = &.{};
            if (!dependency.validity_only) if (input.referenced_place) |place| {
                // A copied pointer retains its referent. Validity-only anchors
                // contribute lifetime requirements without selecting storage.
                referenced_place = if (!has_referent or (referenced_place != null and referenced_place.?.eql(place))) place else null;
                has_referent = true;
            };
            if (dependency.validity_only) {
                var borrowed = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
                try borrowed.appendSlice(input.dependencies);
                if (input.referenced_place) |storage| if (self.valueAtPlace(state, storage)) |stored| {
                    var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                    defer roots.deinit();
                    const contents = try self.reconstructPlaceValue(state, storage, stored);
                    try collectDependencyRoots(contents, &roots);
                    try collectOwnedRoots(contents, &roots);
                    for (roots.items) |root| try appendDependencyFact(&borrowed, .{ .root = root });
                };
                input = .{ .explicit_dependency = input.explicit_dependency, .dependencies = try borrowed.toOwnedSlice() };
            }
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
            var intrinsic_owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            defer intrinsic_owned.deinit();
            try intrinsic_owned.appendSlice(direct_owned_roots);
            // Whole-value transfers can carry intrinsic ownership, such as an
            // Allocation's root, independently of its address/metadata fields.
            // Keep those roots while replacing field-derived ownership below.
            for (result.owned_roots) |root| {
                var field_owned = false;
                for (result.fields) |field| if (valueContainsOwnedRoot(field.value.*, root)) {
                    field_owned = true;
                    break;
                };
                if (!field_owned) try appendRootFact(&intrinsic_owned, root);
            }
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
            // A complete field effect supersedes ownership derived from the
            // prior fields. Intrinsic roots follow the whole-value transfer;
            // roots owned only by replaced fields must leave the parent.
            var current_owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            for (intrinsic_owned.items) |root| try appendRootFact(&current_owned, root);
            for (fields) |field| for (field.value.owned_roots) |root| try appendRootFact(&current_owned, root);
            const old_owned = result.owned_roots;
            result.owned_roots = try current_owned.toOwnedSlice();
            var current_dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
            for (result.dependencies) |dependency| {
                if (containsRoot(old_owned, dependency.root) and !containsRoot(result.owned_roots, dependency.root)) continue;
                try appendDependencyFact(&current_dependencies, dependency);
            }
            result.dependencies = try current_dependencies.toOwnedSlice();
        }
        if (effect.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, effect.variants.len);
            for (effect.variants, 0..) |variant, index| {
                const first_root = state.tracker.roots.items.len;
                const first_capability = state.storage_capabilities.items.len;
                const value = try self.allocator.create(facts.ValueFacts);
                value.* = try self.instantiateOutputWithFresh(variant.value.*, arguments, state, fresh_roots, fresh_capabilities);
                for (state.tracker.roots.items[first_root..]) |*root| {
                    // Input storage generations can be materialized lazily
                    // while instantiating a choice payload. Their lifetime
                    // already exists regardless of which variant is returned.
                    var input_storage = false;
                    for (state.storage_generations.items) |generation| if (generation.generation == root.id) {
                        input_storage = true;
                        break;
                    };
                    if (!input_storage) root.state = .conditional;
                }
                for (state.storage_capabilities.items[first_capability..]) |*capability| if (capability.* == .available) {
                    capability.* = .conditional;
                };
                variants[index] = .{ .index = variant.index, .value = value };
            }
            result.variants = variants;
        }
        result.integer_address = result.integer_address or effect.integer_address;
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
                    var merged: facts.ValueFacts = .{ .foreign_storage = current.foreign_storage };
                    for (current.fields) |field| merged = try self.mergeValueFacts(merged, field.value.*);
                    if (current.fields.len != 0) current = merged;
                },
                .dereference => {},
            }
        }
        return current;
    }

    fn mergeValueFacts(self: *SafetyChecker, left: facts.ValueFacts, right: facts.ValueFacts) !facts.ValueFacts {
        const domains = try mergeDomainFacts(self.allocator, left.domains, right.domains);
        var choice_selectors: std.ArrayList(facts.CallChoiceSelector) = .empty;
        var choice_observations: std.ArrayList(facts.CallChoiceSelector) = .empty;
        var guarded_values: std.ArrayList(facts.GuardedValueFacts) = .empty;
        for (left.choice_selectors) |a| for (right.choice_selectors) |b| if (a.eql(b)) {
            try choice_selectors.append(self.allocator, a);
            break;
        };
        for (left.choice_observations) |a| for (right.choice_observations) |b| if (a.eql(b)) {
            try choice_observations.append(self.allocator, a);
            break;
        };
        for (left.guarded_values) |a| for (right.guarded_values) |b| if (a.eql(b)) {
            try guarded_values.append(self.allocator, a);
            break;
        };
        var generation_outcomes = std.array_list.Managed(facts.GenerationOutcome).init(self.allocator);
        for (left.generation_outcomes) |outcome| for (right.generation_outcomes) |other| {
            if (outcome.eql(other)) {
                try generation_outcomes.append(outcome);
                break;
            }
        };
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

        var symbolic_pointees: std.ArrayList(graph_mod.GlobalBindingId) = .empty;
        defer symbolic_pointees.deinit(self.allocator);
        for (left.symbolic_pointees) |identity| try symbolic_pointees.append(self.allocator, identity);
        for (right.symbolic_pointees) |identity| {
            if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, symbolic_pointees.items, identity) == null)
                try symbolic_pointees.append(self.allocator, identity);
        }
        const symbolic = try self.allocator.dupe(graph_mod.GlobalBindingId, symbolic_pointees.items);
        return .{
            .symbolic_pointees = symbolic,
            .explicit_dependency = left.explicit_dependency or right.explicit_dependency,
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
            .domains = domains,
            .generation_outcomes = try generation_outcomes.toOwnedSlice(),
            .choice_selectors = try choice_selectors.toOwnedSlice(self.allocator),
            .choice_observations = try choice_observations.toOwnedSlice(self.allocator),
            .guarded_values = try guarded_values.toOwnedSlice(self.allocator),
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

    fn requireDescendantsInitialized(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, storage: facts.Place, state: *FunctionState) !void {
        for (state.places.items) |projected| {
            if (!storage.isPrefixOf(projected.storage) or storage.eql(projected.storage)) continue;
            if (projected.initializedness != .initialized)
                try self.requirePlaceInitialized(function, source, projected.storage, projected.initializedness, state);
        }
    }

    /// A projected write is authoritative for its part of an aggregate. Fold
    /// those records into a value read so copies and moves carry the current
    /// fields, including changes made through nested places.
    fn reconstructPlaceValue(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, original: facts.ValueFacts) !facts.ValueFacts {
        var result = original;
        var projections_changed = false;
        for (state.places.items, 0..) |entry, entry_index| {
            if (!storage.isPrefixOf(entry.storage) or entry.storage.projections.len <= storage.projections.len) continue;
            const projection = entry.storage.projections[storage.projections.len];
            var already_seen = false;
            for (state.places.items[0..entry_index]) |prior| {
                if (storage.isPrefixOf(prior.storage) and prior.storage.projections.len > storage.projections.len and
                    projection.eql(prior.storage.projections[storage.projections.len]))
                {
                    already_seen = true;
                    break;
                }
            }
            if (already_seen) continue;
            projections_changed = true;
            const child_storage = facts.Place{
                .root = storage.root,
                .projections = entry.storage.projections[0 .. storage.projections.len + 1],
            };
            const inherited = try self.projectValueFacts(original, &.{projection});
            const child_value = if (self.getPlace(state, child_storage)) |exact| exact.value else inherited;
            const child = try self.reconstructPlaceValue(state, child_storage, child_value);
            switch (projection) {
                .field, .static_index => |index| {
                    const field_index: u32 = @intCast(index);
                    var fields = std.array_list.Managed(facts.FieldFacts).init(self.allocator);
                    var replaced = false;
                    for (result.fields) |field| {
                        if (field.index == field_index) {
                            const stored = try self.allocator.create(facts.ValueFacts);
                            stored.* = child;
                            try fields.append(.{ .index = field_index, .value = stored });
                            replaced = true;
                        } else try fields.append(field);
                    }
                    if (!replaced) {
                        const stored = try self.allocator.create(facts.ValueFacts);
                        stored.* = child;
                        try fields.append(.{ .index = field_index, .value = stored });
                    }
                    result.fields = try fields.toOwnedSlice();
                },
                .variant => |index| {
                    var variants = std.array_list.Managed(facts.VariantFacts).init(self.allocator);
                    var replaced = false;
                    for (result.variants) |variant| {
                        if (variant.index == index) {
                            const stored = try self.allocator.create(facts.ValueFacts);
                            stored.* = child;
                            try variants.append(.{ .index = index, .value = stored });
                            replaced = true;
                        } else try variants.append(variant);
                    }
                    if (!replaced) {
                        const stored = try self.allocator.create(facts.ValueFacts);
                        stored.* = child;
                        try variants.append(.{ .index = index, .value = stored });
                    }
                    result.variants = try variants.toOwnedSlice();
                },
                .dynamic_index => result = try self.mergeValueFacts(result, child),
                .dereference => {},
            }
        }
        if (!projections_changed) return original;

        // Flattened aggregate roots must follow the authoritative projections.
        // Preserve intrinsic ownership and explicit dependencies independently
        // of fields, while removing roots carried only by replaced children.
        const old_children = facts.ValueFacts{ .fields = original.fields, .variants = original.variants };
        const new_children = facts.ValueFacts{ .fields = result.fields, .variants = result.variants };
        var owned = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer owned.deinit();
        for (result.owned_roots) |root| {
            if (!valueContainsOwnedRoot(old_children, root)) try appendRootFact(&owned, root);
        }
        const intrinsic_owned = try self.allocator.dupe(facts.ValidityRootId, owned.items);
        try collectOwnedRoots(new_children, &owned);
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        defer dependencies.deinit();
        for (result.dependencies) |dependency| {
            if (result.explicit_dependency or containsRoot(intrinsic_owned, dependency.root) or
                !valueDependsOnRoot(old_children, dependency.root))
                try appendDependencyFact(&dependencies, dependency);
        }
        var child_dependencies = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer child_dependencies.deinit();
        try collectDependencyRoots(new_children, &child_dependencies);
        for (child_dependencies.items) |root| try appendDependencyFact(&dependencies, .{ .root = root });
        result.owned_roots = try owned.toOwnedSlice();
        result.dependencies = try dependencies.toOwnedSlice();
        return result;
    }

    fn inheritedPlaceFacts(self: *SafetyChecker, state: *const FunctionState, storage: facts.Place) !facts.PlaceFacts {
        var depth = storage.projections.len;
        while (depth > 0) {
            depth -= 1;
            const ancestor = facts.Place{ .root = storage.root, .projections = storage.projections[0..depth] };
            if (findPlaceConst(state, ancestor)) |place| return .{
                .storage = storage,
                .initializedness = place.initializedness,
                .value = try self.projectValueFacts(place.value, storage.projections[depth..]),
            };
        }
        return .{ .storage = storage };
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
                state.storage_generations.items[index].needs_current_generation = false;
                replaced = true;
                index += 1;
            } else {
                _ = state.storage_generations.orderedRemove(index);
            }
        }
        if (!replaced)
            try state.storage_generations.append(.{ .storage = storage, .generation = try state.tracker.establish(.fresh) });
    }

    fn beginLexicalStorage(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) !void {
        for (state.storage_generations.items) |entry| {
            if (!storage.isPrefixOf(entry.storage)) continue;
            try self.refreshStorageGeneration(state, storage);
            return;
        }
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
                // An owning aggregate lives in its binding's storage. Its
                // references to heap storage do not place the binding there.
                if (!isPointer(self.graph, self.graph.binding(binding).ty))
                    break :blk value.value.opaque_provenance;
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
        var stored = value;
        if (ty) |value_type| if (self.typeContainsPointer(value_type)) {
            var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
            try dependencies.appendSlice(value.dependencies);
            // Reading a reference from an opaque slot borrows the references
            // stored there, including dependencies that have already ended.
            // Filtering to live roots would hide precisely the stale read.
            for (provenances.items) |provenance| for (state.opaque_storages.items) |domain| {
                if (!domain.storage.eql(provenance.storage)) continue;
                for (domain.hidden_dependencies) |dependency| {
                    if (!self.opaqueDependencyIsInternalToStorage(state, domain.storage, dependency))
                        try appendDependencyFact(&dependencies, .{ .root = dependency });
                }
            };
            stored.dependencies = try dependencies.toOwnedSlice();
        };
        return self.addOpaqueReadEnvelope(stored, ty, provenances.items);
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
        var owners = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer owners.deinit();
        if (self.valueAtPlace(state, storage)) |value| try collectOwnedRoots(value, &owners);
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            var merged = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            try merged.appendSlice(opaque_storage.hidden_dependencies);
            for (dependencies) |dependency| try appendRootFact(&merged, dependency);
            opaque_storage.hidden_dependencies = try merged.toOwnedSlice();
            opaque_storage.outcome_guard = 0;
            var combined = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            try combined.appendSlice(opaque_storage.owner_roots);
            for (owners.items) |root| try appendRootFact(&combined, root);
            opaque_storage.owner_roots = try combined.toOwnedSlice();
            return;
        }
        var hidden = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        for (dependencies) |dependency| try appendRootFact(&hidden, dependency);
        try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = try hidden.toOwnedSlice(), .owner_roots = try owners.toOwnedSlice() });
    }

    fn markOpaqueStorageEmpty(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) void {
        _ = self;
        for (state.opaque_storages.items) |*opaque_storage| {
            if (!opaque_storage.storage.eql(storage)) continue;
            opaque_storage.hidden_dependencies = &.{};
            opaque_storage.outcome_guard = 0;
            return;
        }
    }

    fn mergeOpaqueOwnerRoots(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, roots: []const facts.ValidityRootId) !void {
        if (roots.len == 0) return;
        for (state.opaque_storages.items) |*domain| {
            if (!domain.storage.eql(storage)) continue;
            var owners = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
            try owners.appendSlice(domain.owner_roots);
            for (roots) |root| try appendRootFact(&owners, root);
            domain.owner_roots = try owners.toOwnedSlice();
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

    fn collectReturnedStorageDependencies(
        self: *SafetyChecker,
        state: *FunctionState,
        storage: facts.Place,
        hidden: *std.array_list.Managed(facts.ValidityRootId),
    ) !void {
        const stored = self.valueAtPlace(state, storage) orelse return;
        // Returned owners conservatively carry hidden input provenance as
        // ordinary dependencies until summaries can name returned domains.
        // Extraction must retain those roots, without retaining backing owners
        // or the lexical slot holding the storage.
        var candidates = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer candidates.deinit();
        try self.collectOpaqueHiddenDependencies(state, stored, &candidates);
        for (candidates.items) |root| {
            if (valueContainsOwnedRoot(stored, root)) continue;
            var slot_generation = false;
            for (state.storage_generations.items) |entry| {
                if (storage.isPrefixOf(entry.storage) and entry.generation == root) slot_generation = true;
            }
            if (!slot_generation) try appendRootFact(hidden, root);
        }
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
        // A pointer to a named owner accesses that owner's fields, not the
        // heap slots it owns. Owned-root dependencies alone cannot identify
        // the address as lying inside an opaque domain.
        if (pointer.referenced_place != null) return;
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

    fn recordOpaqueWrite(
        self: *SafetyChecker,
        source: primitives.SourceRef,
        state: *FunctionState,
        pointer: facts.ValueFacts,
        value: facts.ValueFacts,
    ) !void {
        // Slot contents remain opaque, but every reference stored through an
        // access to the domain must constrain the lifetime of its target.
        var domains = std.array_list.Managed(facts.Place).init(self.allocator);
        defer domains.deinit();
        try self.collectOpaqueDomainsAccessedBy(state, pointer, &domains);
        if (domains.items.len == 0) {
            if (try self.inferOpaqueDomain(state, pointer)) |domain|
                try domains.append(domain)
            else if (self.inferTransferredOpaqueDomain(state, pointer)) |domain|
                try domains.append(domain);
        }
        for (domains.items) |domain| {
            if (try self.opaqueWriteCreatesOwnershipCycle(state, domain, value)) {
                try self.report(source, "root ownership must be acyclic", .{});
                continue;
            }
            try self.hideOpaqueDependencies(state, domain, value);
        }
    }

    fn inferTransferredOpaqueDomain(
        self: *SafetyChecker,
        state: *FunctionState,
        pointer: facts.ValueFacts,
    ) ?facts.Place {
        _ = self;
        for (pointer.dependencies) |dependency| {
            var dependency_is_hidden = false;
            for (state.opaque_storages.items) |opaque_storage| {
                if (!containsRoot(opaque_storage.hidden_dependencies, dependency.root)) continue;
                dependency_is_hidden = true;
                break;
            }
            if (!dependency_is_hidden) continue;

            var index = state.places.items.len;
            while (index > 0) {
                index -= 1;
                const candidate = state.places.items[index];
                if (candidate.initializedness != .moved) continue;
                if (valueContainsOwnedRoot(candidate.value, dependency.root)) return candidate.storage;
            }
        }
        return null;
    }

    fn opaqueWriteCreatesOwnershipCycle(
        self: *SafetyChecker,
        state: *FunctionState,
        domain: facts.Place,
        value: facts.ValueFacts,
    ) !bool {
        const domain_value = self.valueAtPlace(state, domain) orelse return false;
        var owners = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer owners.deinit();
        try collectOwnedRoots(domain_value, &owners);

        var transferred = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer transferred.deinit();
        try collectOwnedRoots(value, &transferred);
        for (owners.items) |owner| {
            if (!state.tracker.roots.items[@intFromEnum(owner)].owned_resource) continue;
            for (transferred.items) |dependency| {
                var visited = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
                defer visited.deinit();
                if (try self.opaqueOwnershipReaches(state, dependency, owner, &visited)) return true;
            }
        }
        return false;
    }

    fn opaqueOwnershipReaches(
        self: *SafetyChecker,
        state: *FunctionState,
        current: facts.ValidityRootId,
        target: facts.ValidityRootId,
        visited: *std.array_list.Managed(facts.ValidityRootId),
    ) !bool {
        if (current == target) return true;
        if (containsRoot(visited.items, current)) return false;
        try visited.append(current);

        for (state.opaque_storages.items) |opaque_storage| {
            const storage_value = self.valueAtPlace(state, opaque_storage.storage) orelse continue;
            if (!valueContainsOwnedRoot(storage_value, current)) continue;
            for (opaque_storage.hidden_dependencies) |dependency| {
                if (!state.tracker.roots.items[@intFromEnum(dependency)].owned_resource) continue;
                if (try self.opaqueOwnershipReaches(state, dependency, target, visited)) return true;
            }
        }
        return false;
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
        // Evaluate every element even when its safety metadata is empty.
        // Defer the dense projection table until a nonempty child needs it.
        var fields: ?[]facts.FieldFacts = null;
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = try self.evaluate(function, node, state);
            if (facts.isEmptyValue(value)) {
                if (fields) |stored| stored[index] = .{ .index = @intCast(index), .value = &facts.empty_value_facts };
                continue;
            }
            if (fields == null) {
                fields = try self.allocator.alloc(facts.FieldFacts, literal.elements.len);
                for (fields.?[0..index], 0..) |*field, prior| field.* = .{ .index = @intCast(prior), .value = &facts.empty_value_facts };
            }
            const owned = try self.allocator.create(facts.ValueFacts);
            owned.* = value;
            fields.?[index] = .{ .index = @intCast(index), .value = owned };
        }
        return .{ .fields = fields orelse &.{} };
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
        for (choice.variants) |variant| if (variant.index == wanted) {
            try self.activate_conditional_resources(state, variant.value.*);
            return variant.value.*;
        };
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
        const inference = self.active_summary_inference orelse return error.MissingSafetySummary;
        const summary = try inference.virtualSummary(call.safety_methods) orelse return error.MissingVirtualSafetyContract;
        var values = try self.allocator.alloc(facts.ValueFacts, argument_nodes.len);
        defer self.allocator.free(values);
        for (argument_nodes, 0..) |field_id, index| {
            const field = self.graph.value_fields.items[@intFromEnum(field_id)];
            const node = self.graph.node(field.value);
            values[index] = if (initializesInput(summary, index) and node.content == .address_of)
                try self.evaluateAddress(caller, node.source, node.content.address_of, &candidate, true)
            else
                try self.evaluate(caller, field.value, &candidate);
        }

        if (call.self_input_index >= values.len) return .{};
        // The call argument points at the Virtual wrapper, while the exact
        // receiver facts are stored in that wrapper's value. Recover them
        // before instantiating the published contract; selected method bodies
        // do not determine dispatch safety.
        const receiver = values[call.self_input_index];
        if (receiver.referenced_place) |wrapper| {
            if (self.valueAtPlace(&candidate, wrapper)) |stored| {
                if (stored.referenced_place != null) {
                    values[call.self_input_index] = stored;
                }
            }
        }
        if (!try self.validateConsumedInputAliasing(input_node.source, summary, argument_nodes, values, &candidate)) return .{};
        const consumed = try self.callCleanupNodes(summary, argument_nodes, values, &candidate, false);
        const initialized = try self.callCleanupNodes(summary, argument_nodes, values, &candidate, true);
        const outcomes = try self.callOutcomeCleanups(summary, argument_nodes, values, &candidate);
        self.graph.virtual_calls.items[@intFromEnum(id)].consumed_auto_deinits = consumed;
        self.graph.virtual_calls.items[@intFromEnum(id)].initialized_auto_deinits = initialized;
        self.graph.virtual_calls.items[@intFromEnum(id)].outcome_cleanups = outcomes;
        const result = (try self.applyVirtualContractSummary(call, input_node.source, argument_nodes, values, &candidate)) orelse facts.ValueFacts{};
        if (self.diagnostics.list.items.len != diagnostic_count) return .{};
        self.commitState(state, &candidate);
        return result;
    }

    fn applyVirtualContractSummary(
        self: *SafetyChecker,
        call: graph_mod.VirtualCall,
        source: primitives.SourceRef,
        argument_nodes: []const graph_mod.GlobalValueFieldId,
        values: []const facts.ValueFacts,
        state: *FunctionState,
    ) !?facts.ValueFacts {
        const inference = self.active_summary_inference orelse return null;
        const summary = try self.selectEntryGuardedSummary(try inference.virtualSummary(call.safety_methods) orelse return error.MissingVirtualSafetyContract, values, state);
        // Private receiver projections are erased at a virtual boundary.
        // Validate the receiver contents as well as the handle lifetime.
        if (call.self_input_index < values.len) {
            if (values[call.self_input_index].referenced_place) |place| if (self.valueAtPlace(state, place)) |stored| {
                const before = self.diagnostics.list.items.len;
                try self.requireLive(@enumFromInt(0), source, stored, state);
                if (self.diagnostics.list.items.len != before) return facts.ValueFacts{};
            };
        }
        if (!try self.validateSummaryRequiredLive(source, summary, values, state)) return facts.ValueFacts{};
        var call_capabilities = std.AutoHashMap(facts.FreshEffectSource, facts.StorageCapabilityId).init(self.allocator);
        defer call_capabilities.deinit();
        const previous_capabilities = self.active_fresh_capabilities;
        self.active_fresh_capabilities = &call_capabilities;
        defer self.active_fresh_capabilities = previous_capabilities;
        const prepared = try self.prepareGeneralValueGuards(summary, values, state);
        const result = try self.applyOutcomeSummary(source, summary, argument_nodes, values, state);
        return try self.attachGeneralValueGuards(summary, prepared, result);
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
        const children = self.graph.auto_deinit_fields.items[fields.start..][0..fields.len];
        if (children.len != 0 and children[0].is_variant) {
            const ty = self.domainStorageType(storage) orelse return;
            const variants = types.variants(self.graph, ty) orelse return;
            var joined: ?FunctionState = null;
            defer if (joined) |*value| value.deinit();
            for (0..variants.len) |index| {
                if (self.activeVariant(state, storage)) |active| {
                    if (active != index) continue;
                }
                if (self.valueAtPlace(state, storage)) |value| if (value.known_choice_variant) |active| {
                    if (active != index) continue;
                };
                if (self.variantRejected(state, storage, @intCast(index))) continue;
                var branch = try state.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                defer branch.deinit();
                self.setActiveVariant(&branch, storage, @intCast(index));
                const payload_storage = try self.project(storage, .{ .variant = @intCast(index) });
                if (self.valueAtPlace(&branch, payload_storage)) |payload|
                    try self.activate_conditional_resources(&branch, payload);
                for (children) |field| {
                    if (field.field_index != index) continue;
                    try self.evaluateAutoDeinitField(function, field, payload_storage, &branch);
                }
                if (joined) |*existing| {
                    var combined = try existing.clone(self.allocator, if (self.collect_stats) &self.stats else null);
                    try self.joinState(&combined, existing, &branch);
                    existing.deinit();
                    existing.* = combined;
                } else joined = try branch.clone(self.allocator, if (self.collect_stats) &self.stats else null);
            }
            if (joined) |*value| self.commitState(state, value);
            return;
        }
        for (children) |field| {
            const field_storage = try self.project(storage, .{ .field = field.field_index });
            try self.evaluateAutoDeinitField(function, field, field_storage, state);
        }
    }

    fn evaluateAutoDeinitField(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, field: graph_mod.AutoDeinitField, field_storage: facts.Place, state: *FunctionState) anyerror!void {
        if (self.initializednessAtPlace(state, field_storage) != .initialized) return;
        if (field.deinit_fn) |deinit_fn| {
            try self.evaluateResolvedDeinit(
                function,
                deinit_fn,
                field.input orelse return,
                field.self_field_index,
                field_storage,
                state,
            );
        } else {
            try self.evaluateStructuralAutoDeinit(function, field.fields, field_storage, state);
            try self.setPlace(state, field_storage, .deinitialized, .{});
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

    fn evaluateAddress(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        child: graph_mod.GlobalNodeId,
        state: *FunctionState,
        allow_moved_destination: bool,
    ) !facts.ValueFacts {
        if (self.graph.node(child).content == .assignment) {
            const assignment = self.graph.node(child).content.assignment;
            const binding = self.graph.binding(assignment.binding);
            if (binding.deferred_initialization) {
                const place = facts.Place{ .root = assignment.binding };
                // Re-evaluating a loop condition replaces the previous
                // temporary and starts a new storage generation.
                if (binding.reinitialize_cleanup) |cleanup| {
                    const cleanup_node = self.graph.node(cleanup);
                    if (cleanup_node.content == .auto_deinit_binding)
                        try self.applyAutoDeinit(function, cleanup_node.content.auto_deinit_binding, state);
                }
                try self.refreshStorageGenerationChecked(source, state, place);
                const value = try self.evaluate(function, assignment.value, state);
                try self.setPlace(state, place, .initialized, value);
            }
        }
        try self.validateAddressAccess(function, source, child, state);
        const storage = try self.resolvePlace(child, state);
        if (!allow_moved_destination) if (storage) |target| if (self.initializednessAtPlace(state, target) == .moved)
            try self.reportMovedPlace(source, target, state);
        const opaque_provenance = try self.opaqueProvenanceForAccess(child, state);
        var dependencies = std.array_list.Managed(facts.ValidityDependency).init(self.allocator);
        if (opaque_provenance.len == 0) {
            if (storage) |target| {
                const generation = try self.storageGeneration(state, target);
                try appendDependencyFact(&dependencies, .{ .root = generation });
                // Taking the address of an input/output slot borrows this
                // function's physical storage. Summaries can also materialize
                // facts rooted at those bindings for caller-derived values;
                // those metadata roots alone do not constitute a slot borrow.
                const record = self.graph.function(function);
                const outputs = self.graph.binding_refs.items[record.output_bindings.start..][0..record.output_bindings.len];
                if (self.functionInputIndex(function, target.root) != null or
                    std.mem.indexOfScalar(graph_mod.GlobalBindingId, outputs, target.root) != null)
                    try appendRootFact(&state.lexical_storage_generations, generation);
            }
        } else {
            for (opaque_provenance) |provenance|
                try appendDependencyFact(&dependencies, .{ .root = provenance.generation });
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .referenced_place = storage,
            .opaque_provenance = opaque_provenance,
        };
    }

    // Address formation and projected reads must validate every pointer used
    // to reach the destination, even when the final Place is resolved directly.
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

    fn reportMovedPlace(self: *SafetyChecker, source: primitives.SourceRef, storage: facts.Place, state: *FunctionState) !void {
        const name = self.graph.text(self.graph.binding(storage.root).name);
        const moved_at = if (self.getPlace(state, storage)) |place| place.moved_at else null;
        if (moved_at) |origin| if (self.location(origin)) |origin_location| {
            const position = self.diagnostics.lineColumn(origin_location);
            if (storage.projections.len == 0)
                return self.report(source, "binding '{s}' was moved and cannot be used again (moved at {s}:{d}:{d})", .{ name, self.diagnostics.path(origin_location), position.line, position.column })
            else
                return self.report(source, "place rooted at '{s}' is moved and cannot be used (moved at {s}:{d}:{d})", .{ name, self.diagnostics.path(origin_location), position.line, position.column });
        };
        if (storage.projections.len == 0) return self.report(source, "binding '{s}' was moved and cannot be used again", .{name});
        return self.report(source, "place rooted at '{s}' is moved and cannot be used", .{name});
    }

    fn reportMovedReassignment(self: *SafetyChecker, source: primitives.SourceRef, storage: facts.Place, state: *FunctionState) !void {
        const name = self.graph.text(self.graph.binding(storage.root).name);
        const moved_at = if (self.getPlace(state, storage)) |place| place.moved_at else null;
        if (moved_at) |origin| if (self.location(origin)) |origin_location| {
            const position = self.diagnostics.lineColumn(origin_location);
            return self.report(source, "binding '{s}' was moved and cannot be reassigned (moved at {s}:{d}:{d})", .{ name, self.diagnostics.path(origin_location), position.line, position.column });
        };
        return self.report(source, "binding '{s}' was moved and cannot be reassigned", .{name});
    }

    fn resolvePlace(self: *SafetyChecker, node_id: graph_mod.GlobalNodeId, state: *FunctionState) !?facts.Place {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .binding_use => |binding| facts.Place{ .root = binding },
            .assignment => |assignment| if (self.graph.binding(assignment.binding).deferred_initialization)
                facts.Place{ .root = assignment.binding }
            else
                null,
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
            .array_index => |access| blk: {
                const pointer = try self.evaluate(@enumFromInt(0), access.array_ptr, state);
                const base = pointer.referenced_place orelse break :blk null;
                break :blk try self.project(base, if (self.staticIndex(access.index)) |index| .{ .static_index = index } else .dynamic_index);
            },
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
        for (state.storage_generations.items) |*entry| if (entry.storage.eql(storage)) {
            // Both paths may leave an initialized Place with different
            // incarnations. A new borrow observes the current storage, while
            // historical aliases keep their original, conservatively joined
            // roots. Materialize only on demand to avoid growing loop states.
            if (entry.needs_current_generation and self.initializednessAtPlace(state, storage) == .initialized) {
                entry.generation = try state.tracker.establish(.fresh);
                entry.needs_current_generation = false;
            }
            return entry.generation;
        };
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
            if (initializedness != .moved) entry.moved_at = null;
            entry.value = value;
            stored = true;
            break;
        };
        if (!stored)
            try state.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
        if (initializedness == .initialized)
            try self.recordKnownChoiceVariants(state, storage, value);
    }

    fn markMoved(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, value: facts.ValueFacts, source: primitives.SourceRef) !void {
        try self.setPlace(state, storage, .moved, value);
        if (self.getPlace(state, storage)) |place| place.moved_at = source;
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

    fn requirePlaceInitialized(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        storage: facts.Place,
        initializedness: value_state.Initializedness,
        state: *FunctionState,
    ) !void {
        if (initializedness == .moved) return self.reportMovedPlace(source, storage, state);
        if (initializedness == .maybe_initialized) {
            const name = self.graph.text(self.graph.binding(storage.root).name);
            return self.report(source, "place rooted at '{s}' is maybe_initialized and cannot be used", .{name});
        }
        try self.requireInitialized(function, source, initializedness);
    }

    fn domainStorageType(self: *SafetyChecker, storage: facts.Place) ?graph_mod.GlobalTypeId {
        var ty = self.graph.binding(storage.root).ty;
        for (storage.projections) |projection| {
            ty = switch (projection) {
                .field => |field| blk: {
                    if (self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
                    break :blk self.fieldTypeAt(ty, field) orelse return null;
                },
                .variant => |variant| self.variantPayloadTypeAt(ty, variant) orelse return null,
                .static_index, .dynamic_index => types.arrayElement(self.graph, ty) orelse return null,
                .dereference => if (self.graph.semanticType(ty) == .pointer) self.graph.semanticType(ty).pointer.child else return null,
            };
        }
        return ty;
    }

    fn domainStorage(self: *SafetyChecker, argument: facts.ValueFacts, index: u32, state: *FunctionState) ![]const facts.Place {
        var value = argument;
        if (value.domains.len == 0) if (value.referenced_place) |wrapper| {
            if (self.valueAtPlace(state, wrapper)) |stored| value = stored;
        };
        for (value.domains) |domain| if (domain.domain_index == index) return domain.storages;
        return error.MissingVirtualStorageDomain;
    }

    fn captureContractStorage(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, state: *FunctionState, storage: facts.Place, ty: graph_mod.GlobalTypeId, dependencies: *std.array_list.Managed(facts.ValidityDependency), visited: *std.array_list.Managed(facts.Place)) anyerror!void {
        for (visited.items) |previous| if (previous.eql(storage)) return;
        try visited.append(storage);
        try self.requirePlaceInitialized(function, source, storage, self.initializednessAtPlace(state, storage), state);
        try self.requireDescendantsInitialized(function, source, storage, state);
        try appendDependencyFact(dependencies, .{ .root = try self.storageGeneration(state, storage) });
        const value = try self.reconstructPlaceValue(state, storage, self.valueAtPlace(state, storage) orelse .{});
        var roots = std.array_list.Managed(facts.ValidityRootId).init(self.allocator);
        defer roots.deinit();
        try collectDependencyRoots(value, &roots);
        try collectOwnedRoots(value, &roots);
        try self.collectOpaqueHiddenDependencies(state, value, &roots);
        for (roots.items) |root| try appendDependencyFact(dependencies, .{ .root = root });
        if (self.graph.semanticType(ty) == .pointer) {
            if (value.referenced_place) |referent|
                try self.captureContractStorage(function, source, state, referent, self.graph.semanticType(ty).pointer.child, dependencies, visited);
            return;
        }
        if (self.graph.semanticType(ty) == .virtual) {
            // Its concrete storage was captured when this nested handle was
            // created. The handle's dependencies remain part of this envelope.
            return;
        }
        const array_element = types.arrayElement(self.graph, ty);
        for (value.fields) |field| {
            const child_type = array_element orelse self.fieldTypeAt(ty, field.index) orelse continue;
            const projection: facts.Projection = if (array_element != null) .{ .static_index = field.index } else .{ .field = field.index };
            try self.captureContractStorage(function, source, state, try self.project(storage, projection), child_type, dependencies, visited);
        }
        for (value.variants) |variant| {
            if (value.known_choice_variant) |known| if (variant.index != known) continue;
            const child_type = self.variantPayloadTypeAt(ty, variant.index) orelse continue;
            try self.captureContractStorage(function, source, state, try self.project(storage, .{ .variant = variant.index }), child_type, dependencies, visited);
        }
    }

    fn requireLive(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, source: primitives.SourceRef, value: facts.ValueFacts, state: *FunctionState) !void {
        _ = function;
        if (!state.tracker.dependenciesAreAlive(try self.refineGeneralValue(value, state))) try self.report(source, "reference depends on a root that has ended", .{});
    }

    fn rejectEscapingLocalRoots(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        source: primitives.SourceRef,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) !void {
        if (self.escapingLocalRoot(function, value, state)) |root| {
            var name: []const u8 = "local or temporary";
            for (state.storage_generations.items) |entry| if (entry.generation == root) {
                name = self.graph.text(self.graph.binding(entry.storage.root).name);
                break;
            };
            try self.report(source, "function output cannot depend on a local storage generation that ends before return (storage rooted at '{s}'); return an owned value instead, or create the owner in the caller and pass a reference to it", .{name});
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
            if (self.initializednessAtPlace(state, storage) != .initialized) continue;
            const source = self.graph.bindings.items[@intFromEnum(binding)].source;
            try self.rejectEscapingLocalRoots(function, source, output, state);
            // Field assignments have their own authoritative place records.
            // Returning the parent also returns those updated projections.
            for (state.places.items) |place| {
                if (place.storage.eql(storage) or !storage.isPrefixOf(place.storage)) continue;
                if (place.initializedness != .initialized) continue;
                try self.rejectEscapingLocalRoots(function, source, place.value, state);
            }
        }
    }

    fn valueDependsOnLocalStorage(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) bool {
        return self.escapingLocalRoot(function, value, state) != null;
    }

    // Dependencies survive erasure into virtual receivers and opaque values.
    // Inspect the facts rather than relying on the output's surface type.
    fn escapingLocalRoot(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        value: facts.ValueFacts,
        state: *FunctionState,
    ) ?facts.ValidityRootId {
        for (value.dependencies) |dependency|
            if (self.isLocalStorageGeneration(function, state, dependency.root)) return dependency.root;
        for (value.opaque_provenance) |provenance|
            if (self.isLocalStorageGeneration(function, state, provenance.generation)) return provenance.generation;
        for (state.opaque_storages.items) |domain| {
            const stored = self.valueAtPlace(state, domain.storage) orelse facts.ValueFacts{};
            var carries_domain = valueSharesOwnedDependency(value, stored);
            for (domain.owner_roots) |root| if (valueContainsOwnedRoot(value, root) or valueDependsOnRoot(value, root)) {
                carries_domain = true;
                break;
            };
            if (!carries_domain) if (self.functionInputIndex(function, domain.storage.root)) |input_index| {
                // Pointer input seeds describe an unknown caller referent.
                // Symbolic output paths identify which input domain escapes;
                // validity roots alone cannot distinguish possibly aliased
                // inputs from unrelated owners sharing an allocator.
                if (self.active_summaries) |summaries| if (summaries.summaryFor(function)) |summary| {
                    for (summary.outputs) |output| if (effectBorrowsInputReferent(output, input_index)) {
                        carries_domain = true;
                        break;
                    };
                };
            };
            if (!carries_domain) continue;
            for (domain.hidden_dependencies) |dependency|
                if (self.isLocalStorageGeneration(function, state, dependency)) return dependency;
        }
        for (value.fields) |field|
            if (self.escapingLocalRoot(function, field.value.*, state)) |root| return root;
        for (value.variants) |variant|
            if (self.escapingLocalRoot(function, variant.value.*, state)) |root| return root;
        return null;
    }

    fn isLocalStorageGeneration(
        self: *SafetyChecker,
        function: graph_mod.GlobalFunctionId,
        state: *const FunctionState,
        root: facts.ValidityRootId,
    ) bool {
        if (containsRoot(state.lexical_storage_generations.items, root)) return true;
        for (state.storage_generations.items) |entry| {
            if (entry.generation != root) continue;
            if (self.graph.isModuleBinding(entry.storage.root)) return false;
            if (self.functionInputIndex(function, entry.storage.root) != null) return false;
            const record = self.graph.function(function);
            const outputs = self.graph.binding_refs.items[record.output_bindings.start..][0..record.output_bindings.len];
            for (outputs) |output| if (output == entry.storage.root) return false;
            return true;
        }
        return false;
    }

    fn endBlockStorage(self: *SafetyChecker, block_id: graph_mod.GlobalBlockId, state: *FunctionState) !void {
        // TODO: Preserve lexical array roots through imported Errable payload
        // extraction; a borrowed aggregate assigned into an outer binding can
        // otherwise lose its dependency when the inner array's scope ends.
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

        for (left.symbolic_pointees.items) |pointee| {
            var result = pointee;
            for (right.symbolic_pointees.items) |other| {
                if (other.identity == pointee.identity and other.initializedness != pointee.initializedness)
                    result.initializedness = .maybe_initialized;
            }
            try joined.symbolic_pointees.append(result);
        }
        for (right.symbolic_pointees.items) |pointee| {
            var found = false;
            for (left.symbolic_pointees.items) |other| if (other.identity == pointee.identity) {
                found = true;
                break;
            };
            if (!found) try joined.symbolic_pointees.append(pointee);
        }

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
                .outcome_guard = if (index < left.tracker.roots.items.len and index < right.tracker.roots.items.len and
                    left.tracker.roots.items[index].outcome_guard == right.tracker.roots.items[index].outcome_guard)
                    left.tracker.roots.items[index].outcome_guard
                else
                    0,
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
            // A projection written on only one path still has a value on the
            // other path: it inherits that path's nearest aggregate record.
            const right_place = if (findPlaceConst(right, left_place.storage)) |exact| exact.* else try self.inheritedPlaceFacts(right, left_place.storage);
            merged.initializedness = joinInitializedness(left_place.initializedness, right_place.initializedness);
            merged.moved_at = if (merged.initializedness == .moved)
                if (left_place.initializedness == .moved) left_place.moved_at else right_place.moved_at
            else
                null;
            merged.value = try self.mergeValueFacts(left_place.value, right_place.value);

            try joined.places.append(merged);
        }
        for (right.places.items) |right_place| {
            if (findPlaceConst(left, right_place.storage) == null) {
                const left_place = try self.inheritedPlaceFacts(left, right_place.storage);
                var merged = right_place;
                merged.initializedness = joinInitializedness(left_place.initializedness, right_place.initializedness);
                merged.moved_at = if (merged.initializedness == .moved)
                    if (left_place.initializedness == .moved) left_place.moved_at else right_place.moved_at
                else
                    null;
                merged.value = try self.mergeValueFacts(left_place.value, right_place.value);

                try joined.places.append(merged);
            }
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
            for (joined.storage_generations.items) |*existing| {
                if (existing.storage.eql(candidate.storage)) {
                    existing.needs_current_generation = existing.needs_current_generation or candidate.needs_current_generation or
                        (existing.generation != candidate.generation and
                            self.initializednessAtPlace(@constCast(left), candidate.storage) == .initialized and
                            self.initializednessAtPlace(@constCast(right), candidate.storage) == .initialized);
                    found = true;
                    break;
                }
            }
            if (!found) try joined.storage_generations.append(candidate);
        }
        for (left.lexical_storage_generations.items) |root| try appendRootFact(&joined.lexical_storage_generations, root);
        for (right.lexical_storage_generations.items) |root| try appendRootFact(&joined.lexical_storage_generations, root);

        for (left.opaque_storages.items) |opaque_storage| {
            try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);
            try self.mergeOpaqueOwnerRoots(&joined, opaque_storage.storage, opaque_storage.owner_roots);
        }
        for (right.opaque_storages.items) |opaque_storage| {
            try self.mergeOpaqueStorage(&joined, opaque_storage.storage, opaque_storage.hidden_dependencies);
            try self.mergeOpaqueOwnerRoots(&joined, opaque_storage.storage, opaque_storage.owner_roots);
        }

        for (joined.opaque_storages.items) |*domain| {
            for (left.opaque_storages.items) |a| if (a.storage.eql(domain.storage)) {
                for (right.opaque_storages.items) |b| if (b.storage.eql(domain.storage) and a.outcome_guard == b.outcome_guard) {
                    domain.outcome_guard = a.outcome_guard;
                    break;
                };
                break;
            };
        }

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
                    try self.activate_conditional_resources(state, payload.value.*);
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
        if (remaining) |only| {
            if (self.valueAtPlace(state, target)) |value| for (value.variants) |payload| if (payload.index == only) {
                try self.activate_conditional_resources(state, payload.value.*);
                break;
            };
            self.setActiveVariant(state, target, only);
        }
    }

    fn activate_conditional_resources(self: *SafetyChecker, state: *FunctionState, value: facts.ValueFacts) !void {
        for (value.generation_outcomes) |outcome| {
            if (outcome.empties_opaque_storage) {
                var current = false;
                for (state.storage_generations.items) |generation| if (generation.storage.eql(outcome.storage) and generation.generation == outcome.generation and !generation.needs_current_generation and state.tracker.isAlive(generation.generation)) {
                    current = true;
                    break;
                };
                if (current) for (state.opaque_storages.items) |domain| if (domain.storage.eql(outcome.storage) and domain.outcome_guard == outcome.guard) {
                    self.markOpaqueStorageEmpty(state, outcome.storage);
                    break;
                };
                continue;
            }
            if (@intFromEnum(outcome.generation) >= state.tracker.roots.items.len) continue;
            const root = &state.tracker.roots.items[@intFromEnum(outcome.generation)];
            if (root.state != .maybe_alive or root.outcome_guard != outcome.guard) continue;
            var current = false;
            for (state.storage_generations.items) |generation| if (generation.storage.eql(outcome.storage) and generation.generation == outcome.generation and !generation.needs_current_generation) {
                current = true;
                break;
            };
            root.outcome_guard = 0;
            if (!current) continue;
            if (outcome.relocation) |relocation| {
                if (@intFromEnum(relocation.generation) >= state.tracker.roots.items.len) continue;
                const destination_root = &state.tracker.roots.items[@intFromEnum(relocation.generation)];
                if (destination_root.state != .maybe_alive or destination_root.outcome_guard != outcome.guard or
                    self.initializednessAtPlace(state, outcome.storage) != .maybe_initialized or
                    self.initializednessAtPlace(state, relocation.destination) != .maybe_initialized) continue;
                var destination_current = false;
                for (state.storage_generations.items) |generation| if (generation.storage.eql(relocation.destination) and
                    generation.generation == relocation.generation and !generation.needs_current_generation)
                {
                    destination_current = true;
                    break;
                };
                if (!destination_current) continue;
                destination_root.outcome_guard = 0;
                if (relocation.moved) {
                    try self.endStorageGenerationsUnder(outcome.source, state, outcome.storage);
                    try self.setPlace(state, outcome.storage, .moved, .{});
                    destination_root.state = .alive;
                    if (self.getPlace(state, relocation.destination)) |place| place.initializedness = .initialized;
                } else {
                    try self.endStorageGenerationsUnder(outcome.source, state, relocation.destination);
                    try self.setPlace(state, relocation.destination, relocation.available_state, .{});
                    root.state = .alive;
                    if (self.getPlace(state, outcome.storage)) |place| place.initializedness = .initialized;
                }
                continue;
            }
            if (outcome.resource_state) |initializedness| {
                if (self.initializednessAtPlace(state, outcome.storage) != .maybe_initialized) continue;
                if (initializedness == .deinitialized) {
                    _ = try self.endRoots(outcome.source, state, outcome.owned_roots);
                    try self.endStorageGenerationsUnder(outcome.source, state, outcome.storage);
                    try self.setPlace(state, outcome.storage, .deinitialized, .{});
                } else {
                    root.state = .alive;
                    for (outcome.owned_roots) |owned| {
                        const entry = &state.tracker.roots.items[@intFromEnum(owned)];
                        if (entry.state == .maybe_alive and entry.outcome_guard == outcome.guard) {
                            entry.state = .alive;
                            entry.outcome_guard = 0;
                        }
                    }
                    if (self.getPlace(state, outcome.storage)) |place| place.initializedness = .initialized;
                }
                continue;
            }
            if (outcome.invalidates) {
                try self.refreshStorageGenerationChecked(outcome.source, state, outcome.storage);
            } else root.state = .alive;
        }
        for (value.fields) |field| try self.activate_conditional_resources(state, field.value.*);
        if (value.known_choice_variant) |active| for (value.variants) |variant| {
            if (variant.index == active) try self.activate_conditional_resources(state, variant.value.*);
        };
        try self.activate_conditional_owner_roots(state, value);
        try self.activate_conditional_capabilities(state, value);
    }

    fn activate_conditional_owner_roots(self: *SafetyChecker, state: *FunctionState, value: facts.ValueFacts) anyerror!void {
        for (value.owned_roots) |root| {
            const entry = &state.tracker.roots.items[@intFromEnum(root)];
            if (entry.state == .conditional) entry.state = .alive;
        }
        for (value.fields) |field| try self.activate_conditional_owner_roots(state, field.value.*);
        // Knowing an outer tag does not establish an inner choice's owner.
        // Preserve the inner condition until its own payload is selected.
        if (value.known_choice_variant) |active| for (value.variants) |variant| {
            if (variant.index == active) try self.activate_conditional_owner_roots(state, variant.value.*);
        };
    }

    fn activate_conditional_capabilities(self: *SafetyChecker, state: *FunctionState, value: facts.ValueFacts) !void {
        for (value.storage_capabilities) |capability| {
            const entry = &state.storage_capabilities.items[@intFromEnum(capability)];
            if (entry.* == .conditional) entry.* = .available;
        }
        for (value.fields) |field| try self.activate_conditional_capabilities(state, field.value.*);
        if (value.known_choice_variant) |active| for (value.variants) |variant| {
            if (variant.index == active) try self.activate_conditional_capabilities(state, variant.value.*);
        };
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
            .int_literal => |value| std.math.cast(usize, value),
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

    fn validateIntegerLiteral(self: *SafetyChecker, source: primitives.SourceRef, maybe_ty: ?graph_mod.GlobalTypeId, value: i128) !void {
        const ty = maybe_ty orelse return;
        const builtin = switch (self.graph.resolvedSemanticType(ty) orelse return) {
            .builtin => |kind| kind,
            else => return,
        };
        const fits = switch (builtin) {
            .Int8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
            .Int16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
            .Int32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
            .Int64 => value >= std.math.minInt(i64) and value <= std.math.maxInt(i64),
            .UInt8 => value >= 0 and value <= std.math.maxInt(u8),
            .UInt16 => value >= 0 and value <= std.math.maxInt(u16),
            .UInt32 => value >= 0 and value <= std.math.maxInt(u32),
            .UInt64 => value >= 0 and value <= std.math.maxInt(u64),
            .UIntNative => value >= 0 and value <= std.math.maxInt(usize),
            else => return,
        };
        if (fits) return;
        switch (builtin) {
            .Int8 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i8), std.math.maxInt(i8) }),
            .Int16 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i16), std.math.maxInt(i16) }),
            .Int32 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i32), std.math.maxInt(i32) }),
            .Int64 => try self.report(source, "integer literal {d} does not fit in '{s}' (min {d}, max {d})", .{ value, @tagName(builtin), std.math.minInt(i64), std.math.maxInt(i64) }),
            .UInt8 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u8) }),
            .UInt16 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u16) }),
            .UInt32 => try self.report(source, "integer literal {d} does not fit in '{s}' (max {d})", .{ value, @tagName(builtin), std.math.maxInt(u32) }),
            .UInt64 => try self.report(source, "integer literal {d} does not fit in '{s}' (min 0, max {d})", .{ value, @tagName(builtin), std.math.maxInt(u64) }),
            .UIntNative => try self.report(source, "integer literal {d} does not fit in '{s}' (min 0, max {d})", .{ value, @tagName(builtin), std.math.maxInt(usize) }),
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

fn effectBorrowsInputReferent(effect: facts.ValueEffect, input_index: usize) bool {
    for (effect.input_places) |path| if (path.input_index == input_index) return true;
    for (effect.input_dependencies) |dependency|
        if (dependency.path.input_index == input_index and !dependency.validity_only and !dependency.transfers_ownership) return true;
    for (effect.fields) |field| if (effectBorrowsInputReferent(field.value.*, input_index)) return true;
    for (effect.variants) |variant| if (effectBorrowsInputReferent(variant.value.*, input_index)) return true;
    return false;
}

// A returned owner or borrow can carry an opaque domain without exposing its
// stored elements. Shared resource roots connect those values to the domain's
// hidden dependencies even after the source owner has moved.
fn valueSharesOwnedDependency(value: facts.ValueFacts, storage: facts.ValueFacts) bool {
    for (value.owned_roots) |root| if (valueContainsOwnedRoot(storage, root)) return true;
    for (value.dependencies) |dependency| if (valueContainsOwnedRoot(storage, dependency.root)) return true;
    for (value.fields) |field| if (valueSharesOwnedDependency(field.value.*, storage)) return true;
    for (value.variants) |variant| if (valueSharesOwnedDependency(variant.value.*, storage)) return true;
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

fn valueHasDeadExplicitDependency(value: facts.ValueFacts, state: *const SafetyChecker.FunctionState) bool {
    return valueHasDeadExplicitDependencyForUse(value, state, false);
}

fn valueHasDeadExplicitDependencyForUse(value: facts.ValueFacts, state: *const SafetyChecker.FunctionState, pointer_identity: bool) bool {
    if (value.explicit_dependency) for (value.dependencies) |dependency| {
        const root = state.tracker.roots.items[@intFromEnum(dependency.root)];
        if (root.state == .alive) continue;
        // Copying pointer bits does not access the resource. Dereference and
        // call preconditions check the complete loan before using it, while
        // non-resource anchors remain obligations of this value itself.
        if (pointer_identity and root.owned_resource) continue;
        // A choice can carry an owner that exists only on its success branch.
        // Inspecting the choice does not use that resource before narrowing.
        // External loans have no ownership envelope and remain checked.
        if (root.owned_resource and (root.state == .conditional or root.state == .maybe_alive) and valueContainsOwnedRoot(value, dependency.root)) continue;
        return true;
    };
    for (value.fields) |field| if (valueHasDeadExplicitDependency(field.value.*, state)) return true;
    for (value.variants) |variant| if (valueHasDeadExplicitDependency(variant.value.*, state)) return true;
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
        left.symbolic_pointees.items.len != right.symbolic_pointees.items.len or
        left.ownership_edges.items.len != right.ownership_edges.items.len or
        left.storage_generations.items.len != right.storage_generations.items.len or
        left.opaque_storages.items.len != right.opaque_storages.items.len or
        left.choice_active.items.len != right.choice_active.items.len or
        left.choice_rejected.items.len != right.choice_rejected.items.len or
        left.choice_temporary_active.items.len != right.choice_temporary_active.items.len) return false;

    for (left.symbolic_pointees.items) |pointee| {
        var found = false;
        for (right.symbolic_pointees.items) |other| if (other.identity == pointee.identity) {
            if (other.initializedness != pointee.initializedness) return false;
            found = true;
            break;
        };
        if (!found) return false;
    }
    for (left.tracker.roots.items, right.tracker.roots.items) |a, b|
        if (a.state != b.state or a.owned_resource != b.owned_resource or a.outcome_guard != b.outcome_guard) return false;
    for (left.storage_capabilities.items, right.storage_capabilities.items) |a, b|
        if (a != b) return false;
    for (left.lexical_storage_generations.items) |root|
        if (!containsRoot(right.lexical_storage_generations.items, root)) return false;
    for (left.places.items) |left_place| {
        const right_place = findPlaceConst(right, left_place.storage) orelse return false;
        if (left_place.initializedness != right_place.initializedness or !std.meta.eql(left_place.moved_at, right_place.moved_at) or !valueFactsEqual(left_place.value, right_place.value)) return false;
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
        for (right.storage_generations.items) |other| if (entry.storage.eql(other.storage) and entry.generation == other.generation and
            entry.needs_current_generation == other.needs_current_generation)
        {
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
        if (opaque_storage.outcome_guard != other.outcome_guard) return false;
        if (opaque_storage.hidden_dependencies.len != other.hidden_dependencies.len) return false;
        for (opaque_storage.hidden_dependencies) |dependency|
            if (!containsRoot(other.hidden_dependencies, dependency)) return false;
        if (opaque_storage.owner_roots.len != other.owner_roots.len) return false;
        for (opaque_storage.owner_roots) |root| if (!containsRoot(other.owner_roots, root)) return false;
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
    if (left.symbolic_pointees.len != right.symbolic_pointees.len) return false;
    for (left.symbolic_pointees) |identity|
        if (std.mem.indexOfScalar(graph_mod.GlobalBindingId, right.symbolic_pointees, identity) == null) return false;
    if (left.domains.len != right.domains.len) return false;
    for (left.domains, right.domains) |a, b| {
        if (a.domain_index != b.domain_index or a.storages.len != b.storages.len) return false;
        for (a.storages, b.storages) |x, y| if (!x.eql(y)) return false;
    }
    if (left.explicit_dependency != right.explicit_dependency or
        left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        left.known_choice_variant != right.known_choice_variant or
        !std.mem.eql(facts.StorageCapabilityId, left.storage_capabilities, right.storage_capabilities) or
        !std.mem.eql(graph_mod.GlobalFunctionId, left.virtual_methods, right.virtual_methods) or
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len or
        left.variants.len != right.variants.len or
        left.opaque_provenance.len != right.opaque_provenance.len or left.generation_outcomes.len != right.generation_outcomes.len) return false;
    if (left.choice_selectors.len != right.choice_selectors.len or left.choice_observations.len != right.choice_observations.len or left.guarded_values.len != right.guarded_values.len) return false;
    for (left.choice_selectors, right.choice_selectors) |a, b| if (!a.eql(b)) return false;
    for (left.choice_observations, right.choice_observations) |a, b| if (!a.eql(b)) return false;
    for (left.guarded_values, right.guarded_values) |a, b| if (!a.eql(b)) return false;
    for (left.generation_outcomes, right.generation_outcomes) |a, b| if (!a.eql(b)) return false;
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
    if (left == .moved or right == .moved) return .moved;
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

fn appendSafetyTypeName(buffer: *std.array_list.Managed(u8), graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) anyerror!void {
    switch (graph.semanticType(ty)) {
        .builtin => |builtin| try buffer.appendSlice(@tagName(builtin)),
        .declared => |decl| try buffer.appendSlice(graph.text(graph.declaration(decl).name)),
        .generic => |generic| try buffer.appendSlice(graph.text(graph.declaration(generic.base).name)),
        .pointer => |pointer| {
            try buffer.appendSlice(if (pointer.mutability == .read_write) "$&" else "&");
            try appendSafetyTypeName(buffer, graph, pointer.child);
        },
        .array => |array| {
            var length: [32]u8 = undefined;
            try buffer.append('[');
            try buffer.appendSlice(try std.fmt.bufPrint(&length, "{d}", .{array.length}));
            try buffer.append(']');
            try appendSafetyTypeName(buffer, graph, array.element);
        },
        .structural => try buffer.appendSlice("{...}"),
        .structural_choice, .inferred_choice => try buffer.appendSlice("choice"),
        .nullable => |child| {
            try buffer.append('?');
            try appendSafetyTypeName(buffer, graph, child);
        },
        else => try buffer.appendSlice("<type>"),
    }
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
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, undefined);
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

    const moved_out = try checker.applyOutcomeSummary(.{ .file_index = 0, .offset = 0 }, .{
        .outputs = &.{.{
            .opaque_storage_dependencies = &.{.{ .input_index = 0 }},
            .fresh_owned_roots = &.{91},
        }},
        .opaque_storage_empties = &.{.{ .input_index = 0 }},
    }, &.{}, &.{.{ .referenced_place = storage }}, &state);
    try std.testing.expect(valueDependsOnRoot(moved_out, external));
    try std.testing.expect(!valueDependsOnRoot(moved_out, backing));
    try std.testing.expect(!valueDependsOnRoot(moved_out, generation));
    try std.testing.expectEqual(@as(usize, 1), moved_out.owned_roots.len);

    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
    try std.testing.expect(state.tracker.isAlive(moved_out.owned_roots[0]));
}

test "opaque receiver effects select only their mapped storage domain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const first = facts.Place{ .root = @enumFromInt(0) };
    const second = facts.Place{ .root = @enumFromInt(1) };
    const first_dependency = try state.tracker.establish(.fresh);
    const second_dependency = try state.tracker.establish(.fresh);
    try checker.mergeOpaqueStorage(&state, first, &.{first_dependency});
    try checker.mergeOpaqueStorage(&state, second, &.{second_dependency});
    const receiver = facts.ValueFacts{ .domains = &.{
        .{ .domain_index = 0, .storages = &.{first} },
        .{ .domain_index = 1, .storages = &.{second} },
    } };
    const extracted = try checker.applyOutcomeSummary(.{ .file_index = 0, .offset = 0 }, .{
        .outputs = &.{.{ .opaque_storage_dependencies = &.{.{ .input_index = 0, .storage_domain = 1 }} }},
        .opaque_storage_empties = &.{.{ .input_index = 0, .storage_domain = 1 }},
    }, &.{}, &.{receiver}, &state);
    try std.testing.expect(valueDependsOnRoot(extracted, second_dependency));
    try std.testing.expect(!valueDependsOnRoot(extracted, first_dependency));
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{first_dependency}, state.opaque_storages.items[0].hidden_dependencies);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[1].hidden_dependencies.len);
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

test "opaque ownership cycle detection follows indirect edges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();

    const first = try state.tracker.establish(.fresh);
    const second = try state.tracker.establish(.fresh);
    const third = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(first)].owned_resource = true;
    state.tracker.roots.items[@intFromEnum(second)].owned_resource = true;
    state.tracker.roots.items[@intFromEnum(third)].owned_resource = true;

    const first_storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const second_storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(1)) };
    const third_storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(2)) };
    try checker.setPlace(&state, first_storage, .initialized, .{ .owned_roots = &.{first} });
    try checker.setPlace(&state, second_storage, .initialized, .{ .owned_roots = &.{second} });
    try checker.setPlace(&state, third_storage, .initialized, .{ .owned_roots = &.{third} });
    try checker.mergeOpaqueStorage(&state, first_storage, &.{second});
    try checker.mergeOpaqueStorage(&state, second_storage, &.{third});

    try std.testing.expect(try checker.opaqueWriteCreatesOwnershipCycle(
        &state,
        third_storage,
        .{ .dependencies = &.{.{ .root = first }}, .owned_roots = &.{first} },
    ));
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
    try left.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{left_dependency}, .owner_roots = &.{left_dependency} });
    try right.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{right_dependency}, .owner_roots = &.{right_dependency} });
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
    try std.testing.expect(containsRoot(joined.opaque_storages.items[0].owner_roots, left_dependency));
    try std.testing.expect(containsRoot(joined.opaque_storages.items[0].owner_roots, right_dependency));
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

test "conditional owner choices preserve explicit validity without admitting expired loans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var state = SafetyChecker.FunctionState.init(arena.allocator());
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = true;
    state.tracker.roots.items[@intFromEnum(root)].state = .conditional;
    const owner = facts.ValueFacts{ .owned_roots = &.{root}, .dependencies = &.{.{ .root = root }}, .explicit_dependency = true };
    const choice = facts.ValueFacts{ .variants = &.{.{ .index = 0, .value = &owner }} };
    try std.testing.expect(!valueHasDeadExplicitDependency(choice, &state));
    const loan = facts.ValueFacts{ .dependencies = owner.dependencies, .explicit_dependency = true };
    try std.testing.expect(valueHasDeadExplicitDependency(loan, &state));
    state.tracker.end(root);
    try std.testing.expect(valueHasDeadExplicitDependency(choice, &state));
    try std.testing.expect(!valueHasDeadExplicitDependencyForUse(loan, &state, true));
    state.tracker.roots.items[@intFromEnum(root)].owned_resource = false;
    try std.testing.expect(valueHasDeadExplicitDependencyForUse(loan, &state, true));
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
    try checker.recordOpaqueWrite(
        .{ .file_index = 0, .offset = 0 },
        &state,
        .{ .opaque_provenance = &.{.{ .storage = domain, .generation = root }} },
        .{ .dependencies = &.{.{ .root = root }} },
    );
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
    try checker.activate_conditional_resources(&state, payload);
    try std.testing.expect(state.tracker.isAlive(root));
    state.tracker.end(root);
    try checker.activate_conditional_resources(&state, payload);
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
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var checker = SafetyChecker.init(allocator, &diags, &graph);
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
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    try checker.recordFunctionCallAutoDeinit(initializes_call, .{ .input_post_states = &.{.{
        .target = .{ .input_index = 0 },
        .initializedness = .initialized,
        .requires_available_destination = true,
    }} }, &.{@as(graph_mod.GlobalValueFieldId, @enumFromInt(0))}, &.{}, &state);
    try checker.recordFunctionCallAutoDeinit(consumes_call, .{ .input_post_states = &.{.{
        .target = .{ .input_index = 0 },
        .initializedness = .deinitialized,
    }} }, &.{@as(graph_mod.GlobalValueFieldId, @enumFromInt(0))}, &.{}, &state);

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

test "choice outputs keep lazily materialized input storage alive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = facts.Place{ .root = @as(graph_mod.GlobalBindingId, @enumFromInt(0)) };
    const projections = [_]facts.Projection{.{ .field = 0 }};
    const payload = facts.ValueEffect{
        .input_places = &.{.{ .input_index = 0, .projections = &projections }},
        .fresh_owned_roots = &.{99},
    };
    const output = try checker.instantiateOutput(
        .{ .variants = &.{.{ .index = 0, .value = &payload }} },
        &.{.{ .referenced_place = storage }},
        &state,
    );
    try std.testing.expectEqual(@as(usize, 1), state.storage_generations.items.len);
    try std.testing.expect(state.tracker.isAlive(state.storage_generations.items[0].generation));
    const owned = output.variants[0].value.owned_roots[0];
    try std.testing.expectEqual(.conditional, state.tracker.roots.items[@intFromEnum(owned)].state);
}

test "allocation primitive agrees with instantiated symbolic transfer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var direct_state = SafetyChecker.FunctionState.init(allocator);
    defer direct_state.deinit();
    var summary_state = SafetyChecker.FunctionState.init(allocator);
    defer summary_state.deinit();
    const deallocator_root = try direct_state.tracker.establish(.fresh);
    const anchor_root = try direct_state.tracker.establish(.fresh);
    _ = try summary_state.tracker.establish(.fresh);
    _ = try summary_state.tracker.establish(.fresh);
    const arguments = [_]facts.ValueFacts{
        .{},                                                                                 .{},                                               .{},
        .{ .explicit_dependency = true, .dependencies = &.{.{ .root = deallocator_root }} }, .{ .dependencies = &.{.{ .root = anchor_root }} },
    };
    var engine = summary_engine.Engine.init(allocator);
    defer engine.deinit();
    var infer = summary_infer.Infer.init(allocator, &graph, &engine);
    defer infer.deinit();
    const effect = try infer.primitiveValueEffect(.establish_allocation, 1);
    const symbolic = try checker.instantiateOutput(effect, &arguments, &summary_state);
    const direct = try checker.evaluatePrimitive(@enumFromInt(0), .establish_allocation, &.{}, &arguments, &direct_state, .{ .file_index = 0, .offset = 0 });
    try std.testing.expect(valueFactsEqual(direct, symbolic));
    try std.testing.expectEqual(@as(usize, 1), direct.owned_roots.len);
    try std.testing.expect(valueDependsOnRoot(direct, deallocator_root));
    try std.testing.expect(valueDependsOnRoot(direct, anchor_root));
    const deallocator = try checker.projectValueFacts(direct, &.{.{ .field = 4 }});
    try std.testing.expect(valueDependsOnRoot(deallocator, deallocator_root));
}

test "new borrows after joined reinitialization do not revive old generations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var left = SafetyChecker.FunctionState.init(allocator);
    defer left.deinit();
    const storage = facts.Place{ .root = @enumFromInt(0) };
    try checker.setPlace(&left, storage, .initialized, .{});
    const historical = try checker.storageGeneration(&left, storage);
    var right = try left.clone(allocator, null);
    defer right.deinit();
    try checker.refreshStorageGeneration(&right, storage);
    var joined = SafetyChecker.FunctionState.init(allocator);
    defer joined.deinit();
    try checker.joinState(&joined, &left, &right);
    try std.testing.expect(!joined.tracker.isAlive(historical));
    const current = try checker.storageGeneration(&joined, storage);
    try std.testing.expect(current != historical);
    try std.testing.expect(joined.tracker.isAlive(current));
    try std.testing.expect(!joined.tracker.isAlive(historical));
    try std.testing.expectEqual(current, try checker.storageGeneration(&joined, storage));
    try checker.setPlace(&joined, storage, .deinitialized, .{});
    joined.tracker.end(current);
    try std.testing.expectEqual(current, try checker.storageGeneration(&joined, storage));
    try std.testing.expect(!joined.tracker.isAlive(current));
}

test "dependency primitives preserve the value referent and borrow only anchor validity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summary_engine.Engine.init(allocator);
    defer engine.deinit();
    var inference = summary_infer.Infer.init(allocator, undefined, &engine);
    defer inference.deinit();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const referent = facts.Place{ .root = @enumFromInt(0) };
    const anchor_place = facts.Place{ .root = @enumFromInt(1) };
    const value_root = try state.tracker.establish(.fresh);
    const anchor_root = try state.tracker.establish(.fresh);
    const arguments = [_]facts.ValueFacts{
        .{ .referenced_place = referent, .dependencies = &.{.{ .root = value_root }} },
        .{ .referenced_place = anchor_place, .dependencies = &.{.{ .root = anchor_root }}, .owned_roots = &.{anchor_root} },
    };
    inline for (.{ primitives.SafetyPrimitive.depend_on, primitives.SafetyPrimitive.restrict_reference }) |primitive| {
        const direct = try checker.dependencyPrimitive(&arguments, primitive_transfer.forPrimitive(primitive).value);
        const effect = try inference.primitiveValueEffect(primitive, 0);
        const symbolic = try checker.instantiateOutput(effect, &arguments, &state);
        try std.testing.expect(symbolic.referenced_place.?.eql(direct.referenced_place.?));
        try std.testing.expectEqual(direct.explicit_dependency, symbolic.explicit_dependency);
        try std.testing.expectEqual(direct.owned_roots.len, symbolic.owned_roots.len);
        try std.testing.expectEqual(direct.dependencies.len, symbolic.dependencies.len);
        try std.testing.expect(valueDependsOnRoot(symbolic, value_root));
        try std.testing.expect(valueDependsOnRoot(symbolic, anchor_root));
    }
}

test "storage capability consumption agrees between primitives and summaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, undefined);
    defer checker.deinit();
    inline for (.{ primitives.SafetyPrimitive.establish_inherited_storage, primitives.SafetyPrimitive.establish_allocation }) |primitive| {
        var direct = SafetyChecker.FunctionState.init(allocator);
        defer direct.deinit();
        try direct.storage_capabilities.append(.available);
        const root = try direct.tracker.establish(.fresh);
        var symbolic = try direct.clone(allocator, null);
        defer symbolic.deinit();
        const anchor = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
        const address = facts.ValueFacts{ .storage_capabilities = &.{@enumFromInt(0)} };
        const arguments: []const facts.ValueFacts = if (primitive == .establish_inherited_storage)
            &.{ address, anchor }
        else
            &.{ address, .{}, .{}, .{}, anchor };
        _ = try checker.evaluatePrimitive(@enumFromInt(0), primitive, &.{}, arguments, &direct, .{ .file_index = 0, .offset = 0 });
        const index = primitive_transfer.forPrimitive(primitive).consumes_storage_input.?;
        try checker.applySummaryEffects(.{ .file_index = 0, .offset = 0 }, .{
            .storage_capability_uses = &.{.{ .target = .{ .input_index = index } }},
        }, &.{}, arguments, &symbolic);
        try std.testing.expectEqualSlices(SafetyChecker.StorageCapabilityState, direct.storage_capabilities.items, symbolic.storage_capabilities.items);
        try std.testing.expectEqual(SafetyChecker.StorageCapabilityState.consumed, symbolic.storage_capabilities.items[0]);
        symbolic.storage_capabilities.items[0] = .available;
        try checker.applySummaryEffects(.{ .file_index = 0, .offset = 0 }, .{
            .storage_capability_uses = &.{.{ .target = .{ .input_index = index }, .minimum = 0 }},
        }, &.{}, arguments, &symbolic);
        try std.testing.expectEqual(SafetyChecker.StorageCapabilityState.maybe_consumed, symbolic.storage_capabilities.items[0]);
    }
    try std.testing.expectEqual(@as(usize, 0), diags.list.items.len);
}

test "native acquisition and page trimming agree with symbolic transfers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var engine = summary_engine.Engine.init(allocator);
    defer engine.deinit();
    var inference = summary_infer.Infer.init(allocator, undefined, &engine);
    defer inference.deinit();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var direct = SafetyChecker.FunctionState.init(allocator);
    defer direct.deinit();
    var symbolic = SafetyChecker.FunctionState.init(allocator);
    defer symbolic.deinit();
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const acquired = try checker.evaluatePrimitive(@enumFromInt(0), .native_allocated_storage, &.{}, &.{}, &direct, source);
    const acquired_effect = try inference.primitiveValueEffect(.native_allocated_storage, 1);
    const inferred = try checker.instantiateOutput(acquired_effect, &.{}, &symbolic);
    try std.testing.expectEqual(acquired.foreign_storage, inferred.foreign_storage);
    try std.testing.expectEqualSlices(facts.StorageCapabilityId, acquired.storage_capabilities, inferred.storage_capabilities);
    const trimmed_effect = try inference.primitiveValueEffect(.acquisition_subaddress, 2);
    inline for (.{ SafetyChecker.StorageCapabilityState.available, SafetyChecker.StorageCapabilityState.consumed }) |state| {
        direct.storage_capabilities.items[0] = state;
        symbolic.storage_capabilities.items[0] = state;
        const trimmed = try checker.evaluatePrimitive(@enumFromInt(0), .acquisition_subaddress, &.{}, &.{ acquired, .{} }, &direct, source);
        const inferred_trimmed = try checker.instantiateOutput(trimmed_effect, &.{ inferred, .{} }, &symbolic);
        try std.testing.expectEqualSlices(facts.StorageCapabilityId, acquired.storage_capabilities, trimmed.storage_capabilities);
        try std.testing.expectEqualSlices(facts.StorageCapabilityId, trimmed.storage_capabilities, inferred_trimmed.storage_capabilities);
        try std.testing.expectEqual(trimmed.foreign_storage, inferred_trimmed.foreign_storage);
        try std.testing.expectEqual(state, direct.storage_capabilities.items[0]);
        try std.testing.expectEqual(state, symbolic.storage_capabilities.items[0]);
    }
}

test "stored anchor lifetime agrees between dependency primitives and summaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    const holder = facts.Place{ .root = @enumFromInt(0) };
    const anchor = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    try checker.setPlace(&state, holder, .initialized, .{ .fields = &.{.{ .index = 0, .value = &anchor }} });
    const direct = try checker.dependencyPrimitive(&.{ .{}, anchor }, .depend_on);
    const symbolic = try checker.instantiateOutput(.{
        .explicit_dependency = true,
        .input_dependencies = &.{.{ .path = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} }, .validity_only = true }},
    }, &.{.{ .referenced_place = holder }}, &state);
    try std.testing.expectEqual(direct.explicit_dependency, symbolic.explicit_dependency);
    try std.testing.expectEqualSlices(facts.ValidityDependency, direct.dependencies, symbolic.dependencies);
    try std.testing.expectEqual(@as(?facts.Place, null), symbolic.referenced_place);
    state.tracker.end(root);
    try std.testing.expect(valueDependsOnDeadRoot(symbolic, &state));
}

test "activating choice payloads never revives consumed storage capabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    inline for (.{ false, true }) |consumed| {
        var state = SafetyChecker.FunctionState.init(allocator);
        defer state.deinit();
        const payload = facts.ValueEffect{
            .fresh_storage_capabilities = &.{15},
            .unavailable_fresh_storage = if (consumed) &.{.{ .source = 15 }} else &.{},
        };
        const choice = try checker.instantiateOutput(.{ .variants = &.{.{ .index = 0, .value = &payload }} }, &.{}, &state);
        try checker.activate_conditional_resources(&state, choice.variants[0].value.*);
        const expected: SafetyChecker.StorageCapabilityState = if (consumed) .consumed else .available;
        try std.testing.expectEqual(expected, state.storage_capabilities.items[0]);
    }
}

test "field materialization preserves intrinsic ownership moved from an input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    const address = facts.ValueFacts{ .dependencies = &.{.{ .root = root }} };
    const allocation = facts.ValueFacts{
        .owned_roots = &.{root},
        .fields = &.{.{ .index = 0, .value = &address }},
    };
    const address_effect = facts.ValueEffect{
        .input_dependencies = &.{.{ .path = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} } }},
    };
    const transferred = try checker.instantiateOutput(.{
        .input_dependencies = &.{.{ .path = .{ .input_index = 0 }, .transfers_ownership = true }},
        .fields = &.{.{ .index = 0, .value = &address_effect }},
    }, &.{allocation}, &state);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{root}, transferred.owned_roots);
    try std.testing.expectEqual(root, transferred.fields[0].value.dependencies[0].root);
}

test "field materialization removes ownership derived from replaced fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const old_root = try state.tracker.establish(.fresh);
    const old_child = facts.ValueFacts{ .owned_roots = &.{old_root} };
    const parent = facts.ValueFacts{
        .owned_roots = &.{old_root},
        .fields = &.{.{ .index = 0, .value = &old_child }},
    };
    const replacement = facts.ValueEffect{ .fresh_owned_roots = &.{91} };
    const transferred = try checker.instantiateOutput(.{
        .input_dependencies = &.{.{ .path = .{ .input_index = 0 }, .transfers_ownership = true }},
        .fields = &.{.{ .index = 0, .value = &replacement }},
    }, &.{parent}, &state);
    try std.testing.expectEqual(@as(usize, 1), transferred.owned_roots.len);
    try std.testing.expect(transferred.owned_roots[0] != old_root);
    try std.testing.expectEqual(transferred.owned_roots[0], transferred.fields[0].value.owned_roots[0]);
}

test "projected writes refresh aggregate roots and preserve explicit dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const old_root = try state.tracker.establish(.fresh);
    const new_root = try state.tracker.establish(.fresh);
    const intrinsic_root = try state.tracker.establish(.fresh);
    const old_leaf = facts.ValueFacts{
        .dependencies = &.{.{ .root = old_root }},
        .owned_roots = &.{old_root},
    };
    const old_child = facts.ValueFacts{
        .dependencies = &.{.{ .root = old_root }},
        .owned_roots = &.{old_root},
        .fields = &.{.{ .index = 0, .value = &old_leaf }},
    };
    const parent = facts.ValueFacts{
        .dependencies = &.{ .{ .root = old_root }, .{ .root = intrinsic_root } },
        .owned_roots = &.{ old_root, intrinsic_root },
        .fields = &.{.{ .index = 0, .value = &old_child }},
    };
    const storage = facts.Place{ .root = @enumFromInt(0) };
    const nested = try checker.project(try checker.project(storage, .{ .field = 0 }), .{ .field = 0 });
    try checker.setPlace(&state, nested, .initialized, .{
        .dependencies = &.{.{ .root = new_root }},
        .owned_roots = &.{new_root},
    });
    state.tracker.end(old_root);
    const refreshed = try checker.reconstructPlaceValue(&state, storage, parent);
    try std.testing.expect(!valueDependsOnRoot(refreshed, old_root));
    try std.testing.expect(!valueContainsOwnedRoot(refreshed, old_root));
    try std.testing.expect(valueDependsOnRoot(refreshed, new_root));
    try std.testing.expect(valueContainsOwnedRoot(refreshed, new_root));
    try std.testing.expect(valueContainsOwnedRoot(refreshed, intrinsic_root));
    try std.testing.expect(!valueDependsOnDeadRoot(refreshed, &state));
    var explicit = parent;
    explicit.explicit_dependency = true;
    const preserved = try checker.reconstructPlaceValue(&state, storage, explicit);
    try std.testing.expect(valueDependsOnDeadRoot(preserved, &state));
}

test "dynamic projected writes retain newly merged roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    const storage = facts.Place{ .root = @enumFromInt(0) };
    try checker.setPlace(&state, try checker.project(storage, .dynamic_index), .initialized, .{
        .dependencies = &.{.{ .root = root }},
        .owned_roots = &.{root},
    });
    const refreshed = try checker.reconstructPlaceValue(&state, storage, .{});
    try std.testing.expect(valueDependsOnRoot(refreshed, root));
    try std.testing.expect(valueContainsOwnedRoot(refreshed, root));
}

test "array concrete projections select and merge element facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    const foreign = facts.ValueFacts{ .foreign_storage = true };
    const local = facts.ValueFacts{};
    const array = facts.ValueFacts{ .fields = &.{
        .{ .index = 0, .value = &foreign },
        .{ .index = 1, .value = &local },
    } };
    try std.testing.expect((try checker.projectValueFacts(array, &.{.{ .static_index = 0 }})).foreign_storage);
    try std.testing.expect(!(try checker.projectValueFacts(array, &.{.{ .static_index = 1 }})).foreign_storage);
    const dynamic = try checker.projectValueFacts(array, &.{.dynamic_index});
    try std.testing.expect(dynamic.foreign_storage);
    try std.testing.expectEqual(@as(usize, 0), dynamic.storage_capabilities.len);
    const uniform = facts.ValueFacts{ .foreign_storage = true, .fields = &.{.{ .index = 1, .value = &local }} };
    try std.testing.expect((try checker.projectValueFacts(uniform, &.{.dynamic_index})).foreign_storage);
}

test "large numeric literals keep no per-element safety records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .int_literal = 0 } });
    try graph.node_refs.resize(allocator, 65536);
    @memset(graph.node_refs.items, @enumFromInt(0));
    var checker = SafetyChecker.init(allocator, undefined, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const value = try checker.evaluateArray(@enumFromInt(0), .{ .elements = graph_mod.NodeRange{ .start = 0, .len = 65536 } }, &state);
    try std.testing.expect(facts.isEmptyValue(value));
    try std.testing.expect(facts.isEmptyValue(try checker.mergeValueFacts(value, value)));
}

fn mergeDomainFacts(allocator: std.mem.Allocator, left: []const facts.DomainFacts, right: []const facts.DomainFacts) ![]const facts.DomainFacts {
    var result: std.ArrayList(facts.DomainFacts) = .empty;
    for (left) |domain| try result.append(allocator, domain);
    for (right) |domain| {
        var found = false;
        for (result.items) |*existing| {
            if (existing.domain_index != domain.domain_index) continue;
            var storages = std.array_list.Managed(facts.Place).init(allocator);
            try storages.appendSlice(existing.storages);
            for (domain.storages) |storage| try appendPlaceFact(&storages, storage);
            existing.storages = try storages.toOwnedSlice();
            found = true;
            break;
        }
        if (!found) try result.append(allocator, domain);
    }
    return result.toOwnedSlice(allocator);
}

fn sameInputPath(left: facts.InputPath, right: facts.InputPath) bool {
    if (left.input_index != right.input_index or left.storage_domain != right.storage_domain or left.projections.len != right.projections.len) return false;
    for (left.projections, right.projections) |a, b| if (!a.eql(b)) return false;
    return true;
}

test "generation outcome proofs cannot be replayed after another call or invalidation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = facts.Place{ .root = @enumFromInt(0) };
    const generation = try checker.storageGeneration(&state, storage);
    const preserved = facts.ValueFacts{ .generation_outcomes = &.{.{ .storage = storage, .generation = generation, .guard = 1, .invalidates = false }} };
    state.tracker.roots.items[@intFromEnum(generation)].state = .maybe_alive;
    state.tracker.roots.items[@intFromEnum(generation)].outcome_guard = 1;
    try checker.activate_conditional_resources(&state, preserved);
    try std.testing.expect(state.tracker.isAlive(generation));
    state.tracker.roots.items[@intFromEnum(generation)].state = .maybe_alive;
    state.tracker.roots.items[@intFromEnum(generation)].outcome_guard = 2;
    try checker.activate_conditional_resources(&state, preserved);
    try std.testing.expect(!state.tracker.isAlive(generation));
    state.tracker.end(generation);
    state.tracker.roots.items[@intFromEnum(generation)].outcome_guard = 1;
    try checker.activate_conditional_resources(&state, preserved);
    try std.testing.expect(!state.tracker.isAlive(generation));
}

test "relocation refinement validates both generations and preserves the transferred owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    for (0..4) |scenario| {
        var state = SafetyChecker.FunctionState.init(allocator);
        defer state.deinit();
        const from = facts.Place{ .root = @enumFromInt(0) };
        const to = facts.Place{ .root = @enumFromInt(1) };
        const generation = try checker.storageGeneration(&state, from);
        const destination_generation = try checker.storageGeneration(&state, to);
        const owner = try state.tracker.establish(.fresh);
        const value = facts.ValueFacts{ .owned_roots = &.{owner} };
        try checker.setPlace(&state, from, .maybe_initialized, value);
        try checker.setPlace(&state, to, .maybe_initialized, value);
        for (&[_]facts.ValidityRootId{ generation, destination_generation }) |root| {
            state.tracker.roots.items[@intFromEnum(root)].state = .maybe_alive;
            state.tracker.roots.items[@intFromEnum(root)].outcome_guard = 7;
        }
        const proof = facts.ValueFacts{ .generation_outcomes = &.{.{
            .storage = from,
            .generation = generation,
            .guard = 7,
            .invalidates = scenario == 0,
            .relocation = .{ .destination = to, .generation = destination_generation, .available_state = .deinitialized, .moved = scenario == 0 },
        }} };
        if (scenario == 2) state.tracker.roots.items[@intFromEnum(destination_generation)].outcome_guard = 8;
        if (scenario == 3) try checker.refreshStorageGeneration(&state, to);
        try checker.activate_conditional_resources(&state, proof);
        try std.testing.expect(state.tracker.isAlive(owner));
        if (scenario == 0) {
            try std.testing.expectEqual(value_state.Initializedness.moved, checker.initializednessAtPlace(&state, from));
            try std.testing.expectEqual(value_state.Initializedness.initialized, checker.initializednessAtPlace(&state, to));
            try std.testing.expect(!state.tracker.isAlive(generation));
            try std.testing.expect(state.tracker.isAlive(destination_generation));
            try std.testing.expectEqual(owner, checker.valueAtPlace(&state, to).?.owned_roots[0]);
        } else if (scenario == 1) {
            try std.testing.expectEqual(value_state.Initializedness.initialized, checker.initializednessAtPlace(&state, from));
            try std.testing.expectEqual(value_state.Initializedness.deinitialized, checker.initializednessAtPlace(&state, to));
            try std.testing.expect(state.tracker.isAlive(generation));
            try std.testing.expect(!state.tracker.isAlive(destination_generation));
            try std.testing.expectEqual(owner, checker.valueAtPlace(&state, from).?.owned_roots[0]);
        } else {
            try std.testing.expectEqual(value_state.Initializedness.maybe_initialized, checker.initializednessAtPlace(&state, from));
            try std.testing.expectEqual(value_state.Initializedness.maybe_initialized, checker.initializednessAtPlace(&state, to));
            try std.testing.expect(!state.tracker.isAlive(generation));
        }
    }
}

test "outer payload selection does not activate owners in an unresolved inner choice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const root = try state.tracker.establish(.fresh);
    state.tracker.roots.items[@intFromEnum(root)].state = .conditional;
    const owned = facts.ValueFacts{ .owned_roots = &.{root} };
    const inner = facts.ValueFacts{ .variants = &.{.{ .index = 0, .value = &owned }} };
    try checker.activate_conditional_resources(&state, inner);
    try std.testing.expectEqual(.conditional, state.tracker.roots.items[@intFromEnum(root)].state);
    try checker.activate_conditional_resources(&state, owned);
    try std.testing.expect(state.tracker.isAlive(root));
}

test "consuming a value ends nested owned roots while preserving borrowed dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.fields.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    try graph.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(1),
        .mutability = .variable,
    });
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, &graph);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const owned = try state.tracker.establish(.fresh);
    const borrowed = try state.tracker.establish(.fresh);
    const child = facts.ValueFacts{ .owned_roots = &.{owned}, .dependencies = &.{.{ .root = borrowed }} };
    const storage = facts.Place{ .root = @enumFromInt(0) };
    try checker.setPlace(&state, storage, .initialized, .{ .fields = &.{.{ .index = 0, .value = &child }} });
    try checker.applySummaryEffects(.{ .file_index = 0, .offset = 0 }, .{
        .input_post_states = &.{.{ .target = .{ .input_index = 0 }, .initializedness = .deinitialized, .ends_previous_roots = true }},
    }, &.{}, &.{.{ .referenced_place = storage }}, &state);
    try std.testing.expect(!state.tracker.isAlive(owned));
    try std.testing.expect(state.tracker.isAlive(borrowed));
    try std.testing.expectEqual(value_state.Initializedness.deinitialized, checker.initializednessAtPlace(&state, storage));
}

test "conditional opaque empty proofs retain current call and storage identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diags = diagnostics.Diagnostics.init(&allocator, &.{});
    defer diags.deinit();
    var checker = SafetyChecker.init(allocator, &diags, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const storage = facts.Place{ .root = @enumFromInt(0) };
    const other = facts.Place{ .root = @enumFromInt(1) };
    const dependency = try state.tracker.establish(.fresh);
    const later_dependency = try state.tracker.establish(.fresh);
    const generation = try checker.storageGeneration(&state, storage);
    try checker.mergeOpaqueStorage(&state, storage, &.{dependency});
    try checker.mergeOpaqueStorage(&state, other, &.{later_dependency});
    const summary = facts.SafetySummary{
        .outputs = &.{.{ .variants = &.{ .{ .index = 0, .value = &.{} }, .{ .index = 1, .value = &.{} } } }},
        .outcome_post_states = &.{
            .{ .variant_index = 0, .input_post_states = &.{} },
            .{ .variant_index = 1, .input_post_states = &.{}, .opaque_storage_empties = &.{.{ .input_index = 0 }} },
        },
    };
    const arguments = [_]facts.ValueFacts{.{ .referenced_place = storage }};
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const result = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items[0].hidden_dependencies.len);
    try checker.activate_conditional_resources(&state, result.variants[0].value.*);
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items[0].hidden_dependencies.len);
    try checker.activate_conditional_resources(&state, result.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items[1].hidden_dependencies.len);
    try std.testing.expect(state.tracker.isAlive(dependency));
    try std.testing.expect(state.tracker.isAlive(generation));

    try checker.mergeOpaqueStorage(&state, storage, &.{dependency});
    const before_write = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    try checker.mergeOpaqueStorage(&state, storage, &.{later_dependency});
    try checker.activate_conditional_resources(&state, before_write.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 2), state.opaque_storages.items[0].hidden_dependencies.len);

    const first = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    const second = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    try checker.activate_conditional_resources(&state, first.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 2), state.opaque_storages.items[0].hidden_dependencies.len);
    try checker.activate_conditional_resources(&state, second.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);

    try checker.mergeOpaqueStorage(&state, storage, &.{dependency});
    const independent_first = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    const independent_other = try checker.applyOutcomeSummary(source, summary, &.{}, &.{.{ .referenced_place = other }}, &state);
    try checker.activate_conditional_resources(&state, independent_first.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items[1].hidden_dependencies.len);
    try checker.activate_conditional_resources(&state, independent_other.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[1].hidden_dependencies.len);

    try checker.mergeOpaqueStorage(&state, storage, &.{dependency});
    const before_generation = try checker.applyOutcomeSummary(source, summary, &.{}, &arguments, &state);
    try checker.refreshStorageGeneration(&state, storage);
    try checker.activate_conditional_resources(&state, before_generation.variants[1].value.*);
    try std.testing.expectEqual(@as(usize, 1), state.opaque_storages.items[0].hidden_dependencies.len);
}

test "input guarded summaries select entry tags without predicting output choices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const conditions = @import("choice_conditions.zig");
    const fallback: facts.SafetySummary = .{ .opaque_storage_empties = &.{.{ .input_index = 9 }} };
    const selected: facts.SafetySummary = .{ .opaque_storage_empties = &.{.{ .input_index = 0 }} };
    const guard = try conditions.normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .entry_input, .index = 1, .variant_index = 2 },
    });
    var summary = fallback;
    summary.guarded_effects = &.{.{ .conditions = guard, .effects = &selected }};
    const known = [_]facts.ValueFacts{ .{ .known_choice_variant = 1 }, .{ .known_choice_variant = 2 } };
    const refined = try checker.selectEntryGuardedSummary(summary, &known, &state);
    try std.testing.expectEqual(@as(u32, 0), refined.opaque_storage_empties[0].input_index);
    const unknown = [_]facts.ValueFacts{ .{ .known_choice_variant = 1 }, .{} };
    try std.testing.expectEqual(@as(u32, 9), (try checker.selectEntryGuardedSummary(summary, &unknown, &state)).opaque_storage_empties[0].input_index);
    const mixed = try conditions.conjoin(allocator, guard, try conditions.normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 1 }}));
    summary.guarded_effects = &.{.{ .conditions = mixed, .effects = &selected }};
    try std.testing.expectEqual(@as(u32, 9), (try checker.selectEntryGuardedSummary(summary, &known, &state)).opaque_storage_empties[0].input_index);
}

test "mutable entry choice observations do not follow post call mutations or missing projections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const place = facts.Place{ .root = @enumFromInt(0) };
    try checker.setPlace(&state, place, .initialized, .{ .known_choice_variant = 1 });
    const pointer: facts.ValueFacts = .{ .referenced_place = place };
    const before = (try checker.entryConditionValue(pointer, &.{.dereference}, &state)).?;
    try checker.setPlace(&state, place, .initialized, .{ .known_choice_variant = 2 });
    const after = (try checker.entryConditionValue(pointer, &.{.dereference}, &state)).?;
    try std.testing.expectEqual(@as(?u32, 1), before.known_choice_variant);
    try std.testing.expectEqual(@as(?u32, 2), after.known_choice_variant);
    try std.testing.expect((try checker.entryConditionValue(before, &.{.{ .field = 42 }}, &state)) == null);
}

test "mixed dependency guards capture mutable entry facts before replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var checker = SafetyChecker.init(allocator, undefined, undefined);
    defer checker.deinit();
    var state = SafetyChecker.FunctionState.init(allocator);
    defer state.deinit();
    const place = facts.Place{ .root = @enumFromInt(0) };
    try checker.setPlace(&state, place, .initialized, .{ .known_choice_variant = 1 });
    const arguments = [_]facts.ValueFacts{.{ .referenced_place = place }};
    const conditions = try @import("choice_conditions.zig").normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .projections = &.{.dereference}, .variant_index = 1 },
        .{ .subject = .output, .index = 0, .variant_index = 0 },
    });
    const precise: facts.SafetySummary = .{ .outputs = &.{.{}} };
    const summary: facts.SafetySummary = .{ .outputs = &.{.{}}, .guarded_effects = &.{.{ .conditions = conditions, .effects = &precise }} };
    const prepared = try checker.prepareGeneralValueGuards(summary, &arguments, &state);
    try checker.setPlace(&state, place, .initialized, .{ .known_choice_variant = 2 });
    try std.testing.expectEqual(@as(usize, 1), prepared.len);
    try std.testing.expectEqual(@as(u32, 1), prepared[0].proof.entry_facts.terms[0].variant_index);
    try std.testing.expectEqual(@as(?u32, 2), (try checker.entryConditionValue(arguments[0], &.{.dereference}, &state)).?.known_choice_variant);
}
