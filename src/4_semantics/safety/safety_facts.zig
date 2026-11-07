const std = @import("std");
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
    /// Sparse branch trackers leave other branches' identities absent.
    present: bool = true,
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

    pub fn eql(left: InputPath, right: InputPath) bool {
        if (left.input_index != right.input_index or left.storage_domain != right.storage_domain or
            left.projections.len != right.projections.len) return false;
        for (left.projections, right.projections) |a, b| if (!a.eql(b)) return false;
        return true;
    }
};

/// Logical selection distinguishes a region from a physical field of its
/// handle. This vocabulary is shared with symbolic storage observations.
pub const StorageSelector = union(enum) {
    projection: place.Projection,
    domain: u32,

    pub fn eql(self: StorageSelector, other: StorageSelector) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .projection => |projection| projection.eql(other.projection),
            .domain => |domain| domain == other.domain,
        };
    }

    pub fn embedded(self: StorageSelector) bool {
        return self == .projection and self.projection != .dereference;
    }
};

/// Exact caller-relative route. Conversion to the legacy flat InputPath is
/// partial; unsupported routes retain their identity here without granting
/// authority or inventing a different representable path. Preserving a route
/// is not a typing judgment: an abstract region has no implied record layout.
pub const InputRoute = struct {
    input_index: u32,
    selectors: []const StorageSelector = &.{},

    pub fn fromInputPath(allocator: std.mem.Allocator, path: InputPath) !InputRoute {
        const selectors = try allocator.alloc(StorageSelector, path.projections.len + @intFromBool(path.storage_domain != null));
        for (path.projections, 0..) |projection, index| selectors[index] = .{ .projection = projection };
        if (path.storage_domain) |domain| selectors[path.projections.len] = .{ .domain = domain };
        return .{ .input_index = path.input_index, .selectors = selectors };
    }

    pub fn append(self: InputRoute, allocator: std.mem.Allocator, selector: StorageSelector) !InputRoute {
        const selectors = try allocator.alloc(StorageSelector, self.selectors.len + 1);
        @memcpy(selectors[0..self.selectors.len], self.selectors);
        selectors[self.selectors.len] = selector;
        return .{ .input_index = self.input_index, .selectors = selectors };
    }

    pub fn toInputPath(self: InputRoute, allocator: std.mem.Allocator) !?InputPath {
        var domain: ?u32 = null;
        for (self.selectors, 0..) |selector, index| if (selector == .domain) {
            if (index + 1 != self.selectors.len) return null;
            domain = selector.domain;
        };
        const count = self.selectors.len - @intFromBool(domain != null);
        const projections = try allocator.alloc(place.Projection, count);
        for (self.selectors[0..count], projections) |selector, *projection| projection.* = selector.projection;
        return .{ .input_index = self.input_index, .projections = projections, .storage_domain = domain };
    }

    pub fn eql(self: InputRoute, other: InputRoute) bool {
        if (self.input_index != other.input_index or self.selectors.len != other.selectors.len) return false;
        for (self.selectors, other.selectors) |left, right| if (!left.eql(right)) return false;
        return true;
    }
};

/// May-access effects are independent of lifetime requirements and final
/// post-values: writing the same value still requires write authority.
pub const AccessMode = enum { read, write };
pub const InputAccess = struct { target: InputPath, mode: AccessMode };
pub const GlobalAccess = struct {
    /// Indexed module binding identity in the retained graph. Summary caches
    /// are graph-local; this is not a native address or a validity root.
    binding: u32,
    mode: AccessMode,
};

pub const CapturedStorage = struct {
    path: InputPath,
    /// A final generation needs an ordered proof; stale also represents an
    /// intermediate capture whose final generation cannot be established.
    phase: enum { entry, post, stale } = .entry,
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
pub const OutputDomainEffect = struct {
    domain_index: u32,
    value: *const ValueEffect,
    /// Caller-relative selectors for storage read while locating this region.
    required_reads: ?*const ValueEffect = null,
};

/// Stable compiler-owned identity for a fresh runtime fact produced while
/// evaluating a summarized expression.
pub const FreshEffectSource = usize;

/// Symbolic value facts for a function output. All references to caller state
/// remain expressed as InputPath until call instantiation.
pub const FreshExecution = struct {
    source: FreshEffectSource,
    inputs: *const ValueEffect,
    input_type: u32,
};

pub const ValueEffect = struct {
    /// Preserves the use-site check for declared dependencies across calls.
    explicit_dependency: bool = false,
    input_dependencies: []const InputDependency = &.{},
    /// Scalar/raw facts copied without borrowing the source lifetime.
    input_storage_capabilities: []const InputPath = &.{},
    /// Select acquisition identity without copying establishment permission.
    input_acquisition_origins: []const InputPath = &.{},
    input_execution_receipts: []const InputPath = &.{},
    input_places: []const InputPath = &.{},
    /// Storage generations borrowed by a value, without making those places
    /// the value's referenced storage.
    input_generation_dependencies: []const InputPath = &.{},
    /// Borrow all reachable generations before receiver layout is erased. This
    /// resolves caller storage identities and never retains local storage.
    input_captured_storages: []const CapturedStorage = &.{},
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
    fresh_executions: []const FreshExecution = &.{},
    /// Nominal cleanup can be required without acquiring storage. This marker
    /// checks ownership permissions without inventing a lifetime root.
    fresh_cleanup_obligation: bool = false,
    fresh_owned_roots: []const FreshEffectSource = &.{},
    integer_address: bool = false,
    foreign_storage: bool = false,
    fresh_storage_capabilities: []const FreshEffectSource = &.{},
    fresh_acquisition_origins: []const FreshEffectSource = &.{},
    unavailable_fresh_storage: []const FreshStorageCapabilityState = &.{},
};

pub const OutputVariantEffect = struct {
    index: u32,
    value: *const ValueEffect,
};

/// Symbolic post-state of a Place reached through a function input.
pub const PlacePostState = struct {
    /// Whether this exit establishes a value independently of entry occupancy.
    /// An initialized post-state alone may simply preserve the incoming value.
    pub const Initialization = enum { preserved, possible, definite };

    target: InputPath,
    initialization: Initialization = .preserved,
    initializedness: value_state.Initializedness,
    value: ValueEffect = .{},
    /// Proven entry-relative destinations of the reference stored in this slot.
    /// Lifetime dependencies alone never establish these identities.
    reference_targets: ?[]const InputPath = null,
    /// This selected reference access observes the destination's post-value;
    /// unrelated copies continue observing their entry generation.
    reference_refresh: bool = false,
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

/// Ordered observations and captures must not alias an incompatible mutation.
/// Coordinates are caller-relative; distinct inputs do not prove disjointness.
pub const StorageObservationConflict = struct {
    incompatible: InputPath,
    kind: enum { lifetime, concurrent_access, capture_update } = .lifetime,
    observed: InputPath,
    /// Compare captured reachable storage, including initializer sources,
    /// rather than only the receiver's lexical envelope.
    captures_reachable: bool = false,
};

pub const FreshStorageCapabilityState = struct {
    source: FreshEffectSource,
    maybe_consumed: bool = false,
};

pub const ChoiceCondition = @import("choice_conditions.zig").ChoiceCondition;
pub const ChoiceConditions = @import("choice_conditions.zig").ChoiceConditions;

/// A complete approximation under an explicitly represented conjunction.
/// Effects are shared between guards and contain no graph binding identities.
pub const GuardedSafetyEffects = struct {
    conditions: ChoiceConditions,
    effects: *const SafetySummary,
};

pub const SafetySummary = struct {
    input_accesses: []const InputAccess = &.{},
    global_accesses: []const GlobalAccess = &.{},
    /// Unknown external/erased effects cannot be interpreted as no access.
    /// This remains conservative until access contracts bound those calls.
    unknown_access: bool = false,
    /// Unconditional fields retain the conservative approximation for unknown
    /// conditions. Guarded records cannot silently remove those obligations.
    guarded_effects: []const GuardedSafetyEffects = &.{},
    /// Inferred regions cover every returning path. Declaration guards alone
    /// are conditional promises and cannot establish exhaustive coverage.
    guarded_returns_complete: bool = false,
    outputs: []const ValueEffect = &.{},
    storage_capability_uses: []const StorageCapabilityUse = &.{},
    storage_capability_conflicts: []const StorageCapabilityConflict = &.{},
    storage_observations: []const InputPath = &.{},
    storage_observation_conflicts: []const StorageObservationConflict = &.{},
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
    completed_executions: []const InputPath = &.{},
    invalidated_domains: []const InputDomain = &.{},

    /// A borrowed view of the current outcome effects, retaining common
    /// provenance and obligations. No derived copy is stored or refreshed.
    pub fn outcomeEffects(self: SafetySummary, outcome: OutcomePostStates) SafetySummary {
        var selected = self;
        selected.guarded_effects = &.{};
        selected.outcome_post_states = &.{};
        selected.input_post_states = outcome.input_post_states;
        selected.invalidated_domains = outcome.invalidated_domains;
        selected.opaque_storage_empties = outcome.opaque_storage_empties;
        selected.completed_executions = outcome.completed_executions;
        return selected;
    }
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
    completed_executions: []const InputPath = &.{},
};

pub const OpaqueStorageEffect = struct {
    storage: InputPath,
    hidden_dependencies: ValueEffect,
};

test "symbolic input routes flatten without losing selector identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const alphabet = [_]StorageSelector{
        .{ .projection = .{ .field = 0 } }, .{ .projection = .{ .field = 1 } },
        .{ .projection = .dereference }, .{ .domain = 0 }, .{ .domain = 1 },
    };
    var count: usize = 1;
    for (0..4) |length| {
        for (0..count) |encoded| {
            var selectors: [3]StorageSelector = undefined;
            var digits = encoded;
            for (selectors[0..length]) |*selector| {
                selector.* = alphabet[digits % alphabet.len];
                digits /= alphabet.len;
            }
            const route = InputRoute{ .input_index = 7, .selectors = selectors[0..length] };
            if (try route.toInputPath(allocator)) |flat| {
                const roundtrip = try InputRoute.fromInputPath(allocator, flat);
                try std.testing.expect(route.eql(roundtrip));
            }
        }
        count *= alphabet.len;
    }
}
