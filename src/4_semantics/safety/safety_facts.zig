const place = @import("place.zig");
const value_state = @import("value_state.zig");

pub const ValidityRootId = enum(u32) { _ };
/// Acquisition authorization shared by known address aliases. Ordinary moves
/// consume an AcquiredStorage binding, but an integer inspected before that
/// move can remain in another binding or cross a summary boundary. Those
/// aliases must observe the same establishment consumption independently of
/// their own Place state and of the established region's temporal lifetime.
pub const StorageCapabilityId = enum(u32) { _ };

pub const ValidityRoot = struct {
    id: ValidityRootId,
    state: enum { alive, conditional, maybe_alive, dead } = .alive,
    owned_resource: bool = false,
    /// Receiving binding for a bounded caller frame; this is checker-local
    /// storage identity and does not enter symbolic function summaries.
    caller_frame_owner: ?u32 = null,
    caller_frame_dependencies: []const ValidityRootId = &.{},
};

pub const ValidityDependency = struct {
    root: ValidityRootId,
};

pub const ValidityRootEstablishment = union(enum) {
    fresh,
    inherit: ValidityRootId,
};

/// Symbolic path rooted at a function input. This representation deliberately
/// contains no Module/Global binding identity so summaries can cross graph
/// boundaries and be instantiated by the indexed safety checker.
pub const InputPath = struct {
    input_index: u32,
    projections: []const place.Projection = &.{},
};

pub const InputDependency = struct {
    path: InputPath,
    transfers_ownership: bool = false,
    /// Copy validity only; the produced value may refer to different storage.
    validity_only: bool = false,
};

pub const OutputFieldEffect = struct {
    index: u32,
    value: *const ValueEffect,
};

/// Stable compiler-owned identity for a fresh runtime fact produced while
/// evaluating a summarized expression.
pub const FreshEffectSource = usize;

/// Ordinary fresh effects and caller-frame storage have distinct temporal
/// meanings. Keep this tag when rebasing identities across direct calls.
/// It grants no storage acquisition capability or resource ownership.
pub const caller_storage_source_bit: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);

/// Symbolic value facts for a function output. All references to caller state
/// remain expressed as InputPath until call instantiation.
pub const ValueEffect = struct {
    /// Preserves the use-site check for declared dependencies across calls.
    explicit_dependency: bool = false,
    input_dependencies: []const InputDependency = &.{},
    /// Scalar/raw facts copied without borrowing the source lifetime.
    input_storage_capabilities: []const InputPath = &.{},
    input_places: []const InputPath = &.{},
    /// Storage generations borrowed by a value, without making those places
    /// the value's referenced storage.
    input_generation_dependencies: []const InputPath = &.{},
    input_place_values: []const InputPath = &.{},
    /// Roots owned by the value at an input reference's place, borrowed as dependencies.
    input_owned_roots: []const InputPath = &.{},
    opaque_generation_dependencies: []const InputPath = &.{},
    opaque_storage_dependencies: []const InputPath = &.{},
    fields: []const OutputFieldEffect = &.{},
    variants: []const OutputVariantEffect = &.{},
    known_choice_variant: ?u32 = null,
    fresh_dependencies: []const FreshEffectSource = &.{},
    fresh_owned_roots: []const FreshEffectSource = &.{},
    integer_address: bool = false,
    foreign_storage: bool = false,
    fresh_storage_capabilities: []const FreshEffectSource = &.{},
    unavailable_fresh_storage: []const FreshStorageCapabilityState = &.{},
};

/// Concrete method results can borrow a field generation of their receiver.
/// Capture those generations when the receiver is erased into a Virtual value.
pub fn receiverBorrowedPlaces(
    allocator: @import("std").mem.Allocator,
    effect: ValueEffect,
    receiver_index: u32,
) ![]const InputPath {
    const std = @import("std");
    var result: std.array_list.Managed(InputPath) = .init(allocator);
    try collectReceiverBorrowedPlaces(&result, effect, receiver_index);
    return result.toOwnedSlice();
}

fn collectReceiverBorrowedPlaces(
    result: *@import("std").array_list.Managed(InputPath),
    effect: ValueEffect,
    receiver_index: u32,
) !void {
    for (effect.input_places) |path| if (path.input_index == receiver_index and path.projections.len != 0)
        try result.append(path);
    for (effect.input_generation_dependencies) |path| if (path.input_index == receiver_index and path.projections.len != 0)
        try result.append(path);
    for (effect.fields) |field| try collectReceiverBorrowedPlaces(result, field.value.*, receiver_index);
    for (effect.variants) |variant| try collectReceiverBorrowedPlaces(result, variant.value.*, receiver_index);
}

pub const OutputVariantEffect = struct {
    index: u32,
    value: *const ValueEffect,
};

/// Symbolic post-state of a Place reached through a function input.
pub const PlacePostState = struct {
    target: InputPath,
    initializedness: value_state.Initializedness,
    value: ValueEffect = .{},
    ends_previous_roots: bool = false,
    refreshes_storage_generation: bool = false,
    requires_available_destination: bool = false,
    opaque_ownership: OpaqueOwnershipConsumption = .none,
    opaque_storage: ?InputPath = null,
    may_repopulate_opaque_storage: bool = false,
};

pub const OpaqueOwnershipConsumption = enum {
    none,
    definite,
    conditional,
    ambiguous,
};

/// Capability use counts saturate at two: one consumption is valid, while
/// two means some execution can consume an input capability repeatedly.
pub const StorageCapabilityUse = struct {
    target: InputPath,
    minimum: u2 = 1,
    maximum: u2 = 1,
};

pub const StorageCapabilityConflict = struct {
    first: InputPath,
    second: InputPath,
};

pub const FreshStorageCapabilityState = struct {
    source: FreshEffectSource,
    maybe_consumed: bool = false,
};

pub const SafetySummary = struct {
    outputs: []const ValueEffect = &.{},
    storage_capability_uses: []const StorageCapabilityUse = &.{},
    storage_capability_conflicts: []const StorageCapabilityConflict = &.{},
    required_live_inputs: []const InputPath = &.{},
    input_post_states: []const PlacePostState = &.{},
    /// Post-states retained separately for a choice-valued function result.
    /// Variant indices refer to the first output field's choice type.
    outcome_post_states: []const OutcomePostStates = &.{},
    opaque_storage_effects: []const OpaqueStorageEffect = &.{},
    opaque_storage_empties: []const InputPath = &.{},
};

pub const OutcomePostStates = struct {
    variant_index: u32,
    input_post_states: []const PlacePostState,
};

pub const OpaqueStorageEffect = struct {
    storage: InputPath,
    hidden_dependencies: ValueEffect,
};
