//! Mutable facts for one Safety path. Values/projection slices are immutable
//! and borrow the proof allocator; cloning copies only the mutable tables.
//! Storage writes retire projected facts and choice refinements together.
//! This state owns no semantic graph, inference engine or diagnostic policy.
const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const facts = @import("facts.zig");
const primitives = @import("../primitives/schema.zig");
const value_state = @import("value_state.zig");
const fact_snapshot = @import("fact_snapshot.zig");

pub const StorageCapabilityState = enum {
    absent,
    available,
    conditional,
    maybe_consumed,
    consumed,

    pub fn join(left: StorageCapabilityState, right: StorageCapabilityState) StorageCapabilityState {
        // A path where the acquisition never happened says nothing about its
        // consumption. In particular, absence must not revive consumed storage.
        if (left == .absent) return right;
        if (right == .absent) return left;
        return if (left == right) left else .maybe_consumed;
    }
};
pub const OwnershipEdge = struct { owner: facts.ValidityRootId, owned: facts.ValidityRootId };
pub const StorageGeneration = struct {
    storage: facts.Place,
    generation: facts.ValidityRootId,
    needs_current_generation: bool = false,
};
pub const OpaqueStorage = struct {
    storage: facts.Place,
    hidden_dependencies: []const facts.ValidityRootId,
    outcome_guard: u64 = 0,
    // Identity only: a moved owner's slot can disappear before output
    // checks. These roots associate hidden contents without keeping any
    // resource or lexical generation alive.
    owner_roots: []const facts.ValidityRootId = &.{},
};
pub const ChoiceActive = struct { storage: facts.Place, variant_index: u32 };
pub const ChoiceRejected = struct { storage: facts.Place, variant_index: u32 };
pub const ChoiceTemporaryActive = struct { expression: graph_mod.GlobalNodeId, variant_index: u32 };

pub const SymbolicPointeeState = struct {
    identity: facts.SymbolicPointeeId,
    ty: ?graph_mod.GlobalTypeId = null,
    initializedness: value_state.Initializedness,
    // Unknown referents keep storage validity separate from the current
    // value incarnation. Neither identity asserts disjointness of inputs.
    backing: ?facts.ValidityRootId = null,
    generation: ?facts.ValidityRootId = null,
};

pub const SymbolicStoredValue = struct {
    identity: facts.SymbolicPointeeId,
    value: facts.ValueFacts,
    definite: bool = true,
};

pub const State = struct {
    tracker: facts.Tracker,
    places: std.array_list.Managed(facts.PlaceFacts),
    symbolic_pointees: std.array_list.Managed(SymbolicPointeeState),
    // Sparse value facts are separate from slot identity and initialization.
    // Ordinary scalar slots need no entry; immutable aggregates share facts.
    symbolic_values: std.array_list.Managed(SymbolicStoredValue),
    storage_capabilities: std.array_list.Managed(StorageCapabilityState),
    ownership_edges: std.array_list.Managed(OwnershipEdge),
    storage_generations: std.array_list.Managed(StorageGeneration),
    lexical_storage_generations: std.array_list.Managed(facts.ValidityRootId),
    opaque_storages: std.array_list.Managed(OpaqueStorage),
    choice_active: std.array_list.Managed(ChoiceActive),
    choice_rejected: std.array_list.Managed(ChoiceRejected),
    choice_temporary_active: std.array_list.Managed(ChoiceTemporaryActive),
    reachable: bool = true,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .tracker = facts.Tracker.init(allocator),
            .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
            .symbolic_pointees = std.array_list.Managed(SymbolicPointeeState).init(allocator),
            .symbolic_values = std.array_list.Managed(SymbolicStoredValue).init(allocator),
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

    pub fn deinit(self: *State) void {
        self.tracker.deinit();
        self.places.deinit();
        self.symbolic_pointees.deinit();
        self.symbolic_values.deinit();
        self.storage_capabilities.deinit();
        self.ownership_edges.deinit();
        self.storage_generations.deinit();
        self.lexical_storage_generations.deinit();
        self.opaque_storages.deinit();
        self.choice_active.deinit();
        self.choice_rejected.deinit();
        self.choice_temporary_active.deinit();
    }

    pub fn clone(self: *const State, allocator: std.mem.Allocator) !State {
        var out = State.init(allocator);
        errdefer out.deinit();
        out.tracker.namespace = self.tracker.namespace;
        try out.tracker.roots.appendSlice(self.tracker.roots.items);
        inline for (@typeInfo(State).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "tracker") or std.mem.eql(u8, field.name, "reachable")) continue;
            try @field(out, field.name).appendSlice(@field(self, field.name).items);
        }
        out.reachable = self.reachable;
        return out;
    }

    pub fn elementCount(self: *const State) usize {
        var count = self.tracker.roots.items.len;
        inline for (@typeInfo(State).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "tracker") or std.mem.eql(u8, field.name, "reachable")) continue;
            count += @field(self, field.name).items.len;
        }
        return count;
    }

    pub fn snapshotFacts(self: *State, copy: *fact_snapshot.Copy) !void {
        inline for (@typeInfo(State).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "tracker") or std.mem.eql(u8, field.name, "reachable")) continue;
            for (@field(self, field.name).items) |*item| item.* = try copy.value(@TypeOf(item.*), item.*);
        }
    }

    /// The new allocator must own the same buffers, e.g. after moving an arena.
    pub fn rebindAllocator(self: *State, allocator: std.mem.Allocator) void {
        self.tracker.allocator = allocator;
        self.tracker.roots.allocator = allocator;
        inline for (@typeInfo(State).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "tracker") or std.mem.eql(u8, field.name, "reachable")) continue;
            @field(self, field.name).allocator = allocator;
        }
    }

    pub fn establishCapability(self: *State) !facts.StorageCapabilityId {
        const index = if (self.tracker.namespace) |namespace| namespace.next_capability_id else self.storage_capabilities.items.len;
        if (index >= std.math.maxInt(u32)) return error.SafetyCapabilityIdentityLimit;
        try self.storage_capabilities.ensureTotalCapacity(index + 1);
        while (self.storage_capabilities.items.len <= index)
            self.storage_capabilities.appendAssumeCapacity(.absent);
        self.storage_capabilities.items[index] = .available;
        if (self.tracker.namespace) |namespace| namespace.next_capability_id += 1;
        return @enumFromInt(index);
    }

    pub fn capabilityState(self: *const State, id: facts.StorageCapabilityId) StorageCapabilityState {
        const index = @intFromEnum(id);
        return if (index < self.storage_capabilities.items.len) self.storage_capabilities.items[index] else .absent;
    }

    pub fn joinCapabilities(self: *State, left: *const State, right: *const State) !void {
        std.debug.assert(self.storage_capabilities.items.len == 0);
        const count = @max(left.storage_capabilities.items.len, right.storage_capabilities.items.len);
        try self.storage_capabilities.ensureTotalCapacity(count);
        for (0..count) |index| {
            const id: facts.StorageCapabilityId = @enumFromInt(index);
            self.storage_capabilities.appendAssumeCapacity(.join(left.capabilityState(id), right.capabilityState(id)));
        }
    }

    pub fn consumeCapability(self: *State, id: facts.StorageCapabilityId, definite: bool) void {
        const index = @intFromEnum(id);
        if (index >= self.storage_capabilities.items.len) return;
        const entry = &self.storage_capabilities.items[index];
        if (entry.* != .absent and entry.* != .consumed)
            entry.* = if (definite) .consumed else .maybe_consumed;
    }

    pub fn setPlace(self: *State, storage: facts.Place, initializedness: value_state.Initializedness, value: facts.ValueFacts) !void {
        self.invalidateChoiceRefinements(storage);
        // Replacing an aggregate invalidates facts recorded for its old
        // projections. Otherwise a later read can observe stale facts from a
        // preceding iteration rather than the newly assigned aggregate.
        var index: usize = 0;
        while (index < self.places.items.len) {
            const candidate = self.places.items[index].storage;
            if (!candidate.eql(storage) and storage.isPrefixOf(candidate)) {
                _ = self.places.orderedRemove(index);
            } else index += 1;
        }
        var stored = false;
        for (self.places.items) |*entry| if (entry.storage.eql(storage)) {
            entry.initializedness = initializedness;
            if (initializedness != .moved) entry.moved_at = null;
            entry.value = value;
            stored = true;
            break;
        };
        if (!stored)
            try self.places.append(.{ .storage = storage, .initializedness = initializedness, .value = value });
        if (initializedness == .initialized)
            try self.recordKnownChoiceVariants(storage, value);
    }

    pub fn recordKnownChoiceVariants(
        self: *State,
        storage: facts.Place,
        value: facts.ValueFacts,
    ) !void {
        if (value.known_choice_variant) |variant_index|
            self.setActiveVariant(storage, variant_index);
        for (value.fields) |field|
            try self.recordKnownChoiceVariants(
                try self.project(storage, .{ .field = field.index }),
                field.value.*,
            );
    }

    pub fn getPlace(self: *State, storage: facts.Place) ?*facts.PlaceFacts {
        for (self.places.items) |*entry| if (entry.storage.eql(storage)) return entry;
        return null;
    }

    pub fn setActiveVariant(self: *State, storage: facts.Place, index: u32) void {
        for (self.choice_active.items) |*entry| if (entry.storage.eql(storage)) {
            entry.variant_index = index;
            self.clearRejectedVariant(storage, index);
            return;
        };
        self.choice_active.append(.{ .storage = storage, .variant_index = index }) catch {};
        self.clearRejectedVariant(storage, index);
    }

    pub fn clearActiveVariant(self: *State, storage: facts.Place, index: u32) void {
        var cursor: usize = 0;
        while (cursor < self.choice_active.items.len) {
            const entry = self.choice_active.items[cursor];
            if (entry.storage.eql(storage) and entry.variant_index == index) {
                _ = self.choice_active.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    pub fn setTemporaryActiveVariant(self: *State, expression: graph_mod.GlobalNodeId, index: u32) !void {
        for (self.choice_temporary_active.items) |*entry| {
            if (entry.expression != expression) continue;
            entry.variant_index = index;
            return;
        }
        try self.choice_temporary_active.append(.{ .expression = expression, .variant_index = index });
    }

    pub fn temporaryVariantActive(self: *const State, expression: graph_mod.GlobalNodeId, index: u32) bool {
        for (self.choice_temporary_active.items) |entry|
            if (entry.expression == expression) return entry.variant_index == index;
        return false;
    }

    pub fn setRejectedVariant(self: *State, storage: facts.Place, index: u32) void {
        for (self.choice_rejected.items) |entry|
            if (entry.storage.eql(storage) and entry.variant_index == index) return;
        self.choice_rejected.append(.{ .storage = storage, .variant_index = index }) catch {};
    }

    pub fn clearRejectedVariant(self: *State, storage: facts.Place, index: u32) void {
        var cursor: usize = 0;
        while (cursor < self.choice_rejected.items.len) {
            const entry = self.choice_rejected.items[cursor];
            if (entry.storage.eql(storage) and entry.variant_index == index) {
                _ = self.choice_rejected.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    pub fn variantRejected(self: *const State, storage: facts.Place, index: u32) bool {
        for (self.choice_rejected.items) |entry|
            if (entry.storage.eql(storage) and entry.variant_index == index) return true;
        return false;
    }

    pub fn invalidateChoiceRefinements(self: *State, storage: facts.Place) void {
        var cursor: usize = 0;
        while (cursor < self.choice_active.items.len) {
            if (storage.isPrefixOf(self.choice_active.items[cursor].storage)) {
                _ = self.choice_active.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
        cursor = 0;
        while (cursor < self.choice_rejected.items.len) {
            if (storage.isPrefixOf(self.choice_rejected.items[cursor].storage)) {
                _ = self.choice_rejected.orderedRemove(cursor);
            } else {
                cursor += 1;
            }
        }
    }

    pub fn activeVariant(self: *const State, storage: facts.Place) ?u32 {
        for (self.choice_active.items) |entry|
            if (entry.storage.eql(storage)) return entry.variant_index;
        return null;
    }

    fn project(self: *State, base: facts.Place, projection: facts.Projection) !facts.Place {
        const projections = try self.tracker.allocator.alloc(facts.Projection, base.projections.len + 1);
        @memcpy(projections[0..base.projections.len], base.projections);
        projections[base.projections.len] = projection;
        return .{ .root = base.root, .projections = projections };
    }

    pub fn findPlace(self: *const State, storage: facts.Place) ?*const facts.PlaceFacts {
        for (self.places.items) |*entry| if (entry.storage.eql(storage)) return entry;
        return null;
    }

    pub fn initializednessAtPlace(
        self: *const State,
        storage: facts.Place,
    ) value_state.Initializedness {
        var projection_count = storage.projections.len;
        while (true) {
            const prefix = facts.Place{ .root = storage.root, .projections = storage.projections[0..projection_count] };
            if (self.findPlace(prefix)) |stored| return stored.initializedness;
            if (projection_count == 0) return .initialized;
            projection_count -= 1;
        }
    }
    pub fn markMoved(self: *State, storage: facts.Place, value: facts.ValueFacts, source: primitives.SourceRef) !void {
        try self.setPlace(storage, .moved, value);
        if (self.getPlace(storage)) |place| place.moved_at = source;
    }
    pub fn variantActive(self: *State, storage: facts.Place, index: u32) bool {
        return if (self.activeVariant(storage)) |active| active == index else false;
    }
    pub fn refreshStorageGeneration(self: *State, storage: facts.Place) !void {
        var index: usize = 0;
        var replaced = false;
        while (index < self.storage_generations.items.len) {
            const entry = self.storage_generations.items[index];
            if (!storage.isPrefixOf(entry.storage)) {
                index += 1;
                continue;
            }
            self.tracker.end(entry.generation);
            if (entry.storage.eql(storage)) {
                self.storage_generations.items[index].generation = try self.tracker.establish(.fresh);
                self.storage_generations.items[index].needs_current_generation = false;
                replaced = true;
                index += 1;
            } else {
                _ = self.storage_generations.orderedRemove(index);
            }
        }
        if (!replaced)
            try self.storage_generations.append(.{ .storage = storage, .generation = try self.tracker.establish(.fresh) });
    }
    pub fn beginLexicalStorage(self: *State, storage: facts.Place) !void {
        for (self.storage_generations.items) |entry| {
            if (!storage.isPrefixOf(entry.storage)) continue;
            try self.refreshStorageGeneration(storage);
            return;
        }
    }
};

test "Safety place replacement retires descendants and refinements while preserving siblings" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const parent: facts.Place = .{ .root = @enumFromInt(0) };
    const child: facts.Place = .{ .root = parent.root, .projections = &.{.{ .field = 0 }} };
    const sibling: facts.Place = .{ .root = @enumFromInt(1) };
    try state.setPlace(child, .initialized, .{ .known_choice_variant = 2 });
    try state.setPlace(sibling, .initialized, .{ .known_choice_variant = 3 });
    state.setRejectedVariant(child, 4);
    state.setRejectedVariant(sibling, 5);
    try state.markMoved(parent, .{}, .{ .file_index = 0, .offset = 7 });
    try std.testing.expectEqual(null, state.findPlace(child));
    try std.testing.expectEqual(null, state.activeVariant(child));
    try std.testing.expect(!state.variantRejected(child, 4));
    try std.testing.expectEqual(@as(?u32, 3), state.activeVariant(sibling));
    try std.testing.expect(state.variantRejected(sibling, 5));
    try std.testing.expectEqual(@as(u32, 7), state.findPlace(parent).?.moved_at.?.offset);
    try state.setPlace(parent, .initialized, .{ .known_choice_variant = 1 });
    try std.testing.expectEqual(null, state.findPlace(parent).?.moved_at);
    try std.testing.expectEqual(@as(?u32, 1), state.activeVariant(parent));
    try std.testing.expectEqual(.initialized, state.initializednessAtPlace(child));
}

test "Safety storage replacement ends projected generations without touching siblings" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const parent: facts.Place = .{ .root = @enumFromInt(0) };
    const child: facts.Place = .{ .root = parent.root, .projections = &.{.{ .field = 0 }} };
    const sibling: facts.Place = .{ .root = @enumFromInt(1) };
    try state.refreshStorageGeneration(parent);
    try state.refreshStorageGeneration(child);
    try state.refreshStorageGeneration(sibling);
    const old_parent = state.storage_generations.items[0].generation;
    const old_child = state.storage_generations.items[1].generation;
    const live_sibling = state.storage_generations.items[2].generation;
    try state.refreshStorageGeneration(parent);
    try std.testing.expect(!state.tracker.isAlive(old_parent));
    try std.testing.expect(!state.tracker.isAlive(old_child));
    try std.testing.expect(state.tracker.isAlive(live_sibling));
    try std.testing.expectEqual(@as(usize, 2), state.storage_generations.items.len);
    try std.testing.expect(state.tracker.isAlive(state.storage_generations.items[0].generation));
}

fn cloneAllocationFailures(allocator: std.mem.Allocator) !void {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const storage: facts.Place = .{ .root = @enumFromInt(0) };
    const root = try state.tracker.establish(.fresh);
    try state.setPlace(storage, .initialized, .{});
    try state.symbolic_pointees.append(.{ .identity = @enumFromInt(0), .initializedness = .initialized });
    try state.symbolic_values.append(.{ .identity = @enumFromInt(0), .value = .{} });
    try state.storage_capabilities.append(.available);
    try state.ownership_edges.append(.{ .owner = root, .owned = root });
    try state.storage_generations.append(.{ .storage = storage, .generation = root });
    try state.lexical_storage_generations.append(root);
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{} });
    state.setActiveVariant(storage, 2);
    state.setRejectedVariant(storage, 3);
    try state.setTemporaryActiveVariant(@enumFromInt(0), 2);
    state.reachable = false;
    var copied = try state.clone(allocator);
    defer copied.deinit();
    try std.testing.expectEqual(state.elementCount(), copied.elementCount());
    try std.testing.expect(!copied.reachable);
    copied.getPlace(storage).?.initializedness = .moved;
    copied.setActiveVariant(storage, 4);
    copied.tracker.end(root);
    try std.testing.expectEqual(.initialized, state.findPlace(storage).?.initializedness);
    try std.testing.expectEqual(@as(?u32, 2), state.activeVariant(storage));
    try std.testing.expect(state.tracker.isAlive(root));
}

test "Safety state clones own independent tables and release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationFailures, .{});
}

test "Safety acquisitions on sibling branches retain distinct identities through joins" {
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(std.testing.allocator);
    var initial = State.init(std.testing.allocator);
    defer initial.deinit();
    initial.tracker.namespace = &namespace;
    const shared = try initial.establishCapability();
    var left = try initial.clone(std.testing.allocator);
    defer left.deinit();
    var right = try initial.clone(std.testing.allocator);
    defer right.deinit();
    const first = try left.establishCapability();
    const second = try right.establishCapability();
    try std.testing.expect(first != second);
    try std.testing.expectEqual(.absent, right.capabilityState(first));
    try std.testing.expectEqual(.absent, left.capabilityState(second));
    left.consumeCapability(first, true);
    right.consumeCapability(shared, false);
    var joined = State.init(std.testing.allocator);
    defer joined.deinit();
    try joined.joinCapabilities(&left, &right);
    try std.testing.expectEqual(.consumed, joined.capabilityState(first));
    try std.testing.expectEqual(.available, joined.capabilityState(second));
    try std.testing.expectEqual(.maybe_consumed, joined.capabilityState(shared));
    joined.consumeCapability(second, true);
    try std.testing.expectEqual(.consumed, joined.capabilityState(second));
    try std.testing.expectEqual(.consumed, joined.capabilityState(first));
}

test "Safety capability joins preserve every present-path consumption state" {
    const tags = std.meta.tags(StorageCapabilityState);
    for (tags) |left| for (tags) |right| {
        const result = StorageCapabilityState.join(left, right);
        try std.testing.expectEqual(result, StorageCapabilityState.join(right, left));
        try std.testing.expectEqual(left, StorageCapabilityState.join(left, left));
        if (left == .absent) {
            try std.testing.expectEqual(right, result);
        } else if (right == .absent or left == right) {
            try std.testing.expectEqual(left, result);
        } else try std.testing.expectEqual(.maybe_consumed, result);
    };
}

fn capabilityAllocationFailure(allocator: std.mem.Allocator) !void {
    var namespace: facts.Tracker.RootNamespace = .{ .next_capability_id = 3 };
    var state = State.init(allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const id = state.establishCapability() catch |err| {
        try std.testing.expectEqual(@as(u32, 3), namespace.next_capability_id);
        try std.testing.expectEqual(@as(usize, 0), state.storage_capabilities.items.len);
        return err;
    };
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(id));
    try std.testing.expectEqual(@as(u32, 4), namespace.next_capability_id);
    for (state.storage_capabilities.items[0..3]) |entry| try std.testing.expectEqual(.absent, entry);
}

test "Safety capability allocation failure preserves namespace and exhaustion cannot wrap" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, capabilityAllocationFailure, .{});
    var namespace: facts.Tracker.RootNamespace = .{ .next_capability_id = std.math.maxInt(u32) };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    try std.testing.expectError(error.SafetyCapabilityIdentityLimit, state.establishCapability());
    try std.testing.expectEqual(@as(usize, 0), state.storage_capabilities.items.len);
}
