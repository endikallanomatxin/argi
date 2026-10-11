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
    /// One unresolved call may refine this generation. Zero means no proof;
    /// joins and independent calls erase the proof rather than combine guards.
    outcome_guard: u64 = 0,
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
    /// Opaque effects may select a named domain after projecting the receiver.
    /// This is a symbolic storage identity, never a physical Place projection.
    storage_domain: ?u32 = null,
};

pub const InputDependency = struct {
    path: InputPath,
    transfers_ownership: bool = false,
    /// Copy validity only; the produced value may refer to different storage.
    validity_only: bool = false,
};

pub const InputDomain = struct { path: InputPath, domain_index: u32 };

pub const OutputFieldEffect = struct {
    index: u32,
    value: *const ValueEffect,
};
pub const OutputDomainEffect = struct { domain_index: u32, value: *const ValueEffect };

/// Stable compiler-owned identity for a fresh runtime fact produced while
/// evaluating a summarized expression.
pub const FreshEffectSource = usize;

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
    /// Borrow all reachable generations before receiver layout is erased. This
    /// resolves caller storage identities and never retains local storage.
    input_captured_storages: []const InputPath = &.{},
    /// A virtual Self dependency names the erased receiver's value, not the
    /// lexical storage holding its handle. It carries validity only.
    input_receiver_values: []const InputPath = &.{},
    input_place_values: []const InputPath = &.{},
    /// Roots owned by the value at an input reference's place, borrowed as dependencies.
    input_owned_roots: []const InputPath = &.{},
    input_domains: []const InputDomain = &.{},
    domain_values: []const OutputDomainEffect = &.{},
    opaque_generation_dependencies: []const InputPath = &.{},
    opaque_storage_dependencies: []const InputPath = &.{},
    fields: []const OutputFieldEffect = &.{},
    variants: []const OutputVariantEffect = &.{},
    known_choice_variant: ?u32 = null,
    fresh_dependencies: []const FreshEffectSource = &.{},
    /// Nominal cleanup can be required without acquiring storage. This marker
    /// checks ownership permissions without inventing a lifetime root.
    fresh_cleanup_obligation: bool = false,
    fresh_owned_roots: []const FreshEffectSource = &.{},
    integer_address: bool = false,
    foreign_storage: bool = false,
    fresh_storage_capabilities: []const FreshEffectSource = &.{},
    unavailable_fresh_storage: []const FreshStorageCapabilityState = &.{},
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
    /// Using stored elements requires their hidden external dependencies;
    /// merely accessing or freeing allocation metadata does not.
    required_opaque_inputs: []const InputPath = &.{},
    input_post_states: []const PlacePostState = &.{},
    /// Post-states retained separately for a choice-valued function result.
    /// Selectors identify the output field and its choice variant.
    outcome_post_states: []const OutcomePostStates = &.{},
    opaque_storage_effects: []const OpaqueStorageEffect = &.{},
    opaque_storage_empties: []const InputPath = &.{},
    invalidated_domains: []const InputDomain = &.{},
};

pub const OutcomePostStates = struct {
    /// A selector with no returning exit has vacuous post-state guarantees.
    reachable: bool = true,
    /// Tags of the enclosing payload choices, from outermost to innermost.
    parent_variants: []const u32 = &.{},
    output_index: u32 = 0,
    variant_index: u32,
    input_post_states: []const PlacePostState,
    invalidated_domains: []const InputDomain = &.{},
    opaque_storage_empties: []const InputPath = &.{},
};

pub const OpaqueStorageEffect = struct {
    storage: InputPath,
    hidden_dependencies: ValueEffect,
};
