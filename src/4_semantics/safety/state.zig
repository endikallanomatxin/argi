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
pub const ReferenceStores = @import("observed_store.zig").Stores(facts.StorageIdentity, facts.ValueFacts);

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

    pub fn covers(self: StorageCapabilityState, incoming: StorageCapabilityState) bool {
        // Absence is also used for reserved identities that may still be
        // established. Keep it distinct when checking a successor.
        return self == incoming or (self == .maybe_consumed and incoming != .absent);
    }
};
pub const StorageGeneration = struct {
    storage: facts.Place,
    generation: facts.ValidityRootId,
    needs_current_generation: bool = false,
};
pub const OpaqueStorage = struct {
    storage: facts.StorageIdentity,
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
    // Entry-relative source for deferred caller alias obligations, not a proof
    // of disjointness. Projected observations derive their path from this root.
    input_path: ?facts.InputPath = null,
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

pub const SymbolicObservation = struct { identity: facts.SymbolicPointeeId, generation: facts.ValidityRootId };

pub const State = struct {
    tracker: facts.Tracker,
    places: std.array_list.Managed(facts.PlaceFacts),
    symbolic_pointees: std.array_list.Managed(SymbolicPointeeState),
    // Sparse value facts are separate from slot identity and initialization.
    // Ordinary scalar slots need no entry; immutable aggregates share facts.
    symbolic_values: std.array_list.Managed(SymbolicStoredValue),
    // Reaching payloads of symbolic reference-cell writes. These add possible
    // contents across aliases; their keys grant no validity or authority.
    reference_writes: std.array_list.Managed(ReferenceStores.Definition),
    executions: std.array_list.Managed(facts.ExecutionState),
    storage_capabilities: std.array_list.Managed(StorageCapabilityState),
    shared_regions: std.array_list.Managed(facts.Place),
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
            .reference_writes = std.array_list.Managed(ReferenceStores.Definition).init(allocator),
            .executions = std.array_list.Managed(facts.ExecutionState).init(allocator),
            .storage_capabilities = std.array_list.Managed(StorageCapabilityState).init(allocator),
            .shared_regions = std.array_list.Managed(facts.Place).init(allocator),
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
        self.reference_writes.deinit();
        self.executions.deinit();
        self.storage_capabilities.deinit();
        self.shared_regions.deinit();
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

    /// Completed entries remain present so an execution identity is never reused.
    pub fn establishExecution(self: *State, loans: []const facts.ExecutionLoan) !facts.ExecutionId {
        return self.establishExecutionAt(loans, null);
    }

    pub fn establishExecutionAt(self: *State, loans: []const facts.ExecutionLoan, origin: ?primitives.SourceRef) !facts.ExecutionId {
        const next = if (self.tracker.namespace) |namespace|
            namespace.next_execution_id
        else if (self.executions.getLastOrNull()) |last|
            std.math.add(u32, @intFromEnum(last.id), 1) catch return error.SafetyExecutionIdentityLimit
        else
            0;
        if (next == std.math.maxInt(u32)) return error.SafetyExecutionIdentityLimit;
        const id: facts.ExecutionId = @enumFromInt(next);
        try self.executions.append(.{ .id = id, .loans = loans, .origin = origin });
        if (self.tracker.namespace) |namespace| namespace.next_execution_id = next + 1;
        return id;
    }

    /// Establishment appends increasing IDs. Preserve that order across joins
    /// so each incoming execution is visited once. An ID shared by both
    /// branches denotes the same loan, still pending if either branch retains it.
    pub fn joinExecutions(self: *State, left: []const facts.ExecutionState, right: []const facts.ExecutionState) !void {
        std.debug.assert(self.executions.items.len == 0);
        var i: usize = 0;
        var j: usize = 0;
        while (i < left.len and j < right.len) {
            switch (std.math.order(@intFromEnum(left[i].id), @intFromEnum(right[j].id))) {
                .lt => {
                    try self.executions.append(left[i]);
                    i += 1;
                },
                .gt => {
                    try self.executions.append(right[j]);
                    j += 1;
                },
                .eq => {
                    var shared = left[i];
                    shared.pending = shared.pending or right[j].pending;
                    const other = right[j].output;
                    if (shared.output != .unavailable or other != .unavailable) {
                        const evidence = shared.output.accessEvidence();
                        const common = if (sameExecutionOutputEvidence(evidence, other.accessEvidence())) evidence else null;
                        shared.output = if (shared.output == .retained and other == .retained and common != null)
                            .{ .retained = common.? }
                        else
                            .{ .consumed = common };
                    }
                    try self.executions.append(shared);
                    i += 1;
                    j += 1;
                },
            }
        }
        try self.executions.appendSlice(left[i..]);
        try self.executions.appendSlice(right[j..]);
    }

    /// Pending loans and output access evidence can both affect the next
    /// transfer. A completed entry without either can be ignored.
    pub fn samePendingExecutions(self: *const State, other: *const State) bool {
        var other_entries = other.executions.items;
        for (self.executions.items) |execution| {
            while (other_entries.len != 0 and @intFromEnum(other_entries[0].id) < @intFromEnum(execution.id)) {
                if (other_entries[0].pending or other_entries[0].output.accessEvidence() != null) return false;
                other_entries = other_entries[1..];
            }
            if (other_entries.len == 0 or other_entries[0].id != execution.id) {
                if (execution.pending or execution.output.accessEvidence() != null) return false;
                continue;
            }

            const opposite = other_entries[0];
            other_entries = other_entries[1..];
            if (execution.pending != opposite.pending) return false;
            if (execution.pending) {
                if (execution.loans.len != opposite.loans.len) return false;
                if (execution.loans.ptr != opposite.loans.ptr) {
                    for (execution.loans, opposite.loans) |a, b| if (!a.eql(b)) return false;
                }
            }
            if (!sameExecutionOutputEvidence(execution.output.accessEvidence(), opposite.output.accessEvidence())) return false;
            if ((execution.output == .retained) != (opposite.output == .retained)) return false;
            // Unavailable pending output can still accept custody. A consumed
            // output cannot, even after its access evidence has been lost.
            if (execution.pending and @as(std.meta.Tag(facts.ExecutionState.Output), execution.output) !=
                @as(std.meta.Tag(facts.ExecutionState.Output), opposite.output)) return false;
        }
        for (other_entries) |entry| if (entry.pending or entry.output.accessEvidence() != null) return false;
        return true;
    }

    fn compareExecutionId(id: facts.ExecutionId, entry: facts.ExecutionState) std.math.Order {
        return std.math.order(@intFromEnum(id), @intFromEnum(entry.id));
    }

    fn sameExecutionOutputEvidence(left: ?*const facts.ValueFacts, right: ?*const facts.ValueFacts) bool {
        if (left == right) return true;
        return if (left != null and right != null) facts.valueFactsEqual(left.?.*, right.?.*) else false;
    }

    fn executionIndex(self: *const State, id: facts.ExecutionId) ?usize {
        return std.sort.binarySearch(facts.ExecutionState, self.executions.items, id, compareExecutionId);
    }

    pub fn executionState(self: *const State, id: facts.ExecutionId) ?facts.ExecutionState {
        const index = self.executionIndex(id) orelse return null;
        return self.executions.items[index];
    }

    pub fn executionPending(self: *const State, id: facts.ExecutionId) bool {
        return if (self.executionState(id)) |execution| execution.pending else false;
    }

    pub fn completeExecution(self: *State, id: facts.ExecutionId) void {
        const index = self.executionIndex(id) orelse return;
        self.executions.items[index].pending = false;
    }

    pub fn retainExecutionOutput(self: *State, id: facts.ExecutionId, value: *const facts.ValueFacts) bool {
        const index = self.executionIndex(id) orelse return false;
        const execution = &self.executions.items[index];
        if (!execution.pending or execution.output != .unavailable) return false;
        execution.output = .{ .retained = value };
        return true;
    }

    pub fn consumeExecutionOutput(self: *State, id: facts.ExecutionId) ?*const facts.ValueFacts {
        if (self.executionPending(id)) return null;
        return self.reserveExecutionOutput(id);
    }

    /// Reserve a single transfer whose completion is certified only on its
    /// successful result. Failure can conservatively lose custody precision.
    pub fn reserveExecutionOutput(self: *State, id: facts.ExecutionId) ?*const facts.ValueFacts {
        const index = self.executionIndex(id) orelse return null;
        const execution = &self.executions.items[index];
        if (execution.output != .retained) return null;
        const value = execution.output.retained;
        execution.output = .{ .consumed = value };
        return value;
    }

    /// Reserve an acquisition origin without creating establishment permission.
    pub fn reserveCapabilityIdentity(self: *State) !facts.StorageCapabilityId {
        const index = if (self.tracker.namespace) |namespace| namespace.next_capability_id else self.storage_capabilities.items.len;
        if (index >= std.math.maxInt(u32)) return error.SafetyCapabilityIdentityLimit;
        const id: facts.StorageCapabilityId = @enumFromInt(index);
        try self.materializeCapabilityIdentity(id);
        if (self.tracker.namespace) |namespace| namespace.next_capability_id += 1;
        return id;
    }

    /// Observe a shared origin on this path without granting permission.
    pub fn materializeCapabilityIdentity(self: *State, id: facts.StorageCapabilityId) !void {
        const index: usize = @intFromEnum(id);
        try self.storage_capabilities.ensureTotalCapacity(index + 1);
        while (self.storage_capabilities.items.len <= index)
            self.storage_capabilities.appendAssumeCapacity(.absent);
    }

    pub fn establishCapability(self: *State) !facts.StorageCapabilityId {
        const id = try self.reserveCapabilityIdentity();
        self.storage_capabilities.items[@intFromEnum(id)] = .available;
        return id;
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

    pub fn symbolicPointeeAt(self: *const State, identity: facts.SymbolicPointeeId, hint: usize) ?SymbolicPointeeState {
        const entries = self.symbolic_pointees.items;
        if (hint < entries.len and entries[hint].identity == identity) return entries[hint];
        return self.symbolicPointee(identity);
    }

    pub fn setSymbolicInitializedness(self: *State, identity: facts.SymbolicPointeeId, initializedness: value_state.Initializedness) void {
        for (self.symbolic_pointees.items) |*entry| if (entry.identity == identity) {
            // Availability alone never renews a reference's observed incarnation.
            entry.initializedness = initializedness;
            return;
        };
    }

    pub fn initializeLiveSymbolicTargets(self: *State, pointer: facts.ValueFacts) void {
        if (pointer.reference_target_incomplete) return;
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
        for (left.symbolic_pointees.items, 0..) |entry, index|
            try self.symbolic_pointees.append(entry.join(right.symbolicPointeeAt(entry.identity, index) orelse right.initialProjectedPointee(entry.identity)));
        for (right.symbolic_pointees.items, 0..) |entry, index| {
            if (left.symbolicPointeeAt(entry.identity, index) != null) continue;
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

    pub fn mergeOpaqueStorage(self: *State, storage: facts.StorageIdentity, dependencies: []const facts.ValidityRootId, owners: []const facts.ValidityRootId) !void {
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

    /// Publish one joined domain. The predecessor slices are immutable and
    /// already deduplicated. Current owners come from the joined value.
    pub fn appendJoinedOpaqueStorage(self: *State, first: OpaqueStorage, second: ?OpaqueStorage, current_owners: []const facts.ValidityRootId) !void {
        try self.opaque_storages.ensureUnusedCapacity(1);
        const a = self.tracker.allocator;
        const hidden = try unionRoots(a, first.hidden_dependencies, if (second) |row| row.hidden_dependencies else &.{});
        errdefer if (hidden.ptr != first.hidden_dependencies.ptr) a.free(hidden);
        const owners = try unionRoots(a, first.owner_roots, if (second) |row| row.owner_roots else &.{});
        const combined = unionRoots(a, owners, current_owners) catch |err| {
            if (owners.ptr != first.owner_roots.ptr) a.free(owners);
            return err;
        };
        if (owners.ptr != first.owner_roots.ptr and owners.ptr != combined.ptr) a.free(owners);
        self.opaque_storages.appendAssumeCapacity(.{
            .storage = first.storage,
            .hidden_dependencies = hidden,
            .owner_roots = combined,
            .outcome_guard = if (second) |row| if (row.outcome_guard == first.outcome_guard) first.outcome_guard else 0 else 0,
        });
    }

    pub fn mergeOpaqueOwnerRoots(self: *State, storage: facts.StorageIdentity, roots: []const facts.ValidityRootId) !void {
        if (roots.len == 0) return;
        for (self.opaque_storages.items) |*entry| {
            if (!entry.storage.eql(storage)) continue;
            entry.owner_roots = try unionRoots(self.tracker.allocator, entry.owner_roots, roots);
            return;
        }
    }

    pub fn markOpaqueStorageEmpty(self: *State, storage: facts.StorageIdentity) void {
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
    pub fn projectSymbolicStorage(self: *State, parent: SymbolicPointeeState, projection: facts.Projection, child_type: ?graph_mod.GlobalTypeId) !?SymbolicObservation {
        return self.observeSymbolicStorage(parent, .{ .projection = projection }, child_type);
    }

    pub fn projectSymbolicDomain(self: *State, parent: SymbolicPointeeState, domain: u32) !?SymbolicObservation {
        return self.observeSymbolicStorage(parent, .{ .domain = domain }, null);
    }

    fn observeSymbolicStorage(self: *State, parent: SymbolicPointeeState, selector: facts.SymbolicStorageSelector, child_type: ?graph_mod.GlobalTypeId) !?SymbolicObservation {
        const namespace = self.tracker.namespace orelse return null;
        const parent_generation = parent.generation orelse return null;
        if (self.symbolicPointee(parent.identity)) |current| {
            // A detached observation cannot create or materialize rows
            // under its old key after the parent was renewed.
            if (current.generation != parent_generation and
                (@intFromEnum(parent_generation) >= self.tracker.roots.items.len or !self.tracker.isAlive(parent_generation))) return null;
        }
        var identity: ?facts.SymbolicPointeeId = null;
        var initial: ?facts.ValidityRootId = null;
        var backing: ?facts.ValidityRootId = null;
        const key: facts.Tracker.RootNamespace.ProjectionObservation = .{ .parent = parent.identity, .generation = parent_generation, .selector = selector };
        if (namespace.observedProjection(key)) |entry| {
            identity = entry.identity;
            initial = entry.generation;
            backing = entry.backing;
        }
        if (identity == null) {
            const next = namespace.next_symbolic_id;
            const following = try std.math.add(u32, next, 1);
            identity = @enumFromInt(next);
            // Embedded fields keep their physical backing across parent
            // generations. A dereference or opaque selector may retarget.
            backing = namespace.embeddedBacking(key);
            // Reserve every table and root before publishing this projection.
            const root_count: u32 = if (backing == null) 2 else 1;
            if (namespace.next_id > std.math.maxInt(u32) - root_count) return error.SafetyRootIdentityLimit;
            try namespace.reserveProjection(self.tracker.allocator, selector);
            try self.symbolic_pointees.ensureUnusedCapacity(1);
            try self.tracker.roots.ensureTotalCapacity(@as(usize, namespace.next_id) + root_count);
            if (backing == null) backing = try self.tracker.establish(.fresh);
            initial = try self.tracker.establish(.fresh);
            namespace.publishProjection(.{
                .parent = parent.identity,
                .parent_generation = parent_generation,
                .selector = selector,
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
    pub fn domainGenerationIsCurrent(self: *const State, storage: facts.StorageIdentity, generation: facts.ValidityRootId) bool {
        return switch (storage) {
            .place => |place| for (self.storage_generations.items) |entry| {
                if (entry.storage.eql(place)) break entry.generation == generation and !entry.needs_current_generation;
            } else false,
            .symbolic => |identity| for (self.symbolic_pointees.items) |entry| {
                if (entry.identity == identity) break entry.generation == generation;
            } else false,
        };
    }

    pub fn domainGeneration(self: *State, storage: facts.StorageIdentity) !facts.ValidityRootId {
        return switch (storage) {
            .place => |place| self.storageGeneration(place),
            .symbolic => |identity| for (self.symbolic_pointees.items) |entry| {
                if (entry.identity == identity) break entry.generation orelse return error.MissingVirtualStorageDomain;
            } else error.MissingVirtualStorageDomain,
        };
    }

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

    /// Record physical lexical storage independently of value generations.
    /// Never refresh this observation on assignment, reinitialization or loops.
    pub fn observeLexicalStorage(self: *State, binding: graph_mod.GlobalBindingId, may_preexist: bool) !void {
        const namespace = self.tracker.namespace orelse return;
        if (namespace.lexical_allocations.contains(binding)) return;
        if (namespace.lexical_allocations.count() == std.math.maxInt(u32)) return error.SafetyLexicalFrameLimit;
        try namespace.lexical_allocations.put(self.tracker.allocator, binding, may_preexist);
    }

    pub fn lexicalFrame(self: *const State) ?u32 {
        const namespace = self.tracker.namespace orelse return null;
        return @intCast(namespace.lexical_allocations.count());
    }

    /// Unknown external backing remains possible. Only later lexical storage
    /// in this proof can be excluded; a dereference denotes external storage,
    /// not the local reference slot from which it was reached.
    pub fn frameExcludesStorage(self: *const State, frame: u32, storage: facts.Place) bool {
        for (storage.projections) |projection| if (projection == .dereference) return false;
        const namespace = self.tracker.namespace orelse return false;
        const index = namespace.lexical_allocations.getIndex(storage.root) orelse return false;
        return !namespace.lexical_allocations.values()[index] and index >= frame;
    }

    pub fn beginLexicalStorage(self: *State, storage: facts.Place) !void {
        try self.observeLexicalStorage(storage.root, false);
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
        var region_index = self.shared_regions.items.len;
        while (region_index != 0) {
            region_index -= 1;
            if (self.shared_regions.items[region_index].root == binding)
                _ = self.shared_regions.swapRemove(region_index);
        }
        kept = 0;
        for (self.places.items) |entry| {
            if (entry.storage.root == binding) continue;
            self.places.items[kept] = entry;
            kept += 1;
        }
        self.places.shrinkRetainingCapacity(kept);
    }

    pub fn storageContains(self: *const State, container: facts.StorageIdentity, target: facts.StorageIdentity) bool {
        return switch (container) {
            .place => |place| target == .place and place.isPrefixOf(target.place),
            .symbolic => |identity| target == .symbolic and self.symbolicStorageContains(identity, target.symbolic),
        };
    }

    pub fn symbolicStorageContains(self: *const State, container: facts.SymbolicPointeeId, target: facts.SymbolicPointeeId) bool {
        var identity = target;
        if (identity == container) return true;
        const namespace = self.tracker.namespace orelse return false;
        while (true) {
            const index = namespace.projectionIndex(identity) orelse return false;
            const entry = namespace.projected_storage.items[index];
            if (!entry.selector.embedded()) return false;
            identity = entry.parent;
            if (identity == container) return true;
        }
    }

    fn symbolicProjectionIndex(self: *const State, identity: facts.SymbolicPointeeId) ?usize {
        const namespace = self.tracker.namespace orelse return null;
        const index = namespace.projectionIndex(identity) orelse return null;
        return if (namespace.projected_storage.items[index].selector.embedded()) index else null;
    }

    fn symbolicStorageDepth(self: *const State, identity: facts.SymbolicPointeeId) usize {
        const namespace = self.tracker.namespace orelse return 0;
        var current = identity;
        var depth: usize = 0;
        while (self.symbolicProjectionIndex(current)) |index| {
            current = namespace.projected_storage.items[index].parent;
            depth += 1;
        }
        return depth;
    }

    pub fn symbolicStorageHasDynamicIndex(self: *const State, identity: facts.SymbolicPointeeId) bool {
        const namespace = self.tracker.namespace orelse return false;
        var current = identity;
        while (true) {
            const index = namespace.projectionIndex(current) orelse return false;
            const entry = namespace.projected_storage.items[index];
            // A stored reference loaded through a wildcard also represents
            // alternatives, even though the referent is not an embedded child.
            if (entry.selector == .projection and entry.selector.projection == .dynamic_index) return true;
            current = entry.parent;
        }
    }

    pub fn symbolicStorageMayOverlap(self: *const State, graph: *const graph_mod.GlobalSemanticGraph, left: facts.SymbolicPointeeId, right: facts.SymbolicPointeeId) bool {
        const namespace = self.tracker.namespace orelse return left == right;
        var a = left;
        var b = right;
        var a_depth = self.symbolicStorageDepth(a);
        var b_depth = self.symbolicStorageDepth(b);
        // Compare paths at the same depth. Peeling unequal paths together can
        // turn distinct sibling fields into an apparent ancestor relationship.
        while (a_depth > b_depth) : (a_depth -= 1)
            a = namespace.projected_storage.items[self.symbolicProjectionIndex(a).?].parent;
        while (b_depth > a_depth) : (b_depth -= 1)
            b = namespace.projected_storage.items[self.symbolicProjectionIndex(b).?].parent;
        while (true) {
            if (a == b) return true;
            const a_index = self.symbolicProjectionIndex(a) orelse return false;
            const b_index = self.symbolicProjectionIndex(b) orelse return false;
            const first = namespace.projected_storage.items[a_index];
            const second = namespace.projected_storage.items[b_index];
            if (first.parent == second.parent or std.meta.eql(namespace.embeddedBase(first.parent), namespace.embeddedBase(second.parent))) {
                if (first.selector.projection == .dynamic_index or second.selector.projection == .dynamic_index) return true;
                if (first.selector.eql(second.selector)) return true;
                if (first.selector.projection != .field or second.selector.projection != .field) return false;
                const container = if (self.symbolicPointee(first.parent)) |parent|
                    parent.ty
                else if (namespace.projectionIndex(first.parent)) |index|
                    namespace.projected_storage.items[index].ty
                else
                    null;
                return @import("access_bounds.zig").fieldsMayOverlap(graph, container);
            }
            a = first.parent;
            b = second.parent;
        }
    }

    pub fn symbolicStorageDescendsFrom(self: *const State, child: facts.SymbolicPointeeId, parent: facts.SymbolicPointeeId) bool {
        return child != parent and self.symbolicStorageContains(parent, child);
    }

    pub fn initialProjectedPointee(self: *const State, identity: facts.SymbolicPointeeId) ?SymbolicPointeeState {
        const namespace = self.tracker.namespace orelse return null;
        const index = namespace.projectionIndex(identity) orelse return null;
        const projected = namespace.projected_storage.items[index];
        if (self.symbolicPointee(projected.parent)) |parent| {
            if (parent.generation != projected.parent_generation or parent.initializedness != .initialized or
                !self.tracker.isAlive(projected.parent_generation)) return null;
        } else {
            const parent = self.initialProjectedPointee(projected.parent) orelse return null;
            if (parent.generation != projected.parent_generation) return null;
        }
        for ([_]facts.ValidityRootId{ projected.backing, projected.generation }) |root| {
            const ordinal = @intFromEnum(root);
            const roots = self.tracker.roots.items;
            if (ordinal < roots.len and roots[ordinal].present and !self.tracker.isAlive(root)) return null;
        }
        return .{ .identity = identity, .ty = projected.ty, .initializedness = .initialized, .backing = projected.backing, .generation = projected.generation };
    }

    pub fn symbolicVariant(self: *const State, identity: facts.SymbolicPointeeId) ?u32 {
        for (self.symbolic_values.items) |stored| if (stored.identity == identity) return stored.value.known_choice_variant;
        return null;
    }

    pub fn renewSymbolicAccess(self: *State, pointer: facts.ValueFacts) !?facts.ValueFacts {
        // A join of possible targets cannot establish one definite destination.
        if (pointer.reference_target_incomplete or pointer.symbolic_pointees.len != 1 or pointer.opaque_provenance.len != 0) return null;
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
    try state.opaque_storages.append(.{ .storage = .{ .place = storage }, .hidden_dependencies = &.{} });
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
            if (existing) try state.opaque_storages.append(.{ .storage = .{ .place = storage }, .hidden_dependencies = &.{root0}, .owner_roots = &.{root2}, .outcome_guard = 9 });
            var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = failure_index });
            state.opaque_storages.allocator = failing.allocator();
            state.tracker.allocator = failing.allocator();
            const merged = state.mergeOpaqueStorage(.{ .place = storage }, &.{ root0, root1, root1 }, &.{ root2, root3, root3 });
            state.opaque_storages.allocator = a;
            state.tracker.allocator = a;
            if (merged) |_| {
                const domain = state.opaque_storages.items[0];
                try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ root0, root1 }, domain.hidden_dependencies);
                try std.testing.expectEqualSlices(facts.ValidityRootId, &.{ root2, root3 }, domain.owner_roots);
                var unavailable = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
                state.opaque_storages.allocator = unavailable.allocator();
                state.tracker.allocator = unavailable.allocator();
                try state.mergeOpaqueStorage(.{ .place = storage }, &.{ root1, root0 }, &.{ root3, root2 });
                try state.mergeOpaqueOwnerRoots(.{ .place = storage }, &.{root3});
                state.opaque_storages.allocator = a;
                state.tracker.allocator = a;
                try std.testing.expectEqual(domain.hidden_dependencies.ptr, state.opaque_storages.items[0].hidden_dependencies.ptr);
                try std.testing.expectEqual(domain.owner_roots.ptr, state.opaque_storages.items[0].owner_roots.ptr);
                state.markOpaqueStorageEmpty(.{ .place = storage });
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

test "Safety symbolic projection partitions keep observations separate from backing" {
    const allocator = std.testing.allocator;
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(allocator);
    var state = State.init(allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    var input = try state.establishSymbolicInput(@enumFromInt(0), null);
    const other = try state.establishSymbolicInput(@enumFromInt(0), input.backing);
    try std.testing.expect(!std.meta.eql(namespace.embeddedBase(input.identity), namespace.embeddedBase(other.identity)));

    const prior = (try state.projectSymbolicStorage(input, .{ .field = 0 }, null)).?;
    const prior_domain = (try state.projectSymbolicDomain(input, 0)).?;
    input.generation = try state.tracker.establish(.fresh);
    const current = (try state.projectSymbolicStorage(input, .{ .field = 0 }, null)).?;
    const current_domain = (try state.projectSymbolicDomain(input, 0)).?;
    try std.testing.expect(prior.identity != current.identity);
    try std.testing.expect(prior.generation != current.generation);
    try std.testing.expectEqualDeep(namespace.embeddedBase(prior.identity), namespace.embeddedBase(current.identity));
    try std.testing.expect(!std.meta.eql(namespace.embeddedBase(prior_domain.identity), namespace.embeddedBase(current_domain.identity)));
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
                try state.mergeOpaqueStorage(.{ .place = storage }, &.{generation}, &.{generation});
                break :original try state.cloneWithAllocators(fact_allocator, table_allocator);
            };
            defer branch.deinit();
            const generation = try branch.storageGeneration(storage);
            try std.testing.expect(branch.tracker.isAlive(generation));
            try std.testing.expectEqual(generation, branch.opaque_storages.items[0].hidden_dependencies[0]);
            const other = try branch.storageGeneration(.{ .root = @enumFromInt(1) });
            try branch.mergeOpaqueOwnerRoots(.{ .place = storage }, &.{other});
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
        .{ .parent = parent, .parent_generation = root, .selector = .{ .projection = .{ .field = 0 } }, .identity = field, .backing = root, .generation = root },
        .{ .parent = field, .parent_generation = root, .selector = .{ .projection = .dereference }, .identity = referent, .backing = root, .generation = root },
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

test "Safety symbolic overlap uses union layout across parent generations" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_union } },
    });
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(allocator);
    var state = State.init(allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    for (0..2) |index| {
        var parent = try state.establishSymbolicInput(@enumFromInt(index), null);
        const prior = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
        const generation = try state.tracker.establish(.fresh);
        parent.generation = generation;
        const other = (try state.projectSymbolicStorage(parent, .{ .field = 1 }, null)).?;
        const current = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
        try std.testing.expect(prior.identity != current.identity);
        try std.testing.expect(state.symbolicStorageMayOverlap(&graph, prior.identity, current.identity));
        try std.testing.expectEqual(index == 1, state.symbolicStorageMayOverlap(&graph, prior.identity, other.identity));
        try std.testing.expectEqual(index == 1, state.symbolicStorageMayOverlap(&graph, other.identity, prior.identity));
    }
}

test "Safety symbolic overlap compares unequal-depth paths at their common ancestor" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } });
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(allocator);
    var state = State.init(allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const generation: facts.ValidityRootId = @enumFromInt(0);
    try state.symbolic_pointees.append(.{ .identity = @enumFromInt(0), .generation = generation, .initializedness = .initialized, .ty = @enumFromInt(0) });
    // owner.first.shape and owner.second.allocation.receipt have different
    // depths but remain disjoint. Unknown array indices remain conservative.
    const edges = [_]struct { parent: u32, field: facts.Projection }{
        .{ .parent = 0, .field = .{ .field = 0 } },
        .{ .parent = 0, .field = .{ .field = 1 } },
        .{ .parent = 1, .field = .{ .field = 3 } },
        .{ .parent = 2, .field = .{ .field = 0 } },
        .{ .parent = 4, .field = .{ .field = 0 } },
        .{ .parent = 0, .field = .dynamic_index },
        .{ .parent = 6, .field = .{ .field = 0 } },
        .{ .parent = 0, .field = .dereference },
        .{ .parent = 0, .field = .{ .static_index = 0 } },
        .{ .parent = 0, .field = .{ .static_index = 1 } },
        .{ .parent = 9, .field = .{ .field = 0 } },
        .{ .parent = 10, .field = .{ .field = 0 } },
    };
    for (edges, 1..) |edge, identity| try namespace.projected_storage.append(allocator, .{
        .parent = @enumFromInt(edge.parent),
        .selector = .{ .projection = edge.field },
        .parent_generation = generation,
        .identity = @enumFromInt(identity),
        .backing = @enumFromInt(identity),
        .generation = generation,
    });
    try namespace.projected_storage.append(allocator, .{
        .parent = @enumFromInt(0),
        .selector = .{ .projection = .{ .field = 1 } },
        .parent_generation = @enumFromInt(1),
        .identity = @enumFromInt(13),
        .backing = @enumFromInt(2),
        .generation = generation,
    });
    for ([_][2]u32{ .{ 3, 5 }, .{ 1, 5 }, .{ 3, 8 }, .{ 9, 10 }, .{ 11, 12 }, .{ 1, 13 } }) |pair| {
        try std.testing.expect(!state.symbolicStorageMayOverlap(&graph, @enumFromInt(pair[0]), @enumFromInt(pair[1])));
        try std.testing.expect(!state.symbolicStorageMayOverlap(&graph, @enumFromInt(pair[1]), @enumFromInt(pair[0])));
    }
    for ([_][2]u32{ .{ 0, 5 }, .{ 2, 5 }, .{ 5, 5 }, .{ 3, 7 }, .{ 2, 13 } }) |pair| {
        try std.testing.expect(state.symbolicStorageMayOverlap(&graph, @enumFromInt(pair[0]), @enumFromInt(pair[1])));
        try std.testing.expect(state.symbolicStorageMayOverlap(&graph, @enumFromInt(pair[1]), @enumFromInt(pair[0])));
    }
}

test "execution receipts keep distinct identities across branches and completion" {
    const a = std.testing.allocator;
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(a);
    var state = State.init(a);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const first = try state.establishExecution(&.{});
    var branch = try state.clone(a);
    defer branch.deinit();
    const second = try branch.establishExecution(&.{});
    const third = try state.establishExecution(&.{});
    try std.testing.expect(first != second and second != third and first != third);
    branch.completeExecution(first);
    try std.testing.expect(!branch.executionPending(first));
    try std.testing.expect(state.executionPending(first));
    try std.testing.expect(branch.executionPending(second));
    state.completeExecution(first);
    try std.testing.expect(state.executionPending(third));
    const later = try state.establishExecution(&.{});
    try std.testing.expect(later != first);
}

test "execution joins preserve interleaved identities and completion in either branch order" {
    const left = [_]facts.ExecutionState{
        .{ .id = @enumFromInt(0), .loans = &.{}, .pending = false },
        .{ .id = @enumFromInt(2), .loans = &.{}, .pending = false },
        .{ .id = @enumFromInt(3), .loans = &.{} },
    };
    const right = [_]facts.ExecutionState{
        .{ .id = @enumFromInt(0), .loans = &.{}, .pending = false },
        .{ .id = @enumFromInt(1), .loans = &.{} },
        .{ .id = @enumFromInt(2), .loans = &.{} },
        .{ .id = @enumFromInt(4), .loans = &.{}, .pending = false },
    };
    for ([_]bool{ false, true }) |reverse| {
        var joined = State.init(std.testing.allocator);
        defer joined.deinit();
        try joined.joinExecutions(if (reverse) &right else &left, if (reverse) &left else &right);
        const expected = [_]bool{ false, true, true, true, false };
        try std.testing.expectEqual(expected.len, joined.executions.items.len);
        for (joined.executions.items, expected, 0..) |entry, pending, index| {
            try std.testing.expectEqual(index, @intFromEnum(entry.id));
            try std.testing.expectEqual(pending, entry.pending);
        }
    }
}

test "pending execution equality ignores completed history and compares receipt identities" {
    var left = State.init(std.testing.allocator);
    defer left.deinit();
    var right = State.init(std.testing.allocator);
    defer right.deinit();
    for (0..5) |i| {
        if (i != 3) try left.executions.append(.{ .id = @enumFromInt(i), .loans = &.{}, .pending = i == 1 });
        if (i != 0) try right.executions.append(.{ .id = @enumFromInt(i), .loans = &.{}, .pending = i == 1 });
    }
    try std.testing.expect(left.samePendingExecutions(&right));
    try std.testing.expect(right.samePendingExecutions(&left));
    const extra = try right.establishExecution(&.{});
    try std.testing.expect(!left.samePendingExecutions(&right));
    try std.testing.expect(!right.samePendingExecutions(&left));
    right.completeExecution(@enumFromInt(1));
    try std.testing.expect(!left.samePendingExecutions(&right));
    left.completeExecution(@enumFromInt(1));
    right.completeExecution(extra);
    try std.testing.expect(left.samePendingExecutions(&right));
}

test "execution joins retain equivalent output facts stored separately" {
    const allocator = std.testing.allocator;
    var left = State.init(allocator);
    defer left.deinit();
    var right = State.init(allocator);
    defer right.deinit();
    var joined = State.init(allocator);
    defer joined.deinit();
    const id = try left.establishExecution(&.{});
    try std.testing.expectEqual(id, try right.establishExecution(&.{}));
    var first: facts.ValueFacts = .{ .known_choice_variant = 0 };
    var second: facts.ValueFacts = .{ .known_choice_variant = 0 };
    try std.testing.expect(left.retainExecutionOutput(id, &first));
    try std.testing.expect(right.retainExecutionOutput(id, &second));
    try std.testing.expect(left.samePendingExecutions(&right));
    try joined.joinExecutions(left.executions.items, right.executions.items);
    try std.testing.expect(joined.executionState(id).?.output == .retained);
    second.known_choice_variant = 1;
    try std.testing.expect(!left.samePendingExecutions(&right));
}

test "pending execution equality includes loan generations and access modes" {
    const allocator = std.testing.allocator;
    var left = State.init(allocator);
    defer left.deinit();
    var right = State.init(allocator);
    defer right.deinit();
    const original: facts.ExecutionLoan = .{ .mode = .write, .symbolic = @enumFromInt(3), .generations = &.{@enumFromInt(4)} };
    var loans = [_]facts.ExecutionLoan{original};
    const receipt = try left.establishExecution(&.{original});
    try std.testing.expectEqual(receipt, try right.establishExecution(&loans));
    try std.testing.expect(left.samePendingExecutions(&right));
    loans[0].generations = &.{@enumFromInt(5)};
    try std.testing.expect(!left.samePendingExecutions(&right));
    loans[0] = original;
    loans[0].mode = .read;
    try std.testing.expect(!left.samePendingExecutions(&right));
    left.completeExecution(receipt);
    right.completeExecution(receipt);
    try std.testing.expect(left.samePendingExecutions(&right));
}

test "completing a receipt absent from this branch preserves nearby loans" {
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(std.testing.allocator);
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const first = try state.establishExecution(&.{});
    var branch = try state.clone(std.testing.allocator);
    defer branch.deinit();
    const absent = try branch.establishExecution(&.{});
    const last = try state.establishExecution(&.{});
    state.completeExecution(absent);
    try std.testing.expect(state.executionState(absent) == null);
    try std.testing.expect(state.executionPending(first));
    try std.testing.expect(state.executionPending(last));
    state.completeExecution(last);
    try std.testing.expect(state.executionPending(first));
    try std.testing.expect(!state.executionPending(last));
    try std.testing.expect(branch.executionPending(absent));
}

fn executionReceiptAllocation(allocator: std.mem.Allocator) !void {
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(allocator);
    var state = State.init(allocator);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const source: primitives.SourceRef = .{ .file_index = 2, .offset = 17 };
    const first = state.establishExecutionAt(&.{}, source) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), state.executions.items.len);
        try std.testing.expectEqual(@as(u32, 0), namespace.next_execution_id);
        return err;
    };
    try std.testing.expectEqual(source, state.executionState(first).?.origin.?);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(first));
    try std.testing.expectEqual(@as(u32, 1), namespace.next_execution_id);
}

test "execution receipt allocation commits its identity only after success" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, executionReceiptAllocation, .{});
}

test "virtual captured domains have stable identities distinct from handle bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var namespace: facts.Tracker.RootNamespace = .{ .next_symbolic_id = 1 };
    defer namespace.deinit(a);
    var state = State.init(a);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const generation = try state.tracker.establish(.fresh);
    const parent: SymbolicPointeeState = .{ .identity = @enumFromInt(0), .initializedness = .initialized, .generation = generation };
    try state.symbolic_pointees.append(parent);
    const first = (try state.projectSymbolicDomain(parent, 0)).?;
    const second = (try state.projectSymbolicDomain(parent, 1)).?;
    const field = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
    try std.testing.expect(first.identity != second.identity and first.identity != field.identity);
    try std.testing.expect(!state.symbolicStorageContains(parent.identity, first.identity));
    try std.testing.expect(state.symbolicStorageContains(parent.identity, field.identity));
    try std.testing.expectEqual(first.identity, (try state.projectSymbolicDomain(parent, 0)).?.identity);
    var branch = try state.clone(a);
    defer branch.deinit();
    try std.testing.expectEqual(first.identity, (try branch.projectSymbolicDomain(parent, 0)).?.identity);
    var replacement = parent;
    replacement.generation = try state.tracker.establish(.fresh);
    const later = (try state.projectSymbolicDomain(replacement, 0)).?;
    try std.testing.expect(later.identity != first.identity);
    try std.testing.expect(state.domainGenerationIsCurrent(.{ .symbolic = first.identity }, first.generation));
    try state.mergeOpaqueStorage(.{ .symbolic = first.identity }, &.{generation}, &.{});
    try state.mergeOpaqueStorage(.{ .symbolic = second.identity }, &.{generation}, &.{});
    state.markOpaqueStorageEmpty(.{ .symbolic = first.identity });
    try std.testing.expectEqual(@as(usize, 2), state.opaque_storages.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.opaque_storages.items[0].hidden_dependencies.len);
    try std.testing.expectEqualSlices(facts.ValidityRootId, &.{generation}, state.opaque_storages.items[1].hidden_dependencies);
}

test "lexical reference frames exclude only later storage and survive generation changes" {
    const a = std.testing.allocator;
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(a);
    var state = State.init(a);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const first = facts.Place{ .root = @enumFromInt(0) };
    const later = facts.Place{ .root = @enumFromInt(1) };
    const external = facts.Place{ .root = @enumFromInt(2) };
    try state.beginLexicalStorage(first);
    const frame = state.lexicalFrame().?;
    const generation = try state.storageGeneration(first);
    try state.beginLexicalStorage(later);
    try std.testing.expect(!state.frameExcludesStorage(frame, first));
    try std.testing.expect(state.frameExcludesStorage(frame, later));
    try std.testing.expect(!state.frameExcludesStorage(frame, external));
    try std.testing.expect(!state.frameExcludesStorage(frame, .{ .root = later.root, .projections = &.{.dereference} }));
    try std.testing.expect(state.frameExcludesStorage(frame, .{ .root = later.root, .projections = &.{.{ .field = 0 }} }));
    try state.refreshStorageGeneration(first);
    try std.testing.expect(generation != try state.storageGeneration(first));
    try std.testing.expect(!state.frameExcludesStorage(frame, first));
    // Repeated loop declarations and branch copies cannot assign a later birth
    // to existing backing. The shared first observation is conservative.
    var branch = try state.clone(a);
    defer branch.deinit();
    try branch.beginLexicalStorage(first);
    try std.testing.expectEqual(@as(usize, 2), namespace.lexical_allocations.count());
    try std.testing.expectEqual(state.lexicalFrame(), branch.lexicalFrame());
    // Address formation can observe storage before its declaration is visited.
    try state.observeLexicalStorage(external.root, true);
    // Even an earlier frame cannot exclude storage first encountered by an
    // address observation: that observation does not establish its birth.
    try std.testing.expect(!state.frameExcludesStorage(0, external));
    const before_declaration = state.lexicalFrame().?;
    try state.beginLexicalStorage(external);
    try std.testing.expect(!state.frameExcludesStorage(before_declaration, external));
    var copied_namespace = try namespace.clone(a);
    defer copied_namespace.deinit(a);
    try std.testing.expectEqual(namespace.lexical_allocations.count(), copied_namespace.lexical_allocations.count());
    try std.testing.expectEqualSlices(graph_mod.GlobalBindingId, namespace.lexical_allocations.keys(), copied_namespace.lexical_allocations.keys());
    try std.testing.expectEqualSlices(bool, namespace.lexical_allocations.values(), copied_namespace.lexical_allocations.values());
}

test "Safety incomplete symbolic targets cannot renew or initialize a candidate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var state = State.init(arena.allocator());
    defer state.deinit();
    const backing = try state.tracker.establish(.fresh);
    const generation = try state.tracker.establish(.fresh);
    const identity: facts.SymbolicPointeeId = @enumFromInt(0);
    try state.symbolic_pointees.append(.{ .identity = identity, .initializedness = .deinitialized, .backing = backing, .generation = generation });
    const pointer: facts.ValueFacts = .{ .symbolic_pointees = &.{identity}, .dependencies = &.{ .{ .root = backing }, .{ .root = generation } } };
    var partial = pointer;
    partial.reference_target_incomplete = true;
    state.initializeLiveSymbolicTargets(partial);
    try std.testing.expectEqual(.deinitialized, state.symbolicPointee(identity).?.initializedness);
    state.tracker.end(generation);
    try std.testing.expect(try state.renewSymbolicAccess(partial) == null);
    try std.testing.expect(!state.tracker.isAlive(generation));
    try std.testing.expect(try state.renewSymbolicAccess(pointer) != null);
}

test "joining an already claimed execution output does not restore custody" {
    const allocator = std.testing.allocator;
    var left = State.init(allocator);
    defer left.deinit();
    const id = try left.establishExecution(&.{});
    try std.testing.expect(left.retainExecutionOutput(id, &facts.empty_value_facts));
    left.completeExecution(id);
    var right = try left.clone(allocator);
    defer right.deinit();
    try std.testing.expect(right.consumeExecutionOutput(id) != null);
    try std.testing.expect(!left.samePendingExecutions(&right));
    for ([_]bool{ false, true }) |reverse| {
        var joined = State.init(allocator);
        defer joined.deinit();
        try joined.joinExecutions(if (reverse) right.executions.items else left.executions.items, if (reverse) left.executions.items else right.executions.items);
        try std.testing.expect(joined.consumeExecutionOutput(id) == null);
    }
}

test "loop execution equality preserves consumed output access evidence" {
    const allocator = std.testing.allocator;
    var absent = State.init(allocator);
    defer absent.deinit();
    var completed = State.init(allocator);
    defer completed.deinit();
    const id = try completed.establishExecution(&.{});
    try std.testing.expect(completed.retainExecutionOutput(id, &facts.empty_value_facts));
    completed.completeExecution(id);
    try std.testing.expect(completed.consumeExecutionOutput(id) != null);

    try std.testing.expect(!absent.samePendingExecutions(&completed));
    try std.testing.expect(!completed.samePendingExecutions(&absent));

    completed.executions.items[0].output = .{ .consumed = null };
    try std.testing.expect(absent.samePendingExecutions(&completed));
    try std.testing.expect(completed.samePendingExecutions(&absent));

    completed.executions.items[0].pending = true;
    try absent.executions.append(.{ .id = id, .loans = &.{} });
    try std.testing.expect(!absent.samePendingExecutions(&completed));
    try std.testing.expect(!completed.samePendingExecutions(&absent));
}

test "lazy symbolic projections require a live parent observation" {
    const a = std.testing.allocator;
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(a);
    var state = State.init(a);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    const parent = try state.establishSymbolicInput(@enumFromInt(0), null);
    var sibling = try state.clone(a);
    defer sibling.deinit();
    const field = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
    try std.testing.expect(sibling.initialProjectedPointee(field.identity) != null);

    sibling.tracker.end(parent.generation.?);
    try std.testing.expect(sibling.initialProjectedPointee(field.identity) == null);
    sibling.symbolic_pointees.items[0].generation = try sibling.tracker.establish(.fresh);
    try std.testing.expectEqual(null, try sibling.projectSymbolicStorage(parent, .{ .field = 0 }, null));
    try std.testing.expectEqual(null, try sibling.projectSymbolicStorage(parent, .{ .field = 1 }, null));
    try std.testing.expectEqual(@as(usize, 1), namespace.projected_storage.items.len);
}

test "embedded symbolic fields keep backing across parent replacement" {
    const a = std.testing.allocator;
    var namespace: facts.Tracker.RootNamespace = .{};
    defer namespace.deinit(a);
    var state = State.init(a);
    defer state.deinit();
    state.tracker.namespace = &namespace;
    var parent = try state.establishSymbolicInput(@enumFromInt(0), null);
    const first = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
    const first_domain = (try state.projectSymbolicDomain(parent, 0)).?;
    const first_nested = (try state.projectSymbolicStorage(state.symbolicPointee(first.identity).?, .{ .field = 1 }, null)).?;
    state.tracker.end(parent.generation.?);
    parent.generation = try state.tracker.establish(.fresh);
    state.symbolic_pointees.items[0] = parent;
    const current = (try state.projectSymbolicStorage(parent, .{ .field = 0 }, null)).?;
    const current_domain = (try state.projectSymbolicDomain(parent, 0)).?;
    const current_nested = (try state.projectSymbolicStorage(state.symbolicPointee(current.identity).?, .{ .field = 1 }, null)).?;

    const old_domain_field = (try state.projectSymbolicStorage(state.symbolicPointee(first_domain.identity).?, .{ .field = 2 }, null)).?;
    const new_domain_field = (try state.projectSymbolicStorage(state.symbolicPointee(current_domain.identity).?, .{ .field = 2 }, null)).?;
    try std.testing.expectEqual(namespace.projectionPartition(old_domain_field.identity), namespace.projectionPartition(new_domain_field.identity));
    try std.testing.expect(state.symbolicPointee(old_domain_field.identity).?.backing != state.symbolicPointee(new_domain_field.identity).?.backing);
    const other_domain = (try state.projectSymbolicDomain(parent, 1)).?;
    const first_key = namespace.projectionPartition(first_domain.identity).?;
    try std.testing.expectEqual(first_key, namespace.projectionPartition(current_domain.identity).?);
    try std.testing.expect(!std.meta.eql(first_key, namespace.projectionPartition(other_domain.identity).?));
    try std.testing.expect(!std.meta.eql(first_key, namespace.projectionPartition(current.identity).?));
    try std.testing.expectEqual(namespace.projectionPartition(first.identity), namespace.projectionPartition(current.identity));
    try std.testing.expectEqual(namespace.projectionPartition(first_nested.identity), namespace.projectionPartition(current_nested.identity));

    try std.testing.expect(first_nested.generation != current_nested.generation);
    try std.testing.expectEqual(state.symbolicPointee(first_nested.identity).?.backing, state.symbolicPointee(current_nested.identity).?.backing);
    try std.testing.expect(first.identity != current.identity);
    try std.testing.expect(first.generation != current.generation);
    try std.testing.expectEqual(state.symbolicPointee(first.identity).?.backing, state.symbolicPointee(current.identity).?.backing);
    try std.testing.expect(state.symbolicPointee(first_domain.identity).?.backing != state.symbolicPointee(current_domain.identity).?.backing);
}
