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

    pub fn join(self: SymbolicPointeeState, other: ?SymbolicPointeeState) SymbolicPointeeState {
        var result = self;
        if (other) |opposite| {
            std.debug.assert(self.identity == opposite.identity);
            if (self.initializedness != opposite.initializedness) result.initializedness = .maybe_initialized;
            if (self.backing != opposite.backing) result.backing = null;
            if (self.generation != opposite.generation) result.generation = null;
        } else result.initializedness = .maybe_initialized;
        return result;
    }
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
    storage_generations: std.array_list.Managed(StorageGeneration),
    lexical_storage_generations: std.array_list.Managed(facts.ValidityRootId),
    opaque_storages: std.array_list.Managed(OpaqueStorage),
    choice_active: std.array_list.Managed(ChoiceActive),
    choice_rejected: std.array_list.Managed(ChoiceRejected),
    choice_temporary_active: std.array_list.Managed(ChoiceTemporaryActive),
    reachable: bool = true,

    pub fn init(allocator: std.mem.Allocator) State {
        return initWithAllocators(allocator, allocator);
    }

    /// Immutable facts and shared namespace entries outlive disposable branch
    /// tables. Keeping their allocators separate lets cloned tables be freed
    /// without invalidating facts borrowed by another state or publication.
    pub fn initWithAllocators(fact_allocator: std.mem.Allocator, allocator: std.mem.Allocator) State {
        var tracker = facts.Tracker.init(fact_allocator);
        tracker.roots.allocator = allocator;
        return .{
            .tracker = tracker,
            .places = std.array_list.Managed(facts.PlaceFacts).init(allocator),
            .symbolic_pointees = std.array_list.Managed(SymbolicPointeeState).init(allocator),
            .symbolic_values = std.array_list.Managed(SymbolicStoredValue).init(allocator),
            .storage_capabilities = std.array_list.Managed(StorageCapabilityState).init(allocator),
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
        self.storage_generations.deinit();
        self.lexical_storage_generations.deinit();
        self.opaque_storages.deinit();
        self.choice_active.deinit();
        self.choice_rejected.deinit();
        self.choice_temporary_active.deinit();
    }

    pub fn clone(self: *const State, allocator: std.mem.Allocator) !State {
        return self.cloneWithAllocators(allocator, allocator);
    }

    pub fn cloneWithAllocators(self: *const State, fact_allocator: std.mem.Allocator, allocator: std.mem.Allocator) !State {
        var out = State.initWithAllocators(fact_allocator, allocator);
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

    pub fn symbolicPointee(self: *const State, identity: facts.SymbolicPointeeId) ?SymbolicPointeeState {
        for (self.symbolic_pointees.items) |entry| if (entry.identity == identity) return entry;
        return null;
    }

    pub fn setSymbolicInitializedness(self: *State, identity: facts.SymbolicPointeeId, initializedness: value_state.Initializedness) void {
        for (self.symbolic_pointees.items) |*entry| if (entry.identity == identity) {
            // Availability alone never renews a reference's observed incarnation.
            entry.initializedness = initializedness;
            return;
        };
    }

    pub fn initializeLiveSymbolicTargets(self: *State, pointer: facts.ValueFacts) void {
        for (pointer.symbolic_pointees) |identity| {
            const entry = self.symbolicPointee(identity) orelse continue;
            if (entry.generation) |generation| if (self.tracker.isAlive(generation))
                self.setSymbolicInitializedness(identity, .initialized);
        }
    }

    pub fn exactSymbolicValue(self: *const State, identity: facts.SymbolicPointeeId) ?SymbolicStoredValue {
        for (self.symbolic_values.items) |stored| if (stored.identity == identity) return stored;
        return null;
    }

    /// The checker prepares weak-write merges. Strong writes retire descendant
    /// slot facts, stopping at dereferences into separately referenced storage.
    pub fn setSymbolicValue(self: *State, next: SymbolicStoredValue, strong: bool, retain_empty: bool) !void {
        if (strong) {
            var kept: usize = 0;
            for (self.symbolic_values.items) |stored| {
                const child = stored.identity;
                if (child != next.identity and self.symbolicStorageDescendsFrom(child, next.identity)) continue;
                self.symbolic_values.items[kept] = stored;
                kept += 1;
            }
            self.symbolic_values.shrinkRetainingCapacity(kept);
        }
        for (self.symbolic_values.items) |*stored| if (stored.identity == next.identity) {
            stored.* = next;
            return;
        };
        if (retain_empty or !facts.isEmptyValue(next.value)) try self.symbolic_values.append(next);
    }

    pub fn joinSymbolicPointees(self: *State, left: *const State, right: *const State) !void {
        std.debug.assert(self.symbolic_pointees.items.len == 0);
        for (left.symbolic_pointees.items) |entry|
            try self.symbolic_pointees.append(entry.join(right.symbolicPointee(entry.identity) orelse right.initialProjectedPointee(entry.identity)));
        for (right.symbolic_pointees.items) |entry| {
            if (left.symbolicPointee(entry.identity) != null) continue;
            try self.symbolic_pointees.append(entry.join(left.initialProjectedPointee(entry.identity)));
        }
    }

    pub fn setPlace(self: *State, storage: facts.Place, initializedness: value_state.Initializedness, value: facts.ValueFacts) !void {
        self.invalidateChoiceRefinements(storage);
        // Replacing an aggregate invalidates facts recorded for its old
        // projections. Otherwise a later read can observe stale facts from a
        // preceding iteration rather than the newly assigned aggregate.
        var kept: usize = 0;
        for (self.places.items) |entry| {
            if (!entry.storage.eql(storage) and storage.isPrefixOf(entry.storage)) continue;
            self.places.items[kept] = entry;
            kept += 1;
        }
        self.places.shrinkRetainingCapacity(kept);
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
            try self.setActiveVariant(storage, variant_index);
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

    pub fn setActiveVariant(self: *State, storage: facts.Place, index: u32) !void {
        for (self.choice_active.items) |*entry| if (entry.storage.eql(storage)) {
            entry.variant_index = index;
            self.clearRejectedVariant(storage, index);
            return;
        };
        try self.choice_active.append(.{ .storage = storage, .variant_index = index });
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

    pub fn setRejectedVariant(self: *State, storage: facts.Place, index: u32) !void {
        for (self.choice_rejected.items) |entry|
            if (entry.storage.eql(storage) and entry.variant_index == index) return;
        try self.choice_rejected.append(.{ .storage = storage, .variant_index = index });
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
        // Stable compaction retires a whole subtree without repeatedly moving
        // every retained sibling after each removed projection.
        inline for (.{ "choice_active", "choice_rejected" }) |name| {
            const entries = &@field(self, name);
            var kept: usize = 0;
            for (entries.items) |entry| {
                if (storage.isPrefixOf(entry.storage)) continue;
                entries.items[kept] = entry;
                kept += 1;
            }
            entries.shrinkRetainingCapacity(kept);
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
    // Fact slices are immutable and may be shared by branch snapshots. Reuse
    // the old slice when possible; only a failed unpublished union is freed.
    fn unionRoots(a: std.mem.Allocator, previous: []const facts.ValidityRootId, additions: []const facts.ValidityRootId) ![]const facts.ValidityRootId {
        var count = previous.len;
        for (additions, 0..) |root, index| {
            if (std.mem.indexOfScalar(facts.ValidityRootId, previous, root) != null or
                std.mem.indexOfScalar(facts.ValidityRootId, additions[0..index], root) != null) continue;
            count += 1;
        }
        if (count == previous.len) return previous;
        const result = try a.alloc(facts.ValidityRootId, count);
        @memcpy(result[0..previous.len], previous);
        var used = previous.len;
        for (additions) |root| {
            if (std.mem.indexOfScalar(facts.ValidityRootId, result[0..used], root) != null) continue;
            result[used] = root;
            used += 1;
        }
        return result;
    }

    pub fn mergeOpaqueStorage(self: *State, storage: facts.Place, dependencies: []const facts.ValidityRootId, owners: []const facts.ValidityRootId) !void {
        const existing = for (self.opaque_storages.items) |*entry| {
            if (entry.storage.eql(storage)) break entry;
        } else @as(?*OpaqueStorage, null);
        if (existing == null) try self.opaque_storages.ensureUnusedCapacity(1);
        const previous: OpaqueStorage = if (existing) |entry| entry.* else .{ .storage = storage, .hidden_dependencies = &.{} };
        const a = self.tracker.allocator;
        const hidden = try unionRoots(a, previous.hidden_dependencies, dependencies);
        errdefer if (hidden.ptr != previous.hidden_dependencies.ptr) a.free(hidden);
        const combined = try unionRoots(a, previous.owner_roots, owners);
        const next: OpaqueStorage = .{ .storage = storage, .hidden_dependencies = hidden, .owner_roots = combined };
        if (existing) |entry| entry.* = next else self.opaque_storages.appendAssumeCapacity(next);
    }

    pub fn mergeOpaqueOwnerRoots(self: *State, storage: facts.Place, roots: []const facts.ValidityRootId) !void {
        if (roots.len == 0) return;
        for (self.opaque_storages.items) |*entry| {
            if (!entry.storage.eql(storage)) continue;
            entry.owner_roots = try unionRoots(self.tracker.allocator, entry.owner_roots, roots);
            return;
        }
    }

    pub fn markOpaqueStorageEmpty(self: *State, storage: facts.Place) void {
        for (self.opaque_storages.items) |*entry| {
            if (!entry.storage.eql(storage)) continue;
            entry.hidden_dependencies = &.{};
            entry.outcome_guard = 0;
            return;
        }
    }

    /// Seed an unknown input referent without asserting that inputs are disjoint.
    /// Backing may be shared; each observation keeps its own value generation.
    pub fn establishSymbolicInput(self: *State, ty: graph_mod.GlobalTypeId, shared_backing: ?facts.ValidityRootId) !SymbolicPointeeState {
        const namespace = self.tracker.namespace;
        const identity = if (namespace) |shared| shared.next_symbolic_id else self.symbolic_pointees.items.len;
        if (identity >= std.math.maxInt(u32)) return error.SafetySymbolicIdentityLimit;
        const root_count: u32 = if (shared_backing == null) 2 else 1;
        const first_root = if (namespace) |shared| shared.next_id else self.tracker.roots.items.len;
        if (first_root > std.math.maxInt(u32) - root_count) return error.SafetyRootIdentityLimit;
        try self.symbolic_pointees.ensureUnusedCapacity(1);
        try self.tracker.roots.ensureTotalCapacity(first_root + root_count);
        const backing = shared_backing orelse try self.tracker.establish(.fresh);
        const generation = try self.tracker.establish(.fresh);
        const input: SymbolicPointeeState = .{
            .identity = @enumFromInt(identity),
            .ty = ty,
            .initializedness = .initialized,
            .backing = backing,
            .generation = generation,
        };
        self.symbolic_pointees.appendAssumeCapacity(input);
        if (namespace) |shared| shared.next_symbolic_id += 1;
        return input;
    }

    /// Observe a projected unknown referent using branch-shared identities.
    /// The caller supplies its checked type; this state owns no type graph.
    pub fn projectSymbolicStorage(self: *State, parent: SymbolicPointeeState, projection: facts.Projection, child_type: ?graph_mod.GlobalTypeId) !?struct { identity: facts.SymbolicPointeeId, generation: facts.ValidityRootId } {
        const namespace = self.tracker.namespace orelse return null;
        const parent_generation = parent.generation orelse return null;
        var identity: ?facts.SymbolicPointeeId = null;
        var initial: ?facts.ValidityRootId = null;
        var backing: ?facts.ValidityRootId = null;
        for (namespace.projected_storage.items) |entry| {
            if (entry.parent == parent.identity and entry.parent_generation == parent_generation and entry.projection.eql(projection)) {
                identity = entry.identity;
                initial = entry.generation;
                backing = entry.backing;
                break;
            }
        }
        if (identity == null) {
            const next = namespace.next_symbolic_id;
            const following = try std.math.add(u32, next, 1);
            identity = @enumFromInt(next);
            for (namespace.projected_storage.items) |entry| {
                if (entry.parent_generation == parent_generation and entry.projection.eql(projection)) {
                    backing = entry.backing;
                    break;
                }
            }
            // Reserve every table and root before publishing this projection.
            const root_count: u32 = if (backing == null) 2 else 1;
            if (namespace.next_id > std.math.maxInt(u32) - root_count) return error.SafetyRootIdentityLimit;
            try namespace.projected_storage.ensureUnusedCapacity(self.tracker.allocator, 1);
            try self.symbolic_pointees.ensureUnusedCapacity(1);
            try self.tracker.roots.ensureTotalCapacity(@as(usize, namespace.next_id) + root_count);
            if (backing == null) backing = try self.tracker.establish(.fresh);
            initial = try self.tracker.establish(.fresh);
            namespace.projected_storage.appendAssumeCapacity(.{
                .parent = parent.identity,
                .parent_generation = parent_generation,
                .projection = projection,
                .identity = identity.?,
                .backing = backing.?,
                .generation = initial.?,
                .ty = child_type,
            });
            namespace.next_symbolic_id = following;
        }
        var generation: ?facts.ValidityRootId = null;
        for (self.symbolic_pointees.items) |*entry| if (entry.identity == identity.?) {
            if (entry.generation) |current| {
                if (entry.initializedness == .initialized and !self.tracker.isAlive(current)) {
                    // A joined write can leave a complete value with several
                    // possible incarnations. A new address observes the current
                    // value; historical references retain the old incarnation.
                    generation = try self.tracker.establish(.fresh);
                    entry.generation = generation;
                } else generation = current;
            } else if (entry.initializedness == .initialized) {
                generation = try self.tracker.establish(.fresh);
                entry.generation = generation;
            } else {
                // Preserve the uncertain incarnation as a validity obligation;
                // never turn failed projection into an untracked reference.
                try self.tracker.materialize(initial.?);
                generation = initial;
            }
            break;
        };
        if (generation == null) {
            // A field not observed on this branch still starts with the input's
            // initialized value. Refreshes retain their separate generations.
            try self.symbolic_pointees.ensureUnusedCapacity(1);
            try self.tracker.roots.ensureTotalCapacity(@as(usize, @max(@intFromEnum(backing.?), @intFromEnum(initial.?))) + 1);
            try self.tracker.materialize(backing.?);
            try self.tracker.materialize(initial.?);
            generation = initial;
            self.symbolic_pointees.appendAssumeCapacity(.{
                .identity = identity.?,
                .initializedness = .initialized,
                .ty = child_type,
                .backing = backing,
                .generation = generation,
            });
        }
        return .{ .identity = identity.?, .generation = generation.? };
    }

    pub fn referenceObservationGeneration(self: *State, pointer: facts.ValueFacts) !?facts.ValidityRootId {
        if (pointer.referenced_place) |place| return try self.storageGeneration(place);
        if (pointer.symbolic_pointees.len == 1) {
            for (self.symbolic_pointees.items) |entry| if (entry.identity == pointer.symbolic_pointees[0]) return entry.generation;
        }
        return null;
    }

    /// Observe the current incarnation without reviving historical aliases.
    pub fn storageGeneration(self: *State, storage: facts.Place) !facts.ValidityRootId {
        for (self.storage_generations.items) |*entry| if (entry.storage.eql(storage)) {
            // Both paths may leave an initialized Place with different
            // incarnations. A new borrow observes the current storage, while
            // historical aliases keep their original, conservatively joined
            // roots. Materialize only on demand to avoid growing loop states.
            if (entry.needs_current_generation and self.initializednessAtPlace(storage) == .initialized) {
                entry.generation = try self.tracker.establish(.fresh);
                entry.needs_current_generation = false;
            }
            return entry.generation;
        };
        try self.storage_generations.ensureUnusedCapacity(1);
        if (self.tracker.namespace) |namespace| {
            for (namespace.initial_storage.items) |initial| if (initial.storage.eql(storage)) {
                const index = @intFromEnum(initial.root);
                if (index >= self.tracker.roots.items.len or !self.tracker.roots.items[index].present) {
                    try self.tracker.materialize(initial.root);
                }
                if (self.tracker.isAlive(initial.root)) {
                    self.storage_generations.appendAssumeCapacity(.{ .storage = storage, .generation = initial.root });
                    return initial.root;
                }
                // An ended incarnation cannot become the initial generation
                // again when a lexical slot is reused in a later iteration.
                const root = try self.tracker.establish(.fresh);
                self.storage_generations.appendAssumeCapacity(.{ .storage = storage, .generation = root });
                return root;
            };
            try namespace.initial_storage.ensureUnusedCapacity(self.tracker.allocator, 1);
            const root = try self.tracker.establish(.fresh);
            namespace.initial_storage.appendAssumeCapacity(.{ .storage = storage, .root = root });
            self.storage_generations.appendAssumeCapacity(.{ .storage = storage, .generation = root });
            return root;
        }
        const root = try self.tracker.establish(.fresh);
        self.storage_generations.appendAssumeCapacity(.{ .storage = storage, .generation = root });
        return root;
    }

    pub fn refreshStorageGeneration(self: *State, storage: facts.Place) !void {
        // Prepare all fallible storage before ending any live generation.
        try self.storage_generations.ensureUnusedCapacity(1);
        const generation = try self.tracker.establish(.fresh);
        var kept: usize = 0;
        var replaced = false;
        for (self.storage_generations.items) |entry| {
            if (!storage.isPrefixOf(entry.storage)) {
                self.storage_generations.items[kept] = entry;
                kept += 1;
                continue;
            }
            self.tracker.end(entry.generation);
            if (entry.storage.eql(storage)) {
                self.storage_generations.items[kept] = .{ .storage = storage, .generation = generation };
                replaced = true;
                kept += 1;
            }
        }
        self.storage_generations.shrinkRetainingCapacity(kept);
        if (!replaced)
            self.storage_generations.appendAssumeCapacity(.{ .storage = storage, .generation = generation });
    }

    pub fn beginLexicalStorage(self: *State, storage: facts.Place) !void {
        for (self.storage_generations.items) |entry| {
            if (!storage.isPrefixOf(entry.storage)) continue;
            try self.refreshStorageGeneration(storage);
            return;
        }
    }

    /// Retire a lexical owner while retaining ended identities for escape checks.
    /// Reserve before changing facts so allocation failure leaves storage live.
    pub fn endLexicalStorage(self: *State, binding: graph_mod.GlobalBindingId) !void {
        var count: usize = 0;
        for (self.storage_generations.items) |entry| if (entry.storage.root == binding) {
            count += 1;
        };
        try self.lexical_storage_generations.ensureUnusedCapacity(count);
        var kept: usize = 0;
        for (self.storage_generations.items) |entry| {
            if (entry.storage.root == binding) {
                if (std.mem.indexOfScalar(facts.ValidityRootId, self.lexical_storage_generations.items, entry.generation) == null)
                    self.lexical_storage_generations.appendAssumeCapacity(entry.generation);
                self.tracker.end(entry.generation);
            } else {
                self.storage_generations.items[kept] = entry;
                kept += 1;
            }
        }
        self.storage_generations.shrinkRetainingCapacity(kept);
        kept = 0;
        for (self.places.items) |entry| {
            if (entry.storage.root == binding) continue;
            self.places.items[kept] = entry;
            kept += 1;
        }
        self.places.shrinkRetainingCapacity(kept);
    }

    pub fn symbolicStorageContains(self: *const State, container: facts.SymbolicPointeeId, target: facts.SymbolicPointeeId) bool {
        var identity = target;
        if (identity == container) return true;
        const namespace = self.tracker.namespace orelse return false;
        while (true) {
            identity = for (namespace.projected_storage.items) |entry| {
                if (entry.identity == identity) {
                    if (entry.projection == .dereference) return false;
                    break entry.parent;
                }
            } else return false;
            if (identity == container) return true;
        }
    }

    pub fn symbolicStorageMayOverlap(self: *const State, left: facts.SymbolicPointeeId, right: facts.SymbolicPointeeId) bool {
        if (self.symbolicStorageContains(left, right) or self.symbolicStorageContains(right, left)) return true;
        const namespace = self.tracker.namespace orelse return false;
        for (namespace.projected_storage.items) |a| {
            if (a.identity != left or a.projection == .dereference) continue;
            for (namespace.projected_storage.items) |b| {
                if (b.identity != right or b.projection == .dereference) continue;
                if (a.parent == b.parent and a.parent_generation == b.parent_generation) {
                    if (a.projection == .dynamic_index or b.projection == .dynamic_index) return true;
                    return a.projection.eql(b.projection);
                }
                // Descendants of the same possibly overlapping element retain
                // that uncertainty; distinct fixed siblings remain separate.
                return self.symbolicStorageMayOverlap(a.parent, b.parent);
            }
            return self.symbolicStorageMayOverlap(a.parent, right);
        }
        for (namespace.projected_storage.items) |b| {
            if (b.identity == right and b.projection != .dereference)
                return self.symbolicStorageMayOverlap(left, b.parent);
        }
        return false;
    }

    pub fn symbolicStorageDescendsFrom(self: *const State, child: facts.SymbolicPointeeId, parent: facts.SymbolicPointeeId) bool {
        return child != parent and self.symbolicStorageContains(parent, child);
    }

    pub fn initialProjectedPointee(self: *const State, identity: facts.SymbolicPointeeId) ?SymbolicPointeeState {
        const namespace = self.tracker.namespace orelse return null;
        for (namespace.projected_storage.items) |projected| {
            if (projected.identity != identity) continue;
            const parent = for (self.symbolic_pointees.items) |entry| {
                if (entry.identity == projected.parent) break entry;
            } else self.initialProjectedPointee(projected.parent) orelse return null;
            if (parent.generation == projected.parent_generation and parent.initializedness == .initialized)
                return .{ .identity = identity, .ty = projected.ty, .initializedness = .initialized, .backing = projected.backing, .generation = projected.generation };
        }
        return null;
    }

    pub fn symbolicVariant(self: *const State, identity: facts.SymbolicPointeeId) ?u32 {
        for (self.symbolic_values.items) |stored| if (stored.identity == identity) return stored.value.known_choice_variant;
        return null;
    }

    pub fn renewSymbolicAccess(self: *State, pointer: facts.ValueFacts) !?facts.ValueFacts {
        // A join of possible targets cannot establish one definite destination.
        if (pointer.symbolic_pointees.len != 1 or pointer.opaque_provenance.len != 0) return null;
        const identity = pointer.symbolic_pointees[0];
        for (self.symbolic_pointees.items, 0..) |entry, index| {
            if (entry.identity != identity or entry.initializedness != .deinitialized) continue;
            const backing = entry.backing orelse return null;
            const previous = entry.generation orelse return null;
            if (!self.tracker.isAlive(backing)) return null;
            for (pointer.dependencies) |dependency| {
                if (dependency.root != previous and !self.tracker.isAlive(dependency.root)) return null;
            }
            // Only an access observing the consumed incarnation can initialize
            // it. An alias from an older replacement cannot become current.
            var observes = false;
            for (pointer.dependencies) |dependency| if (dependency.root == previous) {
                observes = true;
                break;
            };
            if (!observes) return null;
            const generation = try self.tracker.establish(.fresh);
            const renewed = try facts.replaceValueRoots(self.tracker.allocator, pointer, &.{previous}, generation);
            self.symbolic_pointees.items[index].generation = generation;
            return renewed;
        }
        return null;
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
    try state.setRejectedVariant(child, 4);
    try state.setRejectedVariant(sibling, 5);
    // Interleave descendants and independent roots: retiring a subtree must
    // preserve every surviving fact in its original order.
    var projections: [16][1]facts.Projection = undefined;
    for (&projections, 0..) |*path, index| {
        path.* = .{.{ .field = @intCast(index + 1) }};
        const descendant: facts.Place = .{ .root = parent.root, .projections = path };
        const independent: facts.Place = .{ .root = @enumFromInt(index + 2) };
        try state.setPlace(descendant, .initialized, .{ .known_choice_variant = 2 });
        try state.setRejectedVariant(descendant, 4);
        try state.setPlace(independent, .initialized, .{ .known_choice_variant = 3 });
        try state.setRejectedVariant(independent, 5);
    }
    try state.markMoved(parent, .{}, .{ .file_index = 0, .offset = 7 });
    try std.testing.expectEqual(null, state.findPlace(child));
    try std.testing.expectEqual(null, state.activeVariant(child));
    try std.testing.expect(!state.variantRejected(child, 4));
    try std.testing.expectEqual(@as(?u32, 3), state.activeVariant(sibling));
    try std.testing.expect(state.variantRejected(sibling, 5));
    try std.testing.expectEqual(@as(u32, 7), state.findPlace(parent).?.moved_at.?.offset);
    try std.testing.expectEqual(@as(usize, 18), state.places.items.len);
    try std.testing.expectEqual(@as(usize, 17), state.choice_active.items.len);
    try std.testing.expectEqual(@as(usize, 17), state.choice_rejected.items.len);
    for (state.places.items[0..17], 0..) |entry, index|
        try std.testing.expectEqual(index + 1, @intFromEnum(entry.storage.root));
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

test "Safety lexical retirement preserves siblings and is unchanged on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var state = State.init(failing.allocator());
    defer state.deinit();
    const owner: facts.Place = .{ .root = @enumFromInt(0) };
    const child: facts.Place = .{ .root = owner.root, .projections = &.{.{ .field = 0 }} };
    const sibling: facts.Place = .{ .root = @enumFromInt(1) };
    for ([_]facts.Place{ owner, sibling, child }) |place| {
        try state.setPlace(place, .initialized, .{});
        try state.refreshStorageGeneration(place);
    }
    const old = state.storage_generations.items[0].generation;
    const other = state.storage_generations.items[1].generation;
    const projected = state.storage_generations.items[2].generation;
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try std.testing.expectError(error.OutOfMemory, state.endLexicalStorage(owner.root));
    try std.testing.expectEqual(@as(usize, 3), state.places.items.len);
    try std.testing.expectEqual(@as(usize, 3), state.storage_generations.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.lexical_storage_generations.items.len);
    for ([_]facts.ValidityRootId{ old, other, projected }) |root|
        try std.testing.expect(state.tracker.isAlive(root));
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try state.endLexicalStorage(owner.root);
    try std.testing.expect(!state.tracker.isAlive(old));
    try std.testing.expect(!state.tracker.isAlive(projected));
    try std.testing.expect(state.tracker.isAlive(other));
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ old, projected }, state.lexical_storage_generations.items);
    try std.testing.expectEqual(@as(usize, 1), state.places.items.len);
    try std.testing.expect(state.places.items[0].storage.eql(sibling));
    try std.testing.expectEqual(@as(usize, 1), state.storage_generations.items.len);
    try std.testing.expect(state.storage_generations.items[0].storage.eql(sibling));
    try state.endLexicalStorage(owner.root);
    try std.testing.expectEqual(@as(usize, 2), state.lexical_storage_generations.items.len);
}

test "Safety failed generation renewal preserves live storage and descendants" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var state = State.init(failing.allocator());
    defer state.deinit();
    const parent: facts.Place = .{ .root = @enumFromInt(0) };
    const child: facts.Place = .{ .root = parent.root, .projections = &.{.{ .field = 0 }} };
    try state.refreshStorageGeneration(parent);
    try state.refreshStorageGeneration(child);
    const previous = try std.testing.allocator.dupe(StorageGeneration, state.storage_generations.items);
    defer std.testing.allocator.free(previous);
    // Force the new root to allocate while the destination table has room.
    try state.storage_generations.ensureUnusedCapacity(1);
    while (state.tracker.roots.items.len < state.tracker.roots.capacity)
        _ = try state.tracker.establish(.fresh);
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try std.testing.expectError(error.OutOfMemory, state.refreshStorageGeneration(parent));
    try std.testing.expectEqualDeep(previous, state.storage_generations.items);
    for (previous) |entry| try std.testing.expect(state.tracker.isAlive(entry.generation));
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
    try state.storage_generations.append(.{ .storage = storage, .generation = root });
    try state.lexical_storage_generations.append(root);
    try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{} });
    try state.setActiveVariant(storage, 2);
    try state.setRejectedVariant(storage, 3);
    try state.setTemporaryActiveVariant(@enumFromInt(0), 2);
    state.reachable = false;
    var copied = try state.clone(allocator);
    defer copied.deinit();
    try std.testing.expectEqual(state.elementCount(), copied.elementCount());
    try std.testing.expect(!copied.reachable);
    copied.getPlace(storage).?.initializedness = .moved;
    try copied.setActiveVariant(storage, 4);
    copied.tracker.end(root);
    try std.testing.expectEqual(.initialized, state.findPlace(storage).?.initializedness);
    try std.testing.expectEqual(@as(?u32, 2), state.activeVariant(storage));
    try std.testing.expect(state.tracker.isAlive(root));
}

test "Safety opaque merges publish both root sets together and reuse unchanged facts" {
    const root0: facts.ValidityRootId = @enumFromInt(0);
    const root1: facts.ValidityRootId = @enumFromInt(1);
    const root2: facts.ValidityRootId = @enumFromInt(2);
    const root3: facts.ValidityRootId = @enumFromInt(3);
    inline for (.{ false, true }) |existing| {
        var completed = false;
        for (0..8) |failure_index| {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var state = State.init(a);
            defer state.deinit();
            const storage: facts.Place = .{ .root = @enumFromInt(0) };
            if (existing) try state.opaque_storages.append(.{ .storage = storage, .hidden_dependencies = &.{root0}, .owner_roots = &.{root2}, .outcome_guard = 9 });
            var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = failure_index });
            state.opaque_storages.allocator = failing.allocator();
            state.tracker.allocator = failing.allocator();
            const merged = state.mergeOpaqueStorage(storage, &.{ root0, root1, root1 }, &.{ root2, root3, root3 });
            state.opaque_storages.allocator = a;
            state.tracker.allocator = a;
            if (merged) |_| {
                const domain = state.opaque_storages.items[0];
                try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ root0, root1 }, domain.hidden_dependencies);
                try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ root2, root3 }, domain.owner_roots);
                var unavailable = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
                state.opaque_storages.allocator = unavailable.allocator();
                state.tracker.allocator = unavailable.allocator();
                try state.mergeOpaqueStorage(storage, &.{ root1, root0 }, &.{ root3, root2 });
                try state.mergeOpaqueOwnerRoots(storage, &.{root3});
                state.opaque_storages.allocator = a;
                state.tracker.allocator = a;
                try std.testing.expectEqual(domain.hidden_dependencies.ptr, state.opaque_storages.items[0].hidden_dependencies.ptr);
                try std.testing.expectEqual(domain.owner_roots.ptr, state.opaque_storages.items[0].owner_roots.ptr);
                state.markOpaqueStorageEmpty(storage);
                try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
                try std.testing.expectEqualSlices(facts.ValidityRootId, domain.owner_roots, state.opaque_storages.items[0].owner_roots);
                completed = true;
                break;
            } else |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                try std.testing.expectEqual(@as(usize, @intFromBool(existing)), state.opaque_storages.items.len);
                if (existing) {
                    const domain = state.opaque_storages.items[0];
                    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{root0}, domain.hidden_dependencies);
                    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{root2}, domain.owner_roots);
                    try std.testing.expectEqual(@as(u64, 9), domain.outcome_guard);
                }
            }
        }
        try std.testing.expect(completed);
    }
}

test "Safety symbolic inputs publish identities and roots together" {
    inline for (.{ false, true }) |namespaced| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
            fn seed(a: std.mem.Allocator, shared: bool) !void {
                var namespace: facts.Tracker.RootNamespace = .{};
                defer namespace.deinit(a);
                var state = State.init(a);
                defer state.deinit();
                if (shared) state.tracker.namespace = &namespace;
                const first = state.establishSymbolicInput(@enumFromInt(0), null) catch |err| {
                    try std.testing.expectEqual(@as(usize, 0), state.symbolic_pointees.items.len);
                    try std.testing.expectEqual(@as(usize, 0), state.tracker.roots.items.len);
                    try std.testing.expectEqual(@as(u32, 0), namespace.next_symbolic_id);
                    try std.testing.expectEqual(@as(u32, 0), namespace.next_id);
                    return err;
                };
                const second = try state.establishSymbolicInput(@enumFromInt(1), first.backing);
                try std.testing.expectEqual(first.backing, second.backing);
                try std.testing.expect(first.identity != second.identity);
                try std.testing.expect(first.generation != second.generation);
                try std.testing.expectEqual(value_state.Initializedness.initialized, first.initializedness);
                try std.testing.expect(state.tracker.isAlive(first.backing.?));
                try std.testing.expect(state.tracker.isAlive(first.generation.?));
                try std.testing.expect(state.tracker.isAlive(second.generation.?));
            }
        }.seed, .{namespaced});
    }
}

test "Safety symbolic projection publication preserves branch identities on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn project(a: std.mem.Allocator) !void {
            var namespace: facts.Tracker.RootNamespace = .{ .next_symbolic_id = 1 };
            defer namespace.deinit(a);
            var state = State.init(a);
            defer state.deinit();
            state.tracker.namespace = &namespace;
            const backing = try state.tracker.establish(.fresh);
            const generation = try state.tracker.establish(.fresh);
            const parent: SymbolicPointeeState = .{ .identity = @enumFromInt(0), .initializedness = .initialized, .backing = backing, .generation = generation };
            try state.symbolic_pointees.append(parent);
            var other = try state.clone(a);
            defer other.deinit();
            const selected = (state.projectSymbolicStorage(parent, .{ .field = 0 }, null) catch |err| {
                try std.testing.expectEqual(@as(usize, 0), namespace.projected_storage.items.len);
                try std.testing.expectEqual(@as(u32, 1), namespace.next_symbolic_id);
                try std.testing.expectEqual(@as(u32, 2), namespace.next_id);
                try std.testing.expectEqual(@as(usize, 2), state.tracker.roots.items.len);
                try std.testing.expectEqual(@as(usize, 1), state.symbolic_pointees.items.len);
                return err;
            }).?;
            const observed = (try other.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
            try std.testing.expectEqual(selected.identity, observed.identity);
            try std.testing.expectEqual(selected.generation, observed.generation);
            try std.testing.expectEqual(@as(usize, 1), namespace.projected_storage.items.len);
            state.tracker.end(selected.generation);
            const current = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
            try std.testing.expectEqual(selected.identity, current.identity);
            try std.testing.expect(selected.generation != current.generation);
            try std.testing.expect(!state.tracker.isAlive(selected.generation));
            try std.testing.expect(other.tracker.isAlive(selected.generation));
        }
    }.project, .{});
}

test "Safety storage observation publishes generations atomically" {
    inline for (.{ false, true }) |namespaced| {
        try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
            fn observe(a: std.mem.Allocator, shared: bool) !void {
                var namespace: facts.Tracker.RootNamespace = .{};
                defer namespace.deinit(a);
                var state = State.init(a);
                defer state.deinit();
                if (shared) state.tracker.namespace = &namespace;
                const storage: facts.Place = .{ .root = @enumFromInt(0) };
                const generation = state.storageGeneration(storage) catch |err| {
                    try std.testing.expectEqual(@as(usize, 0), state.storage_generations.items.len);
                    try std.testing.expectEqual(@as(usize, 0), state.tracker.roots.items.len);
                    try std.testing.expectEqual(@as(usize, 0), namespace.initial_storage.items.len);
                    try std.testing.expectEqual(@as(u32, 0), namespace.next_id);
                    return err;
                };
                try std.testing.expect(state.tracker.isAlive(generation));
                try std.testing.expectEqual(generation, try state.storageGeneration(storage));
                try std.testing.expectEqual(@as(usize, 1), state.storage_generations.items.len);
                if (shared) {
                    try std.testing.expectEqual(@as(u32, 1), namespace.next_id);
                    try std.testing.expectEqual(generation, namespace.initial_storage.items[0].root);
                }
            }
        }.observe, .{namespaced});
    }
}

test "Safety state clones own independent tables and release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationFailures, .{});
}

test "Safety branch tables release independently of shared proof facts" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn check(table_allocator: std.mem.Allocator) !void {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fact_allocator = arena.allocator();
            var namespace: facts.Tracker.RootNamespace = .{};
            defer namespace.deinit(fact_allocator);
            const storage: facts.Place = .{ .root = @enumFromInt(0) };
            var branch = original: {
                var state = State.initWithAllocators(fact_allocator, table_allocator);
                defer state.deinit();
                state.tracker.namespace = &namespace;
                const generation = try state.storageGeneration(storage);
                try state.mergeOpaqueStorage(storage, &.{generation}, &.{generation});
                break :original try state.cloneWithAllocators(fact_allocator, table_allocator);
            };
            defer branch.deinit();
            const generation = try branch.storageGeneration(storage);
            try std.testing.expect(branch.tracker.isAlive(generation));
            try std.testing.expectEqual(generation, branch.opaque_storages.items[0].hidden_dependencies[0]);
            const other = try branch.storageGeneration(.{ .root = @enumFromInt(1) });
            try branch.mergeOpaqueOwnerRoots(storage, &.{other});
            try std.testing.expectEqual(@as(usize, 2), branch.opaque_storages.items[0].owner_roots.len);
            try std.testing.expectEqual(@as(usize, 2), namespace.initial_storage.items.len);
        }
    }.check, .{});
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

test "Safety capability consumption never weakens an established consumption" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const capability = try state.establishCapability();
    for (std.meta.tags(StorageCapabilityState)) |initial| {
        for ([_]bool{ false, true }) |definite| {
            state.storage_capabilities.items[@intFromEnum(capability)] = initial;
            state.consumeCapability(capability, definite);
            const expected: StorageCapabilityState = switch (initial) {
                .absent, .consumed => initial,
                else => if (definite) .consumed else .maybe_consumed,
            };
            try std.testing.expectEqual(expected, state.capabilityState(capability));
        }
    }
    state.consumeCapability(@enumFromInt(100), true);
    try std.testing.expectEqual(.absent, state.capabilityState(@enumFromInt(100)));
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

test "Safety symbolic joins separate initialization backing and observed generation" {
    const initializations = std.meta.tags(value_state.Initializedness);
    for (initializations) |left_init| for (initializations) |right_init| {
        const left = SymbolicPointeeState{ .identity = @enumFromInt(0), .initializedness = left_init, .backing = @enumFromInt(1), .generation = @enumFromInt(2) };
        var right = left;
        right.initializedness = right_init;
        const joined = left.join(right);
        try std.testing.expectEqualDeep(joined, right.join(left));
        try std.testing.expectEqual(if (left_init == right_init) left_init else .maybe_initialized, joined.initializedness);
        try std.testing.expectEqual(left.backing, joined.backing);
        try std.testing.expectEqual(left.generation, joined.generation);
        right.generation = @enumFromInt(3);
        try std.testing.expectEqual(null, left.join(right).generation);
        try std.testing.expectEqual(left.backing, left.join(right).backing);
        right.backing = @enumFromInt(4);
        try std.testing.expectEqual(null, left.join(right).backing);
        try std.testing.expectEqualDeep(left.join(right), right.join(left));
        try std.testing.expectEqual(.maybe_initialized, left.join(null).initializedness);
    };
}

test "Safety symbolic strong writes retire slots but preserve dereferenced storage and tag refinements" {
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(std.testing.allocator);
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const parent: facts.SymbolicPointeeId = @enumFromInt(0);
    const field: facts.SymbolicPointeeId = @enumFromInt(1);
    const referent: facts.SymbolicPointeeId = @enumFromInt(2);
    const sibling: facts.SymbolicPointeeId = @enumFromInt(3);
    const root: facts.ValidityRootId = @enumFromInt(0);
    try namespace.projected_storage.appendSlice(std.testing.allocator, &.{
        .{ .parent = parent, .parent_generation = root, .projection = .{ .field = 0 }, .identity = field, .backing = root, .generation = root },
        .{ .parent = field, .parent_generation = root, .projection = .dereference, .identity = referent, .backing = root, .generation = root },
    });
    for ([_]facts.SymbolicPointeeId{ parent, field, referent, sibling }) |identity|
        try state.setSymbolicValue(.{ .identity = identity, .value = .{ .known_choice_variant = 1 } }, false, true);
    // A tag proof does not replace payload fields or the storage they reference.
    try state.setSymbolicValue(.{ .identity = parent, .value = .{ .known_choice_variant = 2 } }, false, true);
    try std.testing.expectEqual(@as(?u32, 1), state.symbolicVariant(field));
    try state.setSymbolicValue(.{ .identity = parent, .value = .{} }, true, true);
    try std.testing.expectEqual(null, state.exactSymbolicValue(field));
    try std.testing.expectEqual(@as(?u32, 1), state.symbolicVariant(referent));
    try std.testing.expectEqual(@as(?u32, 1), state.symbolicVariant(sibling));
    try std.testing.expect(state.exactSymbolicValue(parent) != null);
    // Empty explicit facts remain authoritative even after another strong write.
    try state.setSymbolicValue(.{ .identity = parent, .value = .{} }, true, false);
    try std.testing.expect(state.exactSymbolicValue(parent) != null);
}

test "Safety symbolic initialization alone cannot renew a historical reference" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const backing = try state.tracker.establish(.fresh);
    const old = try state.tracker.establish(.fresh);
    const current = try state.tracker.establish(.fresh);
    const identity: facts.SymbolicPointeeId = @enumFromInt(0);
    try state.symbolic_pointees.append(.{ .identity = identity, .initializedness = .deinitialized, .backing = backing, .generation = current });
    state.tracker.end(old);
    const historical: facts.ValueFacts = .{ .symbolic_pointees = &.{identity}, .dependencies = &.{ .{ .root = backing }, .{ .root = old } } };
    try std.testing.expect(try state.renewSymbolicAccess(historical) == null);
    state.setSymbolicInitializedness(identity, .initialized);
    try std.testing.expect(!state.tracker.dependenciesAreAlive(historical));
    state.tracker.end(current);
    state.setSymbolicInitializedness(identity, .deinitialized);
    state.initializeLiveSymbolicTargets(.{ .symbolic_pointees = &.{identity} });
    try std.testing.expectEqual(.deinitialized, state.symbolicPointee(identity).?.initializedness);
    try std.testing.expect(!state.tracker.isAlive(old));
}

test "Safety choice refinements propagate allocation failure without discarding prior facts" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var state = State.init(failing.allocator());
    defer state.deinit();
    const storage: facts.Place = .{ .root = @enumFromInt(0) };
    try std.testing.expectError(error.OutOfMemory, state.setActiveVariant(storage, 1));
    try std.testing.expectError(error.OutOfMemory, state.setRejectedVariant(storage, 2));
    try std.testing.expectEqual(@as(usize, 0), state.choice_active.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.choice_rejected.items.len);

    // Updating an existing positive proof and removing its rejection allocate
    // nothing, even when the backing allocator cannot provide more storage.
    state.choice_active.allocator = std.testing.allocator;
    state.choice_rejected.allocator = std.testing.allocator;
    try state.setActiveVariant(storage, 1);
    try state.setRejectedVariant(storage, 2);
    state.choice_active.allocator = failing.allocator();
    state.choice_rejected.allocator = failing.allocator();
    try state.setActiveVariant(storage, 2);
    try std.testing.expectEqual(@as(u32, 2), state.choice_active.items[0].variant_index);
    try std.testing.expect(!state.variantRejected(storage, 2));
}
