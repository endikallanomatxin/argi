const std = @import("std");
const graph = @import("../global/graph.zig");
const facts = @import("facts.zig");

/// Dependency-driven fixed-point storage for indexed safety summaries.
///
/// The old checker keyed this machinery by SemanticGraph object pointers.  The
/// compact graph keeps the same algorithmic property, but program identity is
/// exclusively GlobalFunctionId.  Reading a summary while inferring another
/// function records the reverse edge; changing the callee later dirties only
/// the callers that observed it.
pub const Engine = struct {
    const FunctionList = std.array_list.Managed(graph.GlobalFunctionId);
    const DependentMap = std.AutoHashMap(graph.GlobalFunctionId, FunctionList);

    allocator: std.mem.Allocator,
    summaries: std.AutoHashMap(graph.GlobalFunctionId, facts.SafetySummary),
    dependents: DependentMap,
    dependencies: DependentMap,
    virtual_dependencies: std.AutoHashMap(graph.GlobalFunctionId, std.array_list.Managed(graph.GlobalVirtualRegistryId)),
    worklist: std.array_list.Managed(graph.GlobalFunctionId),
    dirty: std.AutoHashMap(graph.GlobalFunctionId, void),
    next_work: usize = 0,
    current: ?graph.GlobalFunctionId = null,
    dependency_error: ?anyerror = null,
    retain_dependencies: bool = false,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .summaries = std.AutoHashMap(graph.GlobalFunctionId, facts.SafetySummary).init(allocator),
            .dependents = DependentMap.init(allocator),
            .dependencies = DependentMap.init(allocator),
            .virtual_dependencies = .init(allocator),
            .worklist = FunctionList.init(allocator),
            .dirty = std.AutoHashMap(graph.GlobalFunctionId, void).init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        var values = self.dependents.valueIterator();
        while (values.next()) |list| list.deinit();
        self.dependents.deinit();
        var dependencies = self.dependencies.valueIterator();
        while (dependencies.next()) |list| list.deinit();
        self.dependencies.deinit();
        var virtuals = self.virtual_dependencies.valueIterator();
        while (virtuals.next()) |list| list.deinit();
        self.virtual_dependencies.deinit();
        self.summaries.deinit();
        self.worklist.deinit();
        self.dirty.deinit();
    }

    pub fn ensureEmpty(self: *Engine, function: graph.GlobalFunctionId) !void {
        if (!self.summaries.contains(function)) try self.summaries.put(function, .{});
    }

    pub fn seed(self: *Engine, functions: []const graph.GlobalFunctionId) !void {
        for (functions) |function| try self.markDirty(function);
    }

    pub fn beginInference(self: *Engine, function: graph.GlobalFunctionId) void {
        self.current = function;
        self.dependency_error = null;
    }

    pub fn endInference(self: *Engine) !void {
        self.current = null;
        if (self.dependency_error) |err| return err;
    }

    pub fn summaryFor(self: *Engine, dependency: graph.GlobalFunctionId) ?facts.SafetySummary {
        self.recordDependency(dependency);
        return self.summaries.get(dependency);
    }

    /// Replace one approximation. A real change requeues exactly the callers
    /// that read this summary during inference. Recursive functions naturally
    /// register themselves as dependents and therefore iterate to a fixed point.
    pub fn updateSummary(self: *Engine, function: graph.GlobalFunctionId, summary: facts.SafetySummary) !bool {
        if (self.summaries.get(function)) |previous| {
            if (summaryEql(previous, summary)) return false;
        }
        // A published approximation must never lose its observer notifications.
        // Reserve both queue tables before changing the summary itself.
        const callers = self.dependents.get(function);
        if (callers) |list| {
            var pending: usize = 0;
            for (list.items) |caller| if (!self.dirty.contains(caller)) {
                pending += 1;
            };
            try self.worklist.ensureUnusedCapacity(pending);
            try self.dirty.ensureUnusedCapacity(@intCast(pending));
        }
        try self.summaries.put(function, summary);
        if (callers) |list| {
            for (list.items) |caller| try self.markDirty(caller);
        }
        return true;
    }

    pub fn nextDirty(self: *Engine) ?graph.GlobalFunctionId {
        while (self.next_work < self.worklist.items.len) {
            const function = self.worklist.items[self.next_work];
            self.next_work += 1;
            if (self.dirty.remove(function)) return function;
        }
        return null;
    }

    fn markDirty(self: *Engine, function: graph.GlobalFunctionId) !void {
        if (self.dirty.contains(function)) return;
        try self.worklist.ensureUnusedCapacity(1);
        try self.dirty.put(function, {});
        self.worklist.appendAssumeCapacity(function);
    }

    pub fn addDependency(self: *Engine, dependent: graph.GlobalFunctionId, dependency: graph.GlobalFunctionId) !void {
        const callers = try self.dependents.getOrPut(dependency);
        if (!callers.found_existing) callers.value_ptr.* = FunctionList.init(self.allocator);
        if (std.mem.indexOfScalar(graph.GlobalFunctionId, callers.value_ptr.items, dependent) == null) try callers.value_ptr.append(dependent);
        if (!self.retain_dependencies) return;
        const required = try self.dependencies.getOrPut(dependent);
        if (!required.found_existing) required.value_ptr.* = FunctionList.init(self.allocator);
        if (std.mem.indexOfScalar(graph.GlobalFunctionId, required.value_ptr.items, dependency) == null) try required.value_ptr.append(dependency);
    }

    pub fn addVirtualDependency(self: *Engine, dependent: graph.GlobalFunctionId, registry: graph.GlobalVirtualRegistryId) !void {
        const required = try self.virtual_dependencies.getOrPut(dependent);
        if (!required.found_existing) required.value_ptr.* = .init(self.allocator);
        if (std.mem.indexOfScalar(graph.GlobalVirtualRegistryId, required.value_ptr.items, registry) == null) try required.value_ptr.append(registry);
    }

    pub fn observeVirtual(self: *Engine, registry: graph.GlobalVirtualRegistryId) !void {
        if (!self.retain_dependencies) return;
        if (self.current) |dependent| try self.addVirtualDependency(dependent, registry);
    }

    fn recordDependency(self: *Engine, dependency: graph.GlobalFunctionId) void {
        const dependent = self.current orelse return;
        self.addDependency(dependent, dependency) catch |err| {
            self.dependency_error = err;
        };
    }
};

pub fn summaryEql(a: facts.SafetySummary, b: facts.SafetySummary) bool {
    if (a.guarded_returns_complete != b.guarded_returns_complete or a.guarded_effects.len != b.guarded_effects.len) return false;
    for (a.guarded_effects, b.guarded_effects) |left, right| {
        if (!left.conditions.eql(right.conditions) or !summaryEql(left.effects.*, right.effects.*)) return false;
    }
    if (!domainsEql(a.invalidated_domains, b.invalidated_domains)) return false;
    if (a.storage_observations.len != b.storage_observations.len or a.storage_observation_conflicts.len != b.storage_observation_conflicts.len) return false;
    for (a.storage_observations, b.storage_observations) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.storage_observation_conflicts, b.storage_observation_conflicts) |left, right|
        if (!inputPathEql(left.consumed, right.consumed) or !inputPathEql(left.observed, right.observed)) return false;
    if (a.storage_capability_conflicts.len != b.storage_capability_conflicts.len) return false;
    for (a.storage_capability_conflicts, b.storage_capability_conflicts) |left, right|
        if (!inputPathEql(left.first, right.first) or !inputPathEql(left.second, right.second)) return false;
    if (a.storage_capability_uses.len != b.storage_capability_uses.len) return false;
    for (a.storage_capability_uses, b.storage_capability_uses) |left, right|
        if (!inputPathEql(left.target, right.target) or left.minimum != right.minimum or left.maximum != right.maximum) return false;
    if (a.outputs.len != b.outputs.len or
        a.required_live_inputs.len != b.required_live_inputs.len or
        a.required_opaque_inputs.len != b.required_opaque_inputs.len or
        a.input_post_states.len != b.input_post_states.len or
        a.outcome_post_states.len != b.outcome_post_states.len or
        a.opaque_storage_effects.len != b.opaque_storage_effects.len or
        a.opaque_storage_empties.len != b.opaque_storage_empties.len) return false;

    for (a.outputs, b.outputs) |left, right| if (!valueEffectEql(left, right)) return false;
    for (a.required_live_inputs, b.required_live_inputs) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.required_opaque_inputs, b.required_opaque_inputs) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_post_states, b.input_post_states) |left, right| if (!postStateEql(left, right)) return false;
    for (a.outcome_post_states, b.outcome_post_states) |left, right| {
        if (left.reachable != right.reachable or !std.mem.eql(u32, left.parent_variants, right.parent_variants) or left.output_index != right.output_index or left.variant_index != right.variant_index or left.input_post_states.len != right.input_post_states.len or left.invalidated_domains.len != right.invalidated_domains.len or left.opaque_storage_empties.len != right.opaque_storage_empties.len) return false;
        for (left.opaque_storage_empties, right.opaque_storage_empties) |a_path, b_path| if (!inputPathEql(a_path, b_path)) return false;
        for (left.invalidated_domains, right.invalidated_domains) |a_domain, b_domain| if (a_domain.domain_index != b_domain.domain_index or !inputPathEql(a_domain.path, b_domain.path)) return false;
        for (left.input_post_states, right.input_post_states) |left_state, right_state|
            if (!postStateEql(left_state, right_state)) return false;
    }
    for (a.opaque_storage_effects, b.opaque_storage_effects) |left, right| {
        if (!inputPathEql(left.storage, right.storage) or !valueEffectEql(left.hidden_dependencies, right.hidden_dependencies)) return false;
    }
    for (a.opaque_storage_empties, b.opaque_storage_empties) |left, right| if (!inputPathEql(left, right)) return false;
    return true;
}

pub fn valueEffectEql(a: facts.ValueEffect, b: facts.ValueEffect) bool {
    if (!domainsEql(a.input_domains, b.input_domains)) return false;
    if (a.domain_values.len != b.domain_values.len) return false;
    for (a.domain_values, b.domain_values) |x, y| if (x.domain_index != y.domain_index or !valueEffectEql(x.value.*, y.value.*)) return false;
    if (a.fresh_cleanup_obligation != b.fresh_cleanup_obligation or
        a.explicit_dependency != b.explicit_dependency or
        a.input_dependencies.len != b.input_dependencies.len or
        a.input_places.len != b.input_places.len or
        a.input_generation_dependencies.len != b.input_generation_dependencies.len or
        a.input_captured_storages.len != b.input_captured_storages.len or
        a.input_receiver_values.len != b.input_receiver_values.len or
        a.input_place_values.len != b.input_place_values.len or
        a.input_owned_roots.len != b.input_owned_roots.len or
        a.opaque_generation_dependencies.len != b.opaque_generation_dependencies.len or
        a.opaque_storage_dependencies.len != b.opaque_storage_dependencies.len or
        a.fields.len != b.fields.len or
        a.variants.len != b.variants.len or
        a.fresh_dependencies.len != b.fresh_dependencies.len or
        a.fresh_owned_roots.len != b.fresh_owned_roots.len or
        a.fresh_storage_capabilities.len != b.fresh_storage_capabilities.len or
        a.known_choice_variant != b.known_choice_variant or
        a.integer_address != b.integer_address or
        a.foreign_storage != b.foreign_storage) return false;

    for (a.input_dependencies, b.input_dependencies) |left, right| {
        if (left.transfers_ownership != right.transfers_ownership or
            left.validity_only != right.validity_only or
            !inputPathEql(left.path, right.path)) return false;
    }
    for (a.input_places, b.input_places) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_receiver_values, b.input_receiver_values) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_captured_storages, b.input_captured_storages) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_generation_dependencies, b.input_generation_dependencies) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_place_values, b.input_place_values) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_owned_roots, b.input_owned_roots) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.opaque_generation_dependencies, b.opaque_generation_dependencies) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.opaque_storage_dependencies, b.opaque_storage_dependencies) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.fields, b.fields) |left, right| {
        if (left.index != right.index or !valueEffectEql(left.value.*, right.value.*)) return false;
    }
    for (a.variants, b.variants) |left, right| {
        if (left.index != right.index or !valueEffectEql(left.value.*, right.value.*)) return false;
    }
    if (!std.mem.eql(facts.FreshEffectSource, a.fresh_dependencies, b.fresh_dependencies)) return false;
    if (!std.mem.eql(facts.FreshEffectSource, a.fresh_owned_roots, b.fresh_owned_roots)) return false;
    if (a.input_storage_capabilities.len != b.input_storage_capabilities.len) return false;
    for (a.input_storage_capabilities, b.input_storage_capabilities) |left, right| if (!inputPathEql(left, right)) return false;
    if (!std.mem.eql(facts.FreshEffectSource, a.fresh_storage_capabilities, b.fresh_storage_capabilities)) return false;
    if (a.unavailable_fresh_storage.len != b.unavailable_fresh_storage.len) return false;
    for (a.unavailable_fresh_storage, b.unavailable_fresh_storage) |left, right|
        if (left.source != right.source or left.maybe_consumed != right.maybe_consumed) return false;
    return true;
}

fn domainsEql(a: []const facts.InputDomain, b: []const facts.InputDomain) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x.domain_index != y.domain_index or !inputPathEql(x.path, y.path)) return false;
    return true;
}

fn postStateEql(a: facts.PlacePostState, b: facts.PlacePostState) bool {
    if (!inputPathEql(a.target, b.target) or
        a.initialization != b.initialization or
        a.reference_refresh != b.reference_refresh or
        a.initializedness != b.initializedness or
        a.ends_previous_roots != b.ends_previous_roots or
        a.refreshes_storage_generation != b.refreshes_storage_generation or
        a.requires_available_destination != b.requires_available_destination or
        a.opaque_ownership != b.opaque_ownership or
        a.may_repopulate_opaque_storage != b.may_repopulate_opaque_storage or
        !valueEffectEql(a.value, b.value)) return false;
    if ((a.reference_targets == null) != (b.reference_targets == null)) return false;
    if (a.reference_targets) |paths| {
        if (paths.len != b.reference_targets.?.len) return false;
        for (paths, b.reference_targets.?) |left, right| if (!inputPathEql(left, right)) return false;
    }
    if ((a.opaque_storage == null) != (b.opaque_storage == null)) return false;
    if (a.opaque_storage) |left| if (!inputPathEql(left, b.opaque_storage.?)) return false;
    return true;
}

fn inputPathEql(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.storage_domain != b.storage_domain or a.projections.len != b.projections.len) return false;
    for (a.projections, b.projections) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}

test "summary equality retains ordered storage observations and caller alias obligations" {
    const first = facts.InputPath{ .input_index = 0 };
    const second = facts.InputPath{ .input_index = 1, .projections = &.{.{ .field = 0 }} };
    const observed = facts.SafetySummary{ .storage_observations = &.{second} };
    try std.testing.expect(!summaryEql(.{}, observed));
    var constrained = observed;
    constrained.storage_observation_conflicts = &.{.{ .consumed = first, .observed = second }};
    try std.testing.expect(!summaryEql(observed, constrained));
    var reversed = constrained;
    reversed.storage_observation_conflicts = &.{.{ .consumed = second, .observed = first }};
    try std.testing.expect(!summaryEql(constrained, reversed));
    try std.testing.expect(summaryEql(constrained, constrained));
}

test "opaque storage summary identity includes its receiver domain" {
    const plain = facts.InputPath{ .input_index = 0 };
    const first = facts.InputPath{ .input_index = 0, .storage_domain = 0 };
    const second = facts.InputPath{ .input_index = 0, .storage_domain = 1 };
    const effect = facts.ValueEffect{ .opaque_storage_dependencies = &.{first} };
    try std.testing.expect(!valueEffectEql(effect, .{ .opaque_storage_dependencies = &.{plain} }));
    try std.testing.expect(!valueEffectEql(effect, .{ .opaque_storage_dependencies = &.{second} }));
    try std.testing.expect(!summaryEql(.{ .opaque_storage_empties = &.{first} }, .{ .opaque_storage_empties = &.{second} }));
}

test "summary engine reinfers only reverse dependencies" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    const caller: graph.GlobalFunctionId = @enumFromInt(1);
    const callee: graph.GlobalFunctionId = @enumFromInt(2);
    try engine.ensureEmpty(caller);
    try engine.ensureEmpty(callee);

    engine.beginInference(caller);
    _ = engine.summaryFor(callee);
    try engine.endInference();

    const dependency = [_]facts.InputDependency{.{ .path = .{ .input_index = 0 } }};
    const outputs = [_]facts.ValueEffect{.{ .input_dependencies = &dependency }};
    try std.testing.expect(try engine.updateSummary(callee, .{ .outputs = &outputs }));
    try std.testing.expectEqual(caller, engine.nextDirty().?);
    try std.testing.expect(engine.nextDirty() == null);

    // Replacing an approximation with an identical structural summary is a
    // fixed point and must not schedule the caller again.
    try std.testing.expect(!try engine.updateSummary(callee, .{ .outputs = &outputs }));
    try std.testing.expect(engine.nextDirty() == null);
}

test "recursive summary dependency reschedules itself until convergence" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    const function: graph.GlobalFunctionId = @enumFromInt(7);
    try engine.ensureEmpty(function);
    engine.beginInference(function);
    _ = engine.summaryFor(function);
    try engine.endInference();

    const outputs = [_]facts.ValueEffect{.{ .foreign_storage = true }};
    try std.testing.expect(try engine.updateSummary(function, .{ .outputs = &outputs }));
    try std.testing.expectEqual(function, engine.nextDirty().?);
    try std.testing.expect(!try engine.updateSummary(function, .{ .outputs = &outputs }));
    try std.testing.expect(engine.nextDirty() == null);
}

test "owned input root changes reschedule summary observers" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();
    const caller: graph.GlobalFunctionId = @enumFromInt(0);
    const callee: graph.GlobalFunctionId = @enumFromInt(1);
    const empty = [_]facts.ValueEffect{.{}};
    _ = try engine.updateSummary(callee, .{ .outputs = &empty });
    engine.beginInference(caller);
    _ = engine.summaryFor(callee);
    try engine.endInference();
    const paths = [_]facts.InputPath{.{ .input_index = 0 }};
    const outputs = [_]facts.ValueEffect{.{ .input_owned_roots = &paths }};
    try std.testing.expect(try engine.updateSummary(callee, .{ .outputs = &outputs }));
    try std.testing.expectEqual(caller, engine.nextDirty().?);
    try std.testing.expect(engine.nextDirty() == null);
    try std.testing.expect(!try engine.updateSummary(callee, .{ .outputs = &outputs }));
    const projected = [_]facts.InputPath{.{ .input_index = 0, .projections = &.{.{ .field = 1 }} }};
    const changed = [_]facts.ValueEffect{.{ .input_owned_roots = &projected }};
    try std.testing.expect(try engine.updateSummary(callee, .{ .outputs = &changed }));
    try std.testing.expectEqual(caller, engine.nextDirty().?);
}

test "nested effect equality preserves root paths and explicit dependencies" {
    const root_effect: facts.ValueEffect = .{ .input_owned_roots = &.{.{ .input_index = 0 }} };
    const empty: facts.ValueEffect = .{};
    try std.testing.expect(!valueEffectEql(
        .{ .fields = &.{.{ .index = 0, .value = &root_effect }} },
        .{ .fields = &.{.{ .index = 0, .value = &empty }} },
    ));
    try std.testing.expect(!valueEffectEql(.{ .explicit_dependency = true }, .{}));
    try std.testing.expect(!valueEffectEql(.{ .fresh_cleanup_obligation = true }, .{}));
}

test "summary equality includes selected opaque empty guarantees" {
    const absent = facts.OutcomePostStates{ .variant_index = 0, .input_post_states = &.{} };
    const empty = facts.OutcomePostStates{ .variant_index = 0, .input_post_states = &.{}, .opaque_storage_empties = &.{.{ .input_index = 1 }} };
    try std.testing.expect(!summaryEql(.{ .outcome_post_states = &.{absent} }, .{ .outcome_post_states = &.{empty} }));
    try std.testing.expect(summaryEql(.{ .outcome_post_states = &.{empty} }, .{ .outcome_post_states = &.{empty} }));
}

test "summary equality includes opaque content liveness requirements" {
    const empty: facts.SafetySummary = .{};
    const first: facts.SafetySummary = .{ .required_opaque_inputs = &.{.{ .input_index = 0 }} };
    const second: facts.SafetySummary = .{ .required_opaque_inputs = &.{.{ .input_index = 1 }} };
    try std.testing.expect(!summaryEql(empty, first));
    try std.testing.expect(!summaryEql(first, second));
    try std.testing.expect(summaryEql(first, first));
}

test "guarded summaries retain input output conjunctions and every effect dimension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const conditions = @import("choice_conditions.zig");
    const guard = try conditions.normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 0, .variant_index = 2 },
        .{ .subject = .output, .index = 1, .variant_index = 3 },
    });
    const empty: facts.SafetySummary = .{};
    const effects: facts.SafetySummary = .{
        .outputs = &.{.{ .input_place_values = &.{.{ .input_index = 0 }} }},
        .required_live_inputs = &.{.{ .input_index = 0 }},
        .required_opaque_inputs = &.{.{ .input_index = 1 }},
        .opaque_storage_empties = &.{.{ .input_index = 2 }},
    };
    const summary: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = guard, .effects = &effects }} };
    try std.testing.expect(!summaryEql(empty, summary));
    try std.testing.expect(summaryEql(summary, summary));
    var changed_effects = effects;
    changed_effects.required_opaque_inputs = &.{};
    const changed: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = guard, .effects = &changed_effects }} };
    try std.testing.expect(!summaryEql(summary, changed));
    const input_only = try conditions.normalize(allocator, guard.terms[0..1]);
    const changed_guard: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = input_only, .effects = &effects }} };
    try std.testing.expect(!summaryEql(summary, changed_guard));
}

test "summary equality distinguishes stored reference identities from lifetime facts" {
    const slot: facts.InputPath = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} };
    const left: facts.InputPath = .{ .input_index = 1 };
    const right: facts.InputPath = .{ .input_index = 2 };
    const unknown: facts.SafetySummary = .{ .input_post_states = &.{.{ .target = slot, .initializedness = .initialized }} };
    const first: facts.SafetySummary = .{ .input_post_states = &.{.{ .target = slot, .initializedness = .initialized, .reference_targets = &.{left} }} };
    const second: facts.SafetySummary = .{ .input_post_states = &.{.{ .target = slot, .initializedness = .initialized, .reference_targets = &.{right} }} };
    try std.testing.expect(!summaryEql(unknown, first));
    try std.testing.expect(!summaryEql(first, second));
    try std.testing.expect(summaryEql(first, first));
    const refreshed: facts.SafetySummary = .{ .input_post_states = &.{.{ .target = slot, .initializedness = .initialized, .reference_targets = &.{left}, .reference_refresh = true }} };
    try std.testing.expect(!summaryEql(first, refreshed));
}

test "outcome effect views retain common obligations and current normalized fields" {
    const fallback = [_]facts.PlacePostState{.{ .target = .{ .input_index = 0 }, .initializedness = .maybe_initialized }};
    const selected = [_]facts.PlacePostState{.{ .target = .{ .input_index = 4 }, .initializedness = .initialized, .refreshes_storage_generation = true }};
    const empties = [_]facts.InputPath{.{ .input_index = 1 }};
    const common_opaque = [_]facts.InputPath{.{ .input_index = 2 }};
    const independent: facts.SafetySummary = .{};
    var outcomes = [_]facts.OutcomePostStates{.{ .output_index = 0, .variant_index = 1, .input_post_states = &.{} }};
    const summary: facts.SafetySummary = .{
        .input_post_states = &fallback,
        .required_opaque_inputs = &common_opaque,
        .outcome_post_states = &outcomes,
        .guarded_effects = &.{.{ .conditions = .{}, .effects = &independent }},
    };
    const before = summary.outcomeEffects(outcomes[0]);
    outcomes[0].input_post_states = &selected;
    outcomes[0].opaque_storage_empties = &empties;
    const after = summary.outcomeEffects(outcomes[0]);
    try std.testing.expectEqual(@as(usize, 0), before.input_post_states.len);
    try std.testing.expectEqual(@as(u32, 4), after.input_post_states[0].target.input_index);
    try std.testing.expect(after.input_post_states.ptr == selected[0..].ptr);
    try std.testing.expect(after.required_opaque_inputs.ptr == common_opaque[0..].ptr);
    try std.testing.expect(after.opaque_storage_empties.ptr == empties[0..].ptr);
    try std.testing.expectEqual(@as(usize, 0), after.outcome_post_states.len);
    try std.testing.expectEqual(@as(usize, 0), after.guarded_effects.len);
    try std.testing.expectEqual(@as(usize, 1), summary.input_post_states.len);
    try std.testing.expect(summary.guarded_effects[0].effects == &independent);
}

test "summary work publication remains retryable after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn seed(a: std.mem.Allocator) !void {
            var engine = Engine.init(a);
            defer engine.deinit();
            const function: graph.GlobalFunctionId = @enumFromInt(0);
            engine.seed(&.{function}) catch |err| {
                try std.testing.expectEqual(@as(usize, 0), engine.dirty.count());
                try std.testing.expect(engine.nextDirty() == null);
                return err;
            };
            try std.testing.expectEqual(function, engine.nextDirty().?);
            try std.testing.expect(engine.nextDirty() == null);
        }
    }.seed, .{});
}

test "summary changes publish every observer or preserve the old approximation" {
    inline for (.{ false, true }) |existing| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
            fn update(a: std.mem.Allocator, retained: bool) !void {
                var engine = Engine.init(a);
                defer engine.deinit();
                const callee: graph.GlobalFunctionId = @enumFromInt(0);
                const first: graph.GlobalFunctionId = @enumFromInt(1);
                const second: graph.GlobalFunctionId = @enumFromInt(2);
                try engine.addDependency(first, callee);
                try engine.addDependency(second, callee);
                if (retained) try engine.ensureEmpty(callee);
                const changed: facts.SafetySummary = .{ .required_opaque_inputs = &.{.{ .input_index = 0 }} };
                _ = engine.updateSummary(callee, changed) catch |err| {
                    if (retained) {
                        try std.testing.expect(summaryEql(.{}, engine.summaries.get(callee).?));
                    } else try std.testing.expect(engine.summaries.get(callee) == null);
                    try std.testing.expectEqual(@as(usize, 0), engine.dirty.count());
                    try std.testing.expect(engine.nextDirty() == null);
                    return err;
                };
                try std.testing.expect(summaryEql(changed, engine.summaries.get(callee).?));
                try std.testing.expectEqual(first, engine.nextDirty().?);
                try std.testing.expectEqual(second, engine.nextDirty().?);
                try std.testing.expect(engine.nextDirty() == null);
                try std.testing.expect(!try engine.updateSummary(callee, changed));
                try std.testing.expect(engine.nextDirty() == null);
            }
        }.update, .{existing});
    }
}
