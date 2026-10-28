const std = @import("std");
const graph = @import("../global/graph.zig");
const place_mod = @import("place.zig");
const base = @import("safety_facts.zig");
const value_state = @import("value_state.zig");
const primitives = @import("../primitives/schema.zig");

pub const Place = place_mod.PlaceFor(graph.GlobalBindingId);
pub const Projection = place_mod.Projection;

// Function-local identity of an unknown referent. A record input can contain
// several such accesses; its binding identity cannot distinguish them.
pub const SymbolicPointeeId = enum(u32) { _ };

// Summary/effect vocabulary contains no graph pointers and is shared verbatim.
pub const ValidityRootId = base.ValidityRootId;
pub const StorageCapabilityId = base.StorageCapabilityId;
pub const ValidityRoot = base.ValidityRoot;
pub const ValidityDependency = base.ValidityDependency;
pub const ValidityRootEstablishment = base.ValidityRootEstablishment;
pub const InputPath = base.InputPath;
pub const InputDependency = base.InputDependency;
pub const InputDomain = base.InputDomain;
pub const OutputFieldEffect = base.OutputFieldEffect;
pub const OutputDomainEffect = base.OutputDomainEffect;
pub const FreshEffectSource = base.FreshEffectSource;
pub const ValueEffect = base.ValueEffect;
pub const OutputVariantEffect = base.OutputVariantEffect;
pub const PlacePostState = base.PlacePostState;
pub const StorageObservationConflict = base.StorageObservationConflict;
pub const OpaqueOwnershipConsumption = base.OpaqueOwnershipConsumption;
pub const StorageCapabilityUse = base.StorageCapabilityUse;
pub const StorageCapabilityConflict = base.StorageCapabilityConflict;
pub const FreshStorageCapabilityState = base.FreshStorageCapabilityState;
pub const SafetySummary = base.SafetySummary;
pub const ChoiceCondition = base.ChoiceCondition;
pub const ChoiceConditions = base.ChoiceConditions;
pub const GuardedSafetyEffects = base.GuardedSafetyEffects;
pub const OutcomePostStates = base.OutcomePostStates;
pub const OpaqueStorageEffect = base.OpaqueStorageEffect;

pub const OpaqueProvenance = struct {
    storage: Place,
    generation: ValidityRootId,
};

pub const GenerationOutcome = struct {
    storage: Place,
    generation: ValidityRootId,
    guard: u64,
    invalidates: bool,
    /// Discharge only hidden contents guarded by this call and generation.
    /// This does not end, initialize or restore a resource.
    empties_opaque_storage: bool = false,
    /// Resource proofs retain identities, never snapshots of caller values.
    resource_state: ?value_state.Initializedness = null,
    owned_roots: []const ValidityRootId = &.{},
    relocation: ?Relocation = null,
    source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 },

    pub const Relocation = struct {
        destination: Place,
        generation: ValidityRootId,
        available_state: value_state.Initializedness,
        moved: bool,

        fn eql(self: Relocation, other: Relocation) bool {
            return self.destination.eql(other.destination) and self.generation == other.generation and
                self.available_state == other.available_state and self.moved == other.moved;
        }
    };

    pub fn eql(self: GenerationOutcome, other: GenerationOutcome) bool {
        if (self.relocation) |relocation| {
            if (other.relocation == null or !relocation.eql(other.relocation.?)) return false;
        } else if (other.relocation != null) return false;
        return self.generation == other.generation and self.guard == other.guard and
            self.invalidates == other.invalidates and self.empties_opaque_storage == other.empties_opaque_storage and self.resource_state == other.resource_state and
            std.mem.eql(ValidityRootId, self.owned_roots, other.owned_roots) and self.storage.eql(other.storage);
    }
};

pub const CallChoiceSelector = struct {
    call: u64,
    selector: ChoiceCondition,

    pub fn eql(a: CallChoiceSelector, b: CallChoiceSelector) bool {
        return a.call == b.call and a.selector.eql(b.selector);
    }
};

pub const GuardedValueFacts = struct {
    call: u64,
    conditions: ChoiceConditions,
    entry_facts: ChoiceConditions,
    value: *const ValueFacts,

    pub fn eql(a: GuardedValueFacts, b: GuardedValueFacts) bool {
        return a.call == b.call and a.value == b.value and a.conditions.eql(b.conditions) and a.entry_facts.eql(b.entry_facts);
    }
};

pub const ValueFacts = struct {
    /// A user-declared dependency must be checked on ordinary value reads,
    /// including scalars. Other dependencies retain their operation-specific
    /// checks, such as pointer dereference and opaque storage release.
    explicit_dependency: bool = false,
    dependencies: []const ValidityDependency = &.{},
    owned_roots: []const ValidityRootId = &.{},
    fields: []const FieldFacts = &.{},
    variants: []const VariantFacts = &.{},
    known_choice_variant: ?u32 = null,
    integer_address: bool = false,
    foreign_storage: bool = false,
    storage_capabilities: []const StorageCapabilityId = &.{},
    referenced_place: ?Place = null,
    /// Unknown parameter referents have consumption identities, not concrete
    /// places or owned roots. Copies retain them without granting validity.
    symbolic_pointees: []const SymbolicPointeeId = &.{},
    opaque_provenance: []const OpaqueProvenance = &.{},
    /// Concrete vtable method identities carried by a `Virtual` value. Keeping
    /// this in transient safety facts lets exact dispatch survive bindings and
    /// ordinary value copies without reintroducing graph-object identity.
    virtual_methods: []const graph.GlobalFunctionId = &.{},
    domains: []const DomainFacts = &.{},
    generation_outcomes: []const GenerationOutcome = &.{},
    choice_selectors: []const CallChoiceSelector = &.{},
    choice_observations: []const CallChoiceSelector = &.{},
    guarded_values: []const GuardedValueFacts = &.{},

    pub fn referenceCopy(self: ValueFacts) ValueFacts {
        return .{
            .explicit_dependency = self.explicit_dependency,
            .dependencies = self.dependencies,
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_capabilities = self.storage_capabilities,
            .referenced_place = self.referenced_place,
            .symbolic_pointees = self.symbolic_pointees,
            .opaque_provenance = self.opaque_provenance,
            .virtual_methods = self.virtual_methods,
            .domains = self.domains,
            .generation_outcomes = self.generation_outcomes,
            .choice_selectors = self.choice_selectors,
            .choice_observations = self.choice_observations,
            .guarded_values = self.guarded_values,
        };
    }

    /// Scalar values loaded from opaque storage retain physical/raw-storage
    /// facts, but not the lifetime envelope of the container that happened to
    /// hold them. This is the indexed equivalent of the legacy checker's
    /// scalar opaque-read rule and prevents conservative parent projections
    /// from manufacturing dependencies or ownership for plain scalar values.
    pub fn scalarOpaqueRead(self: ValueFacts) ValueFacts {
        return .{
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_capabilities = self.storage_capabilities,
            .choice_selectors = self.choice_selectors,
            .choice_observations = self.choice_observations,
        };
    }
};

/// Domain storage identities remain usable across handle copies. Current
/// generations are looked up at the call, while returned borrows capture the
/// old generation. Domain invalidation never transfers cleanup ownership.
pub const DomainFacts = struct { domain_index: u32, storages: []const Place };

/// Only a wholly empty value may omit its element records. In a mixed
/// aggregate, explicit empty children prevent projection from inheriting
/// a sibling's dependency or ownership facts from the aggregate envelope.
pub fn isEmptyValue(value: anytype) bool {
    inline for (@typeInfo(@TypeOf(value)).@"struct".fields) |field| {
        const item = @field(value, field.name);
        switch (@typeInfo(field.type)) {
            .bool => if (item) return false,
            .optional => if (item != null) return false,
            .pointer => if (item.len != 0) return false,
            else => @compileError("Update empty safety value detection for the new field kind"),
        }
    }
    return true;
}

pub const empty_value_facts: ValueFacts = .{};
pub const empty_value_effect: ValueEffect = .{};

pub const FieldFacts = struct {
    index: u32,
    value: *const ValueFacts,
};

pub const VariantFacts = struct {
    index: u32,
    value: *const ValueFacts,
};

pub const PlaceFacts = struct {
    storage: Place,
    initializedness: value_state.Initializedness = .initialized,
    moved_at: ?primitives.SourceRef = null,
    value: ValueFacts = .{},
};

pub const Tracker = struct {
    /// Cloned branch states share identities, never reuse another branch's ID.
    pub const RootNamespace = struct {
        next_id: u32 = 0,
        next_symbolic_id: u32 = 0,
        next_capability_id: u32 = 0,
        projected_storage: std.ArrayList(struct {
            parent: SymbolicPointeeId,
            parent_generation: ValidityRootId,
            projection: Projection,
            identity: SymbolicPointeeId,
            backing: ValidityRootId,
            generation: ValidityRootId,
            ty: ?graph.GlobalTypeId = null,
        }) = .empty,
        initial_storage: std.ArrayList(struct { storage: Place, root: ValidityRootId }) = .empty,

        /// Independent session candidates copy allocation state; branches of
        /// one proof still share it. Immutable Place paths retain their arena.
        pub fn clone(self: *const RootNamespace, allocator: std.mem.Allocator) !RootNamespace {
            var result = self.*;
            result.initial_storage = try self.initial_storage.clone(allocator);
            errdefer result.initial_storage.deinit(allocator);
            result.projected_storage = try self.projected_storage.clone(allocator);
            return result;
        }
        pub fn deinit(self: *RootNamespace, allocator: std.mem.Allocator) void {
            self.initial_storage.deinit(allocator);
            self.projected_storage.deinit(allocator);
        }
    };
    namespace: ?*RootNamespace = null,
    allocator: std.mem.Allocator,
    roots: std.array_list.Managed(ValidityRoot),

    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .allocator = allocator, .roots = std.array_list.Managed(ValidityRoot).init(allocator) };
    }

    pub fn deinit(self: *Tracker) void {
        self.roots.deinit();
    }

    pub fn establish(self: *Tracker, rooting: ValidityRootEstablishment) !ValidityRootId {
        return switch (rooting) {
            .inherit => |root| root,
            .fresh => blk: {
                const index = if (self.namespace) |namespace| identity: {
                    const next = namespace.next_id;
                    if (next == std.math.maxInt(u32)) return error.SafetyRootIdentityLimit;
                    namespace.next_id += 1;
                    break :identity next;
                } else @as(u32, @intCast(self.roots.items.len));
                const id: ValidityRootId = @enumFromInt(index);
                try self.materialize(id);
                break :blk id;
            },
        };
    }

    /// Materialize an identity that exists on another branch without reviving
    /// a generation already observed and ended on this path.
    pub fn materialize(self: *Tracker, id: ValidityRootId) !void {
        const index = @intFromEnum(id);
        while (self.roots.items.len <= index) {
            const absent: ValidityRootId = @enumFromInt(self.roots.items.len);
            try self.roots.append(.{ .id = absent, .state = .dead, .present = false });
        }
        if (!self.roots.items[index].present) self.roots.items[index] = .{ .id = id };
    }

    pub fn end(self: *Tracker, id: ValidityRootId) void {
        self.roots.items[@intFromEnum(id)].state = .dead;
        self.roots.items[@intFromEnum(id)].outcome_guard = 0;
    }

    pub fn isAlive(self: *const Tracker, id: ValidityRootId) bool {
        return self.roots.items[@intFromEnum(id)].state == .alive;
    }

    pub fn dependenciesAreAlive(self: *const Tracker, facts: ValueFacts) bool {
        for (facts.dependencies) |dependency| if (!self.isAlive(dependency.root)) return false;
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

test "indexed safety facts key places by GlobalBindingId" {
    const binding: graph.GlobalBindingId = @enumFromInt(5);
    const storage = Place{ .root = binding };
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const root = try tracker.establish(.fresh);
    var source = PlaceFacts{ .storage = storage, .value = .{ .dependencies = &.{.{ .root = root }}, .owned_roots = &.{root} } };
    var destination = PlaceFacts{ .storage = storage, .initializedness = .deinitialized };
    Tracker.moveValue(&source, &destination);
    try std.testing.expectEqual(binding, destination.storage.root);
    try std.testing.expectEqual(root, destination.value.owned_roots[0]);
}

test "scalar opaque reads discard container lifetime facts" {
    const binding: graph.GlobalBindingId = @enumFromInt(7);
    const root: ValidityRootId = @enumFromInt(3);
    const capability: StorageCapabilityId = @enumFromInt(2);
    const method: graph.GlobalFunctionId = @enumFromInt(11);
    const value = ValueFacts{
        .dependencies = &.{.{ .root = root }},
        .owned_roots = &.{root},
        .integer_address = true,
        .foreign_storage = true,
        .storage_capabilities = &.{capability},
        .referenced_place = .{ .root = binding },
        .opaque_provenance = &.{.{ .storage = .{ .root = binding }, .generation = root }},
        .virtual_methods = &.{method},
    };

    const scalar = value.scalarOpaqueRead();
    try std.testing.expectEqual(@as(usize, 0), scalar.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.fields.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.variants.len);
    try std.testing.expectEqual(@as(?Place, null), scalar.referenced_place);
    try std.testing.expectEqual(@as(usize, 0), scalar.opaque_provenance.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.virtual_methods.len);
    try std.testing.expect(scalar.integer_address);
    try std.testing.expect(scalar.foreign_storage);
    try std.testing.expectEqualSlices(StorageCapabilityId, &.{capability}, scalar.storage_capabilities);
}

test "reference copies preserve virtual dispatch identity" {
    const method: graph.GlobalFunctionId = @enumFromInt(9);
    const copied = (ValueFacts{ .virtual_methods = &.{method} }).referenceCopy();
    try std.testing.expectEqualSlices(graph.GlobalFunctionId, &.{method}, copied.virtual_methods);
}

test "empty safety values retain explicit scalar and structural facts" {
    try std.testing.expect(isEmptyValue(ValueFacts{}));
    try std.testing.expect(isEmptyValue(ValueEffect{}));
    try std.testing.expect(!isEmptyValue(ValueFacts{ .foreign_storage = true }));
    try std.testing.expect(!isEmptyValue(ValueFacts{ .explicit_dependency = true }));
    try std.testing.expect(!isEmptyValue(ValueFacts{ .integer_address = true }));
    try std.testing.expect(!isEmptyValue(ValueFacts{ .known_choice_variant = 0 }));
    try std.testing.expect(!isEmptyValue(ValueFacts{ .fields = &.{.{ .index = 0, .value = &empty_value_facts }} }));
    try std.testing.expect(!isEmptyValue(ValueEffect{ .input_places = &.{.{ .input_index = 0 }} }));
    try std.testing.expect(!isEmptyValue(ValueEffect{ .input_storage_capabilities = &.{.{ .input_index = 0 }} }));
    try std.testing.expect(!isEmptyValue(ValueEffect{ .fields = &.{.{ .index = 0, .value = &empty_value_effect }} }));
}

fn cloneRootNamespace(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var original: Tracker.RootNamespace = .{ .next_id = 2 };
    defer original.deinit(a);
    try original.initial_storage.append(a, .{ .storage = .{ .root = @enumFromInt(3) }, .root = @enumFromInt(1) });
    original.next_symbolic_id = 4;
    original.next_capability_id = 7;
    try original.projected_storage.append(a, .{
        .parent = @enumFromInt(0),
        .parent_generation = @enumFromInt(1),
        .projection = .{ .field = 0 },
        .identity = @enumFromInt(3),
        .backing = @enumFromInt(0),
        .generation = @enumFromInt(1),
    });
    var candidate = try original.clone(allocator);
    defer candidate.deinit(allocator);
    var tracker = Tracker.init(allocator);
    defer tracker.deinit();
    tracker.namespace = &candidate;
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(try tracker.establish(.fresh)));
    candidate.initial_storage.items[0].root = @enumFromInt(2);
    candidate.projected_storage.items[0].projection = .{ .variant = 2 };
    candidate.next_symbolic_id = 5;
    candidate.next_capability_id = 8;
    try std.testing.expect(original.projected_storage.items[0].projection.eql(.{ .field = 0 }));
    try std.testing.expectEqual(@as(u32, 4), original.next_symbolic_id);
    try std.testing.expectEqual(@as(u32, 7), original.next_capability_id);
    try std.testing.expectEqual(@as(u32, 2), original.next_id);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(original.initial_storage.items[0].root));
    try std.testing.expectEqual(@as(u32, 3), candidate.next_id);
}

test "safety root namespaces fork candidate identities without changing accepted state" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneRootNamespace, .{});
}

test "safety root identity exhaustion cannot wrap into retained roots" {
    var namespace: Tracker.RootNamespace = .{ .next_id = std.math.maxInt(u32) };
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    tracker.namespace = &namespace;
    try std.testing.expectError(error.SafetyRootIdentityLimit, tracker.establish(.fresh));
    try std.testing.expectEqual(std.math.maxInt(u32), namespace.next_id);
    try std.testing.expectEqual(@as(usize, 0), tracker.roots.items.len);
}

/// Immutable fact fragments borrow the caller's proof allocation region.
pub fn replaceValueRoots(
    allocator: std.mem.Allocator,
    value: ValueFacts,
    sources: []const ValidityRootId,
    replacement: ValidityRootId,
) !ValueFacts {
    var result = value;
    var dependencies = std.array_list.Managed(ValidityDependency).init(allocator);
    for (value.dependencies) |dependency| {
        const next = if (std.mem.indexOfScalar(ValidityRootId, sources, dependency.root) != null) replacement else dependency.root;
        var present = false;
        for (dependencies.items) |entry| if (entry.root == next) {
            present = true;
            break;
        };
        if (!present) try dependencies.append(.{ .root = next });
    }
    result.dependencies = try dependencies.toOwnedSlice();
    var owned_roots = std.array_list.Managed(ValidityRootId).init(allocator);
    for (value.owned_roots) |root| {
        const next = if (std.mem.indexOfScalar(ValidityRootId, sources, root) != null) replacement else root;
        if (std.mem.indexOfScalar(ValidityRootId, owned_roots.items, next) == null) try owned_roots.append(next);
    }
    result.owned_roots = try owned_roots.toOwnedSlice();
    const fields = try allocator.alloc(FieldFacts, value.fields.len);
    for (value.fields, 0..) |field, index| {
        const stored = try allocator.create(ValueFacts);
        stored.* = try replaceValueRoots(allocator, field.value.*, sources, replacement);
        fields[index] = .{ .index = field.index, .value = stored };
    }
    result.fields = fields;
    const variants = try allocator.alloc(VariantFacts, value.variants.len);
    for (value.variants, 0..) |variant, index| {
        const stored = try allocator.create(ValueFacts);
        stored.* = try replaceValueRoots(allocator, variant.value.*, sources, replacement);
        variants[index] = .{ .index = variant.index, .value = stored };
    }
    result.variants = variants;
    return result;
}
