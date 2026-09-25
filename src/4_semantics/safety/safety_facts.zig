const place = @import("place.zig");
const value_state = @import("value_state.zig");

pub const ValidityRootId = enum(u32) { _ };
pub const StorageCapabilityId = enum(u32) { _ };

pub const ValidityRoot = struct {
    id: ValidityRootId,
    state: enum { alive, conditional, maybe_alive, dead } = .alive,
    owned_resource: bool = false,
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
};

pub const OutputFieldEffect = struct {
    index: u32,
    value: *const ValueEffect,
};

/// Stable compiler-owned identity for a fresh runtime fact produced while
/// evaluating a summarized expression.
pub const FreshEffectSource = usize;

/// Symbolic value facts for a function output. All references to caller state
/// remain expressed as InputPath until call instantiation.
pub const ValueEffect = struct {
    input_dependencies: []const InputDependency = &.{},
    input_places: []const InputPath = &.{},
    input_place_values: []const InputPath = &.{},
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
};

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

pub const SafetySummary = struct {
    outputs: []const ValueEffect = &.{},
    required_live_inputs: []const InputPath = &.{},
    input_post_states: []const PlacePostState = &.{},
    opaque_storage_effects: []const OpaqueStorageEffect = &.{},
    opaque_storage_empties: []const InputPath = &.{},
};

pub const OpaqueStorageEffect = struct {
    storage: InputPath,
    hidden_dependencies: ValueEffect,
};
