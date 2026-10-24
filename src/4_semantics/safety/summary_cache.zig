const std = @import("std");
const g = @import("../global/graph.zig");
const facts = @import("facts.zig");
const summaries = @import("summaries.zig");
const Selector = @import("outcome_selectors.zig").Selector;

pub const Key = @import("../global/function_identity.zig").FunctionIdentity;

pub const Dependency = struct { function: g.GlobalFunctionId, revision: u64 };
pub const VirtualDependency = struct { registry: g.GlobalVirtualRegistryId, signature: g.VirtualMethodRegistry };

pub const Entry = struct {
    arena: std.heap.ArenaAllocator,
    function: g.GlobalFunctionId,
    key: Key,
    revision: u64,
    summary: facts.SafetySummary,
    selectors: []const Selector,
    dependencies: []const Dependency,
    virtual_dependencies: []const VirtualDependency,

    fn create(allocator: std.mem.Allocator, scratch: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, function: g.GlobalFunctionId, revision: u64, summary: facts.SafetySummary, selectors: []const Selector, dependencies: []const Dependency, virtuals: []const VirtualDependency) !*Entry {
        const entry = try allocator.create(Entry);
        errdefer allocator.destroy(entry);
        entry.* = .{ .arena = .init(allocator), .function = function, .key = Key.read(graph, function), .revision = revision, .summary = undefined, .selectors = &.{}, .dependencies = &.{}, .virtual_dependencies = &.{} };
        errdefer entry.arena.deinit();
        var copy: @import("fact_snapshot.zig").Copy = .{ .allocator = entry.arena.allocator(), .scratch = scratch };
        defer copy.deinit();
        entry.summary = try copy.value(facts.SafetySummary, summary);
        entry.selectors = try copy.value([]const Selector, selectors);
        entry.dependencies = try copy.value([]const Dependency, dependencies);
        entry.virtual_dependencies = try copy.value([]const VirtualDependency, virtuals);
        return entry;
    }

    fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        self.arena.deinit();
        allocator.destroy(self);
    }
};

/// Candidate-owned immutable publications. Rejection releases every new arena;
/// acceptance reserves the index first and transfers entries without allocating.
pub const Batch = struct {
    // Command roots are evaluated once; only reusable dependencies are retained.
    excluded_function: ?g.GlobalFunctionId = null,
    entries: std.ArrayList(*Entry) = .empty,
    next_revision: u64 = 1,

    pub fn deinit(self: *Batch, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| entry.deinit(allocator);
        self.entries.deinit(allocator);
        self.* = .{};
    }
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    entries: std.AutoHashMapUnmanaged(g.GlobalFunctionId, *Entry) = .empty,
    next_revision: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) Store {
        return .{ .allocator = allocator, .graph = graph };
    }

    pub fn deinit(self: *Store) void {
        var values = self.entries.valueIterator();
        while (values.next()) |entry| entry.*.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reserve(self: *Store, batch: *const Batch) !void {
        try self.entries.ensureUnusedCapacity(self.allocator, @intCast(batch.entries.items.len));
    }

    pub fn commit(self: *Store, batch: *Batch) void {
        for (batch.entries.items) |entry| {
            const previous = self.entries.fetchPutAssumeCapacity(entry.function, entry);
            if (previous) |old| old.value.deinit(self.allocator);
        }
        self.next_revision = batch.next_revision;
        batch.entries.clearRetainingCapacity();
    }

    /// Import only a closed set of valid cached hypotheses. Invalidated SCCs
    /// and callers start from fresh approximations rather than stale summaries.
    pub fn restore(self: *const Store, engine: *summaries.Engine, demands: *const std.AutoHashMap(g.GlobalFunctionId, []const Selector)) !std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) {
        engine.retain_dependencies = true;
        const a = engine.allocator;
        var invalid: std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) = .empty;
        defer invalid.deinit(a);
        var queue: std.ArrayList(g.GlobalFunctionId) = .empty;
        defer queue.deinit(a);
        var reverse: std.AutoHashMapUnmanaged(g.GlobalFunctionId, std.ArrayList(g.GlobalFunctionId)) = .empty;
        defer {
            var lists = reverse.valueIterator();
            while (lists.next()) |list| list.deinit(a);
            reverse.deinit(a);
        }
        var ids = engine.summaries.keyIterator();
        while (ids.next()) |id| {
            const old = self.entries.get(id.*);
            var valid = if (old) |entry| entry.key.matches(self.graph, id.*) and covers(entry.selectors, demands.get(id.*) orelse &.{}) and virtualsMatch(self.graph, entry.virtual_dependencies) else false;
            if (old) |entry| for (entry.dependencies) |dependency| {
                const previous = self.entries.get(dependency.function);
                valid = valid and engine.summaries.contains(dependency.function) and previous != null and previous.?.revision == dependency.revision;
                const callers = try reverse.getOrPut(a, dependency.function);
                if (!callers.found_existing) callers.value_ptr.* = .empty;
                try callers.value_ptr.append(a, id.*);
            };
            if (!valid) {
                try invalid.put(a, id.*, {});
                try queue.append(a, id.*);
            }
        }
        var index: usize = 0;
        while (index < queue.items.len) : (index += 1) {
            if (reverse.get(queue.items[index])) |callers| for (callers.items) |caller| {
                const seen = try invalid.getOrPut(a, caller);
                if (!seen.found_existing) try queue.append(a, caller);
            };
        }
        var reused: std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) = .empty;
        errdefer reused.deinit(a);
        ids = engine.summaries.keyIterator();
        while (ids.next()) |id| {
            if (invalid.contains(id.*)) continue;
            const entry = self.entries.get(id.*).?;
            engine.summaries.getPtr(id.*).?.* = entry.summary;
            for (entry.dependencies) |dependency| try engine.addDependency(id.*, dependency.function);
            for (entry.virtual_dependencies) |dependency| try engine.addVirtualDependency(id.*, dependency.registry);
            try reused.put(a, id.*, {});
        }
        return reused;
    }

    pub fn stage(self: *const Store, batch: *Batch, engine: *const summaries.Engine, demands: *const std.AutoHashMap(g.GlobalFunctionId, []const Selector), reused: *const std.AutoHashMapUnmanaged(g.GlobalFunctionId, void)) !void {
        std.debug.assert(batch.entries.items.len == 0);
        if (!engine.retain_dependencies) return error.MissingSafetyDependencies;
        batch.next_revision = self.next_revision;
        const a = engine.allocator;
        var revisions: std.AutoHashMapUnmanaged(g.GlobalFunctionId, u64) = .empty;
        defer revisions.deinit(a);
        var iterator = engine.summaries.iterator();
        while (iterator.next()) |item| {
            const function = item.key_ptr.*;
            const previous = self.entries.get(function);
            const unchanged = if (previous) |old| reused.contains(function) or
                (old.key.matches(self.graph, function) and virtualsMatch(self.graph, old.virtual_dependencies) and summaries.summaryEql(old.summary, item.value_ptr.*)) else false;
            const revision = if (unchanged) previous.?.revision else fresh: {
                const revision = batch.next_revision;
                batch.next_revision = try std.math.add(u64, revision, 1);
                break :fresh revision;
            };
            try revisions.put(a, function, revision);
        }
        iterator = engine.summaries.iterator();
        while (iterator.next()) |item| {
            const function = item.key_ptr.*;
            if (reused.contains(function) or batch.excluded_function == function or self.graph.function(function).flags.is_comptime_entry) continue;
            var dependencies: std.ArrayList(Dependency) = .empty;
            defer dependencies.deinit(a);
            if (engine.dependencies.get(function)) |required| for (required.items) |dependency| {
                try dependencies.append(a, .{ .function = dependency, .revision = revisions.get(dependency) orelse return error.MissingSafetyDependency });
            };
            var virtuals: std.ArrayList(VirtualDependency) = .empty;
            defer virtuals.deinit(a);
            if (engine.virtual_dependencies.get(function)) |required| for (required.items) |registry| {
                try virtuals.append(a, .{ .registry = registry, .signature = self.graph.virtual_registries.items[@intFromEnum(registry)] });
            };
            const entry = try Entry.create(self.allocator, a, self.graph, function, revisions.get(function).?, item.value_ptr.*, demands.get(function) orelse &.{}, dependencies.items, virtuals.items);
            batch.entries.append(self.allocator, entry) catch |err| {
                entry.deinit(self.allocator);
                return err;
            };
        }
    }
};

fn virtualsMatch(graph: *const g.GlobalSemanticGraph, dependencies: []const VirtualDependency) bool {
    for (dependencies) |dependency| {
        if (@intFromEnum(dependency.registry) >= graph.virtual_registries.items.len or
            !declarationEql(dependency.signature, graph.virtual_registries.items[@intFromEnum(dependency.registry)])) return false;
    }
    return true;
}

fn covers(available: []const Selector, wanted: []const Selector) bool {
    for (wanted) |selector| {
        var found = false;
        for (available) |old| if (old.output_index == selector.output_index and old.variant_index == selector.variant_index and std.mem.eql(u32, old.parent_variants, selector.parent_variants)) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

// Declaration trees contain scalar coordinates and immutable slices only.
// Compare contents, not slice addresses: signatures are independently owned.
fn declarationEql(a: anytype, b: @TypeOf(a)) bool {
    return switch (@typeInfo(@TypeOf(a))) {
        .@"struct" => |record| equal: {
            inline for (record.fields) |field| if (!declarationEql(@field(a, field.name), @field(b, field.name))) break :equal false;
            break :equal true;
        },
        .optional => if (a) |value| if (b) |other| declarationEql(value, other) else false else b == null,
        .pointer => |pointer| equal: {
            if (pointer.size != .slice) @compileError("Safety declaration keys cannot contain object pointers");
            if (a.len != b.len) break :equal false;
            for (a, b) |value, other| if (!declarationEql(value, other)) break :equal false;
            break :equal true;
        },
        else => std.meta.eql(a, b),
    };
}

fn fixtureGraph(a: std.mem.Allocator) !g.GlobalSemanticGraph {
    var graph: g.GlobalSemanticGraph = .{};
    errdefer graph.deinit(a);
    for (0..3) |index| {
        try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 0 } });
        try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .body = @enumFromInt(index), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
    }
    return graph;
}

fn seedEngine(engine: *summaries.Engine) !void {
    for (0..3) |index| try engine.ensureEmpty(@enumFromInt(index));
}

test "summary cache restores dependency closures and invalidates selector SCCs" {
    const a = std.testing.allocator;
    var graph = try fixtureGraph(a);
    defer graph.deinit(a);
    var store = Store.init(a, &graph);
    defer store.deinit();
    var engine = summaries.Engine.init(a);
    defer engine.deinit();
    engine.retain_dependencies = true;
    try seedEngine(&engine);
    try engine.addDependency(@enumFromInt(0), @enumFromInt(1));
    try engine.addDependency(@enumFromInt(1), @enumFromInt(2));
    try engine.addDependency(@enumFromInt(2), @enumFromInt(1));
    var demands = std.AutoHashMap(g.GlobalFunctionId, []const Selector).init(a);
    defer demands.deinit();
    var reused: std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) = .empty;
    defer reused.deinit(a);
    var batch: Batch = .{};
    defer batch.deinit(a);
    try store.stage(&batch, &engine, &demands, &reused);
    try std.testing.expectEqual(@as(usize, 0), store.entries.count());
    try store.reserve(&batch);
    store.commit(&batch);
    var restored = summaries.Engine.init(a);
    defer restored.deinit();
    restored.retain_dependencies = true;
    try seedEngine(&restored);
    var imported = try store.restore(&restored, &demands);
    defer imported.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), imported.count());
    try std.testing.expectEqual(@as(usize, 2), restored.dependents.get(@enumFromInt(1)).?.items.len);
    try demands.put(@enumFromInt(2), &.{.{ .output_index = 0, .parent_variants = &.{1}, .variant_index = 0 }});
    var invalidated = try store.restore(&restored, &demands);
    defer invalidated.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), invalidated.count());
}

test "summary cache owns virtual declaration hypotheses and rejects changed contents" {
    const a = std.testing.allocator;
    var graph = try fixtureGraph(a);
    defer graph.deinit(a);
    var consumed = [_]u32{0};
    try graph.virtual_registries.append(a, .{ .receiver_input_index = 0, .contract_input_count = 1, .safety_contract = .{ .output_count = 0, .consumed_inputs = &consumed, .source = .{ .file_index = 0, .offset = 0 } } });
    var store = Store.init(a, &graph);
    defer store.deinit();
    var engine = summaries.Engine.init(a);
    defer engine.deinit();
    engine.retain_dependencies = true;
    try seedEngine(&engine);
    try engine.addDependency(@enumFromInt(0), @enumFromInt(1));
    try engine.addVirtualDependency(@enumFromInt(1), @enumFromInt(0));
    var demands = std.AutoHashMap(g.GlobalFunctionId, []const Selector).init(a);
    defer demands.deinit();
    var reused: std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) = .empty;
    defer reused.deinit(a);
    var batch: Batch = .{};
    defer batch.deinit(a);
    try store.stage(&batch, &engine, &demands, &reused);
    try store.reserve(&batch);
    store.commit(&batch);
    var restored = summaries.Engine.init(a);
    defer restored.deinit();
    try seedEngine(&restored);
    var imported = try store.restore(&restored, &demands);
    defer imported.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), imported.count());
    consumed[0] = 1;
    var invalidated = try store.restore(&restored, &demands);
    defer invalidated.deinit(a);
    try std.testing.expect(!invalidated.contains(@enumFromInt(0)));
    try std.testing.expect(!invalidated.contains(@enumFromInt(1)));
    try std.testing.expect(invalidated.contains(@enumFromInt(2)));
    try std.testing.expectEqual(@as(u32, 0), store.entries.get(@enumFromInt(1)).?.virtual_dependencies[0].signature.safety_contract.?.consumed_inputs[0]);
}

fn publishOwnedSummary(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var graph = try fixtureGraph(a);
    defer graph.deinit(a);
    var store = Store.init(allocator, &graph);
    defer store.deinit();
    {
        var transient = std.heap.ArenaAllocator.init(a);
        defer transient.deinit();
        const scratch = transient.allocator();
        var engine = summaries.Engine.init(scratch);
        defer engine.deinit();
        engine.retain_dependencies = true;
        try seedEngine(&engine);
        const paths = try scratch.dupe(facts.Projection, &.{.{ .field = 7 }});
        const child = try scratch.create(facts.ValueEffect);
        child.* = .{ .input_places = try scratch.dupe(facts.InputPath, &.{.{ .input_index = 0, .projections = paths }}) };
        const fields = try scratch.dupe(facts.OutputFieldEffect, &.{ .{ .index = 0, .value = child }, .{ .index = 1, .value = child } });
        const outputs = try scratch.dupe(facts.ValueEffect, &.{.{ .fields = fields }});
        const effects = try scratch.create(facts.SafetySummary);
        effects.* = .{ .outputs = outputs };
        try engine.summaries.put(@enumFromInt(0), .{ .outputs = outputs, .guarded_effects = try scratch.dupe(facts.GuardedSafetyEffects, &.{.{ .conditions = .{}, .effects = effects }}) });
        var demands = std.AutoHashMap(g.GlobalFunctionId, []const Selector).init(scratch);
        defer demands.deinit();
        var reused: std.AutoHashMapUnmanaged(g.GlobalFunctionId, void) = .empty;
        defer reused.deinit(scratch);
        var batch: Batch = .{};
        defer batch.deinit(allocator);
        try store.stage(&batch, &engine, &demands, &reused);
        try store.reserve(&batch);
        store.commit(&batch);
    }
    const summary = store.entries.get(@enumFromInt(0)).?.summary;
    try std.testing.expectEqual(@as(u32, 7), summary.outputs[0].fields[0].value.input_places[0].projections[0].field);
    try std.testing.expect(summary.outputs[0].fields[0].value == summary.outputs[0].fields[1].value);
    try std.testing.expect(summary.outputs.ptr == summary.guarded_effects[0].effects.outputs.ptr);
}

test "summary cache publications own guarded effect DAGs and release allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishOwnedSummary, .{});
}

test "summary cache rejects inference against another graph with identical IDs" {
    const a = std.testing.allocator;
    var graph = try fixtureGraph(a);
    defer graph.deinit(a);
    var foreign = try graph.clone(a);
    defer foreign.deinit(a);
    var store = Store.init(a, &graph);
    defer store.deinit();
    var engine = summaries.Engine.init(a);
    defer engine.deinit();
    var inference = @import("summary_infer.zig").Infer.init(a, &foreign, &engine);
    defer inference.deinit();
    inference.cache = &store;
    try std.testing.expectError(error.ForeignSafetySummaryCache, inference.inferSafetySummariesFixedPoint());
}
