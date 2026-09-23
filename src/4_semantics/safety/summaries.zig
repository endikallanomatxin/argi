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

pub fn summaryEql(a: facts.SafetySummary, b: facts.SafetySummary) bool {
    if (a.outputs.len != b.outputs.len or
        a.required_live_inputs.len != b.required_live_inputs.len or
        a.input_post_states.len != b.input_post_states.len or
        a.opaque_storage_effects.len != b.opaque_storage_effects.len or
        a.opaque_storage_empties.len != b.opaque_storage_empties.len) return false;

    for (a.outputs, b.outputs) |left, right| if (!valueEffectEql(left, right)) return false;
    for (a.required_live_inputs, b.required_live_inputs) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_post_states, b.input_post_states) |left, right| if (!postStateEql(left, right)) return false;
    for (a.opaque_storage_effects, b.opaque_storage_effects) |left, right| {
        if (!inputPathEql(left.storage, right.storage) or !valueEffectEql(left.hidden_dependencies, right.hidden_dependencies)) return false;
    }
    for (a.opaque_storage_empties, b.opaque_storage_empties) |left, right| if (!inputPathEql(left, right)) return false;
    return true;
}

fn valueEffectEql(a: facts.ValueEffect, b: facts.ValueEffect) bool {
    if (a.input_dependencies.len != b.input_dependencies.len or
        a.input_places.len != b.input_places.len or
        a.input_place_values.len != b.input_place_values.len or
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
        if (left.transfers_ownership != right.transfers_ownership or !inputPathEql(left.path, right.path)) return false;
    }
    for (a.input_places, b.input_places) |left, right| if (!inputPathEql(left, right)) return false;
    for (a.input_place_values, b.input_place_values) |left, right| if (!inputPathEql(left, right)) return false;
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
    if (!std.mem.eql(facts.FreshEffectSource, a.fresh_storage_capabilities, b.fresh_storage_capabilities)) return false;
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
    if (a.input_index != b.input_index or a.projections.len != b.projections.len) return false;
    for (a.projections, b.projections) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
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
