const std = @import("std");
const g = @import("../global/graph.zig");
const Identity = @import("../global/function_identity.zig").FunctionIdentity;
const facts = @import("facts.zig");
const summaries = @import("summaries.zig");
const Annotations = @import("annotations.zig").Annotations;
const VirtualDependency = @import("summary_cache.zig").VirtualDependency;

const Dependency = struct { function: g.GlobalFunctionId, summary: facts.SafetySummary };

/// A body proof owns its execution annotations and the converged hypotheses
/// actually consulted while checking it. Caller temporal state is never cached.
pub const Proof = struct {
    arena: std.heap.ArenaAllocator,
    function: g.GlobalFunctionId,
    revision: u64,
    identity: Identity,
    dependencies: []const Dependency,
    virtuals: []const VirtualDependency,
    annotations: Annotations,

    fn deinit(self: *Proof, allocator: std.mem.Allocator) void {
        self.annotations.deinit(self.arena.allocator());
        self.arena.deinit();
        allocator.destroy(self);
    }
};

pub const Batch = struct {
    entries: std.ArrayList(*Proof) = .empty,
    reused: std.AutoHashMapUnmanaged(g.GlobalFunctionId, u64) = .empty,
    next_revision: ?u64 = null,

    pub fn revision(self: *const Batch, function: g.GlobalFunctionId) ?u64 {
        for (self.entries.items) |proof| if (proof.function == function) return proof.revision;
        return self.reused.get(function);
    }

    pub fn deinit(self: *Batch, allocator: std.mem.Allocator) void {
        for (self.entries.items) |proof| proof.deinit(allocator);
        self.entries.deinit(allocator);
        self.reused.deinit(allocator);
        self.* = .{};
    }
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    entries: std.AutoHashMapUnmanaged(g.GlobalFunctionId, *Proof) = .empty,
    next_revision: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) Store {
        return .{ .allocator = allocator, .graph = graph };
    }

    pub fn deinit(self: *Store) void {
        var proofs = self.entries.valueIterator();
        while (proofs.next()) |proof| proof.*.deinit(self.allocator);
        self.entries.deinit(self.allocator);
    }

    pub fn lookup(self: *const Store, function: g.GlobalFunctionId, engine: *const summaries.Engine) ?*const Proof {
        const proof = self.entries.get(function) orelse return null;
        if (!proof.identity.matches(self.graph, function)) return null;
        for (proof.dependencies) |dependency| {
            const current = engine.summaries.get(dependency.function) orelse return null;
            if (!summaries.summaryEql(current, dependency.summary)) return null;
        }
        if (!@import("summary_cache.zig").virtualsMatch(self.graph, proof.virtuals)) return null;
        return proof;
    }

    pub fn stage(self: *const Store, batch: *Batch, function: g.GlobalFunctionId, engine: *const summaries.Engine, annotations: *const Annotations) !void {
        if (!engine.retain_dependencies) return error.MissingSafetyDependencies;
        var dependencies: std.ArrayList(Dependency) = .empty;
        defer dependencies.deinit(engine.allocator);
        if (engine.dependencies.get(function)) |required| for (required.items) |dependency| {
            // A fallback body without a summary has no reusable proof yet.
            const summary = engine.summaries.get(dependency) orelse return;
            try dependencies.append(engine.allocator, .{ .function = dependency, .summary = summary });
        };
        var virtuals: std.ArrayList(VirtualDependency) = .empty;
        defer virtuals.deinit(engine.allocator);
        if (engine.virtual_dependencies.get(function)) |required| for (required.items) |registry| {
            try virtuals.append(engine.allocator, .{ .registry = registry, .signature = self.graph.virtual_registries.items[@intFromEnum(registry)] });
        };
        const revision = batch.next_revision orelse self.next_revision;
        const next_revision = try std.math.add(u64, revision, 1);
        const proof = try self.allocator.create(Proof);
        errdefer self.allocator.destroy(proof);
        proof.* = .{ .arena = .init(self.allocator), .function = function, .revision = revision, .identity = Identity.read(self.graph, function), .dependencies = &.{}, .virtuals = &.{}, .annotations = .{} };
        errdefer proof.arena.deinit();
        var copy: @import("fact_snapshot.zig").Copy = .{ .allocator = proof.arena.allocator(), .scratch = engine.allocator };
        defer copy.deinit();
        proof.dependencies = try copy.value([]const Dependency, dependencies.items);
        proof.virtuals = try copy.value([]const VirtualDependency, virtuals.items);
        proof.annotations = try annotations.clone(proof.arena.allocator());
        errdefer proof.annotations.deinit(proof.arena.allocator());
        try batch.entries.append(self.allocator, proof);
        batch.next_revision = next_revision;
    }

    pub fn reserve(self: *Store, batch: *const Batch) !void {
        try self.entries.ensureUnusedCapacity(self.allocator, @intCast(batch.entries.items.len));
    }

    pub fn commit(self: *Store, batch: *Batch) void {
        for (batch.entries.items) |proof| {
            if (self.entries.fetchPutAssumeCapacity(proof.function, proof)) |old| old.value.deinit(self.allocator);
        }
        if (batch.next_revision) |revision| self.next_revision = revision;
        batch.next_revision = null;
        batch.entries.clearRetainingCapacity();
        batch.reused.clearRetainingCapacity();
    }
};

fn publicationFailures(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const function: g.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } };
    try graph.functions.appendSlice(a, &.{ function, function });
    var consumed = [_]u32{0};
    try graph.virtual_registries.append(a, .{ .receiver_input_index = 0, .contract_input_count = 1, .safety_contract = .{ .output_count = 0, .consumed_inputs = &consumed, .source = .{ .file_index = 0, .offset = 0 } } });
    var engine = summaries.Engine.init(a);
    defer engine.deinit();
    engine.retain_dependencies = true;
    try engine.ensureEmpty(@enumFromInt(0));
    try engine.ensureEmpty(@enumFromInt(1));
    try engine.addDependency(@enumFromInt(0), @enumFromInt(0));
    try engine.addDependency(@enumFromInt(0), @enumFromInt(1));
    try engine.addVirtualDependency(@enumFromInt(0), @enumFromInt(0));
    var annotations: Annotations = .{};
    defer annotations.deinit(a);
    try annotations.recordInitialization(a, @enumFromInt(7), true);
    try annotations.setCall(a, @enumFromInt(8), .{ .consumed_auto_deinits = &.{@enumFromInt(9)} });
    var store = Store.init(allocator, &graph);
    defer store.deinit();
    {
        var rejected: Batch = .{};
        defer rejected.deinit(allocator);
        try store.stage(&rejected, @enumFromInt(0), &engine, &annotations);
        try std.testing.expectEqual(@as(usize, 0), store.entries.count());
    }
    var batch: Batch = .{};
    defer batch.deinit(allocator);
    try store.stage(&batch, @enumFromInt(0), &engine, &annotations);
    try store.reserve(&batch);
    store.commit(&batch);
    annotations.clear(a);
    const proof = store.lookup(@enumFromInt(0), &engine).?;
    try std.testing.expect(proof.revision != 0);
    const accepted_revision = store.next_revision;
    {
        var rejected: Batch = .{};
        defer rejected.deinit(allocator);
        try store.stage(&rejected, @enumFromInt(0), &engine, &annotations);
        try std.testing.expect(rejected.revision(@enumFromInt(0)).? != proof.revision);
        try std.testing.expectEqual(accepted_revision, store.next_revision);
    }
    try std.testing.expectEqual(accepted_revision, store.next_revision);
    try std.testing.expect(proof.annotations.initializes(@enumFromInt(7)));
    try std.testing.expectEqual(@as(g.GlobalNodeId, @enumFromInt(9)), proof.annotations.call(@enumFromInt(8)).consumed_auto_deinits[0]);
    var merged: Annotations = .{};
    defer merged.deinit(allocator);
    try merged.merge(allocator, &proof.annotations);
    try std.testing.expect(merged.initializes(@enumFromInt(7)));
    // A callee's converged effects are hypotheses even when body IDs match.
    engine.summaries.getPtr(@enumFromInt(1)).?.* = .{ .required_live_inputs = &.{.{ .input_index = 0 }} };
    try std.testing.expect(store.lookup(@enumFromInt(0), &engine) == null);
    engine.summaries.getPtr(@enumFromInt(1)).?.* = .{};
    try std.testing.expect(store.lookup(@enumFromInt(0), &engine) != null);
    consumed[0] = 1;
    try std.testing.expect(store.lookup(@enumFromInt(0), &engine) == null);
    consumed[0] = 0;
    try std.testing.expect(store.lookup(@enumFromInt(0), &engine) != null);
    graph.functions.items[0].flags.is_comptime_entry = true;
    try std.testing.expect(store.lookup(@enumFromInt(0), &engine) == null);
}

test "body proof cache owns hypotheses and annotations through rejected publications and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publicationFailures, .{});
}
