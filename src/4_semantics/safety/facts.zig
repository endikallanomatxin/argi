const std = @import("std");
const graph = @import("../global/graph.zig");
const place_mod = @import("../place.zig");
const base = @import("../safety_facts.zig");
const value_state = @import("../value_state.zig");

pub const Place = place_mod.PlaceFor(graph.GlobalBindingId);
pub const Projection = place_mod.Projection;

// Summary/effect vocabulary contains no graph pointers and is shared verbatim.
pub const ValidityRootId = base.ValidityRootId;
pub const StorageCapabilityId = base.StorageCapabilityId;
pub const ValidityRoot = base.ValidityRoot;
pub const ValidityDependency = base.ValidityDependency;
pub const ValidityRootEstablishment = base.ValidityRootEstablishment;
pub const InputPath = base.InputPath;
pub const InputDependency = base.InputDependency;
pub const OutputFieldEffect = base.OutputFieldEffect;
pub const FreshEffectSource = base.FreshEffectSource;
pub const ValueEffect = base.ValueEffect;
pub const OutputVariantEffect = base.OutputVariantEffect;
pub const PlacePostState = base.PlacePostState;
pub const OpaqueOwnershipConsumption = base.OpaqueOwnershipConsumption;
pub const SafetySummary = base.SafetySummary;
pub const OpaqueStorageEffect = base.OpaqueStorageEffect;

pub const OpaqueProvenance = struct {
    storage: Place,
    generation: ValidityRootId,
};

pub const ValueFacts = struct {
    dependencies: []const ValidityDependency = &.{},
    owned_roots: []const ValidityRootId = &.{},
    fields: []const FieldFacts = &.{},
    variants: []const VariantFacts = &.{},
    known_choice_variant: ?u32 = null,
    integer_address: bool = false,
    foreign_storage: bool = false,
    storage_capabilities: []const StorageCapabilityId = &.{},
    referenced_place: ?Place = null,
    opaque_provenance: []const OpaqueProvenance = &.{},
    /// Concrete vtable method identities carried by a `Virtual` value. Keeping
    /// this in transient safety facts lets exact dispatch survive bindings and
    /// ordinary value copies without reintroducing graph-object identity.
    virtual_methods: []const graph.GlobalFunctionId = &.{},

    pub fn referenceCopy(self: ValueFacts) ValueFacts {
        return .{
            .dependencies = self.dependencies,
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_capabilities = self.storage_capabilities,
            .referenced_place = self.referenced_place,
            .opaque_provenance = self.opaque_provenance,
            .virtual_methods = self.virtual_methods,
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
        };
    }
};

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
    value: ValueFacts = .{},
};

pub const Tracker = struct {
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
                const id: ValidityRootId = @enumFromInt(self.roots.items.len);
                try self.roots.append(.{ .id = id });
                break :blk id;
            },
        };
    }

    pub fn end(self: *Tracker, id: ValidityRootId) void {
        self.roots.items[@intFromEnum(id)].state = .dead;
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
