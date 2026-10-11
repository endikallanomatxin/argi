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
    worklist: std.array_list.Managed(graph.GlobalFunctionId),
    dirty: std.AutoHashMap(graph.GlobalFunctionId, void),
    next_work: usize = 0,
    current: ?graph.GlobalFunctionId = null,
    dependency_error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .summaries = std.AutoHashMap(graph.GlobalFunctionId, facts.SafetySummary).init(allocator),
            .dependents = DependentMap.init(allocator),
            .worklist = FunctionList.init(allocator),
            .dirty = std.AutoHashMap(graph.GlobalFunctionId, void).init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        var values = self.dependents.valueIterator();
        while (values.next()) |list| list.deinit();
        self.dependents.deinit();
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
        try self.summaries.put(function, summary);
        if (self.dependents.get(function)) |callers| {
            for (callers.items) |caller| try self.markDirty(caller);
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
        try self.dirty.put(function, {});
        try self.worklist.append(function);
    }

    fn recordDependency(self: *Engine, dependency: graph.GlobalFunctionId) void {
        const dependent = self.current orelse return;
        const entry = self.dependents.getOrPut(dependency) catch |err| {
            self.dependency_error = err;
            return;
        };
        if (!entry.found_existing) entry.value_ptr.* = FunctionList.init(self.allocator);
        for (entry.value_ptr.items) |existing| if (existing == dependent) return;
        entry.value_ptr.append(dependent) catch |err| {
            self.dependency_error = err;
        };
    }
};

/// Publish legacy outcome partitions in the general condition vocabulary while
/// retaining their unconditional fallback. The effect records are complete
/// approximations, not patches that may erase unrepresented caller effects.
/// Allocations belong to the immutable summary arena.
pub fn withOutcomeGuards(allocator: std.mem.Allocator, summary: facts.SafetySummary) !facts.SafetySummary {
    if (summary.guarded_effects.len != 0 or summary.outcome_post_states.len == 0) return summary;
    var guards: std.ArrayList(facts.GuardedSafetyEffects) = .empty;
    defer guards.deinit(allocator);
    for (summary.outcome_post_states) |outcome| {
        if (!outcome.reachable) continue;
        const projections = try allocator.alloc(facts.Projection, outcome.parent_variants.len);
        for (outcome.parent_variants, projections) |variant, *projection| projection.* = .{ .variant = variant };
        const condition = try @import("choice_conditions.zig").normalize(allocator, &.{.{
            .subject = .output,
            .index = outcome.output_index,
            .projections = projections,
            .variant_index = outcome.variant_index,
        }});
        const effects = try allocator.create(facts.SafetySummary);
        effects.* = summary;
        effects.guarded_effects = &.{};
        effects.outcome_post_states = &.{};
        effects.input_post_states = outcome.input_post_states;
        effects.invalidated_domains = outcome.invalidated_domains;
        effects.opaque_storage_empties = outcome.opaque_storage_empties;
        try guards.append(allocator, .{ .origin = .outcome_partition, .conditions = condition, .effects = effects });
    }
    var result = summary;
    result.guarded_effects = try guards.toOwnedSlice(allocator);
    return result;
}

/// Refresh only the compatibility records affected by domain normalization.
/// General conjunctive records remain immutable and retain their identities.
pub fn refreshOutcomeGuards(allocator: std.mem.Allocator, summary: facts.SafetySummary) !facts.SafetySummary {
    var general: std.ArrayList(facts.GuardedSafetyEffects) = .empty;
    defer general.deinit(allocator);
    for (summary.guarded_effects) |guarded| if (guarded.origin == .general) try general.append(allocator, guarded);
    var result = summary;
    result.guarded_effects = &.{};
    result = try withOutcomeGuards(allocator, result);
    result.guarded_effects = try std.mem.concat(allocator, facts.GuardedSafetyEffects, &.{ general.items, result.guarded_effects });
    return result;
}

pub fn summaryEql(a: facts.SafetySummary, b: facts.SafetySummary) bool {
    if (a.guarded_returns_complete != b.guarded_returns_complete or a.guarded_effects.len != b.guarded_effects.len) return false;
    for (a.guarded_effects, b.guarded_effects) |left, right| {
        if (left.origin != right.origin or !left.conditions.eql(right.conditions) or !summaryEql(left.effects.*, right.effects.*)) return false;
    }
    if (!domainsEql(a.invalidated_domains, b.invalidated_domains)) return false;
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
        a.initializedness != b.initializedness or
        a.ends_previous_roots != b.ends_previous_roots or
        a.refreshes_storage_generation != b.refreshes_storage_generation or
        a.requires_available_destination != b.requires_available_destination or
        a.opaque_ownership != b.opaque_ownership or
        a.may_repopulate_opaque_storage != b.may_repopulate_opaque_storage or
        !valueEffectEql(a.value, b.value)) return false;
    if ((a.opaque_storage == null) != (b.opaque_storage == null)) return false;
    if (a.opaque_storage) |left| if (!inputPathEql(left, b.opaque_storage.?)) return false;
    return true;
}

fn inputPathEql(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.storage_domain != b.storage_domain or a.projections.len != b.projections.len) return false;
    for (a.projections, b.projections) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
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

test "legacy outcome summaries publish nested output conditions with a conservative fallback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input_states = [_]facts.PlacePostState{.{ .target = .{ .input_index = 0 }, .initializedness = .initialized, .refreshes_storage_generation = true }};
    const original: facts.SafetySummary = .{
        .input_post_states = &input_states,
        .required_opaque_inputs = &.{.{ .input_index = 0 }},
        .outcome_post_states = &.{
            .{ .output_index = 1, .parent_variants = &.{2}, .variant_index = 3, .input_post_states = &.{}, .opaque_storage_empties = &.{.{ .input_index = 0 }} },
            .{ .reachable = false, .output_index = 1, .variant_index = 4, .input_post_states = &.{} },
        },
    };
    const represented = try withOutcomeGuards(arena.allocator(), original);
    try std.testing.expectEqual(@as(usize, 1), represented.guarded_effects.len);
    try std.testing.expectEqual(@as(usize, 2), represented.guarded_effects[0].conditions.terms.len);
    try std.testing.expectEqual(@as(usize, 1), represented.input_post_states.len);
    try std.testing.expectEqual(@as(usize, 0), represented.guarded_effects[0].effects.input_post_states.len);
    try std.testing.expectEqual(@as(usize, 1), represented.guarded_effects[0].effects.required_opaque_inputs.len);
    try std.testing.expectEqual(@as(usize, 1), represented.guarded_effects[0].effects.opaque_storage_empties.len);
    try std.testing.expect(summaryEql(represented, try withOutcomeGuards(arena.allocator(), represented)));
}

test "outcome guard refresh preserves general conjunctions and replaces stale mapped effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const conditions = try @import("choice_conditions.zig").normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 1, .variant_index = 2 },
    });
    const independent: facts.SafetySummary = .{ .required_opaque_inputs = &.{.{ .input_index = 3 }} };
    const initial: facts.SafetySummary = .{ .outcome_post_states = &.{.{ .output_index = 0, .variant_index = 1, .input_post_states = &.{} }} };
    var converted = try withOutcomeGuards(allocator, initial);
    const stale = converted.guarded_effects[0].effects;
    converted.guarded_effects = try std.mem.concat(allocator, facts.GuardedSafetyEffects, &.{
        &.{.{ .conditions = conditions, .effects = &independent }},
        converted.guarded_effects,
    });
    converted.outcome_post_states = &.{.{ .output_index = 0, .variant_index = 1, .input_post_states = &.{.{ .target = .{ .input_index = 4 }, .initializedness = .initialized, .refreshes_storage_generation = true }} }};
    const refreshed = try refreshOutcomeGuards(allocator, converted);
    try std.testing.expectEqual(@as(usize, 2), refreshed.guarded_effects.len);
    try std.testing.expect(refreshed.guarded_effects[0].effects == &independent);
    try std.testing.expect(refreshed.guarded_effects[0].conditions.eql(conditions));
    try std.testing.expectEqual(@as(u32, 4), refreshed.guarded_effects[1].effects.input_post_states[0].target.input_index);
    try std.testing.expectEqual(@as(usize, 0), stale.input_post_states.len);
    try std.testing.expect(summaryEql(refreshed, try refreshOutcomeGuards(allocator, refreshed)));
}
