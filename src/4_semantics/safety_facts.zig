const std = @import("std");
const place = @import("place.zig");
const value_state = @import("value_state.zig");

pub const RootId = enum(u32) { _ };

pub const Root = struct {
    id: RootId,
    state: enum { alive, dead } = .alive,
};

pub const ReferenceDependency = struct {
    root: RootId,
};

pub const CleanupResponsibility = struct {
    root: RootId,
};

/// Facts travel with values. Dependencies and cleanup responsibilities are
/// intentionally separate: copying a reference copies only its dependencies,
/// while moving a value transfers both lists.
pub const ValueFacts = struct {
    dependencies: []const ReferenceDependency = &.{},
    cleanup_responsibilities: []const CleanupResponsibility = &.{},

    pub fn referenceCopy(self: ValueFacts) ValueFacts {
        return .{ .dependencies = self.dependencies };
    }
};

pub const PlaceFacts = struct {
    storage: place.Place,
    initializedness: value_state.Initializedness = .initialized,
    value: ValueFacts = .{},
};

pub const RootEstablishment = union(enum) {
    fresh,
    inherit: RootId,
};

pub const OutputEffect = union(enum) {
    independent,
    depends_on_input: u32,
    fresh,
    transfers_input: u32,
};

pub const FunctionSummary = struct {
    outputs: []const OutputEffect = &.{},
    ends_input_roots: []const u32 = &.{},
    deinitializes_inputs: []const u32 = &.{},
    invalidates_dynamic_slots: []const u32 = &.{},
};

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    roots: std.array_list.Managed(Root),

    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .allocator = allocator, .roots = std.array_list.Managed(Root).init(allocator) };
    }

    pub fn deinit(self: *Tracker) void {
        self.roots.deinit();
    }

    pub fn establish(self: *Tracker, rooting: RootEstablishment) !RootId {
        return switch (rooting) {
            .inherit => |root| root,
            .fresh => blk: {
                const id: RootId = @enumFromInt(self.roots.items.len);
                try self.roots.append(.{ .id = id });
                break :blk id;
            },
        };
    }

    pub fn end(self: *Tracker, id: RootId) void {
        self.roots.items[@intFromEnum(id)].state = .dead;
    }

    pub fn isAlive(self: *const Tracker, id: RootId) bool {
        return self.roots.items[@intFromEnum(id)].state == .alive;
    }

    pub fn dependenciesAreAlive(self: *const Tracker, facts: ValueFacts) bool {
        for (facts.dependencies) |dependency| {
            if (!self.isAlive(dependency.root)) return false;
        }
        return true;
    }

    pub fn moveValue(source: *PlaceFacts, destination: *PlaceFacts) void {
        destination.initializedness = .initialized;
        destination.value = source.value;
        source.initializedness = .moved;
        source.value = .{};
    }

    pub fn deinitialize(place_facts: *PlaceFacts) void {
        place_facts.initializedness = .deinitialized;
        place_facts.value = .{};
    }
};

test "fresh roots are independent and inherit preserves identity" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const first = try tracker.establish(.fresh);
    const second = try tracker.establish(.fresh);
    try std.testing.expect(first != second);
    try std.testing.expectEqual(first, try tracker.establish(.{ .inherit = first }));
    tracker.end(first);
    try std.testing.expect(!tracker.isAlive(first));
    try std.testing.expect(tracker.isAlive(second));
}

test "move transfers responsibilities without changing root identity" {
    const binding: *const @import("semantic_graph.zig").BindingDeclaration = undefined;
    const storage = place.Place{ .root = binding };
    const root: RootId = @enumFromInt(3);
    var source = PlaceFacts{
        .storage = storage,
        .value = .{
            .dependencies = &.{.{ .root = root }},
            .cleanup_responsibilities = &.{.{ .root = root }},
        },
    };
    var destination = PlaceFacts{ .storage = storage, .initializedness = .deinitialized };
    Tracker.moveValue(&source, &destination);
    try std.testing.expectEqual(value_state.Initializedness.moved, source.initializedness);
    try std.testing.expectEqual(root, destination.value.dependencies[0].root);
    try std.testing.expectEqual(root, destination.value.cleanup_responsibilities[0].root);
}

test "copying a reference does not duplicate cleanup responsibility" {
    const root: RootId = @enumFromInt(7);
    const original = ValueFacts{
        .dependencies = &.{.{ .root = root }},
        .cleanup_responsibilities = &.{.{ .root = root }},
    };
    const copied = original.referenceCopy();
    try std.testing.expectEqual(root, copied.dependencies[0].root);
    try std.testing.expectEqual(@as(usize, 0), copied.cleanup_responsibilities.len);
}
