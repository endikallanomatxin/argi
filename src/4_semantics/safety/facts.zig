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
pub const RootProducerId = base.RootProducerId;
pub const StorageCapabilityId = base.StorageCapabilityId;
pub const ValidityRoot = base.ValidityRoot;
pub const ValidityDependency = base.ValidityDependency;
pub const ValidityRootEstablishment = base.ValidityRootEstablishment;
pub const InputPath = base.InputPath;
pub const TaskOutputSelection = base.TaskOutputSelection;
pub const ReferenceRelation = base.ReferenceRelation;
pub const AccessMode = base.AccessMode;
pub const commonVirtualNoAccess = base.commonVirtualNoAccess;

// Identities name logical executions, not threads or validity generations.
pub const ExecutionId = enum(u32) { _ };
pub const ExecutionLoan = struct {
    storage: ?Place = null,
    symbolic: ?SymbolicPointeeId = null,
    generations: []const ValidityRootId = &.{},
    mode: AccessMode,
    concurrent_reference: bool = false,

    pub fn eql(self: ExecutionLoan, other: ExecutionLoan) bool {
        if (self.mode != other.mode or self.concurrent_reference != other.concurrent_reference or self.symbolic != other.symbolic) return false;
        if ((self.storage == null) != (other.storage == null)) return false;
        if (self.storage) |storage| if (!storage.eql(other.storage.?)) return false;
        return std.mem.eql(ValidityRootId, self.generations, other.generations);
    }

    pub fn allowsOverlap(self: ExecutionLoan, other: AccessMode, other_concurrent: bool) bool {
        if (self.concurrent_reference or other_concurrent)
            return self.concurrent_reference and other_concurrent;
        return self.mode == .read and other == .read;
    }
};
pub const ExecutionState = struct {
    id: ExecutionId,
    loans: []const ExecutionLoan,
    origin: ?primitives.SourceRef = null,
    pending: bool = true,
    output: Output = .unavailable,

    pub const Output = union(enum) {
        unavailable,
        retained: *const ValueFacts,
        consumed: ?*const ValueFacts,

        pub fn accessEvidence(self: Output) ?*const ValueFacts {
            return switch (self) {
                .unavailable => null,
                .retained => |value| value,
                .consumed => |value| value,
            };
        }
    };
};
pub const InputAccess = base.InputAccess;
pub const GlobalAccess = base.GlobalAccess;
pub const CapturedStorage = base.CapturedStorage;
pub const InputDependency = base.InputDependency;
pub const InputDomain = base.InputDomain;
pub const OutputFieldEffect = base.OutputFieldEffect;
pub const OutputDomainEffect = base.OutputDomainEffect;
pub const FreshEffectSource = base.FreshEffectSource;
pub const ValueEffect = base.ValueEffect;
pub const FreshExecution = base.FreshExecution;
pub const ExecutionResult = base.ExecutionResult;
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

/// Identity for retained storage obligations, independent of a data address.
/// Symbolic identities grant neither a concrete Place nor an acquisition proof.
pub const StorageIdentity = union(enum) {
    place: Place,
    symbolic: SymbolicPointeeId,

    pub fn eql(self: StorageIdentity, other: StorageIdentity) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .place => |place| place.eql(other.place),
            .symbolic => |symbolic| symbolic == other.symbolic,
        };
    }

    pub fn isPrefixOf(self: StorageIdentity, other: StorageIdentity) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .place => |place| place.isPrefixOf(other.place),
            .symbolic => |symbolic| symbolic == other.symbolic,
        };
    }
};

pub const OpaqueProvenance = struct {
    storage: StorageIdentity,
    generation: ValidityRootId,
};

pub const GenerationOutcome = struct {
    storage: StorageIdentity,
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
            std.mem.eql(ValidityRootId, self.owned_roots, other.owned_roots) and
            self.storage.eql(other.storage);
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
    /// The observed address is within this owned resource backing.
    owned_backing: ?ValidityRootId = null,
    /// Custody established by an authenticated acquisition of this value.
    intrinsic_backing_owner: ?ValidityRootId = null,
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
    /// Some retained value alternative lacks acquisition authorization. Keep
    /// possible identities for consumption checks without proving presence.
    storage_capability_incomplete: bool = false,
    /// Acquisition identity only: no establishment permission, initializedness,
    /// physical range, owner liveness or access authority follows from this fact.
    acquisition_origins: []const StorageCapabilityId = &.{},
    /// Upper bound on lexical allocations visible when this valid reference was
    /// observed, relative to this proof's shared namespace. This is separation
    /// evidence only; it grants neither liveness nor access authority.
    lexical_frame: ?u32 = null,
    referenced_place: ?Place = null,
    /// A represented reference alternative has no retained target identity.
    /// Keep known may-targets, but do not treat their singleton as exhaustive.
    reference_target_incomplete: bool = false,
    /// Known possible destinations retained only for conservative mutation.
    /// This list alone never grants exact access or ownership.
    mutation_places: []const Place = &.{},
    /// Every alternative is covered by an authenticated place or symbolic
    /// target. Only a join or substitution of covered references sets this.
    reference_coverage_complete: bool = false,

    /// Unknown parameter referents have consumption identities, not concrete
    /// places or owned roots. Copies retain them without granting validity.
    symbolic_pointees: []const SymbolicPointeeId = &.{},
    execution_receipts: []const ExecutionId = &.{},
    /// Possible receipts remain obligations when selection loses precision.
    execution_receipt_incomplete: bool = false,
    task_output_execution: ?ExecutionId = null,
    /// An output recipe awaiting its matching completion proof.
    task_output_claim: ?ExecutionId = null,
    opaque_provenance: []const OpaqueProvenance = &.{},
    /// The erased receiver retains concurrent reference authority.
    concurrent_receiver: bool = false,
    /// Operation indices with verified empty memory effects.
    virtual_no_access: []const u32 = &.{},
    domains: []const DomainFacts = &.{},
    generation_outcomes: []const GenerationOutcome = &.{},
    /// Exact receipts certified complete when this outcome is selected.
    completed_executions: []const ExecutionId = &.{},
    choice_selectors: []const CallChoiceSelector = &.{},
    choice_observations: []const CallChoiceSelector = &.{},
    guarded_values: []const GuardedValueFacts = &.{},

    pub fn hasCompleteReferenceCoverage(self: ValueFacts) bool {
        if (self.reference_target_incomplete) return false;
        if (self.reference_coverage_complete)
            return self.referenced_place != null or self.symbolic_pointees.len != 0 or self.mutation_places.len != 0;
        if (self.referenced_place) |exact| {
            if (self.symbolic_pointees.len != 0) return false;
            for (self.mutation_places) |candidate| if (!exact.eql(candidate)) return false;
            return true;
        }
        return self.symbolic_pointees.len == 1 and self.mutation_places.len == 0;
    }

    /// Traverses represented structural children. Guarded refinements are
    /// separate alternatives and may form recursive graphs.
    pub fn structuralChildren(self: ValueFacts) StructuralChildren {
        return .{ .fields = self.fields, .variants = self.variants };
    }

    pub const StructuralChildren = struct {
        fields: []const FieldFacts,
        variants: []const VariantFacts,

        pub fn next(self: *StructuralChildren) ?*const ValueFacts {
            if (self.fields.len != 0) {
                const value = self.fields[0].value;
                self.fields = self.fields[1..];
                return value;
            }
            if (self.variants.len != 0) {
                const value = self.variants[0].value;
                self.variants = self.variants[1..];
                return value;
            }
            return null;
        }
    };

    pub fn referenceCopy(self: ValueFacts) ValueFacts {
        return .{
            .owned_backing = self.owned_backing,
            .explicit_dependency = self.explicit_dependency,
            .dependencies = self.dependencies,
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_capabilities = self.storage_capabilities,
            .storage_capability_incomplete = self.storage_capability_incomplete,
            .acquisition_origins = self.acquisition_origins,
            .lexical_frame = self.lexical_frame,
            .referenced_place = self.referenced_place,
            .reference_target_incomplete = self.reference_target_incomplete,
            .mutation_places = self.mutation_places,
            .reference_coverage_complete = self.reference_coverage_complete,
            .symbolic_pointees = self.symbolic_pointees,
            .execution_receipts = self.execution_receipts,
            .execution_receipt_incomplete = self.execution_receipt_incomplete,
            .opaque_provenance = self.opaque_provenance,
            .concurrent_receiver = self.concurrent_receiver,
            .virtual_no_access = self.virtual_no_access,
            .domains = self.domains,
            .generation_outcomes = self.generation_outcomes,
            .completed_executions = self.completed_executions,
            .choice_selectors = self.choice_selectors,
            .choice_observations = self.choice_observations,
            .guarded_values = self.guarded_values,
        };
    }

    /// A derived view can retain caller-certified backing, but its selected
    /// slot or extent and stored identities need not match the base reference.
    pub fn derivedReference(self: ValueFacts) ValueFacts {
        var result = self.referenceCopy();
        result.owned_backing = null;
        result.referenced_place = null;
        result.reference_target_incomplete = true;
        result.mutation_places = &.{};
        result.reference_coverage_complete = false;
        result.symbolic_pointees = &.{};
        result.concurrent_receiver = false;
        result.virtual_no_access = &.{};
        result.domains = &.{};
        return result;
    }

    /// Scalar values loaded from opaque storage retain physical/raw-storage
    /// facts, but not the lifetime envelope of the container that happened to
    /// hold them. This is the indexed equivalent of the legacy checker's
    /// scalar opaque-read rule and prevents conservative parent projections
    /// from manufacturing dependencies or ownership for plain scalar values.
    pub fn scalarOpaqueRead(self: ValueFacts) ValueFacts {
        return .{
            .generation_outcomes = self.generation_outcomes,
            .completed_executions = self.completed_executions,
            .execution_receipts = self.execution_receipts,
            .execution_receipt_incomplete = self.execution_receipt_incomplete,
            .integer_address = self.integer_address,
            .foreign_storage = self.foreign_storage,
            .storage_capabilities = self.storage_capabilities,
            .storage_capability_incomplete = self.storage_capability_incomplete,
            .acquisition_origins = self.acquisition_origins,
            .choice_selectors = self.choice_selectors,
            .choice_observations = self.choice_observations,
        };
    }
};

/// A captured region reached through a reference remains exact only while
/// that reference still denotes the captured storage.
pub const RegionTraversal = struct {
    slot: Place,
    target: Place,

    pub fn eql(a: RegionTraversal, b: RegionTraversal) bool {
        return a.slot.eql(b.slot) and a.target.eql(b.target);
    }
};

/// Domain storage identities remain usable across handle copies. Current
/// generations are looked up at the call, while returned borrows capture the
/// old generation. Domain invalidation never transfers cleanup ownership.
pub const DomainFacts = struct {
    domain_index: u32,
    storages: []const Place,
    traversals: []const RegionTraversal = &.{},
    /// Read authority needed to locate a projected region, independently of
    /// the operation's authority over the selected payload storage.
    required_reads: []const StorageIdentity = &.{},
    /// The internal receiver region can retain an unknown caller referent
    /// without inventing a concrete Place. Named lifetime domains still use
    /// materialized storage until symbolic domain projections are represented.
    symbolic_pointees: []const SymbolicPointeeId = &.{},
};

/// Only a wholly empty value may omit its element records. In a mixed
/// aggregate, explicit empty children prevent projection from inheriting
/// a sibling's dependency or ownership facts from the aggregate envelope.
/// Select an explicitly represented child without inheriting enclosing facts.
pub fn representedProjection(value: anytype, projection: Projection) ?@TypeOf(value) {
    switch (projection) {
        .field, .static_index => |index| {
            for (value.fields) |field| if (field.index == index) return field.value.*;
        },
        .variant => |index| {
            if (value.known_choice_variant) |active| if (active != index) return null;
            for (value.variants) |variant| if (variant.index == index) return variant.value.*;
        },
        .dereference, .dynamic_index => {},
    }
    return null;
}

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

/// Symbolic observations distinguish embedded storage from an erased resource.
/// A domain is not a byte projection or a subobject of its handle.
pub const StorageSelector = base.StorageSelector;
pub const InputRoute = base.InputRoute;
pub const SymbolicStorageSelector = StorageSelector;

pub const Tracker = struct {
    /// Cloned branch states share identities, never reuse another branch's ID.
    pub const RootNamespace = struct {
        pub const ProducerSite = union(enum) {
            call: graph.GlobalNodeId,
            virtual_call: graph.GlobalVirtualCallId,
        };
        pub const Producer = struct {
            site: ProducerSite,
            effect: union(enum) { summary: FreshEffectSource, primitive_owner },
        };
        /// Embedded projections follow physical storage across observations.
        /// Ordinary symbolic inputs may share a validity root without sharing
        /// a storage identity.
        pub const EmbeddedBase = union(enum) {
            input: SymbolicPointeeId,
            projected: ValidityRootId,
        };

        pub const ProjectionPartition = enum(u32) { _ };
        const PartitionStep = struct {
            parent: union(enum) { input: SymbolicPointeeId, projected: ProjectionPartition },
            selector: SymbolicStorageSelector,
        };
        const EmbeddedSlot = struct {
            base: EmbeddedBase,
            selector: SymbolicStorageSelector,
        };

        pub const ProjectedStorage = struct {
            parent: SymbolicPointeeId,
            parent_generation: ValidityRootId,
            selector: SymbolicStorageSelector,
            identity: SymbolicPointeeId,
            backing: ValidityRootId,
            generation: ValidityRootId,
            ty: ?graph.GlobalTypeId = null,
            partition: ProjectionPartition = undefined,
        };
        pub const ProjectionObservation = struct {
            parent: SymbolicPointeeId,
            generation: ValidityRootId,
            selector: SymbolicStorageSelector,
        };
        next_id: u32 = 0,
        next_symbolic_id: u32 = 0,
        next_capability_id: u32 = 0,
        next_execution_id: u32 = 0,
        retirement_mark: u32 = 1,
        // First observations persist across branches and loop iterations. A
        // repeated lexical binding never receives a later, stronger birth.
        lexical_allocations: std.AutoArrayHashMapUnmanaged(graph.GlobalBindingId, bool) = .empty,
        producers: std.AutoArrayHashMapUnmanaged(Producer, void) = .empty,
        projected_storage: std.ArrayList(ProjectedStorage) = .empty,
        projection_observations: std.AutoHashMapUnmanaged(ProjectionObservation, usize) = .empty,
        projection_parents: std.AutoHashMapUnmanaged(ValidityRootId, void) = .empty,
        embedded_slots: std.AutoHashMapUnmanaged(EmbeddedSlot, ValidityRootId) = .empty,
        projection_partitions: std.AutoArrayHashMapUnmanaged(PartitionStep, void) = .empty,
        initial_storage: std.ArrayList(struct { storage: Place, root: ValidityRootId }) = .empty,

        pub fn embeddedBase(self: *const RootNamespace, identity: SymbolicPointeeId) EmbeddedBase {
            const index = self.projectionIndex(identity) orelse return .{ .input = identity };
            return .{ .projected = self.projected_storage.items[index].backing };
        }

        /// This key groups possible targets. Exact reads and updates still
        /// use the projected observation identity and its generation.
        pub fn projectionPartition(self: *const RootNamespace, identity: SymbolicPointeeId) ?ProjectionPartition {
            const index = self.projectionIndex(identity) orelse return null;
            return self.projected_storage.items[index].partition;
        }

        pub fn internProducer(self: *RootNamespace, allocator: std.mem.Allocator, producer: Producer) !RootProducerId {
            const entry = try self.producers.getOrPut(allocator, producer);
            return @enumFromInt(entry.index);
        }

        pub fn observedProjection(self: *const RootNamespace, observation: ProjectionObservation) ?ProjectedStorage {
            const index = self.projection_observations.get(observation) orelse return null;
            return self.projected_storage.items[index];
        }

        pub fn embeddedBacking(self: *const RootNamespace, observation: ProjectionObservation) ?ValidityRootId {
            if (!observation.selector.embedded()) return null;
            return self.embedded_slots.get(.{ .base = self.embeddedBase(observation.parent), .selector = observation.selector });
        }

        pub fn hasProjectionFrom(self: *const RootNamespace, generation: ValidityRootId) bool {
            return self.projection_parents.contains(generation);
        }

        pub fn reserveProjection(self: *RootNamespace, allocator: std.mem.Allocator, selector: SymbolicStorageSelector) !void {
            try self.projected_storage.ensureUnusedCapacity(allocator, 1);
            try self.projection_observations.ensureUnusedCapacity(allocator, 1);
            try self.projection_parents.ensureUnusedCapacity(allocator, 1);
            try self.projection_partitions.ensureUnusedCapacity(allocator, 1);
            if (selector.embedded()) try self.embedded_slots.ensureUnusedCapacity(allocator, 1);
        }

        pub fn publishProjection(self: *RootNamespace, row: ProjectedStorage) void {
            const key: ProjectionObservation = .{ .parent = row.parent, .generation = row.parent_generation, .selector = row.selector };
            self.projection_observations.putAssumeCapacityNoClobber(key, self.projected_storage.items.len);
            self.projection_parents.putAssumeCapacity(row.parent_generation, {});
            if (row.selector.embedded()) {
                const slot: EmbeddedSlot = .{ .base = self.embeddedBase(row.parent), .selector = row.selector };
                const entry = self.embedded_slots.getOrPutAssumeCapacity(slot);
                if (entry.found_existing) {
                    std.debug.assert(entry.value_ptr.* == row.backing);
                } else entry.value_ptr.* = row.backing;
            }
            const step: PartitionStep = .{
                .parent = if (self.projectionPartition(row.parent)) |partition| .{ .projected = partition } else .{ .input = row.parent },
                .selector = row.selector,
            };
            const partition = self.projection_partitions.getOrPutAssumeCapacity(step);
            // The partition ordinal follows the path table, independently
            // of how many symbolic observations precede this path.
            var observed = row;
            observed.partition = @enumFromInt(partition.index);
            self.projected_storage.appendAssumeCapacity(observed);
        }

        /// Projections are appended in identity allocation order. Ordinary
        /// symbolic inputs can occupy gaps in the projection table.
        pub fn projectionIndex(self: *const RootNamespace, identity: SymbolicPointeeId) ?usize {
            var start: usize = 0;
            var limit = self.projected_storage.items.len;
            const wanted = @intFromEnum(identity);
            while (start < limit) {
                const middle = start + (limit - start) / 2;
                const candidate = @intFromEnum(self.projected_storage.items[middle].identity);
                if (candidate == wanted) return middle;
                if (candidate < wanted) start = middle + 1 else limit = middle;
            }
            return null;
        }

        /// Independent session candidates copy allocation state; branches of
        /// one proof still share it. Immutable Place paths retain their arena.
        pub fn clone(self: *const RootNamespace, allocator: std.mem.Allocator) !RootNamespace {
            var result = self.*;
            result.lexical_allocations = try self.lexical_allocations.clone(allocator);
            errdefer result.lexical_allocations.deinit(allocator);
            result.producers = try self.producers.clone(allocator);
            errdefer result.producers.deinit(allocator);
            result.initial_storage = try self.initial_storage.clone(allocator);
            errdefer result.initial_storage.deinit(allocator);
            result.projected_storage = try self.projected_storage.clone(allocator);
            errdefer result.projected_storage.deinit(allocator);
            result.projection_observations = try self.projection_observations.clone(allocator);
            errdefer result.projection_observations.deinit(allocator);
            result.projection_parents = try self.projection_parents.clone(allocator);
            errdefer result.projection_parents.deinit(allocator);
            result.embedded_slots = try self.embedded_slots.clone(allocator);
            errdefer result.embedded_slots.deinit(allocator);
            result.projection_partitions = try self.projection_partitions.clone(allocator);
            return result;
        }
        pub fn deinit(self: *RootNamespace, allocator: std.mem.Allocator) void {
            self.lexical_allocations.deinit(allocator);
            self.producers.deinit(allocator);
            self.initial_storage.deinit(allocator);
            self.projected_storage.deinit(allocator);
            self.projection_observations.deinit(allocator);
            self.projection_parents.deinit(allocator);
            self.embedded_slots.deinit(allocator);
            self.projection_partitions.deinit(allocator);
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
                    break :identity next;
                } else @as(u32, @intCast(self.roots.items.len));
                const id: ValidityRootId = @enumFromInt(index);
                try self.materialize(id);
                if (self.namespace) |namespace| namespace.next_id += 1;
                break :blk id;
            },
        };
    }

    /// Materialize an identity that exists on another branch without reviving
    /// a generation already observed and ended on this path.
    pub fn materialize(self: *Tracker, id: ValidityRootId) !void {
        const index = @intFromEnum(id);
        try self.roots.ensureTotalCapacity(index + 1);
        while (self.roots.items.len <= index) {
            const absent: ValidityRootId = @enumFromInt(self.roots.items.len);
            self.roots.appendAssumeCapacity(.{ .id = absent, .state = .dead, .present = false });
        }
        if (!self.roots.items[index].present) self.roots.items[index] = .{ .id = id };
    }

    pub const untracked_retirement = std.math.maxInt(u32);

    fn recordRetirement(self: *Tracker, root: *ValidityRoot) void {
        const namespace = self.namespace orelse {
            root.retirement_mark = untracked_retirement;
            return;
        };
        namespace.retirement_mark +|= 1;
        root.retirement_mark = namespace.retirement_mark;
    }

    pub fn end(self: *Tracker, id: ValidityRootId) void {
        const root = &self.roots.items[@intFromEnum(id)];
        if (root.summarized_instances) {
            self.markPossiblyRetired(id);
            return;
        }
        if (root.state != .dead) self.recordRetirement(root);
        root.state = .dead;
        root.outcome_guard = 0;
    }

    /// A possible retirement with no result that can refine it.
    pub fn markPossiblyRetired(self: *Tracker, id: ValidityRootId) void {
        const root = &self.roots.items[@intFromEnum(id)];
        if (root.state == .dead) return;
        root.state = .maybe_alive;
        root.outcome_guard = 0;
        if (root.summarized_instances) {
            // No witness can distinguish retirements of members of this
            // partition. Keep repeated possible retirements idempotent.
            root.retirement_mark = untracked_retirement;
        } else self.recordRetirement(root);
    }

    /// Register a possible retirement whose result can still refine this root.
    /// A nested projection may encounter the same transition more than once.
    pub fn deferRetirement(self: *Tracker, id: ValidityRootId, guard: u64) bool {
        std.debug.assert(guard != 0);
        const root = &self.roots.items[@intFromEnum(id)];
        if (root.summarized_instances) {
            self.end(id);
            return false;
        }
        if (root.state == .alive) {
            self.recordRetirement(root);
            root.state = .maybe_alive;
            root.outcome_guard = guard;
        } else if (root.outcome_guard != guard) {
            // Neither outcome can resolve uncertainty introduced by the other.
            if (root.state != .dead) self.recordRetirement(root);
            root.outcome_guard = 0;
        }
        return root.state == .maybe_alive and root.outcome_guard == guard;
    }

    pub fn isAlive(self: *const Tracker, id: ValidityRootId) bool {
        const root = self.roots.items[@intFromEnum(id)];
        return !root.summarized_instances and root.state == .alive;
    }

    pub fn dependenciesAreAlive(self: *const Tracker, facts: ValueFacts) bool {
        for (facts.dependencies) |dependency| if (!self.dependencyIsAlive(dependency)) return false;
        return true;
    }

    pub fn dependencyIsAlive(self: *const Tracker, dependency: ValidityDependency) bool {
        const root = self.roots.items[@intFromEnum(dependency.root)];
        if (root.summarized_instances) return false;
        if (root.state == .alive) return true;
        return root.state == .maybe_alive and self.namespace != null and
            dependency.retirement_mark != 0 and dependency.retirement_mark != untracked_retirement and
            root.retirement_mark == dependency.retirement_mark;
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

test "independent guarded retirements invalidate either outcome proof" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const root = try tracker.establish(.fresh);
    try std.testing.expect(tracker.deferRetirement(root, 1));
    try std.testing.expect(tracker.deferRetirement(root, 1));
    try std.testing.expect(!tracker.deferRetirement(root, 2));
    try std.testing.expect(!tracker.deferRetirement(root, 1));
    try std.testing.expectEqual(@as(u64, 0), tracker.roots.items[@intFromEnum(root)].outcome_guard);
    try std.testing.expect(!tracker.isAlive(root));
}

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

test "history roots cannot authorize a live dependency or retire every instance" {
    var namespace: Tracker.RootNamespace = .{};
    defer namespace.deinit(std.testing.allocator);
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    tracker.namespace = &namespace;
    const id = try tracker.establish(.fresh);
    tracker.roots.items[@intFromEnum(id)].summarized_instances = true;
    const dependency: ValidityDependency = .{ .root = id, .retirement_mark = namespace.retirement_mark };
    try std.testing.expect(!tracker.dependencyIsAlive(dependency));
    tracker.end(id);
    try std.testing.expectEqual(.maybe_alive, tracker.roots.items[@intFromEnum(id)].state);
    try std.testing.expect(!tracker.deferRetirement(id, 1));
    try std.testing.expectEqual(Tracker.untracked_retirement, tracker.roots.items[@intFromEnum(id)].retirement_mark);
    try std.testing.expectEqual(@as(u32, 0), tracker.roots.items[@intFromEnum(id)].outcome_guard);
    try std.testing.expect(!tracker.dependencyIsAlive(dependency));
    try std.testing.expect(!tracker.isAlive(id));
    const counter = namespace.retirement_mark;
    tracker.markPossiblyRetired(id);
    try std.testing.expectEqual(counter, namespace.retirement_mark);
    try std.testing.expectEqual(Tracker.untracked_retirement, tracker.roots.items[@intFromEnum(id)].retirement_mark);
}

test "scalar opaque reads discard container lifetime facts" {
    const binding: graph.GlobalBindingId = @enumFromInt(7);
    const root: ValidityRootId = @enumFromInt(3);
    const capability: StorageCapabilityId = @enumFromInt(2);
    const method: u32 = 11;
    const value = ValueFacts{
        .dependencies = &.{.{ .root = root }},
        .owned_roots = &.{root},
        .integer_address = true,
        .foreign_storage = true,
        .storage_capabilities = &.{capability},
        .referenced_place = .{ .root = binding },
        .opaque_provenance = &.{.{ .storage = .{ .place = .{ .root = binding } }, .generation = root }},
        .virtual_no_access = &.{method},
    };

    const scalar = value.scalarOpaqueRead();
    try std.testing.expectEqual(@as(usize, 0), scalar.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.owned_roots.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.fields.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.variants.len);
    try std.testing.expectEqual(@as(?Place, null), scalar.referenced_place);
    try std.testing.expectEqual(@as(usize, 0), scalar.opaque_provenance.len);
    try std.testing.expectEqual(@as(usize, 0), scalar.virtual_no_access.len);
    try std.testing.expect(scalar.integer_address);
    try std.testing.expect(scalar.foreign_storage);
    try std.testing.expectEqualSlices(StorageCapabilityId, &.{capability}, scalar.storage_capabilities);
}

test "reference copies preserve virtual dispatch identity" {
    const method: u32 = 9;
    const copied = (ValueFacts{ .virtual_no_access = &.{method} }).referenceCopy();
    try std.testing.expectEqualSlices(u32, &.{method}, copied.virtual_no_access);
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
    const field: SymbolicStorageSelector = .{ .projection = .{ .field = 0 } };
    try original.reserveProjection(a, field);
    original.publishProjection(.{
        .parent = @enumFromInt(0),
        .parent_generation = @enumFromInt(1),
        .selector = field,
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
    const variant: SymbolicStorageSelector = .{ .projection = .{ .variant = 2 } };
    try candidate.reserveProjection(allocator, variant);
    candidate.publishProjection(.{
        .parent = @enumFromInt(0),
        .parent_generation = @enumFromInt(1),
        .selector = variant,
        .identity = @enumFromInt(4),
        .backing = @enumFromInt(2),
        .generation = @enumFromInt(2),
    });
    candidate.next_symbolic_id = 5;
    candidate.next_capability_id = 8;
    try std.testing.expect(original.projected_storage.items[0].selector.eql(.{ .projection = .{ .field = 0 } }));
    const key: Tracker.RootNamespace.ProjectionObservation = .{ .parent = @enumFromInt(0), .generation = @enumFromInt(1), .selector = variant };
    try std.testing.expectEqual(null, original.observedProjection(key));
    try std.testing.expectEqual(@as(SymbolicPointeeId, @enumFromInt(4)), candidate.observedProjection(key).?.identity);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(original.projectionPartition(@enumFromInt(3)).?));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(candidate.projectionPartition(@enumFromInt(4)).?));
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
    return (try replaceValueRootsIfChanged(allocator, value, .{ .sources = sources, .destinations = .{ .shared = replacement } })) orelse value;
}

/// Rebase structural ownership facts simultaneously so a replacement is
/// never treated as another source. External roots keep their identities.
pub fn remapValueRoots(allocator: std.mem.Allocator, value: ValueFacts, mapping: *const std.AutoHashMap(ValidityRootId, ValidityRootId)) !ValueFacts {
    return (try replaceValueRootsIfChanged(allocator, value, .{ .sources = &.{}, .destinations = .{ .map = mapping } })) orelse value;
}

/// Summarize dependencies that lack a live witness. The caller proves
/// the destination cannot revalidate any mapped observation.
pub fn summarizeHistoricalDependencies(allocator: std.mem.Allocator, value: ValueFacts, mapping: *const std.AutoHashMap(ValidityRootId, ValidityRootId)) !ValueFacts {
    return (try replaceValueRootsIfChanged(allocator, value, .{
        .sources = &.{},
        .destinations = .{ .map = mapping },
        .expired_dependencies = true,
    })) orelse value;
}

/// Rebase a verified current owner alternative. Conditional witnesses can
/// follow the owner only when that exact observation is valid at the join.
pub fn rebaseLoopOwnerRoots(allocator: std.mem.Allocator, value: ValueFacts, sources: []const ValidityRootId, destination: ValidityRootId, tracker: *const Tracker) !ValueFacts {
    return (try replaceValueRootsIfChanged(allocator, value, .{
        .sources = sources,
        .destinations = .{ .shared = destination },
        .owner_tracker = tracker,
    })) orelse value;
}

const RootReplacement = struct {
    owner_tracker: ?*const Tracker = null,
    expired_dependencies: bool = false,
    sources: []const ValidityRootId,
    destinations: union(enum) {
        shared: ValidityRootId,
        map: *const std.AutoHashMap(ValidityRootId, ValidityRootId),
    },

    fn apply(self: RootReplacement, root: ValidityRootId) ValidityRootId {
        return switch (self.destinations) {
            .shared => |replacement| if (std.mem.indexOfScalar(ValidityRootId, self.sources, root) != null) replacement else root,
            .map => |mapping| mapping.get(root) orelse root,
        };
    }

    fn applyObservation(self: RootReplacement, observation: ValidityDependency) ValidityDependency {
        // Conditional witnesses require the tracker from the owner join.
        const target = self.apply(observation.root);
        if (target == observation.root) return observation;
        if (self.expired_dependencies) return .{ .root = target };
        if (observation.retirement_mark != 0) {
            const tracker = self.owner_tracker orelse return observation;
            if (!tracker.dependencyIsAlive(observation)) return observation;
        }
        return .{ .root = target };
    }
};

fn replaceValueRootsIfChanged(
    allocator: std.mem.Allocator,
    value: ValueFacts,
    replacement: RootReplacement,
) !?ValueFacts {
    var result = value;
    var changed = false;
    if (value.owned_backing) |root| {
        if (root != replacement.apply(root)) {
            result.owned_backing = replacement.apply(root);
            changed = true;
        }
    }
    if (value.intrinsic_backing_owner) |root| {
        if (root != replacement.apply(root)) {
            result.intrinsic_backing_owner = replacement.apply(root);
            changed = true;
        }
    }
    for (value.dependencies) |dependency| {
        if (std.meta.eql(dependency, replacement.applyObservation(dependency))) continue;
        var dependencies: std.ArrayList(ValidityDependency) = .empty;
        for (value.dependencies) |entry| {
            const remapped = replacement.applyObservation(entry);
            for (dependencies.items) |existing| {
                if (std.meta.eql(existing, remapped)) break;
            } else try dependencies.append(allocator, remapped);
        }
        result.dependencies = try dependencies.toOwnedSlice(allocator);
        changed = true;
        break;
    }
    for (value.owned_roots) |owned| {
        if (owned == replacement.apply(owned)) continue;
        var roots: std.ArrayList(ValidityRootId) = .empty;
        for (value.owned_roots) |entry| {
            const root = replacement.apply(entry);
            if (std.mem.indexOfScalar(ValidityRootId, roots.items, root) == null) try roots.append(allocator, root);
        }
        result.owned_roots = try roots.toOwnedSlice(allocator);
        changed = true;
        break;
    }
    inline for (.{ "fields", "variants" }) |member| {
        const entries = @field(value, member);
        var updated: ?[]std.meta.Elem(@TypeOf(entries)) = null;
        for (entries, 0..) |entry, index| {
            const child = try replaceValueRootsIfChanged(allocator, entry.value.*, replacement) orelse continue;
            if (updated == null) updated = try allocator.dupe(std.meta.Elem(@TypeOf(entries)), entries);
            const stored = try allocator.create(ValueFacts);
            stored.* = child;
            updated.?[index].value = stored;
        }
        if (updated) |entries_updated| {
            @field(result, member) = entries_updated;
            changed = true;
        }
    }
    return if (changed) result else null;
}

test "rebasing ownership preserves unrelated fact fragments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const old: ValidityRootId = @enumFromInt(0);
    const renewed: ValidityRootId = @enumFromInt(1);
    const external: ValidityRootId = @enumFromInt(2);
    const internal: ValueFacts = .{ .owned_backing = old, .dependencies = &.{.{ .root = old }} };
    const unrelated: ValueFacts = .{ .dependencies = &.{.{ .root = external }} };
    const historical: ValueFacts = .{ .dependencies = &.{.{ .root = old, .retirement_mark = 2 }} };
    const owner: ValueFacts = .{
        .owned_roots = &.{old},
        .fields = &.{
            .{ .index = 0, .value = &internal },
            .{ .index = 1, .value = &unrelated },
            .{ .index = 2, .value = &historical },
        },
    };
    const result = try replaceValueRoots(arena.allocator(), owner, &.{old}, renewed);
    try std.testing.expectEqual(renewed, result.owned_roots[0]);
    try std.testing.expectEqual(renewed, result.fields[0].value.dependencies[0].root);
    try std.testing.expectEqual(renewed, result.fields[0].value.referenceCopy().owned_backing.?);
    try std.testing.expect(result.fields[0].value.derivedReference().owned_backing == null);
    try std.testing.expectEqual(&unrelated, result.fields[1].value);
    try std.testing.expectEqual(&historical, result.fields[2].value);
    try std.testing.expectEqual(old, internal.dependencies[0].root);
    const unchanged = try replaceValueRoots(arena.allocator(), result, &.{old}, renewed);
    try std.testing.expectEqual(result.fields.ptr, unchanged.fields.ptr);
}

test "remapping preserves separate owned backing identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const first: ValidityRootId = @enumFromInt(0);
    const second: ValidityRootId = @enumFromInt(1);
    const external: ValidityRootId = @enumFromInt(2);
    const renewed_first: ValidityRootId = @enumFromInt(3);
    const renewed_second: ValidityRootId = @enumFromInt(4);
    var mapping = std.AutoHashMap(ValidityRootId, ValidityRootId).init(allocator);
    defer mapping.deinit();
    try mapping.put(first, renewed_first);
    try mapping.put(second, renewed_second);
    const first_observation: ValueFacts = .{ .owned_backing = first, .dependencies = &.{.{ .root = first }} };
    const second_observation: ValueFacts = .{ .owned_backing = second, .dependencies = &.{.{ .root = second }} };
    const owner: ValueFacts = .{
        .owned_roots = &.{ first, second },
        .dependencies = &.{.{ .root = external }},
        .fields = &.{ .{ .index = 0, .value = &first_observation }, .{ .index = 1, .value = &second_observation } },
    };
    const remapped = try remapValueRoots(allocator, owner, &mapping);
    try std.testing.expectEqualSlices(ValidityRootId, &.{ renewed_first, renewed_second }, remapped.owned_roots);
    try std.testing.expectEqual(external, remapped.dependencies[0].root);
    try std.testing.expectEqual(renewed_first, remapped.fields[0].value.owned_backing.?);
    try std.testing.expectEqual(renewed_second, remapped.fields[1].value.owned_backing.?);
    try std.testing.expectEqual(first, first_observation.owned_backing.?);
    try std.testing.expectEqual(second, second_observation.owned_backing.?);
}

test "Safety root materialization does not publish partial gaps on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn materialize(a: std.mem.Allocator) !void {
            var tracker = Tracker.init(a);
            defer tracker.deinit();
            tracker.materialize(@enumFromInt(67)) catch |err| {
                try std.testing.expectEqual(@as(usize, 0), tracker.roots.items.len);
                return err;
            };
            try std.testing.expect(tracker.isAlive(@enumFromInt(67)));
            for (tracker.roots.items[0..67]) |root| try std.testing.expect(!root.present);
        }
    }.materialize, .{});
}

test "reference offsets retain validity observations without retaining a false target" {
    const original = ValueFacts{
        .referenced_place = .{ .root = @enumFromInt(0), .projections = &.{.{ .field = 0 }} },
        .symbolic_pointees = &.{@enumFromInt(1)},
        .dependencies = &.{.{ .root = @enumFromInt(2) }},
        .lexical_frame = 3,
        .virtual_no_access = &.{4},
        .domains = &.{.{ .domain_index = 0, .storages = &.{} }},
    };
    const offset = original.derivedReference();
    try std.testing.expectEqual(@as(?Place, null), offset.referenced_place);
    try std.testing.expectEqual(@as(usize, 0), offset.symbolic_pointees.len);
    try std.testing.expectEqual(@as(usize, 0), offset.domains.len);
    try std.testing.expectEqual(@as(usize, 0), offset.virtual_no_access.len);
    try std.testing.expectEqual(@as(?u32, 3), offset.lexical_frame);
    try std.testing.expectEqualSlices(ValidityDependency, original.dependencies, offset.dependencies);
}

test "loop owner rebasing preserves an expired conditional observation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var namespace: Tracker.RootNamespace = .{};
    defer namespace.deinit(a);
    var tracker = Tracker.init(a);
    defer tracker.deinit();
    tracker.namespace = &namespace;
    const source = try tracker.establish(.fresh);
    const destination = try tracker.establish(.fresh);
    try std.testing.expect(tracker.deferRetirement(source, 1));
    const mark = tracker.roots.items[@intFromEnum(source)].retirement_mark;
    const value: ValueFacts = .{ .dependencies = &.{
        .{ .root = source, .retirement_mark = mark },
        .{ .root = source, .retirement_mark = mark - 1 },
    } };
    const rebased = try rebaseLoopOwnerRoots(a, value, &.{source}, destination, &tracker);
    try std.testing.expectEqual(destination, rebased.dependencies[0].root);
    try std.testing.expectEqual(value.dependencies[1], rebased.dependencies[1]);
    try std.testing.expect(!tracker.dependenciesAreAlive(rebased));
}

pub fn valueFactsEqual(left: ValueFacts, right: ValueFacts) bool {
    if (left.intrinsic_backing_owner != right.intrinsic_backing_owner) return false;
    if (left.task_output_execution != right.task_output_execution or left.task_output_claim != right.task_output_claim) return false;
    if (left.execution_receipt_incomplete != right.execution_receipt_incomplete) return false;
    if (left.owned_backing != right.owned_backing) return false;
    if (left.reference_target_incomplete != right.reference_target_incomplete) return false;
    if (left.reference_coverage_complete != right.reference_coverage_complete) return false;
    if (left.mutation_places.len != right.mutation_places.len) return false;
    for (left.mutation_places, right.mutation_places) |a, b| if (!a.eql(b)) return false;
    if (left.lexical_frame != right.lexical_frame) return false;
    if (!std.mem.eql(ExecutionId, left.execution_receipts, right.execution_receipts)) return false;
    if (left.symbolic_pointees.len != right.symbolic_pointees.len) return false;
    for (left.symbolic_pointees) |identity|
        if (std.mem.indexOfScalar(SymbolicPointeeId, right.symbolic_pointees, identity) == null) return false;
    if (left.domains.len != right.domains.len) return false;
    for (left.domains, right.domains) |a, b| {
        if (a.domain_index != b.domain_index or a.storages.len != b.storages.len or !std.mem.eql(SymbolicPointeeId, a.symbolic_pointees, b.symbolic_pointees)) return false;
        if (a.required_reads.len != b.required_reads.len) return false;
        for (a.required_reads, b.required_reads) |x, y| if (!x.eql(y)) return false;
        if (a.traversals.len != b.traversals.len) return false;
        for (a.traversals, b.traversals) |x, y| if (!x.eql(y)) return false;
        for (a.storages, b.storages) |x, y| if (!x.eql(y)) return false;
    }
    if (left.explicit_dependency != right.explicit_dependency or
        left.integer_address != right.integer_address or
        left.foreign_storage != right.foreign_storage or
        left.storage_capability_incomplete != right.storage_capability_incomplete or
        left.known_choice_variant != right.known_choice_variant or
        !std.mem.eql(StorageCapabilityId, left.storage_capabilities, right.storage_capabilities) or
        !std.mem.eql(StorageCapabilityId, left.acquisition_origins, right.acquisition_origins) or
        left.concurrent_receiver != right.concurrent_receiver or
        !std.mem.eql(u32, left.virtual_no_access, right.virtual_no_access) or
        left.dependencies.len != right.dependencies.len or
        left.owned_roots.len != right.owned_roots.len or
        left.fields.len != right.fields.len or
        left.variants.len != right.variants.len or
        left.opaque_provenance.len != right.opaque_provenance.len or left.generation_outcomes.len != right.generation_outcomes.len) return false;
    if (left.choice_selectors.len != right.choice_selectors.len or left.choice_observations.len != right.choice_observations.len or left.guarded_values.len != right.guarded_values.len) return false;
    for (left.choice_selectors, right.choice_selectors) |a, b| if (!a.eql(b)) return false;
    for (left.choice_observations, right.choice_observations) |a, b| if (!a.eql(b)) return false;
    for (left.guarded_values, right.guarded_values) |a, b| if (!a.eql(b)) return false;
    if (!std.mem.eql(ExecutionId, left.completed_executions, right.completed_executions)) return false;
    for (left.generation_outcomes, right.generation_outcomes) |a, b| if (!a.eql(b)) return false;
    for (left.dependencies, right.dependencies) |a, b| if (!std.meta.eql(a, b)) return false;
    for (left.owned_roots, right.owned_roots) |a, b| if (a != b) return false;
    if ((left.referenced_place == null) != (right.referenced_place == null)) return false;
    if (left.referenced_place) |left_place| if (!left_place.eql(right.referenced_place.?)) return false;
    for (left.opaque_provenance, right.opaque_provenance) |a, b|
        if (!a.storage.eql(b.storage) or a.generation != b.generation) return false;
    for (left.fields, right.fields) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    for (left.variants, right.variants) |a, b| if (a.index != b.index or !valueFactsEqual(a.value.*, b.value.*)) return false;
    return true;
}
