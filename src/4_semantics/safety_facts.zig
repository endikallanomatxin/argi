const std = @import("std");
const place = @import("place.zig");
const value_state = @import("value_state.zig");

pub const RootId = enum(u32) { _ };
pub const StorageAuthorityId = enum(u32) { _ };

pub const Root = struct {
    id: RootId,
    state: enum { alive, conditional, maybe_alive, dead } = .alive,
    owned_resource: bool = false,
};

pub const ReferenceDependency = struct {
    root: RootId,
};

/// Provenance of a pointer into one opaque storage domain. `storage` names the
/// structural domain while `generation` permanently names the temporal
/// generation observed when the provenance was established.
pub const OpaqueOrigin = struct {
    storage: place.Place,
    generation: RootId,
};

/// Facts travel with values. Dependencies and owned roots are intentionally
/// separate: copying a reference copies only its dependencies, while moving a
/// value transfers both lists.
pub const ValueFacts = struct {
    dependencies: []const ReferenceDependency = &.{},
    owned_roots: []const RootId = &.{},
    fields: []const FieldFacts = &.{},
    /// Mutually exclusive payload facts for a choice value. Unlike `fields`,
    /// these values do not all exist at once and are refined by a match arm.
    variants: []const VariantFacts = &.{},
    /// Runtime tag intrinsic to this concrete value. General choice values
    /// keep this null even when `variants` contains possible payload facts.
    known_choice_variant: ?u32 = null,
    integer_address: bool = false,
    foreign_storage: bool = false,
    storage_authorities: []const StorageAuthorityId = &.{},
    referenced_place: ?place.Place = null,
    /// Aggregate provenance for a pointer that accesses opaque storage
    /// domains. It identifies mutation destinations while the pointer is used
    /// for access and storage-generation dependencies when used as data.
    /// Entries identify domains, never individual slots.
    opaque_origins: []const OpaqueOrigin = &.{},

    pub fn referenceCopy(self: ValueFacts) ValueFacts {
        return .{
            .dependencies = self.dependencies,
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_authorities = self.storage_authorities,
            .referenced_place = self.referenced_place,
            .opaque_origins = self.opaque_origins,
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
    storage: place.Place,
    initializedness: value_state.Initializedness = .initialized,
    value: ValueFacts = .{},
};

pub const RootEstablishment = union(enum) {
    fresh,
    inherit: RootId,
};

pub const InputPath = struct {
    input_index: u32,
    projections: []const place.Projection = &.{},
};

pub const InputDependency = struct {
    path: InputPath,
    transfers_ownership: bool = false,
};

pub const OutputFieldEffect = struct {
    index: u32,
    value: *const OutputEffect,
};

/// Stable compiler-owned identity for one fresh root produced while evaluating
/// a summarized expression. Calls instantiate each distinct source as a new
/// runtime RootId; fields naming the same source share that root.
pub const FreshRootSource = usize;

/// Symbolic ValueFacts for a function output. Input dependencies retain their
/// structural path until a call instantiates them with the caller's facts.
pub const OutputEffect = struct {
    input_dependencies: []const InputDependency = &.{},
    input_places: []const InputPath = &.{},
    /// Values currently stored in Places reached through function inputs.
    /// This differs from `input_dependencies`: for a pointer input, the
    /// argument value is the pointer while this denotes its pointee value.
    input_place_values: []const InputPath = &.{},
    /// Opaque reads cannot name caller RootIds directly. Each path records
    /// that instantiation must add the concrete generations carried by that
    /// caller value as temporal dependencies of this output.
    opaque_generation_dependencies: []const InputPath = &.{},
    /// Opaque take operations recover the domain's conservatively hidden
    /// borrows. The domain remains imprecise and release_all is still needed
    /// when its runtime slots are all empty.
    opaque_storage_dependencies: []const InputPath = &.{},
    fields: []const OutputFieldEffect = &.{},
    /// Alternative effects selected by the runtime choice tag. Fresh roots
    /// below an alternative are never promoted to the enclosing output.
    variants: []const OutputVariantEffect = &.{},
    /// Concrete tag guaranteed for this output on every summarized exit.
    known_choice_variant: ?u32 = null,
    fresh_dependencies: []const FreshRootSource = &.{},
    fresh_owned_roots: []const FreshRootSource = &.{},
    integer_address: bool = false,
    foreign_storage: bool = false,
    fresh_storage_authorities: []const FreshRootSource = &.{},
};

pub const OutputVariantEffect = struct {
    index: u32,
    value: *const OutputEffect,
};

/// Symbolic post-state of a Place reached through a function input.  The
/// target uses the same input/projection vocabulary as OutputEffect, so call
/// composition can substitute it without inventing a second Place model.
pub const InputPlaceEffect = struct {
    target: InputPath,
    initializedness: value_state.Initializedness,
    value: OutputEffect = .{},
    ends_previous_roots: bool = false,
    refreshes_storage_root: bool = false,
    /// This post-state comes from relocation, which requires the caller to
    /// provide storage that is not currently initialized.
    requires_available_destination: bool = false,
    /// Whether this input crosses trusted opaque runtime storage. Conditional
    /// consumption remains tied to `opaque_storage` when the primitive names
    /// one. A null storage retains the historical unscoped boundary, which
    /// cannot retain dependencies on external roots. Ambiguous means a join
    /// encountered two different symbolic destinations.
    opaque_ownership: OpaqueOwnershipConsumption = .none,
    /// Storage that conservatively retains the consumed value's dependencies.
    /// This is symbolic so wrappers can map the opaque boundary to a caller Place.
    opaque_storage: ?InputPath = null,
    /// The write reaches its target through pointer provenance and can add the
    /// written value's dependencies to an opaque domain at the caller.
    may_repopulate_opaque_storage: bool = false,
};

pub const OpaqueOwnershipConsumption = enum {
    none,
    definite,
    conditional,
    ambiguous,
};

pub const FunctionSummary = struct {
    outputs: []const OutputEffect = &.{},
    required_live_inputs: []const InputPath = &.{},
    input_post_states: []const InputPlaceEffect = &.{},
    opaque_storage_effects: []const OpaqueStorageEffect = &.{},
    /// Domains whose opaque runtime contents are definitely gone on return.
    /// This clears only their conservative hidden temporal dependencies.
    opaque_storage_releases: []const InputPath = &.{},
};

/// A storage domain conservatively gains the dependencies described by
/// `hidden_dependencies`. This is separate from consuming precise ownership:
/// the crossing value may be a local aggregate even when its dependencies
/// originate in function inputs.
pub const OpaqueStorageEffect = struct {
    storage: InputPath,
    hidden_dependencies: OutputEffect,
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

test "move transfers owned roots without changing root identity" {
    const binding: *const @import("semantic_graph.zig").BindingDeclaration = undefined;
    const storage = place.Place{ .root = binding };
    const root: RootId = @enumFromInt(3);
    var source = PlaceFacts{
        .storage = storage,
        .value = .{
            .dependencies = &.{.{ .root = root }},
            .owned_roots = &.{root},
        },
    };
    var destination = PlaceFacts{ .storage = storage, .initializedness = .deinitialized };
    Tracker.moveValue(&source, &destination);
    try std.testing.expectEqual(value_state.Initializedness.moved, source.initializedness);
    try std.testing.expectEqual(root, destination.value.dependencies[0].root);
    try std.testing.expectEqual(root, destination.value.owned_roots[0]);
}

test "copying a reference does not duplicate root ownership" {
    const root: RootId = @enumFromInt(7);
    const original = ValueFacts{
        .dependencies = &.{.{ .root = root }},
        .owned_roots = &.{root},
    };
    const copied = original.referenceCopy();
    try std.testing.expectEqual(root, copied.dependencies[0].root);
    try std.testing.expectEqual(@as(usize, 0), copied.owned_roots.len);
}
