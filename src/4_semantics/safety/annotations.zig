const std = @import("std");
const g = @import("../global/graph.zig");

/// Caller-relative cleanup changes, including evaluated argument identities
/// and outcome-dependent transitions. These are derived proofs, not semantics.
pub const CallEffects = struct {
    consumes_auto_deinit: ?g.GlobalNodeId = null,
    consumed_auto_deinits: []const g.GlobalNodeId = &.{},
    initialized_auto_deinits: []const g.GlobalNodeId = &.{},
    outcome_cleanups: []const @import("../primitives/schema.zig").OutcomeCleanup(g.Ids) = &.{},
    initializes_auto_deinit: ?g.GlobalNodeId = null,

    fn isEmpty(self: CallEffects) bool {
        return self.consumes_auto_deinit == null and self.initializes_auto_deinit == null and
            self.consumed_auto_deinits.len == 0 and self.initialized_auto_deinits.len == 0 and self.outcome_cleanups.len == 0;
    }
};

/// Sparse execution proofs indexed by stable semantic identities. Builder
/// buffers use storageAllocator; clone publishes independent immutable storage.
/// Missing entries never establish a first-initialization guarantee.
pub const Annotations = struct {
    pub const empty: Annotations = .{};
    writes: std.AutoHashMapUnmanaged(g.GlobalNodeId, bool) = .empty,
    calls: std.AutoHashMapUnmanaged(g.GlobalNodeId, CallEffects) = .empty,
    virtual_calls: std.AutoHashMapUnmanaged(g.GlobalVirtualCallId, CallEffects) = .empty,
    arena: ?*std.heap.ArenaAllocator = null,
    published: bool = false,

    pub fn storageAllocator(self: *Annotations, parent: std.mem.Allocator) !std.mem.Allocator {
        std.debug.assert(!self.published);
        if (self.arena == null) {
            const arena = try parent.create(std.heap.ArenaAllocator);
            arena.* = .init(parent);
            self.arena = arena;
        }
        return self.arena.?.allocator();
    }

    pub fn call(self: *const Annotations, id: g.GlobalNodeId) CallEffects {
        return self.calls.get(id) orelse .{};
    }

    pub fn virtualCall(self: *const Annotations, id: g.GlobalVirtualCallId) CallEffects {
        return self.virtual_calls.get(id) orelse .{};
    }

    pub fn setCall(self: *Annotations, parent: std.mem.Allocator, id: g.GlobalNodeId, effects: CallEffects) !void {
        std.debug.assert(!self.published);
        if (effects.isEmpty()) {
            _ = self.calls.remove(id);
        } else try self.calls.put(parent, id, effects);
    }

    pub fn setVirtualCall(self: *Annotations, parent: std.mem.Allocator, id: g.GlobalVirtualCallId, effects: CallEffects) !void {
        std.debug.assert(!self.published);
        if (effects.isEmpty()) {
            _ = self.virtual_calls.remove(id);
        } else try self.virtual_calls.put(parent, id, effects);
    }

    pub fn initializes(self: *const Annotations, id: g.GlobalNodeId) bool {
        return self.writes.get(id) == true;
    }

    pub fn observed(self: *const Annotations, id: g.GlobalNodeId) ?bool {
        return self.writes.get(id);
    }

    /// Every incoming state must establish the guarantee. A later successful
    /// path cannot overwrite an earlier replacement observation.
    pub fn recordInitialization(self: *Annotations, allocator: std.mem.Allocator, id: g.GlobalNodeId, initializes_: bool) !void {
        std.debug.assert(!self.published);
        if (self.writes.getPtr(id)) |previous| {
            previous.* = previous.* and initializes_;
        } else try self.writes.put(allocator, id, initializes_);
    }

    /// RHS evaluation may refill a previously vacant captured destination.
    pub fn constrainInitialization(self: *Annotations, allocator: std.mem.Allocator, id: g.GlobalNodeId, vacant: bool) !void {
        std.debug.assert(!self.published);
        const value = self.initializes(id) and vacant;
        try self.writes.put(allocator, id, value);
    }

    pub fn clear(self: *Annotations, parent: std.mem.Allocator) void {
        std.debug.assert(!self.published);
        self.writes.clearRetainingCapacity();
        self.calls.clearRetainingCapacity();
        self.virtual_calls.clearRetainingCapacity();
        if (self.arena) |arena| {
            arena.deinit();
            parent.destroy(arena);
            self.arena = null;
        }
    }

    /// Combine independently checked bodies without borrowing their temporary
    /// buffers. Repeated observations retain the conservative initialization join.
    pub fn merge(self: *Annotations, allocator: std.mem.Allocator, source: *const Annotations) !void {
        var writes = source.writes.iterator();
        while (writes.next()) |entry| try self.recordInitialization(allocator, entry.key_ptr.*, entry.value_ptr.*);
        if (source.calls.count() == 0 and source.virtual_calls.count() == 0) return;
        var copy: @import("fact_snapshot.zig").Copy = .{ .allocator = try self.storageAllocator(allocator), .scratch = allocator };
        defer copy.deinit();
        var calls = source.calls.iterator();
        while (calls.next()) |entry| try self.calls.put(allocator, entry.key_ptr.*, try copy.value(CallEffects, entry.value_ptr.*));
        var virtuals = source.virtual_calls.iterator();
        while (virtuals.next()) |entry| try self.virtual_calls.put(allocator, entry.key_ptr.*, try copy.value(CallEffects, entry.value_ptr.*));
    }

    pub fn clone(self: *const Annotations, allocator: std.mem.Allocator) !Annotations {
        var result: Annotations = .{};
        errdefer result.deinit(allocator);
        result.writes = try self.writes.clone(allocator);
        result.calls = try self.calls.clone(allocator);
        result.virtual_calls = try self.virtual_calls.clone(allocator);
        if (result.calls.count() != 0 or result.virtual_calls.count() != 0) {
            var copy: @import("fact_snapshot.zig").Copy = .{ .allocator = try result.storageAllocator(allocator), .scratch = allocator };
            defer copy.deinit();
            var calls = result.calls.valueIterator();
            while (calls.next()) |effects| effects.* = try copy.value(CallEffects, effects.*);
            var virtuals = result.virtual_calls.valueIterator();
            while (virtuals.next()) |effects| effects.* = try copy.value(CallEffects, effects.*);
        }
        result.published = true;
        return result;
    }

    pub fn deinit(self: *Annotations, allocator: std.mem.Allocator) void {
        self.writes.deinit(allocator);
        self.calls.deinit(allocator);
        self.virtual_calls.deinit(allocator);
        if (self.arena) |arena| {
            arena.deinit();
            allocator.destroy(arena);
        }
        self.* = .{};
    }
};

test "initialization annotations join incoming states and preserve independent publications" {
    const a = std.testing.allocator;
    var plan: Annotations = .{};
    defer plan.deinit(a);
    const write: g.GlobalNodeId = @enumFromInt(0);
    try std.testing.expect(!plan.initializes(write));
    try plan.recordInitialization(a, write, true);
    try std.testing.expect(plan.initializes(write));
    var published = try plan.clone(a);
    defer published.deinit(a);
    try plan.recordInitialization(a, write, false);
    try plan.recordInitialization(a, write, true);
    try std.testing.expect(!plan.initializes(write));
    try std.testing.expect(published.initializes(write));
    plan.clear(a);
    try plan.recordInitialization(a, write, true);
    try plan.constrainInitialization(a, write, false);
    try std.testing.expect(!plan.initializes(write));
}

fn publishCallEffects(a: std.mem.Allocator) !void {
    var builder: Annotations = .{};
    defer builder.deinit(a);
    const storage = try builder.storageAllocator(a);
    const targets = try storage.dupe(g.GlobalNodeId, &.{@enumFromInt(3)});
    const projections = try storage.dupe(@import("../primitives/schema.zig").CleanupInputProjection, &.{ .{ .field = 1 }, .{ .element = 2 } });
    const parents = try storage.dupe(u32, &.{4});
    const outcomes = try storage.dupe(@import("../primitives/schema.zig").OutcomeCleanup(g.Ids), &.{.{
        .place = @enumFromInt(3),
        .captured_input = .{ .argument_index = 2, .projections = projections },
        .parent_variants = parents,
        .output_index = 0,
        .variant_index = 1,
    }});
    const effects: CallEffects = .{ .consumed_auto_deinits = targets, .outcome_cleanups = outcomes };
    try builder.setCall(a, @enumFromInt(7), effects);
    try builder.setVirtualCall(a, @enumFromInt(5), effects);
    var published = try builder.clone(a);
    defer published.deinit(a);
    builder.clear(a);
    const call_effects = published.call(@enumFromInt(7));
    const virtual_effects = published.virtualCall(@enumFromInt(5));
    try std.testing.expectEqual(@as(g.GlobalNodeId, @enumFromInt(3)), call_effects.consumed_auto_deinits[0]);
    try std.testing.expectEqual(@as(u32, 4), call_effects.outcome_cleanups[0].parent_variants[0]);
    try std.testing.expectEqual(@as(u32, 2), virtual_effects.outcome_cleanups[0].captured_input.?.argument_index);
    try std.testing.expectEqual(@as(u32, 1), virtual_effects.outcome_cleanups[0].captured_input.?.projections[0].field);
    try std.testing.expectEqual(@as(u64, 2), virtual_effects.outcome_cleanups[0].captured_input.?.projections[1].element);
}

test "call annotations own nested effects and release failed publications" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishCallEffects, .{});
}
