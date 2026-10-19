const std = @import("std");
const c_abi = @import("c_abi.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const primitives = @import("../primitives/schema.zig");
const global_sg = @import("graph.zig");
const global_types = @import("types.zig");
const globalizer = @import("globalizer.zig");
const module_linker = @import("module_linker.zig");
const global_verify = @import("verify.zig");
const core_mod = @import("core.zig");
const expression_mod = @import("expressions.zig");
const control_mod = @import("control.zig");
const generic_mod = @import("generics.zig");
const generic_functions_mod = @import("generic_functions.zig");
const contract_mod = @import("contracts.zig");
const error_mod = @import("errors.zig");
const ownership_mod = @import("ownership.zig");
const resolution = @import("resolution.zig");
const dispatch_mod = @import("dispatch.zig");
const reachability_mod = @import("reachability.zig");
const reach_context = @import("reach_context.zig");

pub const Options = struct {
    target: @import("../../1_base/target.zig").Config = .{},
    selected_test_name: ?[]const u8 = null,
    exhaustive_function_bodies: bool = true,
    diagnostics: ?*diagnostics_mod.Diagnostics = null,
    profile_io: ?std.Io = null,
};

pub const SetupStage = enum { external_types, conformance_registration, associated_types, known_types, sugar_types, worklists, conformance_validation, roots };
const setup_stage_count = @typeInfo(SetupStage).@"enum".fields.len;

pub const Stats = struct {
    pub const PendingResolution = struct {
        initial_operations: u64 = 0,
        attempts: u64 = 0,
        resolved: u64 = 0,
        invalid: u64 = 0,
        deferred: u64 = 0,
        ns: u64 = 0,
        resolved_ns: u64 = 0,
        deferred_ns: u64 = 0,
        invalid_ns: u64 = 0,
    };

    pub const Timings = struct {
        relocation_ns: u64 = 0,
        setup_ns: u64 = 0,
        setup_stages_ns: [setup_stage_count]u64 = @splat(0),
        fixed_point_ns: u64 = 0,
        pending_ns: u64 = 0,
        string_literal_types_ns: u64 = 0,
        binding_types_ns: u64 = 0,
        assignment_values_ns: u64 = 0,
        dereferences_ns: u64 = 0,
        addresses_ns: u64 = 0,
        known_generic_types_ns: u64 = 0,
        field_access_types_ns: u64 = 0,
        sugar_types_ns: u64 = 0,
        error_inference_ns: u64 = 0,
        error_summary_ns: u64 = 0,
        error_refresh_ns: u64 = 0,
        cleanup_ns: u64 = 0,
        implicit_destructor_ns: u64 = 0,
        generic_constraints_ns: u64 = 0,
        generic_selection_prefilter_ns: u64 = 0,
        generic_selection_constraints_ns: u64 = 0,
        generic_selection_arguments_ns: u64 = 0,
        generic_selection_instantiation_ns: u64 = 0,
        source_generic_selection_ns: u64 = 0,
        source_generic_completion_ns: u64 = 0,
        generic_instantiation_ns: u64 = 0,
        generic_instantiation_lookup_ns: u64 = 0,
        generic_instantiation_body_ns: u64 = 0,
        generic_instance_context_init_ns: u64 = 0,
        post_resolution_ns: u64 = 0,
        verify_ns: u64 = 0,
    };

    core: core_mod.Stats = .{},
    expressions: expression_mod.Stats = .{},
    control: control_mod.Stats = .{},
    generics: generic_mod.Stats = .{},
    generic_functions: generic_functions_mod.Stats = .{},
    generic_selection: generic_functions_mod.SelectionProfile = .{},
    contracts: contract_mod.Stats = .{},
    errors: error_mod.Stats = .{},
    ownership: ownership_mod.Stats = .{},
    pending_call_stages: [@typeInfo(dispatch_mod.PendingCallStage).@"enum".fields.len]dispatch_mod.PendingCallStageStats = @splat(.{}),
    pending_total: u32 = 0,
    pending_resolved: u32 = 0,
    pending_attempts: u64 = 0,
    pending_by_owner: [pending_owner_count]PendingResolution = @splat(.{}),
    pending_by_operation: [pending_tag_count]PendingResolution = @splat(.{}),
    remaining: u32 = 0,
    rounds: u32 = 0,
    cleanup_attempts: u32 = 0,
    destructor_lookups: u32 = 0,
    generic_instantiation_calls: u64 = 0,
    generic_existing_instances: u64 = 0,
    generic_bodies_built: u64 = 0,
    generic_bodies_unreachable: u64 = 0,
    generic_reachability_tracked: bool = false,
    timings: Timings = .{},
};

pub const Result = struct {
    graph: global_sg.GlobalSemanticGraph,
    stats: Stats,
};

fn profileTimestamp(io: ?std.Io) i96 {
    if (io) |profile_io| return std.Io.Timestamp.now(profile_io, .boot).nanoseconds;
    return 0;
}

fn profileAccumulate(io: ?std.Io, start: i96, elapsed: *i96) void {
    if (io) |profile_io| elapsed.* += std.Io.Timestamp.now(profile_io, .boot).nanoseconds - start;
}

/// Top-level semantic ownership is stable for the lifetime of a pending
/// operation. Composite owners such as calls and indexing may try multiple
/// implementation strategies internally, but those strategies never compete
/// for ownership at the GlobalSema boundary.
pub const PendingOwner = enum {
    types,
    calls,
    indexing,
    core,
    expressions,
    control,
    contracts,
    errors,
    ownership,
};

pub const PendingTag = @typeInfo(module_entities.PendingOperation).@"union".tag_type.?;
const pending_owner_count = @typeInfo(PendingOwner).@"enum".fields.len;
const pending_tag_count = @typeInfo(PendingTag).@"enum".fields.len;

const PendingResolutionStats = struct {
    owners: [pending_owner_count]Stats.PendingResolution = @splat(.{}),
    operations: [pending_tag_count]Stats.PendingResolution = @splat(.{}),

    fn initial(self: *PendingResolutionStats, operation: module_entities.PendingOperation) void {
        self.owners[@intFromEnum(pendingOwner(operation))].initial_operations += 1;
        self.operations[@intFromEnum(std.meta.activeTag(operation))].initial_operations += 1;
    }

    fn attempt(self: *PendingResolutionStats, operation: module_entities.PendingOperation, result: resolution.Result, elapsed_ns: u64) void {
        const owner = &self.owners[@intFromEnum(pendingOwner(operation))];
        const tag = &self.operations[@intFromEnum(std.meta.activeTag(operation))];
        owner.attempts += 1;
        tag.attempts += 1;
        owner.ns += elapsed_ns;
        tag.ns += elapsed_ns;
        switch (result) {
            .resolved => {
                owner.resolved += 1;
                tag.resolved += 1;
                owner.resolved_ns += elapsed_ns;
                tag.resolved_ns += elapsed_ns;
            },
            .invalid => {
                owner.invalid += 1;
                tag.invalid += 1;
                owner.invalid_ns += elapsed_ns;
                tag.invalid_ns += elapsed_ns;
            },
            .deferred => {
                owner.deferred += 1;
                tag.deferred += 1;
                owner.deferred_ns += elapsed_ns;
                tag.deferred_ns += elapsed_ns;
            },
            .not_applicable => unreachable,
        }
    }
};

const PendingPhase = enum {
    types_and_generics,
    expressions_and_calls,
    control_and_contracts,
    errors,
    ownership,
};

const pending_phases = [_]PendingPhase{
    .types_and_generics,
    .expressions_and_calls,
    .control_and_contracts,
    .errors,
    .ownership,
};

const PendingWorkItem = struct {
    module_index: u32,
    operation_index: u32,
    flat_index: u32,
    owner_function: ?global_sg.GlobalFunctionId = null,
};

/// Pending operations are routed once, then only unresolved work is retained.
/// This preserves source order inside each phase while avoiding repeated scans
/// of unrelated phases and already-resolved operations on every fixed-point
/// iteration.
const PendingWorklists = struct {
    types_and_generics: std.ArrayList(PendingWorkItem) = .empty,
    expressions_and_calls: std.ArrayList(PendingWorkItem) = .empty,
    control_and_contracts: std.ArrayList(PendingWorkItem) = .empty,
    errors: std.ArrayList(PendingWorkItem) = .empty,
    ownership: std.ArrayList(PendingWorkItem) = .empty,
    module_count: usize = 0,
    operation_count: u32 = 0,

    fn init(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !PendingWorklists {
        var result: PendingWorklists = .{};
        errdefer result.deinit(allocator);
        try result.appendModules(allocator, modules, offsets);
        return result;
    }

    // Append only the new module suffix. Compaction of resolved queues never
    // changes flat operation identities used by diagnostics and status tables.
    fn appendModules(self: *PendingWorklists, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !void {
        if (modules.len < self.module_count or offsets.len != modules.len) return error.InvalidPendingModulePrefix;
        var lengths: [pending_phases.len]usize = undefined;
        for (pending_phases, &lengths) |phase, *length| length.* = self.forPhase(phase).items.len;
        const saved_operations = self.operation_count;
        errdefer {
            for (pending_phases, lengths) |phase, length| self.forPhase(phase).shrinkRetainingCapacity(length);
            self.operation_count = saved_operations;
        }
        for (modules[self.module_count..], self.module_count..) |*module, module_index| {
            for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
                try self.forPhase(pendingPhase(operation)).append(allocator, .{
                    .module_index = @intCast(module_index),
                    .operation_index = @intCast(operation_index),
                    .flat_index = self.operation_count,
                    .owner_function = if (operation_index < module.semantic.pending_owner_functions.items.len)
                        if (module.semantic.pending_owner_functions.items[operation_index]) |owner|
                            globalizer.globalFunction(offsets[module_index], owner)
                        else
                            null
                    else
                        null,
                });
                self.operation_count = std.math.add(u32, self.operation_count, 1) catch return error.TooManyPendingOperations;
            }
        }
        self.module_count = modules.len;
    }

    fn deinit(self: *PendingWorklists, allocator: std.mem.Allocator) void {
        self.types_and_generics.deinit(allocator);
        self.expressions_and_calls.deinit(allocator);
        self.control_and_contracts.deinit(allocator);
        self.errors.deinit(allocator);
        self.ownership.deinit(allocator);
    }

    fn forPhase(self: *PendingWorklists, phase: PendingPhase) *std.ArrayList(PendingWorkItem) {
        return switch (phase) {
            .types_and_generics => &self.types_and_generics,
            .expressions_and_calls => &self.expressions_and_calls,
            .control_and_contracts => &self.control_and_contracts,
            .errors => &self.errors,
            .ownership => &self.ownership,
        };
    }

    fn remaining(self: *const PendingWorklists, reachable: ?*const reachability_mod.FunctionSet) usize {
        var count: usize = 0;
        for (pending_phases) |phase| for (self.forPhaseConst(phase).items) |item| {
            if (isActive(item, reachable)) count += 1;
        };
        return count;
    }

    fn forPhaseConst(self: *const PendingWorklists, phase: PendingPhase) *const std.ArrayList(PendingWorkItem) {
        return switch (phase) {
            .types_and_generics => &self.types_and_generics,
            .expressions_and_calls => &self.expressions_and_calls,
            .control_and_contracts => &self.control_and_contracts,
            .errors => &self.errors,
            .ownership => &self.ownership,
        };
    }
};

// Resolution state outlives individual fixed-point passes. Dense status tables
// use the same append-only operation identities as the phase queues.
const ResolutionState = struct {
    worklists: PendingWorklists = .{},
    resolved: std.ArrayList(bool) = .empty,
    invalid: std.ArrayList(bool) = .empty,
    finalized_functions: std.AutoHashMap(global_sg.GlobalFunctionId, void),
    progress: ResolutionProgress = .{},
    pending_stats: PendingResolutionStats = .{},

    fn init(allocator: std.mem.Allocator) ResolutionState {
        return .{ .finalized_functions = .init(allocator) };
    }

    fn clone(self: *const ResolutionState, allocator: std.mem.Allocator) !ResolutionState {
        var result = ResolutionState.init(allocator);
        errdefer result.deinit(allocator);
        result.progress = self.progress;
        result.pending_stats = self.pending_stats;
        result.worklists.module_count = self.worklists.module_count;
        result.worklists.operation_count = self.worklists.operation_count;
        for (pending_phases) |phase| {
            try result.worklists.forPhase(phase).appendSlice(allocator, self.worklists.forPhaseConst(phase).items);
        }
        try result.resolved.appendSlice(allocator, self.resolved.items);
        try result.invalid.appendSlice(allocator, self.invalid.items);
        result.finalized_functions = try self.finalized_functions.cloneWithAllocator(allocator);
        return result;
    }

    fn appendModules(self: *ResolutionState, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !void {
        const total = totalPending(modules);
        // Reserve before publishing queues so failure preserves all logical state.
        try self.resolved.ensureTotalCapacity(allocator, total);
        try self.invalid.ensureTotalCapacity(allocator, total);
        try self.worklists.appendModules(allocator, modules, offsets);
        const previous = self.resolved.items.len;
        self.resolved.expandToCapacity();
        self.resolved.shrinkRetainingCapacity(total);
        self.invalid.expandToCapacity();
        self.invalid.shrinkRetainingCapacity(total);
        @memset(self.resolved.items[previous..], false);
        @memset(self.invalid.items[previous..], false);
    }

    fn deinit(self: *ResolutionState, allocator: std.mem.Allocator) void {
        self.worklists.deinit(allocator);
        self.resolved.deinit(allocator);
        self.invalid.deinit(allocator);
        self.finalized_functions.deinit();
        self.* = undefined;
    }
};

pub fn semantize(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
) !Result {
    return semantizeWithOptions(allocator, modules, .{});
}

pub fn semantizeWithOptions(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
    options: Options,
) !Result {
    var session: Session = undefined;
    try session.init(allocator, modules, options);
    defer session.deinit();
    try session.advance();
    return session.finish();
}

/// Retained semantic construction state, separate from graph publication.
/// Initialize in final storage. Borrowed ModuleSGs and optional diagnostics
/// must remain alive until deinit.
/// Failed advancement poisons the session; callers must discard it rather than
/// expose an incompletely checked graph. Published graphs transfer to Result.
pub const Session = struct {
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
    options: Options,
    relocation: globalizer.Relocation = .{ .graph = .{} },
    resolvers: @import("resolver_context.zig").Context = undefined,
    resolvers_initialized: bool = false,
    resolution: ResolutionState,
    reachable: ?reachability_mod.FunctionSet = null,
    phase: enum { preparing, ready, quiescent, published, failed } = .preparing,
    setup_stages: [setup_stage_count]i96 = @splat(0),
    profile_start: i96 = 0,
    profile_relocated: i96 = 0,
    profile_preloop: i96 = 0,
    profile_postloop: i96 = 0,
    fixed_point_ns: i96 = 0,

    pub fn init(self: *Session, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: Options) !void {
        self.* = .{ .allocator = allocator, .modules = modules, .options = options, .resolution = ResolutionState.init(allocator) };
        errdefer self.deinit();
        self.profile_start = profileTimestamp(options.profile_io);
        self.relocation = try globalizer.relocate(allocator, modules, .allow_holes);
        const relocation = &self.relocation;
        relocation.graph.target = options.target;
        try module_linker.link(allocator, &relocation.graph, modules, relocation.offsets.items);
        self.profile_relocated = profileTimestamp(options.profile_io);

        // The globalizer preallocates stable GlobalTypeId slots. Record which of
        // those slots are genuinely unresolved before any resolver can inspect
        // them; unresolved is construction state, not the language type `Any`.
        try markUnresolvedTypeSlots(allocator, &relocation.graph, modules, relocation.offsets.items);

        try @import("c_abi.zig").prepareForeignCapabilities(allocator, &relocation.graph);

        const resolvers = &self.resolvers;
        resolvers.init(allocator, &relocation.graph, modules, relocation.offsets.items, options.diagnostics, options.profile_io);
        self.resolvers_initialized = true;
        const core = &resolvers.core;
        const control = &resolvers.control;
        const generics = &resolvers.generics;
        const contracts = &resolvers.contracts;
        if (try resolveQualifiedChoiceOptions(core, options.diagnostics)) return error.Reported;

        const setup_stages = &self.setup_stages;
        var setup_start = profileTimestamp(options.profile_io);
        try core.resolveExternalTypes();
        try generics.resolveExternalTypes();
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.external_types)]);
        setup_start = profileTimestamp(options.profile_io);
        // Generic record fields can contain associated projections. Publish tuple
        // associations before materializing either their records or operation types.
        try contracts.prepareParticipantConformances();
        try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.conformance_registration)]);
        setup_start = profileTimestamp(options.profile_io);
        contracts.resolveAssociatedTypes() catch |err| {
            try reportComptimeExpressionFailure(&relocation.graph, options.diagnostics, generics);
            try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
            return err;
        };
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.associated_types)]);
        setup_start = profileTimestamp(options.profile_io);
        _ = generics.materializeKnownTypes() catch |err| {
            try reportGenericArgumentFailure(&relocation.graph, options.diagnostics, generics);
            try reportComptimeExpressionFailure(&relocation.graph, options.diagnostics, generics);
            try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
            return err;
        };
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.known_types)]);
        setup_start = profileTimestamp(options.profile_io);
        _ = try control.materializeSugarTypes();

        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.sugar_types)]);
        setup_start = profileTimestamp(options.profile_io);
        if (options.diagnostics) |diagnostics| {
            for (relocation.graph.functions.items) |function| {
                for (relocation.graph.fields.items[function.output.start..][0..function.output.len]) |field| {
                    const contract_use = contracts.typeContractUse(field.ty) orelse continue;
                    const declaration = relocation.graph.declaration(function.declaration);
                    try diagnostics.add(
                        diagnosticLocation(&relocation.graph, diagnostics, declaration.source),
                        .semantic,
                        "function '{s}' cannot return contract '{s}' as a runtime value; use a concrete type or Virtual",
                        .{ relocation.graph.text(declaration.name), relocation.graph.text(relocation.graph.declaration(contract_use.declaration).name) },
                    );
                    return error.Reported;
                }
            }
        }

        try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);

        const resolution_state = &self.resolution;
        try resolution_state.appendModules(allocator, modules, relocation.offsets.items);
        const pending_resolution_stats = &resolution_state.pending_stats;
        if (options.profile_io != null) {
            for (modules) |module| for (module.semantic.pending_operations.items) |operation| {
                pending_resolution_stats.initial(operation);
            };
        }
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.worklists)]);
        setup_start = profileTimestamp(options.profile_io);
        // Validate declarations independently of executable use. Body proofs follow
        // selected operations, or all materialized bodies in exhaustive mode.
        contracts.validateParticipantConformances() catch |err| {
            try reportComptimeExpressionFailure(&relocation.graph, options.diagnostics, generics);
            try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
            return err;
        };
        try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.conformance_validation)]);
        setup_start = profileTimestamp(options.profile_io);
        if (!options.exhaustive_function_bodies)
            self.reachable = try reachability_mod.executionRoots(allocator, &relocation.graph, options.selected_test_name);
        profileAccumulate(options.profile_io, setup_start, &setup_stages[@intFromEnum(SetupStage.roots)]);
        self.phase = .ready;
    }

    /// Build an independent candidate without rerunning accepted source.
    /// Both sessions borrow the same immutable ModuleSG prefix. Initialize the
    /// candidate in its final storage; reject it by deinitializing it. Accepting
    /// a candidate exchanges owner pointers, never moves these callback targets.
    pub fn fork(self: *const Session, candidate: *Session, allocator: std.mem.Allocator, diagnostics: ?*diagnostics_mod.Diagnostics) !void {
        if (self == candidate or self.phase != .quiescent) return error.InvalidSemanticSessionState;
        var options = self.options;
        options.diagnostics = diagnostics;
        candidate.* = .{ .allocator = allocator, .modules = self.modules, .options = options, .resolution = ResolutionState.init(allocator) };
        errdefer candidate.deinit();
        candidate.relocation.graph = try self.relocation.graph.clone(allocator);
        candidate.relocation.offsets = try self.relocation.offsets.clone(allocator);
        try candidate.resolvers.cloneFrom(&self.resolvers, allocator, &candidate.relocation.graph, candidate.relocation.offsets.items, diagnostics);
        candidate.resolvers_initialized = true;
        candidate.resolution = try self.resolution.clone(allocator);
        if (self.reachable) |*set| candidate.reachable = try set.clone(allocator);
        candidate.setup_stages = self.setup_stages;
        candidate.profile_start = self.profile_start;
        candidate.profile_relocated = self.profile_relocated;
        candidate.profile_preloop = self.profile_preloop;
        candidate.profile_postloop = self.profile_postloop;
        candidate.fixed_point_ns = self.fixed_point_ns;
        candidate.phase = .quiescent;
    }

    fn reachableSet(self: *Session) ?*reachability_mod.FunctionSet {
        return if (self.reachable) |*set| set else null;
    }

    /// Add a borrowed immutable module suffix to an unpublished session.
    /// This construction API poisons the session on a preparation failure.
    /// Interactive publication must add a transaction around this operation.
    pub fn appendModules(self: *Session, modules: []const module_sg.ModuleSemanticGraph) !void {
        return self.appendModuleSuffix(modules, null);
    }

    /// Extend one logical module without moving existing declaration/file
    /// ranges. The caller retains the immutable fragment with borrowed ModuleSGs.
    pub fn appendModuleFragment(self: *Session, modules: []const module_sg.ModuleSemanticGraph, owner: global_sg.GlobalModuleId) !void {
        return self.appendModuleSuffix(modules, owner);
    }

    fn appendModuleSuffix(self: *Session, modules: []const module_sg.ModuleSemanticGraph, fragment_owner: ?global_sg.GlobalModuleId) !void {
        if (self.phase != .ready and self.phase != .quiescent) return error.InvalidSemanticSessionState;
        const previous = self.modules.len;
        if (modules.len < previous) return error.InvalidSemanticModuleViews;
        const namespace = if (fragment_owner) |owner| blk: {
            if (@intFromEnum(owner) >= previous or modules.len != previous + 1) return error.InvalidModuleFragment;
            const original = self.relocation.graph.modules.items[@intFromEnum(owner)];
            const fragment = &modules[previous];
            if (!std.mem.eql(u8, self.relocation.graph.text(original.dir), fragment.module_dir) or original.is_bundled_core != fragment.is_bundled_core)
                return error.InvalidModuleFragment;
            break :blk self.relocation.graph.moduleNamespace(owner);
        } else null;
        if (modules.len == previous) return;
        errdefer self.phase = .failed;
        const allocator = self.allocator;
        try self.relocation.append(allocator, modules[previous..], .allow_holes);
        if (namespace) |owner| {
            self.relocation.graph.modules.items[previous].namespace = owner;
            try self.validateFragmentFunctions(@enumFromInt(previous));
        }
        self.modules = modules;
        try self.resolvers.extendModuleViews(modules, self.relocation.offsets.items);
        try module_linker.append(allocator, &self.relocation.graph, modules, self.relocation.offsets.items, previous);
        try markUnresolvedTypeSlots(allocator, &self.relocation.graph, modules[previous..], self.relocation.offsets.items[previous..]);
        try c_abi.prepareForeignCapabilities(allocator, &self.relocation.graph);
        const core = &self.resolvers.core;
        const generics = &self.resolvers.generics;
        const contracts = &self.resolvers.contracts;
        if (try resolveQualifiedChoiceOptions(core, self.options.diagnostics)) return error.Reported;
        try core.resolveExternalTypesFrom(previous);
        try generics.resolveExternalTypesFrom(previous);
        try contracts.prepareParticipantConformances();
        try reportParticipantConformanceFailure(allocator, &self.relocation.graph, self.options.diagnostics, contracts.participant_conformance_failure);
        try contracts.resolveAssociatedTypes();
        _ = try generics.materializeKnownTypes();
        _ = try self.resolvers.control.materializeSugarTypes();
        try self.resolution.appendModules(allocator, modules, self.relocation.offsets.items);
        if (self.options.profile_io != null) {
            for (modules[previous..]) |module| for (module.semantic.pending_operations.items) |operation| {
                self.resolution.pending_stats.initial(operation);
            };
        }
        try contracts.validateParticipantConformances();
        try reportParticipantConformanceFailure(allocator, &self.relocation.graph, self.options.diagnostics, contracts.participant_conformance_failure);
        if (self.reachable) |*set| {
            var roots = try reachability_mod.executionRoots(allocator, &self.relocation.graph, self.options.selected_test_name);
            defer roots.deinit();
            // Root selection includes newly added entry and test declarations;
            // retain the existing closure through the ordinary expansion pass.
            var iterator = roots.values.keyIterator();
            while (iterator.next()) |id| _ = try set.include(id.*);
        }
        self.phase = .ready;
    }

    fn validateFragmentFunctions(self: *Session, fragment: global_sg.GlobalModuleId) !void {
        const graph = &self.relocation.graph;
        const range = graph.modules.items[@intFromEnum(fragment)].declarations;
        for (graph.declarations.items[range.start..][0..range.len], range.start..) |declaration, index| {
            if (declaration.kind != .function) continue;
            const name = graph.text(declaration.name);
            // Generated implementation identities have no source identifier.
            if (std.mem.indexOfScalar(u8, name, '$') != null) continue;
            for (try graph.declarationsNamed(self.allocator, name)) |other| {
                if (@intFromEnum(other) == index or graph.declaration(other).kind != .function) continue;
                const owner = graph.moduleForDeclaration(other) orelse continue;
                if (!graph.sameModuleNamespace(owner, fragment)) continue;
                if (self.options.diagnostics) |diagnostics| {
                    try diagnostics.add(diagnosticLocation(graph, diagnostics, declaration.source), .semantic, "ordinary function '{s}' has more than one declaration; provide specialized behavior through a contract implementation", .{name});
                    return error.Reported;
                }
                return error.DuplicateOrdinaryFunction;
            }
        }
    }

    /// Keep an explicitly selected command executable through lazy resolution
    /// and publication. It uses the same reachability closure as program roots.
    /// Designate a command before ownership finalization. Direct declarations
    /// survive command completion; their selected cleanup remains available for
    /// explicit session exit. Nested scopes keep ordinary destruction rules.
    pub fn prepareContinuationScope(self: *Session, function: global_sg.GlobalFunctionId) !void {
        if (@intFromEnum(function) >= self.relocation.graph.functions.items.len) return error.InvalidSafetyContinuation;
        const target = self.relocation.graph.function(function);
        if (target.input.len != 0 or target.output.len != 0 or (self.resolution.finalized_functions.contains(function) and self.resolvers.ownership.continuation_function != function))
            return error.InvalidSafetyContinuation;
        _ = try self.resolvers.core.builtin(.Bool);
        try self.includeExecutionRoot(function);
        self.resolvers.ownership.continuation_function = function;
        self.resolvers.ownership.continuation_bindings.clearRetainingCapacity();
        try self.resolvers.ownership.continuation_bindings.appendSlice(self.allocator, self.resolvers.expressions.session_bindings.items);
        self.resolvers.expressions.continuation_function = function;
        try self.inheritContinuationAssumptions(function);
    }

    /// Seed only this command's lexical call sites. Ordinary function bodies
    /// retain their own capability inputs; nested blocks can shadow this evidence.
    fn inheritContinuationAssumptions(self: *Session, function: global_sg.GlobalFunctionId) !void {
        const namespace = self.resolvers.core.session_namespace orelse return;
        if (namespace.assumptions.items.len == 0) return;
        for (self.modules, self.relocation.offsets.items) |module, offsets| {
            for (module.semantic.pending_operations.items, module.semantic.pending_owner_functions.items) |operation, owner| {
                const local_owner = owner orelse continue;
                if (globalizer.globalFunction(offsets, local_owner) != function) continue;
                const input = switch (operation) {
                    .resolve_call => |call| call.input,
                    .resolve_binary => |call| call.assumed_arguments orelse continue,
                    .resolve_comparison => |call| call.assumed_arguments orelse continue,
                    else => continue,
                };
                const visible_range = switch (operation) {
                    .resolve_call => |call| call.visible_bindings,
                    .resolve_binary => |call| call.visible_bindings,
                    .resolve_comparison => |call| call.visible_bindings,
                    else => unreachable,
                };
                const start = offsets.binding_ref_base + visible_range.start;
                const visible = self.relocation.graph.binding_refs.items[start..][0..visible_range.len];
                try self.inheritAssumedInput(globalizer.globalNode(offsets, input), namespace.assumptions.items, visible);
            }
        }
    }

    fn inheritAssumedInput(self: *Session, input: global_sg.GlobalNodeId, assumptions: []const global_sg.GlobalBindingId, visible: []const global_sg.GlobalBindingId) !void {
        const node = self.relocation.graph.node(input);
        if (node.content != .struct_value_literal) return error.InvalidSafetyContinuation;
        const fields = try self.resolvers.ownership.inheritAssumedFields(node.source, node.content.struct_value_literal.assumed_fields, assumptions, visible);
        self.relocation.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.assumed_fields = fields;
    }

    /// Fill an empty checked command with the retained selected cleanup list.
    /// No source body is overwritten and no ordinary function gains implicit
    /// destruction semantics. The exit is checked as a temporal continuation.
    pub fn retainContinuationBindings(self: *Session, function: global_sg.GlobalFunctionId) !void {
        if (self.phase != .quiescent or self.resolvers.expressions.continuation_function != function) return error.InvalidSafetyContinuation;
        const body = self.relocation.graph.function(function).body orelse return error.InvalidSafetyContinuation;
        const block = self.relocation.graph.blocks.items[@intFromEnum(body)];
        const retained = &self.resolvers.expressions.session_bindings;
        for (self.relocation.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            const content = self.relocation.graph.node(node).content;
            if (content != .binding_declaration) continue;
            const binding = content.binding_declaration;
            if (std.mem.indexOfScalar(global_sg.GlobalBindingId, retained.items, binding) != null) continue;
            const name = self.relocation.graph.text(self.relocation.graph.binding(binding).name);
            for (retained.items) |previous| if (std.mem.eql(u8, self.relocation.graph.text(self.relocation.graph.binding(previous).name), name)) return error.DuplicateSessionBinding;
            if (self.resolvers.core.session_namespace) |namespace| for (namespace.declarations.items) |declaration| {
                if (std.mem.eql(u8, self.relocation.graph.text(self.relocation.graph.declaration(declaration).name), name)) return error.DuplicateSessionDeclaration;
            };
            try retained.append(self.allocator, binding);
        }
        const namespace = try self.resolvers.core.sessionNamespace();
        for (self.relocation.graph.block_assumptions.items) |evidence| {
            if (evidence.block != body) continue;
            for (self.relocation.graph.binding_refs.items[evidence.bindings.start..][0..evidence.bindings.len]) |binding| {
                if (std.mem.indexOfScalar(global_sg.GlobalBindingId, namespace.assumptions.items, binding) == null)
                    try namespace.assumptions.append(self.allocator, binding);
            }
        }
    }

    pub fn prepareExitScope(self: *Session, function: global_sg.GlobalFunctionId, bindings: []const global_sg.GlobalBindingId) !void {
        if (self.phase != .ready and self.phase != .quiescent) return error.InvalidSemanticSessionState;
        if (@intFromEnum(function) >= self.relocation.graph.functions.items.len or self.resolution.finalized_functions.contains(function))
            return error.InvalidSafetyContinuation;
        const target = self.relocation.graph.function(function);
        const body = target.body orelse return error.InvalidSafetyContinuation;
        if (target.input.len != 0 or target.output.len != 0 or self.relocation.graph.blocks.items[@intFromEnum(body)].nodes.len != 0)
            return error.InvalidSafetyContinuation;
        const nodes = try self.resolvers.ownership.selectedSessionCleanup(self.allocator, bindings);
        defer self.allocator.free(nodes);
        const start = std.math.cast(u32, self.relocation.graph.node_refs.items.len) orelse return error.SemanticGraphTooLarge;
        const count = std.math.cast(u32, nodes.len) orelse return error.SemanticGraphTooLarge;
        _ = std.math.add(u32, start, count) catch return error.SemanticGraphTooLarge;
        try self.relocation.graph.node_refs.appendSlice(self.allocator, nodes);
        self.relocation.graph.blocks.items[@intFromEnum(body)].nodes = .{ .start = start, .len = count };
        try self.prepareContinuationScope(function);
    }

    pub fn includeExecutionRoot(self: *Session, function: global_sg.GlobalFunctionId) !void {
        if (self.phase != .ready and self.phase != .quiescent) return error.InvalidSemanticSessionState;
        if (@intFromEnum(function) >= self.relocation.graph.functions.items.len) return error.InvalidSafetyContinuation;
        if (self.reachable) |*set| _ = try set.include(function);
        self.phase = .ready;
    }

    /// Request a closed module condition through the ordinary staged scheduler.
    /// Null means semantic dependencies remain pending; callers can append the
    /// required modules before retrying. No runtime/session value is captured.
    pub fn evaluateModuleCondition(self: *Session, module_index: usize, expression: @import("../module/parameterized/ir.zig").ParameterizedNodeId) !?bool {
        if (self.phase != .ready and self.phase != .quiescent) return error.InvalidSemanticSessionState;
        if (self.options.diagnostics == null) return error.MissingCompileTimeDiagnostics;
        if (module_index >= self.modules.len or @intFromEnum(expression) >= self.modules[module_index].semantic.parameterized_storage.ir.nodes.items.len)
            return error.InvalidModuleCondition;
        const Scheduler = @import("comptime_execution.zig").Scheduler;
        const bindings = @import("generics.zig").Resolver.Bindings{ .types = &.{}, .ints = &.{} };
        return Scheduler.boolean(&self.resolvers.staged_execution, module_index, expression, &bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => blk: {
                try self.advance();
                break :blk Scheduler.boolean(&self.resolvers.staged_execution, module_index, expression, &bindings) catch |retry| switch (retry) {
                    error.ComptimeExecutionPending => null,
                    else => return retry,
                };
            },
            else => return err,
        };
    }

    pub fn advance(self: *Session) !void {
        if (self.phase != .ready and self.phase != .quiescent) return error.InvalidSemanticSessionState;
        errdefer self.phase = .failed;
        const start = profileTimestamp(self.options.profile_io);
        if (self.phase == .ready) self.profile_preloop = start;
        try advanceResolution(&self.options, &self.resolvers, &self.resolution, self.reachableSet());
        self.profile_postloop = profileTimestamp(self.options.profile_io);
        self.fixed_point_ns += self.profile_postloop - start;
        self.phase = .quiescent;
    }

    pub fn finish(self: *Session) !Result {
        if (self.phase != .quiescent) return error.InvalidSemanticSessionState;
        errdefer self.phase = .failed;
        const allocator = self.allocator;
        const modules = self.modules;
        const options = self.options;
        const relocation = &self.relocation;
        const resolvers = &self.resolvers;
        const resolution_state = &self.resolution;
        const total = resolution_state.resolved.items.len;
        const resolved = resolution_state.resolved.items;
        const worklists = &resolution_state.worklists;
        const pending_resolution_stats = &resolution_state.pending_stats;
        const progress = &resolution_state.progress;
        const reachable = self.reachableSet();
        const setup_stages = self.setup_stages;
        const profile_start = self.profile_start;
        const profile_relocated = self.profile_relocated;
        const profile_preloop = self.profile_preloop;
        const profile_postloop = self.profile_postloop;
        const core = &resolvers.core;
        const expressions = &resolvers.expressions;
        const control = &resolvers.control;
        const generics = &resolvers.generics;
        const generic_functions = &resolvers.generic_functions;
        const contracts = &resolvers.contracts;
        const errors = &resolvers.errors;
        const dispatch = &resolvers.dispatch;
        const ownership = &resolvers.ownership;
        const staged_execution = &resolvers.staged_execution;
        try contracts.validateGenericFunctionInstances();
        control.annotateChoiceTests();

        if (reachable) |set| try retireDormantBindingResolution(&relocation.graph, set, try core.builtin(.Any));

        if (control.for_each_failure) |failure| {
            if (options.diagnostics) |diagnostics| {
                var actual_name = std.array_list.Managed(u8).init(allocator);
                defer actual_name.deinit();
                try appendTypeName(&actual_name, &relocation.graph, failure.actual);
                try diagnostics.add(
                    diagnosticLocation(&relocation.graph, diagnostics, failure.source),
                    .semantic,
                    "for expects a type implementing contract '{s}', got '{s}'",
                    .{ failure.contract_name, actual_name.items },
                );
                return error.Reported;
            }
            return error.InvalidForEach;
        }

        if (contracts.virtual_signature_failure) |failure| {
            if (options.diagnostics) |diagnostics| {
                const location = diagnosticLocation(&relocation.graph, diagnostics, failure.source);
                if (failure.static_contract) {
                    try diagnostics.add(location, .semantic, "invalid safety contract for '{s}': {s}", .{ failure.method_name, failure.reason });
                } else {
                    try diagnostics.add(location, .semantic, "cannot use '{s}' for virtual dispatch: {s}", .{ failure.method_name, failure.reason });
                }
                return error.Reported;
            }
            return error.InvalidVirtualSignature;
        }

        if (try diagnoseArrayAssignments(allocator, &relocation.graph, reachable, options.diagnostics))
            return error.Reported;

        if (options.diagnostics) |diagnostics| {
            if (try diagnoseUnresolvedPropagatedReach(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnosePrivateFields(&relocation.graph, modules, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnoseContractRuntimeBindings(&relocation.graph, contracts, diagnostics))
                return error.Reported;
            if (try diagnoseMissingArrayTypeContext(&relocation.graph, diagnostics))
                return error.Reported;
        }

        const remaining = worklists.remaining(reachable);
        var resolved_count: usize = 0;
        for (resolved) |done| if (done) {
            resolved_count += 1;
        };
        if (remaining != 0) {
            if (options.diagnostics) |diagnostics| {
                if (try diagnoseUnresolvedAssignments(&relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedArithmetic(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedDereference(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedQualifiedNames(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics, false))
                    return error.Reported;
                if (try diagnoseUnresolvedIndex(&relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedCopy(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                    return error.Reported;
                // A denied copy may already be represented in the graph so Safety
                // can prefer a preceding move error. If another operation remains
                // unresolved, report that definite copy failure before unrelated
                // call-resolution diagnostics prevent Safety from running.
                if (ownership.denied_copy) |denied| {
                    var type_name = std.array_list.Managed(u8).init(allocator);
                    defer type_name.deinit();
                    try appendTypeName(&type_name, &relocation.graph, denied.ty);
                    try diagnostics.add(
                        diagnosticLocation(&relocation.graph, diagnostics, denied.source),
                        .semantic,
                        "type '{s}' cannot be copied implicitly; use '~value' to transfer ownership",
                        .{type_name.items},
                    );
                    return error.Reported;
                }
                if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, generic_functions, contracts, diagnostics))
                    return error.Reported;
                if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics, true))
                    return error.Reported;
            }
            dumpUnresolved(modules, resolved, reachable, relocation.offsets.items);
            return error.UnsupportedGlobalSemantic;
        }
        if (staged_execution.diagnosePending()) {
            try reportComptimeExpressionFailure(&relocation.graph, options.diagnostics, generics);
            return error.UnresolvedCompileTimeExecution;
        }
        if (relocation.graph.hasUnresolvedTypes()) {
            if (options.diagnostics) |diagnostics|
                if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
                    return error.Reported;
            std.debug.print("global sema unresolved global type slots remain\n", .{});
            return error.UnsupportedGlobalSemantic;
        }
        if (relocation.graph.hasUnresolvedBindingTypes()) {
            if (options.diagnostics) |diagnostics|
                if (try diagnoseUnresolvedBindingTypes(&relocation.graph, diagnostics))
                    return error.Reported;
            std.debug.print("global sema unresolved binding types remain\n", .{});
            return error.UnsupportedGlobalSemantic;
        }

        if (try diagnoseInvalidMatchPayloadCopies(
            allocator,
            &relocation.graph,
            ownership,
            reachable,
            options.diagnostics,
        ))
            return if (options.diagnostics != null) error.Reported else error.InvalidImplicitCopy;

        if (try diagnoseInvalidNumericAssignments(allocator, &relocation.graph, reachable, options.diagnostics))
            return if (options.diagnostics != null) error.Reported else error.InvalidNumericAssignment;

        if (try diagnoseInvalidComparisons(allocator, core, reachable, options.diagnostics))
            return if (options.diagnostics != null) error.Reported else error.InvalidComparison;

        if (try diagnoseInvalidPointerOperations(allocator, &relocation.graph, reachable, options.diagnostics))
            return if (options.diagnostics != null) error.Reported else error.InvalidPointerOperation;

        if (options.diagnostics) |diagnostics|
            if (try contracts.findGenericTypeConstraintFailure()) |failure| {
                var actual_name = std.array_list.Managed(u8).init(allocator);
                defer actual_name.deinit();
                try appendTypeName(&actual_name, &relocation.graph, failure.actual);
                try diagnostics.add(
                    diagnosticLocation(&relocation.graph, diagnostics, failure.source),
                    .semantic,
                    "type '{s}' does not implement contract '{s}' required by generic type parameter '.{s}' of '{s}'",
                    .{
                        actual_name.items,
                        relocation.graph.text(relocation.graph.declaration(failure.contract_decl).name),
                        failure.parameter_name,
                        relocation.graph.text(relocation.graph.declaration(failure.generic_decl).name),
                    },
                );
                return error.Reported;
            };

        try contracts.closeVirtualMethodRegistries();

        // Construction-only resolution metadata must disappear before the graph is
        // exposed to Safety, Codegen or editor consumers.
        try relocation.graph.finishTypeResolution(allocator);
        contracts.validateParticipantConformances() catch |err| {
            try reportComptimeExpressionFailure(&relocation.graph, options.diagnostics, generics);
            try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
            return err;
        };
        try reportParticipantConformanceFailure(allocator, &relocation.graph, options.diagnostics, contracts.participant_conformance_failure);
        try relocation.graph.finishBindingTypeResolution(allocator);

        var generic_bodies_built: u64 = 0;
        var generic_bodies_unreachable: u64 = 0;
        if (options.profile_io != null) {
            for (relocation.graph.functions.items) |function| {
                if (function.flags.is_generic_instantiation and function.body != null)
                    generic_bodies_built += 1;
            }
        }
        if (reachable) |set| {
            for (relocation.graph.contract_safety_conformances.items) |*proof| {
                const conformance = relocation.graph.contract_conformances.items[proof.selection.conformance];
                const cleanup = set.cleanup_functions.contains(proof.method) and
                    @import("standard_contracts.zig").standardDeclaration(&relocation.graph, "Deinit") == conformance.declaration;
                proof.safety_required = cleanup or set.operations.contains(proof.selection);
            }
            for (relocation.graph.virtualizes.items, 0..) |*value, raw| {
                value.safety_required = set.virtualizes.contains(@enumFromInt(raw));
            }
            for (relocation.graph.functions.items, 0..) |*function, raw| {
                const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
                if (options.profile_io != null and function.flags.is_generic_instantiation and function.body != null) {
                    if (!set.contains(id)) generic_bodies_unreachable += 1;
                }
                if (!set.contains(id)) function.body = null;
            }
        }

        var stats = Stats{
            .core = core.stats,
            .expressions = expressions.stats,
            .control = control.stats,
            .generics = generics.stats,
            .generic_functions = generic_functions.stats,
            .generic_selection = generic_functions.selection_profile,
            .contracts = contracts.stats,
            .errors = errors.stats,
            .ownership = ownership.stats,
            .pending_call_stages = dispatch.pending_call_stages,
            .pending_total = @intCast(total),
            .pending_resolved = @intCast(resolved_count),
            .pending_attempts = progress.pending_attempts,
            .pending_by_owner = pending_resolution_stats.owners,
            .pending_by_operation = pending_resolution_stats.operations,
            .remaining = 0,
            .rounds = @intCast(progress.profile_rounds),
            .cleanup_attempts = @intCast(progress.profile_finalize_count),
            .destructor_lookups = @intCast(ownership.profile_destructor_calls),
            .generic_instantiation_calls = generic_functions.profile_instantiate_calls,
            .generic_existing_instances = generic_functions.profile_instantiate_existing,
            .generic_bodies_built = generic_bodies_built,
            .generic_bodies_unreachable = generic_bodies_unreachable,
            .generic_reachability_tracked = reachable != null,
        };

        const profile_preverify = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        try global_verify.verifyGlobal(&relocation.graph);
        const profile_end = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        stats.remaining = 0;
        var setup_stage_times: [setup_stage_count]u64 = undefined;
        for (setup_stages, &setup_stage_times) |elapsed, *time| time.* = @intCast(elapsed);
        if (options.profile_io != null) stats.timings = .{
            .relocation_ns = @intCast(profile_relocated - profile_start),
            .setup_ns = @intCast(profile_preloop - profile_relocated),
            .setup_stages_ns = setup_stage_times,
            .fixed_point_ns = @intCast(self.fixed_point_ns),
            .pending_ns = @intCast(progress.profile_pending_ns),
            .string_literal_types_ns = @intCast(progress.profile_string_literal_types_ns),
            .binding_types_ns = @intCast(progress.profile_binding_types_ns),
            .assignment_values_ns = @intCast(progress.profile_assignment_values_ns),
            .dereferences_ns = @intCast(progress.profile_dereferences_ns),
            .addresses_ns = @intCast(progress.profile_addresses_ns),
            .known_generic_types_ns = @intCast(progress.profile_known_generic_types_ns),
            .field_access_types_ns = @intCast(progress.profile_field_access_types_ns),
            .sugar_types_ns = @intCast(progress.profile_sugar_types_ns),
            .error_inference_ns = @intCast(progress.profile_errors_ns),
            .error_summary_ns = @intCast(progress.profile_error_summary_ns),
            .error_refresh_ns = @intCast(progress.profile_error_refresh_ns),
            .cleanup_ns = @intCast(progress.profile_finalize_ns),
            .implicit_destructor_ns = @intCast(ownership.profile_destructor_ns),
            .source_generic_selection_ns = @intCast(generic_functions.profile_source_selection_ns),
            .source_generic_completion_ns = @intCast(generic_functions.profile_source_completion_ns),
            .generic_instantiation_ns = @intCast(generic_functions.profile_instantiate_ns),
            .generic_instantiation_lookup_ns = @intCast(generic_functions.profile_instantiate_lookup_ns),
            .generic_instantiation_body_ns = @intCast(generic_functions.profile_instantiate_body_ns),
            .generic_instance_context_init_ns = @intCast(generic_functions.profile_instance_context_init_ns),
            .generic_constraints_ns = @intCast(generic_functions.profile_constraints_ns),
            .post_resolution_ns = @intCast(profile_preverify - profile_postloop),
            .verify_ns = @intCast(profile_end - profile_preverify),
        };
        self.phase = .published;
        return .{ .graph = relocation.takeGraph(allocator), .stats = stats };
    }

    pub fn deinit(self: *Session) void {
        if (self.reachable) |*set| set.deinit();
        self.resolution.deinit(self.allocator);
        if (self.resolvers_initialized) self.resolvers.deinit();
        self.relocation.deinit(self.allocator);
        self.* = undefined;
    }
};

const ResolutionProgress = struct {
    pending_attempts: u64 = 0,
    profile_rounds: usize = 0,
    profile_pending_ns: i96 = 0,
    profile_string_literal_types_ns: i96 = 0,
    profile_binding_types_ns: i96 = 0,
    profile_assignment_values_ns: i96 = 0,
    profile_dereferences_ns: i96 = 0,
    profile_addresses_ns: i96 = 0,
    profile_known_generic_types_ns: i96 = 0,
    profile_field_access_types_ns: i96 = 0,
    profile_sugar_types_ns: i96 = 0,
    profile_errors_ns: i96 = 0,
    profile_error_summary_ns: i96 = 0,
    profile_error_refresh_ns: i96 = 0,
    profile_finalize_ns: i96 = 0,
    profile_finalize_count: usize = 0,
};

// Advance to quiescence without sealing construction metadata or diagnosing
// unresolved work. A coordinator can retain this state and resume after adding
// semantic inputs; only the final publication path seals the graph.
fn advanceResolution(
    options: *const Options,
    resolvers: *@import("resolver_context.zig").Context,
    state: *ResolutionState,
    reachable: ?*reachability_mod.FunctionSet,
) !void {
    const progress = &state.progress;
    const pending_resolution_stats = &state.pending_stats;
    const graph = resolvers.core.graph;
    const allocator = resolvers.core.allocator;
    const modules = resolvers.core.modules;
    const offsets = resolvers.core.offsets;
    const core = &resolvers.core;
    const expressions = &resolvers.expressions;
    const control = &resolvers.control;
    const generics = &resolvers.generics;
    const generic_functions = &resolvers.generic_functions;
    const contracts = &resolvers.contracts;
    const errors = &resolvers.errors;
    const dispatch = &resolvers.dispatch;
    const ownership = &resolvers.ownership;
    const staged_execution = &resolvers.staged_execution;
    const resolved = state.resolved.items;
    const invalid = state.invalid.items;
    const worklists = &state.worklists;
    // GlobalSema is staged by semantic domain. Ownership finalization can add
    // cleanup calls to functions absent from the source call graph. Each newly
    // reachable body gets another resolution pass before its cleanup is built.
    const finalized_functions = &state.finalized_functions;
    var changed = true;
    while (true) {
        while (changed) {
            staged_execution.stable_type_count = graph.types.items.len;
            progress.profile_rounds += 1;
            changed = false;
            // Published operation signatures do not make their bodies roots.
            // Complete selected bodies before resolving their pending uses.
            if (generic_functions.materializePublishedBodies(reachable) catch |err| {
                try reportComptimeExpressionFailure(graph, options.diagnostics, generics);
                try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
                return err;
            }) changed = true;
            if (reachable) |set| {
                if (try reachability_mod.expand(allocator, graph, set)) changed = true;
            }
            const pending_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            for (pending_phases) |phase| {
                if (resolvePendingPhase(
                    core,
                    expressions,
                    dispatch,
                    control,
                    generics,
                    contracts,
                    errors,
                    ownership,
                    modules,
                    offsets,
                    resolved,
                    invalid,
                    worklists.forPhase(phase),
                    reachable,
                    &progress.pending_attempts,
                    if (options.profile_io != null) pending_resolution_stats else null,
                    options.profile_io,
                    options.diagnostics,
                ) catch |err| {
                    try reportComptimeExpressionFailure(graph, options.diagnostics, generics);
                    try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
                    return err;
                }) changed = true;
            }
            try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
            if (options.profile_io) |io| progress.profile_pending_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - pending_start;

            var sweep_start = profileTimestamp(options.profile_io);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeTextLiteralTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_string_literal_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try core.materializeBindingTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_binding_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeAssignmentValues()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_assignment_values_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeDereferences()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_dereferences_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try core.materializeAddresses()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_addresses_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (generics.materializeKnownTypes() catch |err| {
                try reportComptimeExpressionFailure(graph, options.diagnostics, generics);
                try reportGenericArgumentFailure(graph, options.diagnostics, generics);
                try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
                return err;
            }) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_known_generic_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try contracts.materializeFieldAccessTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_field_access_types_ns);
            // Generic instantiation can intern nullable or inferred Errable
            // types during this pass. Their materialization must schedule a
            // further pass so pending uses can observe the final choice shape.
            sweep_start = profileTimestamp(options.profile_io);
            if (try control.materializeSugarTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &progress.profile_sugar_types_ns);
            const errors_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            if (try errors.inferFunctionErrorReasons(reachable)) changed = true;
            profileAccumulate(options.profile_io, errors_start, &progress.profile_error_summary_ns);
            const refresh_start = profileTimestamp(options.profile_io);
            if (errors.refreshPropagationResults()) changed = true;
            profileAccumulate(options.profile_io, refresh_start, &progress.profile_error_refresh_ns);
            if (options.profile_io) |io| progress.profile_errors_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - errors_start;
            if (try completePropagatedReachCalls(core, modules, offsets)) changed = true;
            // Evidence selected by newly specialized bodies belongs to this
            // fixed point. Its operation bodies must become reachable and have
            // their cleanup finalized before construction metadata is retired.
            const evidence_functions = graph.functions.items.len;
            const evidence_types = graph.types.items.len;
            const evidence_conformances = graph.contract_conformances.items.len;
            contracts.validateParticipantConformances() catch |err| {
                try reportComptimeExpressionFailure(graph, options.diagnostics, generics);
                try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
                return err;
            };
            try reportParticipantConformanceFailure(allocator, graph, options.diagnostics, contracts.participant_conformance_failure);
            if (evidence_functions != graph.functions.items.len or
                evidence_types != graph.types.items.len or
                evidence_conformances != graph.contract_conformances.items.len) changed = true;
            if (try staged_execution.materialize()) changed = true;
            if (reachable) |set| {
                if (try reachability_mod.expand(allocator, graph, set)) changed = true;
            }
        }
        var finalized_any = false;
        const finalization_count = graph.functions.items.len;
        var raw: usize = 0;
        while (raw < finalization_count) : (raw += 1) {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (finalized_functions.contains(id)) continue;
            if (reachable) |set| {
                if (!set.contains(id)) continue;
            }
            if (graph.functions.items[raw].body == null) continue;
            const finalize_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const did_finalize = try ownership.finalizeFunctionBody(id);
            if (options.profile_io) |io| progress.profile_finalize_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - finalize_start;
            progress.profile_finalize_count += 1;
            if (!did_finalize) continue;
            try finalized_functions.put(id, {});
            finalized_any = true;
        }
        const reached_cleanup = if (reachable) |set|
            try reachability_mod.expand(allocator, graph, set)
        else
            false;
        var pending_bodies = std.AutoHashMap(global_sg.GlobalFunctionId, void).init(allocator);
        defer pending_bodies.deinit();
        if (staged_execution.requests.items.len != 0) {
            for (pending_phases) |phase| for (worklists.forPhase(phase).items) |item| {
                if (item.owner_function) |owner| try pending_bodies.put(owner, {});
            };
        }
        const evaluated = if (options.diagnostics) |diagnostics|
            staged_execution.evaluateReady(contracts, diagnostics, finalized_functions, &pending_bodies) catch |err| {
                try reportComptimeExpressionFailure(graph, options.diagnostics, generics);
                return err;
            }
        else
            false;
        if (evaluated) try contracts.resolveAssociatedTypes();
        if (!finalized_any and !reached_cleanup and !evaluated) break;
        changed = true;
    }
}

fn diagnoseInvalidMatchPayloadCopies(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    ownership: *ownership_mod.Resolver,
    reachable: ?*const reachability_mod.FunctionSet,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    for (graph.switch_cases.items) |case| {
        if (case.payload_mode != .value) continue;
        const binding_id = case.payload_binding orelse continue;
        if (reachable) |set| if (!set.containsBinding(binding_id)) continue;
        const binding = graph.binding(binding_id);
        if (std.mem.eql(u8, graph.text(binding.name), "_")) continue;
        if (graph.isTypeUnresolved(binding.ty) or ownership.canImplicitlyCopy(binding.ty)) continue;
        if (diagnostics) |sink| {
            var type_name = std.array_list.Managed(u8).init(allocator);
            defer type_name.deinit();
            try appendTypeName(&type_name, graph, binding.ty);
            try sink.add(
                diagnosticLocation(graph, sink, binding.source),
                .semantic,
                "type '{s}' cannot be copied implicitly; use '~value' to transfer ownership",
                .{type_name.items},
            );
        }
        return true;
    }
    return false;
}

fn diagnoseUnresolvedDereference(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const dereference = switch (operation) {
                .resolve_dereference => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value|
                    globalizer.globalFunction(offsets[module_index], value)
                else
                    null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            const operand = globalizer.globalNode(offsets[module_index], dereference.pointer);
            const ty = graph.node(operand).ty orelse continue;
            if (graph.isTypeUnresolved(ty)) continue;
            if (graph.semanticType(ty) == .pointer) continue;
            var type_name = std.array_list.Managed(u8).init(allocator);
            defer type_name.deinit();
            try appendTypeName(&type_name, graph, ty);
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, graph.node(operand).source),
                .semantic,
                "type '{s}' is not dereferenceable; expected '&T' or '$&T'",
                .{type_name.items},
            );
            return true;
        }
    }
    return false;
}

fn diagnoseUnresolvedArithmetic(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const binary = switch (operation) {
                .resolve_binary => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value|
                    globalizer.globalFunction(offsets[module_index], value)
                else
                    null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            const left = globalizer.globalNode(offsets[module_index], binary.left);
            const right = globalizer.globalNode(offsets[module_index], binary.right);
            const left_ty = graph.node(left).ty orelse continue;
            const right_ty = graph.node(right).ty orelse continue;
            if (graph.isTypeUnresolved(left_ty) or graph.isTypeUnresolved(right_ty)) continue;
            const left_representation_pointer = graph.semanticType(left_ty) == .pointer and switch (graph.semanticType(graph.semanticType(left_ty).pointer.child)) {
                .builtin, .array, .pointer, .nullable => true,
                else => false,
            };
            const right_representation_pointer = graph.semanticType(right_ty) == .pointer and switch (graph.semanticType(graph.semanticType(right_ty).pointer.child)) {
                .builtin, .array, .pointer, .nullable => true,
                else => false,
            };
            // References to nominal participants are legitimate contract
            // operands. Report their concrete types and dimensions when no
            // conforming operation exists, rather than calling them addresses.
            if (left_representation_pointer or right_representation_pointer) {
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, graph.node(left).source),
                    .semantic,
                    "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
                    .{},
                );
            } else {
                var left_name = std.array_list.Managed(u8).init(allocator);
                defer left_name.deinit();
                var right_name = std.array_list.Managed(u8).init(allocator);
                defer right_name.deinit();
                try appendTypeName(&left_name, graph, left_ty);
                try appendTypeName(&right_name, graph, right_ty);
                const operator: []const u8 = switch (binary.operator) {
                    .addition => "+",
                    .subtraction => "-",
                    .multiplication => "*",
                    .division => "/",
                    .modulo => "%",
                };
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], binary.source)),
                    .semantic,
                    "operator '{s}' is not defined for '{s}' and '{s}'",
                    .{ operator, left_name.items, right_name.items },
                );
            }
            return true;
        }
    }
    return false;
}

const ArrayMismatch = struct {
    value: global_sg.GlobalNodeId,
    expected: global_sg.GlobalTypeId,
    length: ?usize = null,
};

fn arrayMismatch(graph: *const global_sg.GlobalSemanticGraph, value: global_sg.GlobalNodeId, expected: global_sg.GlobalTypeId) ?ArrayMismatch {
    if (@intFromEnum(expected) >= graph.types.items.len or graph.isTypeUnresolved(expected)) return null;
    const node = graph.node(value);
    if (global_types.arrayElement(graph, expected)) |element| {
        const elements = switch (node.content) {
            .list_literal => |literal| literal.elements,
            .array_literal => |literal| literal.elements,
            else => null,
        };
        if (elements) |items| {
            if (items.len != global_types.arrayLength(graph, expected).?)
                return .{ .value = value, .expected = expected, .length = items.len };
            for (graph.node_refs.items[items.start..][0..items.len]) |child|
                if (arrayMismatch(graph, child, element)) |mismatch| return mismatch;
        } else if (node.ty) |actual| {
            if (!graph.isTypeUnresolved(actual) and global_types.arrayElement(graph, actual) != null and !global_types.equal(graph, actual, expected))
                return .{ .value = value, .expected = expected };
        }
    } else if (graph.semanticType(expected) == .pointer) {
        const pointer = graph.semanticType(expected).pointer;
        if (global_types.arrayElement(graph, pointer.child) != null) {
            const actual = node.ty orelse return null;
            if (graph.isTypeUnresolved(actual)) return null;
            if (graph.semanticType(actual) == .pointer and !global_types.equal(graph, graph.semanticType(actual).pointer.child, pointer.child))
                return .{ .value = value, .expected = expected };
        }
    }
    if (node.content == .struct_value_literal) {
        const fields = global_types.fields(graph, expected) orelse return null;
        for (graph.value_fields.items[node.content.struct_value_literal.fields.start..][0..node.content.struct_value_literal.fields.len], 0..) |field, index| {
            const target = if (graph.text(field.name).len != 0)
                if (global_types.findField(graph, expected, graph.text(field.name))) |hit| hit.field.ty else continue
            else if (index < fields.len)
                graph.fields.items[fields.start + index].ty
            else
                continue;
            if (arrayMismatch(graph, field.value, target)) |mismatch| return mismatch;
        }
    }
    return null;
}

// Contextual types are destinations, not proof that aggregate elements or
// referenced storage have that shape. Validate before safety and codegen,
// including when a rejected literal has no inferred type at all.
fn diagnoseArrayAssignments(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    reachable: ?*const reachability_mod.FunctionSet,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    for (graph.nodes.items, 0..) |node, raw| {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable) |set| if (!set.containsNode(id)) continue;
        const value, const expected = switch (node.content) {
            .binding_declaration => |binding| .{ graph.binding(binding).initialization orelse continue, graph.binding(binding).ty },
            .assignment => |assignment| .{ assignment.value, graph.binding(assignment.binding).ty },
            .array_store => |store| .{ store.value, store.element_type },
            .pointer_assignment => |assignment| blk: {
                const ty = graph.node(assignment.pointer).ty orelse continue;
                if (graph.isTypeUnresolved(ty) or graph.semanticType(ty) != .pointer) continue;
                break :blk .{ assignment.value, graph.semanticType(ty).pointer.child };
            },
            .struct_value_literal, .array_literal => .{ id, node.ty orelse continue },
            else => continue,
        };
        const mismatch = arrayMismatch(graph, value, expected) orelse continue;
        if (diagnostics) |sink| {
            const location = diagnosticLocation(graph, sink, graph.node(mismatch.value).source);
            if (mismatch.length) |length| {
                try sink.add(location, .semantic, "array initializer has {d} elements; expected {d}", .{ length, global_types.arrayLength(graph, mismatch.expected).? });
            } else {
                var actual_name = std.array_list.Managed(u8).init(allocator);
                defer actual_name.deinit();
                var expected_name = std.array_list.Managed(u8).init(allocator);
                defer expected_name.deinit();
                try appendTypeName(&actual_name, graph, graph.node(mismatch.value).ty.?);
                try appendTypeName(&expected_name, graph, mismatch.expected);
                try sink.add(location, .semantic, "array value has type '{s}'; expected '{s}'", .{ actual_name.items, expected_name.items });
            }
        }
        return true;
    }
    return false;
}

// Literal contextualization has already finished. Typed numeric values must
// agree with their destination; changing their node type would conceal a
// conversion that codegen has no corresponding instruction to perform.
fn diagnoseInvalidNumericAssignments(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    reachable: ?*const reachability_mod.FunctionSet,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    for (graph.nodes.items, 0..) |node, raw| {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable) |set| if (!set.containsNode(id)) continue;
        const value, const expected = switch (node.content) {
            .binding_declaration => |binding| .{
                graph.binding(binding).initialization orelse continue,
                graph.binding(binding).ty,
            },
            .struct_value_literal, .array_literal => findAggregateNumericMismatch(graph, id) orelse continue,
            .assignment => |assignment| .{ assignment.value, graph.binding(assignment.binding).ty },
            .array_store => |store| .{ store.value, store.element_type },
            .pointer_assignment => |assignment| blk: {
                const pointer_ty = graph.node(assignment.pointer).ty orelse continue;
                const pointer = switch (graph.semanticType(pointer_ty)) {
                    .pointer => |pointer| pointer,
                    else => continue,
                };
                break :blk .{ assignment.value, pointer.child };
            },
            else => continue,
        };
        // Literal range failures have a more precise Safety diagnostics_mod. Their
        // default type is not evidence of an implicit variable conversion.
        if (graph.node(value).content == .int_literal and switch (graph.semanticType(expected)) {
            .builtin => |builtin| switch (builtin) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
                else => false,
            },
            else => false,
        }) continue;
        const actual = graph.node(value).ty orelse continue;
        if (isNumericType(graph, expected)) {
            if (global_types.findVariant(graph, actual, "ok")) |ok| {
                if (ok.variant.payload_type) |payload| {
                    if (global_types.equal(graph, payload, expected) and global_types.findVariant(graph, actual, "error") != null) {
                        if (diagnostics) |sink| try sink.add(
                            diagnosticLocation(graph, sink, graph.node(value).source),
                            .semantic,
                            "cannot assign a fallible numeric result directly; handle its error or propagate it with '!'",
                            .{},
                        );
                        return true;
                    }
                }
            }
        }
        const unicode_mismatch = isUnicodeScalarType(graph, actual) or isUnicodeScalarType(graph, expected);
        if (!unicode_mismatch and (!isNumericType(graph, actual) or !isNumericType(graph, expected))) continue;
        if (global_types.equal(graph, actual, expected)) continue;
        if (diagnostics) |sink| {
            var actual_name = std.array_list.Managed(u8).init(allocator);
            defer actual_name.deinit();
            var expected_name = std.array_list.Managed(u8).init(allocator);
            defer expected_name.deinit();
            try appendTypeName(&actual_name, graph, actual);
            try appendTypeName(&expected_name, graph, expected);
            if (unicode_mismatch) {
                try sink.add(
                    diagnosticLocation(graph, sink, node.source),
                    .semantic,
                    "cannot assign value of type '{s}' to destination of type '{s}'; Unicode scalars and bytes require explicit conversion",
                    .{ actual_name.items, expected_name.items },
                );
            } else {
                try sink.add(
                    diagnosticLocation(graph, sink, node.source),
                    .semantic,
                    "cannot assign numeric value of type '{s}' to destination of type '{s}'; implicit numeric conversion is not supported",
                    .{ actual_name.items, expected_name.items },
                );
            }
        }
        return true;
    }
    return false;
}

// Aggregate types alone do not prove that each child has the representation
// expected by LLVM. Check typed numeric children after contextualization.
fn findAggregateNumericMismatch(graph: *const global_sg.GlobalSemanticGraph, id: global_sg.GlobalNodeId) ?struct { global_sg.GlobalNodeId, global_sg.GlobalTypeId } {
    const node = graph.node(id);
    const ty = node.ty orelse return null;
    switch (node.content) {
        .struct_value_literal => |literal| {
            const fields = global_types.fields(graph, ty) orelse return null;
            for (graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, offset| {
                var expected: ?global_sg.GlobalTypeId = null;
                if (graph.text(field.name).len != 0) {
                    for (graph.fields.items[fields.start..][0..fields.len]) |candidate| {
                        if (std.mem.eql(u8, graph.text(field.name), graph.text(candidate.name))) {
                            expected = candidate.ty;
                            break;
                        }
                    }
                } else if (offset < fields.len) expected = graph.fields.items[fields.start + offset].ty;
                if (expected) |target| if (numericChildMismatch(graph, field.value, target)) return .{ field.value, target };
            }
        },
        .array_literal => |literal| {
            for (graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child| {
                if (numericChildMismatch(graph, child, literal.element_type)) return .{ child, literal.element_type };
            }
        },
        else => {},
    }
    return null;
}

fn numericChildMismatch(graph: *const global_sg.GlobalSemanticGraph, child: global_sg.GlobalNodeId, expected: global_sg.GlobalTypeId) bool {
    const node = graph.node(child);
    const actual = node.ty orelse return false;
    if (isUnicodeScalarType(graph, actual) or isUnicodeScalarType(graph, expected))
        return !global_types.equal(graph, actual, expected);
    // Integer range errors retain the dedicated safety diagnostics_mod.
    if (node.content == .int_literal and !global_types.isBuiltin(graph, expected, .Float16) and
        !global_types.isBuiltin(graph, expected, .Float32) and !global_types.isBuiltin(graph, expected, .Float64)) return false;
    return isNumericType(graph, actual) and isNumericType(graph, expected) and !global_types.equal(graph, actual, expected);
}

fn isUnicodeScalarType(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) bool {
    const declaration = switch (graph.semanticType(ty)) {
        .declared => |id| id,
        else => return false,
    };
    const owner = graph.moduleForDeclaration(declaration) orelse return false;
    return graph.modules.items[@intFromEnum(owner)].is_bundled_core and
        std.mem.eql(u8, graph.text(graph.declaration(declaration).name), "UnicodeScalar");
}

fn isNumericType(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) bool {
    return switch (graph.semanticType(ty)) {
        .builtin => |builtin| switch (builtin) {
            .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64 => true,
            else => false,
        },
        else => false,
    };
}

fn diagnoseInvalidComparisons(
    allocator: std.mem.Allocator,
    core: *core_mod.Resolver,
    reachable: ?*const reachability_mod.FunctionSet,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    const graph = core.graph;
    for (graph.nodes.items, 0..) |node, raw| {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable) |set| if (!set.containsNode(id)) continue;
        const comparison = switch (node.content) {
            .comparison => |value| value,
            else => continue,
        };
        const left = graph.node(comparison.left);
        const right = graph.node(comparison.right);
        const left_ty = left.ty orelse continue;
        const right_ty = right.ty orelse continue;
        if (core.isDirectComparison(comparison.operator, left_ty, right_ty)) continue;
        const equality = comparison.operator == .equal or comparison.operator == .not_equal;
        // Choice tests are explicit tag comparisons, including nodes created
        // by is()/nullable tests. References already have scalar equality.
        if (equality and global_types.variants(graph, left_ty) != null and
            (global_types.variants(graph, right_ty) != null or right.content == .int_literal)) continue;
        if (equality and graph.semanticType(left_ty) == .pointer and
            graph.semanticType(right_ty) == .pointer and global_types.equal(graph, left_ty, right_ty)) continue;
        if (diagnostics) |sink| {
            var left_name = std.array_list.Managed(u8).init(allocator);
            defer left_name.deinit();
            var right_name = std.array_list.Managed(u8).init(allocator);
            defer right_name.deinit();
            try appendTypeName(&left_name, graph, left_ty);
            try appendTypeName(&right_name, graph, right_ty);
            const operator = switch (comparison.operator) {
                .equal => "==",
                .not_equal => "!=",
                .less_than => "<",
                .greater_than => ">",
                .less_than_or_equal => "<=",
                .greater_than_or_equal => ">=",
            };
            try sink.add(
                diagnosticLocation(graph, sink, node.source),
                .semantic,
                "no matching comparison operator '{s}' for '{s}' and '{s}'",
                .{ operator, left_name.items, right_name.items },
            );
        }
        return true;
    }
    return false;
}

fn diagnoseInvalidPointerOperations(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    reachable: ?*const reachability_mod.FunctionSet,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    for (graph.nodes.items, 0..) |node, raw| {
        const node_id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable) |set| if (!set.containsNode(node_id)) continue;
        switch (node.content) {
            .pointer_assignment => |assignment| {
                const pointer_ty = graph.node(assignment.pointer).ty orelse continue;
                const pointer = switch (graph.semanticType(pointer_ty)) {
                    .pointer => |value| value,
                    else => continue,
                };
                if (pointer.mutability != .read_only) {
                    const actual = graph.node(assignment.value).ty orelse continue;
                    const actual_pointer = switch (graph.semanticType(actual)) {
                        .pointer => |value| value,
                        else => continue,
                    };
                    const expected_pointer = switch (graph.semanticType(pointer.child)) {
                        .pointer => |value| value,
                        else => continue,
                    };
                    if (global_types.equal(graph, actual_pointer.child, expected_pointer.child) and
                        (expected_pointer.mutability == .read_only or actual_pointer.mutability == .read_write)) continue;
                    if (diagnostics) |sink| {
                        var actual_name = std.array_list.Managed(u8).init(allocator);
                        defer actual_name.deinit();
                        var expected_name = std.array_list.Managed(u8).init(allocator);
                        defer expected_name.deinit();
                        try appendTypeName(&actual_name, graph, actual);
                        try appendTypeName(&expected_name, graph, pointer.child);
                        try sink.add(
                            diagnosticLocation(graph, sink, graph.node(assignment.value).source),
                            .semantic,
                            "cannot assign reference of type '{s}' to destination of type '{s}'",
                            .{ actual_name.items, expected_name.items },
                        );
                    }
                    return true;
                }
                if (diagnostics) |sink| {
                    var name = std.array_list.Managed(u8).init(allocator);
                    defer name.deinit();
                    try appendTypeName(&name, graph, pointer_ty);
                    var source = node.source;
                    if (graph.node(assignment.pointer).content == .binding_use) {
                        const binding = graph.node(assignment.pointer).content.binding_use;
                        source.offset += @intCast(graph.text(graph.binding(binding).name).len);
                    }
                    try sink.add(
                        diagnosticLocation(graph, sink, source),
                        .semantic,
                        "cannot assign through pointer '{s}' because it is read-only; use '$&' when acquiring it",
                        .{name.items},
                    );
                }
                return true;
            },
            .array_index => |access| {
                if (try diagnoseConstantArrayIndex(graph, access.array_type, access.index, diagnostics)) return true;
                const index_ty = graph.node(access.index).ty orelse continue;
                if (global_types.isBuiltin(graph, index_ty, .UIntNative)) continue;
                // Integer literals retain their default type until a consumer gives
                // them context. Array indexing supplies UIntNative context, so a
                // non-negative literal is valid even if its node still says Int32.
                if (graph.node(access.index).content == .int_literal and
                    graph.node(access.index).content.int_literal >= 0) continue;
                if (diagnostics) |sink| {
                    var name = std.array_list.Managed(u8).init(allocator);
                    defer name.deinit();
                    try appendTypeName(&name, graph, index_ty);
                    try sink.add(
                        diagnosticLocation(graph, sink, graph.node(access.index).source),
                        .semantic,
                        "array index must be 'UIntNative', got '{s}'",
                        .{name.items},
                    );
                }
                return true;
            },
            .array_store => |store| {
                if (try diagnoseConstantArrayIndex(graph, store.array_type, store.index, diagnostics)) return true;
            },
            else => {},
        }
    }
    for (graph.bindings.items, 0..) |destination, raw| {
        const destination_id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable) |set| if (!set.containsBinding(destination_id)) continue;
        const initialization = destination.initialization orelse continue;
        const node = graph.node(initialization);
        const child = switch (node.content) {
            .address_of => |value| value,
            else => continue,
        };
        const pointer_ty = node.ty orelse continue;
        const pointer = switch (graph.semanticType(pointer_ty)) {
            .pointer => |value| value,
            else => continue,
        };
        if (pointer.mutability != .read_write) continue;
        const binding = switch (graph.node(child).content) {
            .binding_use => |value| value,
            else => continue,
        };
        const source = graph.binding(binding);
        if (source.mutability != .constant) continue;
        if (diagnostics) |sink|
            try sink.add(
                diagnosticLocation(graph, sink, graph.node(child).source),
                .semantic,
                "binding '{s}' is immutable; declare it with '::' or use '&{s}'",
                .{ graph.text(source.name), graph.text(source.name) },
            );
        return true;
    }
    return false;
}

fn constantArrayIndex(graph: *const global_sg.GlobalSemanticGraph, node_id: global_sg.GlobalNodeId, depth: u8) ?i128 {
    if (depth == 0) return null;
    return switch (graph.node(node_id).content) {
        .int_literal => |value| value,
        .binding_use => |binding_id| blk: {
            const binding = graph.binding(binding_id);
            if (binding.mutability != .constant) break :blk null;
            break :blk if (binding.initialization) |initializer| constantArrayIndex(graph, initializer, depth - 1) else null;
        },
        .move_value => |value| constantArrayIndex(graph, value, depth - 1),
        .explicit_cast => |cast| constantArrayIndex(graph, cast.value, depth - 1),
        else => null,
    };
}

fn diagnoseConstantArrayIndex(
    graph: *const global_sg.GlobalSemanticGraph,
    array_type: global_sg.GlobalTypeId,
    index: global_sg.GlobalNodeId,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    const raw = constantArrayIndex(graph, index, 8) orelse return false;
    const length = global_types.arrayLength(graph, array_type) orelse return false;
    if (raw >= 0 and @as(u64, @intCast(raw)) < length) return false;
    if (diagnostics) |sink| try sink.add(
        diagnosticLocation(graph, sink, graph.node(index).source),
        .semantic,
        "array index {d} is out of bounds for length {d}",
        .{ raw, length },
    );
    return true;
}

fn diagnoseUnresolvedPropagatedReach(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (modules, offsets) |*module, offset| {
        for (module.semantic.pending_operations.items) |operation| {
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const node = graph.node(globalizer.globalNode(offset, call.node));
            const resolved = switch (node.content) {
                .function_call => |value| value,
                else => continue,
            };
            const input = switch (graph.node(resolved.input).content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            const function = graph.functions.items[@intFromEnum(resolved.callee)];
            if (input.fields.len >= function.input.len) continue;
            const field = graph.fields.items[function.input.start + input.fields.len];
            const fallback = field.default_value orelse continue;
            const reach_id = switch (graph.node(fallback).content) {
                .reach_directive => |value| value,
                else => continue,
            };
            const reach = graph.reaches.items[@intFromEnum(reach_id)];
            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try message.print("cannot resolve reached argument '.{s}' with alternatives [", .{graph.text(field.name)});
            for (graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len], 0..) |alternative, index| {
                if (index != 0) try message.appendSlice(", ");
                for (graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len], 0..) |segment, segment_index| {
                    if (segment_index != 0) try message.append('.');
                    try message.appendSlice(graph.text(segment));
                }
            }
            try message.appendSlice("] expected as '");
            try appendTypeName(&message, graph, field.ty);
            try message.append('\'');
            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            const source = globalSource(offset, reference.source);
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, .{ .file_index = source.file_index, .offset = source.offset + @as(u32, @intCast(module.text(reference.name).len)) }),
                .semantic,
                "{s}",
                .{message.items},
            );
            return true;
        }
    }
    return false;
}

fn completePropagatedReachCalls(
    core: *core_mod.Resolver,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
) !bool {
    // A callee can acquire reached inputs after its callers have resolved.
    // Rebuild those call inputs until their shape follows the final signature.
    var changed = try core.completeTrackedReachedCalls();
    for (modules, offsets) |*module, offset| {
        for (module.semantic.pending_operations.items) |operation| {
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const node = core.graph.nodes.items[@intFromEnum(globalizer.globalNode(offset, call.node))];
            const callee = switch (node.content) {
                .function_call => |value| value.callee,

                else => continue,
            };
            const input_id = switch (node.content) {
                .function_call => |value| value.input,

                else => unreachable,
            };
            const input = core.graph.nodes.items[@intFromEnum(input_id)];
            const literal = switch (input.content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            const fields = core.graph.function(callee).input;

            if (literal.fields.len == fields.len) continue;
            const context = reach_context.Context.fromModule(module, offset, call.visible_bindings, call.owner_function);
            if (try core.completeCallInputFieldsWithReach(fields, input_id, context)) changed = true;
        }
    }
    return changed;
}

fn resolvePendingPhase(
    core: *core_mod.Resolver,
    expressions: *expression_mod.Resolver,
    dispatch: *dispatch_mod.Resolver,
    control: *control_mod.Resolver,
    generics: *generic_mod.Resolver,
    contracts: *contract_mod.Resolver,
    errors: *error_mod.Resolver,
    ownership: *ownership_mod.Resolver,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    resolved: []bool,
    invalid: []bool,
    work: *std.ArrayList(PendingWorkItem),
    reachable: ?*const reachability_mod.FunctionSet,
    pending_attempts: *u64,
    detailed_stats: ?*PendingResolutionStats,
    profile_io: ?std.Io,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !bool {
    var changed = false;
    var write: usize = 0;
    const original_len = work.items.len;
    for (work.items[0..original_len]) |item| {
        if (!isActive(item, reachable)) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        const module_index: usize = @intCast(item.module_index);
        const operation_index: usize = @intCast(item.operation_index);
        const flat_index: usize = @intCast(item.flat_index);
        if (invalid[flat_index]) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        pending_attempts.* += 1;
        const module = &modules[module_index];
        const operation = module.semantic.pending_operations.items[operation_index];
        const attempt_start = if (detailed_stats != null) profileTimestamp(profile_io) else 0;
        expressions.operation_owner = item.owner_function;
        defer expressions.operation_owner = null;
        const result = resolvePendingOperation(
            core,
            expressions,
            dispatch,
            control,
            generics,
            contracts,
            errors,
            ownership,
            module_index,
            module,
            offsets[module_index],
            operation,
        ) catch |err| {
            if (err == error.ComptimeExecutionPending) {
                work.items[write] = item;
                write += 1;
                continue;
            }
            if (err == error.ConflictingGenericArgument and operation == .resolve_call) {
                if (diagnostics) |bag| {
                    const reference = module.semantic.external_refs.items[@intFromEnum(operation.resolve_call.callee)];
                    const source = globalSource(offsets[module_index], reference.source);
                    try bag.add(diagnosticLocation(core.graph, bag, source), .semantic, "conflicting inferred generic parameters in call to '{s}'; repeated types and dimensions must agree", .{module.text(reference.name)});
                    return error.Reported;
                }
            }
            return err;
        };
        if (detailed_stats) |stats| {
            const elapsed = profileTimestamp(profile_io) - attempt_start;
            stats.attempt(operation, result, @intCast(@max(0, elapsed)));
        }
        if (result.isResolved()) {
            resolved[flat_index] = true;
            changed = true;
        } else {
            if (result.isInvalid()) invalid[flat_index] = true;
            work.items[write] = item;
            write += 1;
        }
    }
    work.shrinkRetainingCapacity(write);
    return changed;
}

fn isActive(item: PendingWorkItem, reachable: ?*const reachability_mod.FunctionSet) bool {
    const set = reachable orelse return true;
    const owner = item.owner_function orelse return true;
    return set.contains(owner);
}

/// ModuleSG owns relocatable storage for every lowered body. Selective
/// semantizing publishes only the reachable bodies, so provisional binding
/// types in the remaining dormant storage must not keep GlobalSG in its
/// construction state. Any is used solely as a valid inert payload for those
/// unreachable records; no published body can observe it.
fn retireDormantBindingResolution(
    graph: *global_sg.GlobalSemanticGraph,
    reachable: *const reachability_mod.FunctionSet,
    dormant_type: global_sg.GlobalTypeId,
) !void {
    for (0..graph.bindings.items.len) |raw| {
        const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (!graph.isBindingTypeUnresolved(binding)) continue;
        if (reachable.containsBinding(binding)) continue;
        try graph.resolveBindingType(binding, dormant_type);
    }
}

fn pendingOwnerTag(tag: PendingTag) PendingOwner {
    return switch (tag) {
        .resolve_type => .types,
        .resolve_call, .resolve_local_reach => .calls,
        .resolve_index => .indexing,
        .resolve_field,
        .resolve_binary,
        .resolve_comparison,
        .resolve_dereference,
        .resolve_address,
        => .core,
        .resolve_name_use,
        .resolve_name_assignment,
        .resolve_import,
        => .expressions,
        .resolve_choice_literal,
        .resolve_choice_payload,
        .resolve_nullable_unwrap,
        .resolve_nullable_test,
        .resolve_for_each,
        .resolve_match,
        .resolve_match_case,
        => .control,
        .resolve_contract => .contracts,
        .resolve_error_propagation => .errors,
        .resolve_defer,
        .resolve_copy,
        .resolve_deinit,
        => .ownership,
    };
}

fn pendingOwner(operation: module_entities.PendingOperation) PendingOwner {
    return pendingOwnerTag(std.meta.activeTag(operation));
}

fn pendingPhase(operation: module_entities.PendingOperation) PendingPhase {
    return switch (pendingOwner(operation)) {
        .types => .types_and_generics,
        .calls,
        .indexing,
        .core,
        .expressions,
        => .expressions_and_calls,
        .control,
        .contracts,
        => .control_and_contracts,
        .errors => .errors,
        .ownership => .ownership,
    };
}

/// A single-owner resolver rejecting its assigned operation is an internal
/// routing bug. Composite owners consume `not_applicable` themselves while
/// selecting an implementation strategy and expose only deferred/resolved.
fn ownedResult(result: resolution.Result) resolution.Result {
    std.debug.assert(result != .not_applicable);
    return result;
}

fn resolveTypeOperation(
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !resolution.Result {
    const value = switch (operation) {
        .resolve_type => |value| value,
        else => unreachable,
    };
    const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
    const result = if (reference.generic_arguments != null or reference.projection_base != null or reference.computed_type != null)
        try generics.tryResolve(module_index, module, o, operation)
    else
        try core.tryResolve(module_index, module, o, operation);
    return ownedResult(result);
}

fn resolvePendingOperation(
    core: *core_mod.Resolver,
    expressions: *expression_mod.Resolver,
    dispatch: *dispatch_mod.Resolver,
    control: *control_mod.Resolver,
    generics: *generic_mod.Resolver,
    contracts: *contract_mod.Resolver,
    errors: *error_mod.Resolver,
    ownership: *ownership_mod.Resolver,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !resolution.Result {
    return switch (pendingOwner(operation)) {
        .types => resolveTypeOperation(core, generics, module_index, module, o, operation),
        .calls => if (operation == .resolve_local_reach)
            dispatch.resolveLocalReach(module, o, operation.resolve_local_reach)
        else
            dispatch.resolveCall(module_index, module, o, operation),
        .indexing => blk: {
            const result = try core.tryResolve(module_index, module, o, operation);
            break :blk if (result == .not_applicable) .deferred else result;
        },
        .core => blk: {
            if (operation == .resolve_binary) {
                const contract_result = try dispatch.generic_functions.resolveContractArithmetic(module_index, module, o, operation.resolve_binary);
                break :blk ownedResult(contract_result);
            }
            const core_result = try core.tryResolve(module_index, module, o, operation);
            if (core_result != .resolved and operation == .resolve_comparison) {
                const contract_result = try dispatch.generic_functions.resolveContractComparison(module_index, module, o, operation.resolve_comparison);
                if (contract_result == .resolved) break :blk contract_result;
            }
            break :blk ownedResult(core_result);
        },
        .expressions => ownedResult(try expressions.tryResolve(module_index, module, o, operation)),
        .control => ownedResult(try control.tryResolve(module_index, module, o, operation)),
        .contracts => ownedResult(try contracts.tryResolve(module_index, module, o, operation)),
        .errors => ownedResult(try errors.tryResolve(module_index, module, o, operation)),
        .ownership => ownedResult(try ownership.tryResolve(o, operation)),
    };
}

fn markUnresolvedTypeSlots(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
) !void {
    for (modules, 0..) |*module, module_index| {
        for (0..module_views.typeCount(module)) |raw| {
            const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            switch (try module_views.typeView(module, local)) {
                .resolved => {},
                .external => try graph.markTypeUnresolved(allocator, globalizer.globalType(offsets[module_index], local)),
            }
        }
    }
}

fn diagnoseUnresolvedQualifiedTypes(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (modules, 0..) |*module, module_index| {
        for (0..module_views.typeCount(module)) |raw| {
            const local_type: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            const external = switch (try module_views.typeView(module, local_type)) {
                .external => |id| id,
                .resolved => continue,
            };
            const global_type = globalizer.globalType(offsets[module_index], local_type);
            if (!graph.isTypeUnresolved(global_type)) continue;
            const reference = module.semantic.external_refs.items[@intFromEnum(external)];
            if (reference.kind != .type or reference.module_path == null) continue;
            const target = module_linker.resolveImportPath(
                allocator,
                graph,
                modules,
                module_index,
                module.text(reference.module_path.?),
            ) catch |err| switch (err) {
                error.UnknownModuleReference, error.AmbiguousModuleReference => continue,
                else => return err,
            };
            const name = module.text(reference.name);
            if (!declarationNameExistsInModule(graph, target, name, &.{ .type, .contract_type })) {
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], reference.source)),
                    .semantic,
                    "module '{s}' has no type named '{s}'",
                    .{ module.text(reference.module_path.?), name },
                );
                return true;
            }
            if (@intFromEnum(target) == module_index) continue;
            if (!std.mem.startsWith(u8, name, "_")) continue;
            if (!declarationNameExistsInModule(graph, target, name, &.{ .type, .contract_type })) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], reference.source)),
                .semantic,
                "type '{s}' is private to its module",
                .{name},
            );
            return true;
        }
    }
    return false;
}

fn resolveQualifiedChoiceOptions(core: *core_mod.Resolver, diagnostics: ?*diagnostics_mod.Diagnostics) !bool {
    const graph = core.graph;
    for (graph.variants.items) |*variant| {
        const qualifier = variant.qualifier orelse continue;
        const source = variant.source;
        if (source.file_index >= graph.files.items.len) return error.InvalidChoiceOptionSource;
        const module_index: usize = @intFromEnum(graph.files.items[source.file_index].module);
        const target = try core.findModuleForQualifier(module_index, graph.text(qualifier));
        const name = graph.text(variant.name);
        const declarations = graph.modules.items[@intFromEnum(target)].declarations;
        var found: ?global_sg.GlobalDeclId = null;
        for (declarations.start..declarations.start + declarations.len) |raw| {
            const declaration = graph.declarations.items[raw];
            if (declaration.kind == .choice_option and std.mem.eql(u8, graph.text(declaration.name), name)) {
                found = @enumFromInt(@as(u32, @intCast(raw)));
                break;
            }
        }
        if (diagnostics) |diags| {
            if (found != null and @intFromEnum(target) != module_index and std.mem.startsWith(u8, name, "_")) {
                try diags.add(diagnosticLocation(graph, diags, source), .semantic, "choice option '{s}' is private to its module", .{name});
                return true;
            }
            if (found == null) {
                try diags.add(diagnosticLocation(graph, diags, source), .semantic, "module '{s}' has no choice option '..{s}'", .{ graph.text(qualifier), name });
                return true;
            }
        }
        variant.option_decl = found orelse return error.UnknownChoiceOption;
        variant.qualifier = null;
    }
    return false;
}

fn diagnosePrivateFields(
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            const access = switch (operation) {
                .resolve_field => |value| value,
                else => continue,
            };
            const name = module.text(access.field_name);
            if (!std.mem.startsWith(u8, name, "_")) continue;
            if (reachable) |set| {
                if (operation_index < module.semantic.pending_owner_functions.items.len) {
                    if (module.semantic.pending_owner_functions.items[operation_index]) |owner| {
                        if (!set.contains(globalizer.globalFunction(offsets[module_index], owner))) continue;
                    }
                }
            }
            const target = globalizer.globalNode(offsets[module_index], access.node);
            const node = graph.node(target);
            if (node.content != .struct_field_access) continue;
            const value = node.content.struct_field_access.value;
            const value_ty = graph.node(value).ty orelse continue;
            const field = global_types.findField(graph, value_ty, name) orelse continue;
            if (field.field.source.file_index >= graph.files.items.len) continue;
            const owner_module = graph.files.items[field.field.source.file_index].module;
            if (graph.sameModuleNamespace(owner_module, @enumFromInt(module_index))) continue;
            if (graph.modules.items[module_index].is_bundled_core and
                graph.modules.items[@intFromEnum(owner_module)].is_bundled_core) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], access.source)),
                .semantic,
                "field '{s}' is private to its module",
                .{name},
            );
            return true;
        }
    }
    // Check contextual construction against destination fields, including
    // lists whose shape cannot be materialized as the requested record.
    for (graph.bindings.items) |binding| {
        const initialization = binding.initialization orelse continue;
        const node = graph.node(initialization);
        if (node.content != .list_literal and node.content != .struct_value_literal) continue;
        if (try diagnosePrivateConstruction(graph, binding.ty, node.source, diagnostics)) return true;
    }
    for (graph.nodes.items) |node| {
        if (node.content != .struct_value_literal) continue;
        if (try diagnosePrivateConstruction(graph, node.ty orelse continue, node.source, diagnostics)) return true;
    }
    return false;
}

fn diagnosePrivateConstruction(
    graph: *const global_sg.GlobalSemanticGraph,
    ty: global_sg.GlobalTypeId,
    source: primitives.SourceRef,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    if (@intFromEnum(ty) >= graph.types.items.len) return false;
    const fields = global_types.fields(graph, ty) orelse return false;
    if (source.file_index >= graph.files.items.len) return false;
    const caller_module = graph.files.items[source.file_index].module;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| {
        const name = graph.text(field.name);
        if (!std.mem.startsWith(u8, name, "_")) continue;
        if (field.source.file_index >= graph.files.items.len) continue;
        const owner_module = graph.files.items[field.source.file_index].module;
        if (graph.sameModuleNamespace(owner_module, caller_module)) continue;
        if (graph.modules.items[@intFromEnum(caller_module)].is_bundled_core and
            graph.modules.items[@intFromEnum(owner_module)].is_bundled_core) continue;
        try diagnostics.add(
            diagnosticLocation(graph, diagnostics, source),
            .semantic,
            "field '{s}' is private to its module",
            .{name},
        );
        return true;
    }
    return false;
}

// Array literals whose elements do not determine a homogeneous type need
// context. Report it before diagnostics for operations using the binding;
// unresolved leaf expressions retain their own name/call diagnostics.
fn arrayLiteralLeavesResolved(graph: *const global_sg.GlobalSemanticGraph, id: global_sg.GlobalNodeId) bool {
    const node = graph.node(id);
    if (node.content == .list_literal) {
        const elements = node.content.list_literal.elements;
        for (graph.node_refs.items[elements.start..][0..elements.len]) |element|
            if (!arrayLiteralLeavesResolved(graph, element)) return false;
        return true;
    }
    const ty = node.ty orelse return false;
    return !graph.isTypeUnresolved(ty);
}

fn diagnoseMissingArrayTypeContext(graph: *const global_sg.GlobalSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !bool {
    for (graph.bindings.items, 0..) |binding, raw| {
        if (!graph.isBindingTypeUnresolved(@enumFromInt(raw))) continue;
        const initialization = binding.initialization orelse continue;
        if (graph.node(initialization).content != .list_literal or !arrayLiteralLeavesResolved(graph, initialization)) continue;
        if (binding.name.len == 0 or binding.deferred_initialization) {
            try diagnostics.add(diagnosticLocation(graph, diagnostics, binding.source), .semantic, "cannot infer an array type for this literal; add an explicit array type annotation", .{});
        } else {
            try diagnostics.add(diagnosticLocation(graph, diagnostics, binding.source), .semantic, "cannot infer the array type of '{s}' from this literal; add an explicit array type annotation", .{graph.text(binding.name)});
        }
        return true;
    }
    return false;
}

fn diagnoseUnresolvedBindingTypes(graph: *const global_sg.GlobalSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !bool {
    for (graph.bindings.items, 0..) |binding, raw| {
        if (!graph.isBindingTypeUnresolved(@enumFromInt(raw))) continue;
        if (binding.name.len == 0 or binding.deferred_initialization) {
            try diagnostics.add(diagnosticLocation(graph, diagnostics, binding.source), .semantic, "cannot infer the type of this value; add an explicit type annotation", .{});
        } else {
            try diagnostics.add(diagnosticLocation(graph, diagnostics, binding.source), .semantic, "cannot infer the type of '{s}'; add an explicit type annotation", .{graph.text(binding.name)});
        }
        return true;
    }
    return false;
}

fn diagnoseContractRuntimeBindings(
    graph: *const global_sg.GlobalSemanticGraph,
    contracts: *contract_mod.Resolver,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (graph.bindings.items, 0..) |binding, raw| {
        const binding_id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        const contract_use = contracts.runtimeBindingContract(binding_id) orelse continue;
        const name = graph.text(graph.declarations.items[@intFromEnum(contract_use.declaration)].name);
        try diagnostics.add(
            diagnosticLocation(graph, diagnostics, binding.source),
            .semantic,
            "contract '{s}' has no runtime representation; use a concrete type or Virtual#(.contract: {s})",
            .{ name, name },
        );
        return true;
    }
    return false;
}

fn diagnoseUnresolvedQualifiedNames(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const value = switch (operation) {
                .resolve_name_use => |item| item,
                else => continue,
            };
            const path = value.module_path orelse continue;
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |item| globalizer.globalFunction(offsets[module_index], item) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            const target = module_linker.resolveImportPath(
                allocator,
                graph,
                modules,
                module_index,
                module.text(path),
            ) catch |err| switch (err) {
                error.UnknownModuleReference, error.AmbiguousModuleReference => continue,
                else => return err,
            };
            const target_index: usize = @intFromEnum(target);
            const name = module.text(value.name);
            const source = globalSource(offsets[module_index], value.source);
            if (moduleBindingNameExists(&modules[target_index], name)) {
                if (target_index == module_index or !std.mem.startsWith(u8, name, "_")) continue;
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "value '{s}' is private to its module",
                    .{name},
                );
                return true;
            }
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, source),
                .semantic,
                "module '{s}' has no value '.{s}'",
                .{ moduleQualifierText(graph, diagnostics, source, module, path, name), name },
            );
            return true;
        }
    }
    return false;
}

fn globalSource(o: globalizer.Offsets, source: primitives.SourceRef) primitives.SourceRef {
    return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
}

fn moduleQualifierText(
    graph: *const global_sg.GlobalSemanticGraph,
    diagnostics: *const diagnostics_mod.Diagnostics,
    source: primitives.SourceRef,
    module: *const module_sg.ModuleSemanticGraph,
    path: primitives.StringRange,
    member_name: []const u8,
) []const u8 {
    if (sourceQualifierText(graph, diagnostics, source, member_name)) |value| return value;
    const spelling = std.mem.trim(u8, module.text(path), "\"'");
    return std.fs.path.basename(spelling);
}

fn sourceQualifierText(
    graph: *const global_sg.GlobalSemanticGraph,
    diagnostics: *const diagnostics_mod.Diagnostics,
    source: primitives.SourceRef,
    member_name: []const u8,
) ?[]const u8 {
    const location = diagnosticLocation(graph, diagnostics, source);
    const file_index: usize = @intFromEnum(location.file);
    if (file_index >= diagnostics.source_files.len) return null;
    const code = diagnostics.source_files[file_index].code;
    const offset: usize = @intCast(location.offset);
    if (offset > code.len) return null;

    // Most member nodes point either at the qualifier (`dep.foo`) or at the
    // member token itself. Handle both without storing duplicate source text in
    // the compact semantic graph.
    if (offset < code.len and std.mem.startsWith(u8, code[offset..], member_name)) {
        if (offset != 0 and code[offset - 1] == '.') return identifierBefore(code, offset - 1);
    }
    if (offset < code.len and isIdentifierByte(code[offset])) {
        var end = offset;
        while (end < code.len and isIdentifierByte(code[end])) : (end += 1) {}
        if (end < code.len and code[end] == '.') return code[offset..end];
    }
    if (offset < code.len and code[offset] == '.') return identifierBefore(code, offset);
    return null;
}

fn identifierBefore(code: []const u8, dot: usize) ?[]const u8 {
    if (dot == 0 or code[dot] != '.') return null;
    var start = dot;
    while (start != 0 and isIdentifierByte(code[start - 1])) : (start -= 1) {}
    if (start == dot) return null;
    return code[start..dot];
}

fn isIdentifierByte(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '_';
}

fn moduleBindingNameExists(module: *const module_sg.ModuleSemanticGraph, name: []const u8) bool {
    for (module.semantic.declaration_bindings.items) |relation| {
        const declaration = module.declarations.items[@intFromEnum(relation.declaration)];
        if (std.mem.eql(u8, module.text(declaration.name), name)) return true;
    }
    return false;
}

fn declarationNameExistsInModule(
    graph: *const global_sg.GlobalSemanticGraph,
    module: global_sg.GlobalModuleId,
    name: []const u8,
    kinds: []const primitives.DeclarationKind,
) bool {
    for (graph.declarations.items, 0..) |declaration, raw| {
        const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (graph.moduleForDeclaration(id) != module) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        for (kinds) |kind| if (declaration.kind == kind) return true;
    }
    return false;
}

fn visibleFunctionNameExists(
    core: *const core_mod.Resolver,
    current_module: usize,
    qualified_module: ?global_sg.GlobalModuleId,
    name: []const u8,
) bool {
    const graph = core.graph;
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .function and declaration.kind != .test_function) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (core.declarationVisible(current_module, id, qualified_module)) return true;
    }
    return false;
}

fn diagnoseUnresolvedChoice(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
    missing_context: bool,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            switch (operation) {
                .resolve_choice_literal => |choice| {
                    const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                    const name = module.text(reference.name);
                    const target = globalizer.globalNode(offsets[module_index], choice.node);
                    const choice_ty = if (choice.expected_type) |local_ty|
                        globalizer.globalType(offsets[module_index], local_ty)
                    else
                        graph.node(target).ty orelse {
                            if (!missing_context) continue;
                            const source: @import("../primitives/schema.zig").SourceRef = .{
                                .file_index = offsets[module_index].file_base + reference.source.file_index,
                                .offset = reference.source.offset,
                            };
                            try diagnostics.add(diagnosticLocation(graph, diagnostics, source), .semantic, "choice option '..{s}' needs a concrete choice type", .{name});
                            return true;
                        };
                    if (graph.isTypeUnresolved(choice_ty) or global_types.isBuiltin(graph, choice_ty, .Any)) continue;
                    // A known non-choice may still become meaningful through a
                    // different pending operation. Only classify operations for
                    // which the choice family itself is already final.
                    if (global_types.variants(graph, choice_ty) == null) continue;

                    const source: @import("../primitives/schema.zig").SourceRef = .{
                        .file_index = offsets[module_index].file_base + reference.source.file_index,
                        .offset = reference.source.offset,
                    };
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse {
                        var type_name = std.array_list.Managed(u8).init(allocator);
                        defer type_name.deinit();
                        try appendTypeName(&type_name, graph, choice_ty);
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "choice type '{s}' has no variant '..{s}'",
                            .{ type_name.items, name },
                        );
                        return true;
                    };
                    if (hit.variant.payload_type != null and choice.payload == null) {
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "choice variant '..{s}' requires a payload",
                            .{name},
                        );
                        return true;
                    }
                },
                .resolve_choice_payload => |access| {
                    const value = graph.node(globalizer.globalNode(offsets[module_index], access.value));
                    const choice_ty = value.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty)) continue;
                    if (access.requires_errable and !global_types.isErrable(graph, choice_ty)) {
                        const source: @import("../primitives/schema.zig").SourceRef = .{ .file_index = offsets[module_index].file_base + access.source.file_index, .offset = access.source.offset };
                        try diagnostics.add(diagnosticLocation(graph, diagnostics, source), .semantic, "handle expects an Errable value", .{});
                        return true;
                    }
                    if (global_types.variants(graph, choice_ty) == null) continue;
                    const name = module.text(access.option_name);
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse continue;
                    if (hit.variant.payload_type != null) continue;
                    const source: @import("../primitives/schema.zig").SourceRef = .{
                        .file_index = offsets[module_index].file_base + access.source.file_index,
                        .offset = access.source.offset,
                    };
                    try diagnostics.add(
                        diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "choice variant '..{s}' has no payload",
                        .{name},
                    );
                    return true;
                },
                .resolve_match => |match| {
                    const expression = graph.node(globalizer.globalNode(offsets[module_index], match.value));
                    const choice_ty = expression.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty)) continue;
                    const variants = global_types.variants(graph, choice_ty) orelse {
                        var type_name = std.array_list.Managed(u8).init(allocator);
                        defer type_name.deinit();
                        try appendTypeName(&type_name, graph, choice_ty);
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, expression.source),
                            .semantic,
                            "match expects a choice value, found '{s}'",
                            .{type_name.items},
                        );
                        return true;
                    };
                    _ = variants;

                    var seen: std.ArrayList(global_sg.GlobalVariantId) = .empty;
                    defer seen.deinit(allocator);
                    for (module.semantic.node_refs.items[match.cases.start..][0..match.cases.len]) |local_case_node| {
                        const pending_id = switch (module.semantic.nodes.items[@intFromEnum(local_case_node)]) {
                            .pending => |id| id,
                            else => continue,
                        };
                        const case = switch (module.semantic.pending_operations.items[@intFromEnum(pending_id)]) {
                            .resolve_match_case => |item| item,
                            else => continue,
                        };
                        const option_ref = module.semantic.external_refs.items[@intFromEnum(case.option)];
                        const name = module.text(option_ref.name);
                        const source = globalSource(offsets[module_index], option_ref.source);
                        const hit = global_types.findVariant(graph, choice_ty, name) orelse {
                            var type_name = std.array_list.Managed(u8).init(allocator);
                            defer type_name.deinit();
                            try appendTypeName(&type_name, graph, choice_ty);
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice type '{s}' has no variant '..{s}'",
                                .{ type_name.items, name },
                            );
                            return true;
                        };
                        var duplicate = false;
                        for (seen.items) |previous| if (previous == hit.id) {
                            duplicate = true;
                            break;
                        };
                        if (duplicate) {
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice variant '..{s}' appears more than once in match",
                                .{name},
                            );
                            return true;
                        }
                        try seen.append(allocator, hit.id);

                        if (case.payload_binding != null and hit.variant.payload_type == null) {
                            const payload_source: @import("../primitives/schema.zig").SourceRef = .{
                                .file_index = source.file_index,
                                .offset = source.offset + @as(u32, @intCast(name.len + 1)),
                            };
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, payload_source),
                                .semantic,
                                "choice variant '..{s}' has no payload to bind",
                                .{name},
                            );
                            return true;
                        }
                        if (case.payload_binding == null and hit.variant.payload_type != null) {
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice variant '..{s}' carries a payload and match must bind it explicitly; use '..{s} _' to ignore it",
                                .{ name, name },
                            );
                            return true;
                        }
                    }
                },
                else => {},
            }
        }
    }
    return false;
}

fn diagnoseUnresolvedAssignments(
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const access = switch (operation) {
                .resolve_name_assignment => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            var source = access.source;
            source.file_index += offsets[module_index].file_base;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, source),
                .semantic,
                "cannot assign to undeclared binding '{s}'; declare it first with ':=' or '::='",
                .{module.text(access.name)},
            );
            return true;
        }
    }
    return false;
}

fn diagnoseUnresolvedIndex(
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const access = switch (operation) {
                .resolve_index => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            const collection = graph.node(globalizer.globalNode(offsets[module_index], access.value));
            const ty = collection.ty orelse continue;
            if (graph.isTypeUnresolved(ty) or global_types.arrayElement(graph, ty) != null) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, collection.source),
                .semantic,
                "indexing is only supported for native arrays; use a named collection operation",
                .{},
            );
            return true;
        }
    }
    return false;
}

fn diagnoseUnresolvedCopy(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const copy = switch (operation) {
                .resolve_copy => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            const value = graph.node(globalizer.globalNode(offsets[module_index], copy.value));
            const ty = value.ty orelse continue;
            if (graph.isTypeUnresolved(ty)) continue;
            var type_name = std.array_list.Managed(u8).init(allocator);
            defer type_name.deinit();
            try appendTypeName(&type_name, graph, ty);
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, value.source),
                .semantic,
                "type '{s}' cannot be copied implicitly; use '~value' to transfer ownership",
                .{type_name.items},
            );
            return true;
        }
    }
    return false;
}

fn appendAmbiguousCallPrefix(
    message: *std.array_list.Managed(u8),
    graph: *const global_sg.GlobalSemanticGraph,
    diagnostics: *const diagnostics_mod.Diagnostics,
    source: primitives.SourceRef,
    module: *const module_sg.ModuleSemanticGraph,
    reference: module_entities.ExternalRef,
) !void {
    const name = module.text(reference.name);
    if (reference.module_path) |path| {
        try message.appendSlice("module-qualified call '");
        try message.appendSlice(moduleQualifierText(graph, diagnostics, source, module, path, name));
        try message.append('.');
    } else {
        try message.appendSlice("ambiguous call to '");
    }
    try message.appendSlice(name);
    if (reference.module_path != null)
        try message.appendSlice("' is ambiguous for arguments ")
    else
        try message.appendSlice("' for arguments ");
}

fn diagnoseUnresolvedCall(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    generic_functions: *generic_functions_mod.Resolver,
    contracts: *contract_mod.Resolver,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            const name = module.text(reference.name);
            const qualified_module: ?global_sg.GlobalModuleId = if (reference.module_path) |path|
                module_linker.resolveImportPath(allocator, graph, modules, module_index, module.text(path)) catch |err| switch (err) {
                    error.UnknownModuleReference, error.AmbiguousModuleReference => null,
                    else => return err,
                }
            else
                null;
            const source = globalSource(offsets[module_index], reference.source);
            const location = diagnosticLocation(graph, diagnostics, .{
                .file_index = source.file_index,
                .offset = source.offset + @as(u32, @intCast(name.len)),
            });

            if (call.callee_value) |local| {
                const pointer = graph.node(globalizer.globalNode(offsets[module_index], local));
                const ty = pointer.ty orelse continue;
                if (graph.isTypeUnresolved(ty)) continue;
                if (!c_abi.isFunctionPointer(graph, ty)) {
                    try diagnostics.add(location, .semantic, "cannot call binding '{s}': expected a CFunctionPointer value", .{name});
                } else {
                    const declaration = switch (graph.resolvedSemanticType(ty).?) {
                        .declared => |id| graph.declaration(id),
                        else => unreachable,
                    };
                    const signature = graph.function(declaration.function_id.?);
                    const input = globalizer.globalNode(offsets[module_index], call.input);
                    if (generic_functions.core.matchCallInput(signature.input, input) == .applicable) {
                        try diagnostics.add(location, .semantic, "cannot resolve C callback '{s}': .ffi uses reach [ffi] and requires a ForeignFunctionInterface capability", .{name});
                    } else {
                        try diagnostics.add(location, .semantic, "arguments do not match the C callback signature of '{s}'", .{name});
                    }
                }
                return true;
            }

            // Incomplete identities deliberately cannot participate in value
            // construction or layout queries. Explain that boundary before
            // the generic call-mismatch diagnostic hides the actual cause.
            if (reference.module_path == null and (std.mem.eql(u8, name, "size_of") or std.mem.eql(u8, name, "alignment_of"))) {
                const input_node = graph.node(globalizer.globalNode(offsets[module_index], call.input));
                if (input_node.content == .struct_value_literal) {
                    const fields = input_node.content.struct_value_literal.fields;
                    for (graph.value_fields.items[fields.start..][0..fields.len]) |field| {
                        const argument = graph.node(field.value);
                        if (argument.content != .type_literal) continue;
                        if (global_types.incompleteDeclaration(graph, argument.content.type_literal)) |id| {
                            try diagnostics.add(location, .semantic, "CIncomplete type '{s}' has no size or alignment; use RawPointer for foreign handles", .{graph.text(graph.declaration(id).name)});
                            return true;
                        }
                    }
                }
            }
            for (try graph.declarationsNamed(allocator, name)) |id| {
                const declaration = graph.declaration(id);
                if (declaration.struct_layout != .c_incomplete or !generic_functions.core.declarationVisible(module_index, id, qualified_module)) continue;
                try diagnostics.add(location, .semantic, "CIncomplete type '{s}' cannot be constructed; use RawPointer for foreign handles", .{name});
                return true;
            }

            if (reference.module_path == null and reference.generic_arguments == null and reference.computed_arguments == null and std.mem.eql(u8, name, "to_virtual") and call.expected_type == null) {
                try diagnostics.add(diagnosticLocation(graph, diagnostics, source), .semantic, "cannot infer the contract parameter of 'to_virtual'; provide a Virtual result type or '#(.contract: ContractName)'", .{});
                return true;
            }

            if (reference.module_path) |path| {
                const target = qualified_module orelse continue;
                const has_name = declarationNameExistsInModule(graph, target, name, &.{ .function, .test_function });
                const core_peer = graph.modules.items[module_index].is_bundled_core and
                    graph.modules.items[@intFromEnum(target)].is_bundled_core;
                if (has_name and @intFromEnum(target) != module_index and !core_peer and std.mem.startsWith(u8, name, "_")) {
                    try diagnostics.add(location, .semantic, "function '{s}' is private to its module", .{name});
                    return true;
                }
                if (!has_name) {
                    try diagnostics.add(
                        location,
                        .semantic,
                        "module '{s}' has no function named '{s}'",
                        .{ moduleQualifierText(graph, diagnostics, source, module, path, name), name },
                    );
                    return true;
                }
            } else if (!visibleFunctionNameExists(generic_functions.core, module_index, null, name)) {
                try diagnostics.add(location, .semantic, "no function named '{s}' exists", .{name});
                return true;
            }

            const input_id = globalizer.globalNode(offsets[module_index], call.input);
            const input = switch (graph.node(input_id).content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            var candidates: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer candidates.deinit(allocator);
            for (graph.functions.items, 0..) |function, raw| {
                const declaration = graph.declaration(function.declaration);
                if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
                if (!generic_functions.core.declarationVisible(module_index, function.declaration, qualified_module)) continue;
                try candidates.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));
            }
            var input_complete = true;
            for (graph.value_fields.items[input.fields.start..][0..input.fields.len]) |field| {
                const ty = graph.node(field.value).ty orelse {
                    input_complete = false;
                    break;
                };
                if (graph.isTypeUnresolved(ty)) {
                    input_complete = false;
                    break;
                }
            }
            if (!input_complete) {
                // Untyped choice arguments can still make multiple candidate
                // contracts fit. Diagnose that ambiguity before waiting for a
                // context that only selection of a candidate could provide.
                var contextual_core = core_mod.Resolver{
                    .allocator = allocator,
                    .graph = graph,
                    .modules = modules,
                    .offsets = offsets,
                };
                var contextual_matches: usize = 0;
                for (candidates.items) |candidate| {
                    const function = graph.function(candidate);
                    if (contextual_core.matchCallInput(function.input, input_id) == .applicable) contextual_matches += 1;
                }
                if (contextual_matches < 2) continue;
            }

            var constraint_failures: std.ArrayList(generic_functions_mod.ConstraintFailure) = .empty;
            defer constraint_failures.deinit(allocator);
            var constraint_actual_name = std.array_list.Managed(u8).init(allocator);
            defer constraint_actual_name.deinit();
            var missing_generic_reach = std.array_list.Managed(u8).init(allocator);
            defer missing_generic_reach.deinit();
            try generic_functions.collectGenericCallFailures(
                module_index,
                module,
                reference,
                input_id,
                reach_context.Context.fromModule(module, offsets[module_index], call.visible_bindings, call.owner_function),
                &constraint_failures,
                &missing_generic_reach,
                &constraint_actual_name,
                appendTypeName,
            );
            if (constraint_failures.items.len != 0) {
                const failure = constraint_failures.items[0];
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "type '{s}' does not satisfy contract constraint '{s}' required by generic function parameter '.{s}' of '{s}'",
                    .{
                        constraint_actual_name.items,
                        graph.text(graph.declaration(failure.contract_decl).name),
                        failure.parameter_name,
                        graph.text(graph.declaration(failure.function).name),
                    },
                );
                return true;
            }

            // Materialized specializations must not hide the intrinsic's useful
            // rejection diagnostic for an incompatible explicit type argument.
            if (reference.module_path == null and std.mem.eql(u8, name, "zeroed") and
                generic_functions.hasVisibleParameterizedFunctionName(module_index, name, qualified_module))
            {
                try diagnostics.add(diagnosticLocation(graph, diagnostics, source), .semantic, "zeroed requires a numeric type or a fixed array of numeric types; references and resource-bearing types cannot be zero-initialized", .{});
                return true;
            }

            if (candidates.items.len == 0) {
                if (generic_functions.hasVisibleParameterizedFunctionName(module_index, name, qualified_module)) {
                    var applicable_generic_functions: std.ArrayList(global_sg.GlobalDeclId) = .empty;
                    defer applicable_generic_functions.deinit(allocator);
                    if (try generic_functions.collectImplicitGenericAmbiguity(
                        module_index,
                        module,
                        reference,
                        input_id,
                        &applicable_generic_functions,
                    )) {
                        var ambiguity = std.array_list.Managed(u8).init(allocator);
                        defer ambiguity.deinit();
                        try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                        try appendValueShape(&ambiguity, graph, input);
                        try ambiguity.appendSlice(". Applicable function identities:");
                        try diagnostics.add(
                            if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "{s}",
                            .{ambiguity.items},
                        );
                        return true;
                    }

                    var mismatch = std.array_list.Managed(u8).init(allocator);
                    defer mismatch.deinit();
                    try mismatch.appendSlice("no generic function named '");
                    try mismatch.appendSlice(name);
                    try mismatch.appendSlice("' accepts arguments ");
                    try appendValueShape(&mismatch, graph, input);
                    if (missing_generic_reach.items.len != 0) {
                        try mismatch.appendSlice("; omitted inputs have unavailable reach defaults:");
                        try mismatch.appendSlice(missing_generic_reach.items);
                        try mismatch.appendSlice("\nPass these inputs explicitly or make the required capabilities reachable in the caller.");
                    } else try mismatch.appendSlice("; input types and repeated generic dimensions must agree");
                    try diagnostics.add(
                        if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "{s}",
                        .{mismatch.items},
                    );
                    return true;
                }
                continue;
            }

            // Reuse Core's applicability matcher so diagnostics report every
            // applicable identity, without introducing specificity ranking.
            var diagnostic_core = core_mod.Resolver{
                .allocator = allocator,
                .graph = graph,
                .modules = modules,
                .offsets = offsets,
            };
            var applicable_functions: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer applicable_functions.deinit(allocator);
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                if (function.flags.is_generic_instantiation or function.flags.is_c_function_pointer) continue;
                switch (diagnostic_core.matchCallInput(function.input, input_id)) {
                    .applicable => {},
                    .no_match, .deferred => continue,
                }
                try applicable_functions.append(allocator, candidate);
            }
            if (applicable_functions.items.len > 1) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Applicable function identities:");
                for (applicable_functions.items) |candidate| {
                    const function = graph.functions.items[@intFromEnum(candidate)];
                    try ambiguity.appendSlice("\n  - ");
                    try ambiguity.appendSlice(name);
                    try ambiguity.append(' ');
                    try appendFieldShape(&ambiguity, graph, function.input);
                    try ambiguity.appendSlice(" -> ");
                    try appendFieldShape(&ambiguity, graph, function.output);
                }
                try diagnostics.add(
                    if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "{s}",
                    .{ambiguity.items},
                );
                return true;
            }

            var applicable_generic_functions: std.ArrayList(global_sg.GlobalDeclId) = .empty;
            defer applicable_generic_functions.deinit(allocator);
            if (try generic_functions.collectImplicitGenericAmbiguity(
                module_index,
                module,
                reference,
                input_id,
                &applicable_generic_functions,
            )) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Applicable function identities:");
                for (applicable_generic_functions.items) |declaration_id| {
                    const declaration = graph.declaration(declaration_id);
                    const function_id = declaration.function_id orelse continue;
                    const function = graph.functions.items[@intFromEnum(function_id)];
                    try ambiguity.appendSlice("\n  - ");
                    try ambiguity.appendSlice(name);
                    try ambiguity.append(' ');
                    try appendFieldShape(&ambiguity, graph, function.input);
                    try ambiguity.appendSlice(" -> ");
                    try appendFieldShape(&ambiguity, graph, function.output);
                }
                try diagnostics.add(
                    if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "{s}",
                    .{ambiguity.items},
                );
                return true;
            }

            if (candidates.items.len == 1 and diagnostic_core.callInputNamesMatch(graph.functions.items[@intFromEnum(candidates.items[0])].input, input)) {
                const function = graph.functions.items[@intFromEnum(candidates.items[0])];
                var missing_contract: ?struct {
                    actual: global_sg.GlobalTypeId,
                    contract_type: global_sg.GlobalTypeId,
                    declaration: global_sg.GlobalDeclId,
                    field: global_sg.Field,
                    source: primitives.SourceRef,
                } = null;
                var other_mismatch = false;
                for (graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, field_index| {
                    var argument: ?global_sg.GlobalNodeId = null;
                    for (graph.value_fields.items[input.fields.start..][0..input.fields.len], 0..) |supplied, supplied_index| {
                        if (supplied_index < input.dispatch_prefix_positional_count or graph.text(supplied.name).len == 0) {
                            if (supplied_index == field_index) argument = supplied.value;
                        } else if (std.mem.eql(u8, graph.text(supplied.name), graph.text(field.name))) {
                            argument = supplied.value;
                        }
                    }
                    const supplied_node = argument orelse {
                        if (field.default_value == null) other_mismatch = true;
                        continue;
                    };
                    const actual = graph.node(supplied_node).ty orelse {
                        other_mismatch = true;
                        continue;
                    };
                    if (global_types.equal(graph, actual, field.ty) or diagnostic_core.callTypesCompatible(actual, field.ty)) continue;

                    var expected_contract_type = field.ty;
                    var actual_concrete = actual;
                    switch (graph.semanticType(field.ty)) {
                        .pointer => |expected_pointer| {
                            const actual_pointer = switch (graph.semanticType(actual)) {
                                .pointer => |value| value,
                                else => {
                                    other_mismatch = true;
                                    continue;
                                },
                            };
                            if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) {
                                other_mismatch = true;
                                continue;
                            }
                            expected_contract_type = expected_pointer.child;
                            actual_concrete = actual_pointer.child;
                        },
                        else => {},
                    }

                    const declaration = contracts.contractDeclarationForType(expected_contract_type) orelse {
                        other_mismatch = true;
                        continue;
                    };
                    if (contracts.concreteImplements(actual_concrete, expected_contract_type)) {
                        other_mismatch = true;
                        continue;
                    }
                    if (missing_contract != null) {
                        other_mismatch = true;
                    } else {
                        missing_contract = .{
                            .actual = actual_concrete,
                            .contract_type = expected_contract_type,
                            .declaration = declaration,
                            .field = field,
                            .source = graph.node(supplied_node).source,
                        };
                    }
                }
                if (!other_mismatch) if (missing_contract) |missing| {
                    var actual_name = std.array_list.Managed(u8).init(allocator);
                    defer actual_name.deinit();
                    try appendTypeName(&actual_name, graph, missing.actual);
                    var message = std.array_list.Managed(u8).init(allocator);
                    defer message.deinit();
                    try appendFormatted(
                        &message,
                        allocator,
                        "type '{s}' does not implement contract '{s}' required by parameter '.{s}' of '{s}'",
                        .{
                            actual_name.items,
                            graph.text(graph.declaration(missing.declaration).name),
                            graph.text(missing.field.name),
                            name,
                        },
                    );
                    try diagnostics.add(
                        argumentFieldLocation(
                            graph,
                            diagnostics,
                            missing.source,
                            graph.text(missing.field.name),
                        ),
                        .semantic,
                        "{s}",
                        .{message.items},
                    );
                    return true;
                };
            }

            var reach_details = std.array_list.Managed(u8).init(allocator);
            defer reach_details.deinit();
            var reach_candidate_count: usize = 0;
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                if (diagnostic_core.matchCallInput(function.input, input_id) != .applicable) continue;
                if (try appendOmittedReachDefaults(&reach_details, graph, name, function, input))
                    reach_candidate_count += 1;
            }
            if (reach_candidate_count != 0) {
                var message = std.array_list.Managed(u8).init(allocator);
                defer message.deinit();
                try message.print("function '{s}' exists, but its arguments do not match.\nCandidates with omitted reach defaults:\n", .{name});
                try message.appendSlice(reach_details.items);
                if (std.mem.indexOf(u8, reach_details.items, ".ffi uses reach") != null)
                    try message.appendSlice("\n\nForeign calls require a live ForeignFunctionInterface capability. Bind 'assume ffi := system.ffi' in the caller or pass '.ffi' explicitly; this dependency is not part of the C signature.");
                try message.appendSlice("\n\nAdd a reachable value in the caller, for example:\n  main(.system: System) -> (.status_code: Int32 = 0) := { ... }\n\nOr pass the omitted argument explicitly.");
                try diagnostics.add(location, .semantic, "{s}", .{message.items});
                return true;
            }

            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try message.appendSlice("no function named '");
            try message.appendSlice(name);
            try message.appendSlice("' accepts arguments ");
            try appendValueShape(&message, graph, input);
            try message.appendSlice(". Available signatures:");
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                try message.appendSlice("\n  - ");
                try message.appendSlice(name);
                try message.append(' ');
                try appendFieldShape(&message, graph, function.input);
                try message.appendSlice(" -> ");
                try appendFieldShape(&message, graph, function.output);
            }
            try diagnostics.add(location, .semantic, "{s}", .{message.items});
            return true;
        }
    }
    return false;
}

fn appendFormatted(
    buffer: *std.array_list.Managed(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try buffer.appendSlice(text);
}

fn appendValueShape(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, literal: anytype) !void {
    try buffer.append('(');
    for (graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.append('.');
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(": ");
        const ty = graph.node(field.value).ty orelse {
            try buffer.appendSlice("?");
            continue;
        };
        try appendTypeName(buffer, graph, ty);
    }
    try buffer.append(')');
}

fn appendFieldShape(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, range: global_sg.FieldRange) !void {
    try buffer.append('(');
    for (graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.append('.');
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(": ");
        try appendTypeName(buffer, graph, field.ty);
    }
    try buffer.append(')');
}

fn appendOmittedReachDefaults(
    buffer: *std.array_list.Managed(u8),
    graph: *const global_sg.GlobalSemanticGraph,
    name: []const u8,
    function: global_sg.Function,
    input: anytype,
) !bool {
    var omitted_count: usize = 0;
    for (graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, field_index| {
        if (callInputSuppliesField(graph, input, field, field_index)) continue;
        const fallback = field.default_value orelse continue;
        if (graph.node(fallback).content == .reach_directive) omitted_count += 1;
    }
    if (omitted_count == 0) return false;

    if (buffer.items.len != 0) try buffer.append('\n');
    try buffer.appendSlice("  - ");
    try buffer.appendSlice(name);
    try buffer.append('(');
    for (graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.append('.');
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(": ");
        try appendTypeName(buffer, graph, field.ty);
        const fallback = field.default_value orelse continue;
        const reach_id = switch (graph.node(fallback).content) {
            .reach_directive => |value| value,
            else => continue,
        };
        try buffer.appendSlice(" = reach ");
        try appendReachAlternatives(buffer, graph, reach_id);
    }
    try buffer.appendSlice(") -> ");
    try appendFieldShape(buffer, graph, function.output);
    try buffer.appendSlice("\n    omitted reach defaults:");

    for (graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, field_index| {
        if (callInputSuppliesField(graph, input, field, field_index)) continue;
        const fallback = field.default_value orelse continue;
        const reach_id = switch (graph.node(fallback).content) {
            .reach_directive => |value| value,
            else => continue,
        };
        try buffer.appendSlice("\n      - .");
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(" uses reach [");
        try appendReachAlternatives(buffer, graph, reach_id);
        try buffer.appendSlice("] expected as '");
        try appendTypeName(buffer, graph, field.ty);
        try buffer.append('\'');
    }
    return true;
}

fn callInputSuppliesField(
    graph: *const global_sg.GlobalSemanticGraph,
    input: anytype,
    field: global_sg.Field,
    field_index: usize,
) bool {
    for (graph.value_fields.items[input.fields.start..][0..input.fields.len], 0..) |supplied, supplied_index| {
        if (supplied_index < input.dispatch_prefix_positional_count or graph.text(supplied.name).len == 0) {
            if (supplied_index == field_index) return true;
        } else if (std.mem.eql(u8, graph.text(supplied.name), graph.text(field.name))) return true;
    }
    return false;
}

fn appendReachAlternatives(
    buffer: *std.array_list.Managed(u8),
    graph: *const global_sg.GlobalSemanticGraph,
    reach_id: global_sg.GlobalReachId,
) !void {
    const reach = graph.reaches.items[@intFromEnum(reach_id)];
    for (graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len], 0..) |alternative, index| {
        if (index != 0) try buffer.appendSlice(", ");
        for (graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len], 0..) |segment, segment_index| {
            if (segment_index != 0) try buffer.append('.');
            try buffer.appendSlice(graph.text(segment));
        }
    }
}

fn appendTypeName(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) anyerror!void {
    // Candidate signatures may still contain unresolved slots while reporting
    // a failed call. Their poison payload is not a declaration to inspect.
    if (graph.isTypeUnresolved(ty)) {
        try buffer.appendSlice("<unresolved>");
        return;
    }
    if (global_types.arrayLength(graph, ty)) |length| {
        const element = global_types.arrayElement(graph, ty) orelse return error.InvalidArrayType;
        try buffer.append('[');
        var storage: [32]u8 = undefined;
        try buffer.appendSlice(try std.fmt.bufPrint(&storage, "{d}", .{length}));
        try buffer.append(']');
        try appendTypeName(buffer, graph, element);
        return;
    }
    switch (graph.semanticType(ty)) {
        .builtin => |builtin| try buffer.appendSlice(@tagName(builtin)),
        .declared => |declaration| try buffer.appendSlice(graph.text(graph.declaration(declaration).name)),
        .generic => |generic| {
            const base_name = graph.text(graph.declaration(generic.base).name);
            if (std.mem.eql(u8, base_name, "Nullable")) {
                for (graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| switch (argument.value) {
                    .type => |value| {
                        try buffer.append('?');
                        try appendTypeName(buffer, graph, value);
                        return;
                    },
                    else => {},
                };
            }
            try buffer.appendSlice(base_name);
            try buffer.appendSlice("#(");
            for (graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len], 0..) |argument, index| {
                if (index != 0) try buffer.appendSlice(", ");
                const name = graph.text(argument.name);
                if (name.len != 0) {
                    try buffer.append('.');
                    try buffer.appendSlice(name);
                }
                switch (argument.value) {
                    .type => |value| {
                        if (name.len != 0) try buffer.appendSlice(": ");
                        try appendTypeName(buffer, graph, value);
                    },
                    .comptime_int => |value| {
                        if (name.len != 0) try buffer.appendSlice(" = ");
                        var storage: [32]u8 = undefined;
                        try buffer.appendSlice(try std.fmt.bufPrint(&storage, "{d}", .{value}));
                    },
                }
            }
            try buffer.append(')');
        },
        .pointer => |pointer| {
            try buffer.appendSlice(if (pointer.mutability == .read_write) "$&" else "&");
            try appendTypeName(buffer, graph, pointer.child);
        },
        .nullable => |child| {
            try buffer.append('?');
            try appendTypeName(buffer, graph, child);
        },
        .structural_choice => |choice| try appendChoiceTypeName(buffer, graph, choice.variants),
        .inferred_choice => |choice| try appendChoiceTypeName(buffer, graph, choice.variants),
        .array => unreachable,
        .structural => try buffer.appendSlice("{...}"),
        else => try buffer.appendSlice("<type>"),
    }
}

fn appendChoiceTypeName(
    buffer: *std.array_list.Managed(u8),
    graph: *const global_sg.GlobalSemanticGraph,
    variants: global_sg.VariantRange,
) anyerror!void {
    try buffer.append('(');
    for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.appendSlice("..");
        try buffer.appendSlice(graph.text(variant.name));
        if (variant.payload_type) |payload| {
            try buffer.appendSlice(": ");
            try appendTypeName(buffer, graph, payload);
        }
    }
    try buffer.append(')');
}

fn argumentFieldLocation(
    graph: *const global_sg.GlobalSemanticGraph,
    diagnostics: *const diagnostics_mod.Diagnostics,
    value_source: primitives.SourceRef,
    field_name: []const u8,
) tok.Location {
    const value_location = diagnosticLocation(graph, diagnostics, value_source);
    const file = diagnostics.source_db.get(value_location.file);
    const end = @min(@as(usize, value_location.offset), file.source.len);
    var line_start = end;
    while (line_start > 0 and file.source[line_start - 1] != '\n') line_start -= 1;

    var cursor = end;
    while (cursor > line_start) {
        cursor -= 1;
        if (file.source[cursor] != '.') continue;
        const name_start = cursor + 1;
        const name_end = name_start + field_name.len;
        if (name_end <= end and std.mem.eql(u8, file.source[name_start..name_end], field_name)) {
            const argument_start = if (cursor > line_start and file.source[cursor - 1] == '(') cursor - 1 else cursor;
            return .{ .file = value_location.file, .offset = @intCast(argument_start) };
        }
    }
    return value_location;
}

fn diagnosticLocation(graph: *const global_sg.GlobalSemanticGraph, diagnostics: *const diagnostics_mod.Diagnostics, source: @import("../primitives/schema.zig").SourceRef) tok.Location {
    if (source.file_index < graph.files.items.len) {
        const graph_file = graph.files.items[source.file_index];
        const wanted_name = graph.text(graph_file.path);
        const wanted_dir = graph.text(graph.modules.items[@intFromEnum(graph_file.module)].dir);
        for (diagnostics.source_files, 0..) |file, index| {
            if (std.mem.eql(u8, std.fs.path.basename(file.path), wanted_name) and
                std.mem.eql(u8, std.fs.path.dirname(file.path) orelse ".", wanted_dir))
                return .{ .file = @enumFromInt(@as(u32, @intCast(index))), .offset = source.offset };
        }
    }
    return .{ .file = @enumFromInt(0), .offset = source.offset };
}

fn dumpUnresolved(
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
) void {
    var flat: usize = 0;
    var shown: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            const item: PendingWorkItem = .{
                .module_index = @intCast(module_index),
                .operation_index = @intCast(operation_index),
                .flat_index = @intCast(flat),
                .owner_function = if (operation_index < module.semantic.pending_owner_functions.items.len)
                    if (module.semantic.pending_owner_functions.items[operation_index]) |owner|
                        globalizer.globalFunction(offsets[module_index], owner)
                    else
                        null
                else
                    null,
            };
            if (!resolved[flat] and isActive(item, reachable) and shown < 8) {
                switch (operation) {
                    .resolve_call => |call| {
                        const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
                        std.debug.print(
                            "global sema unresolved: module={d} dir={s} op=resolve_call name={s} generic={any} input={d}\n",
                            .{ module_index, module.module_dir, module.text(reference.name), reference.generic_arguments != null, @intFromEnum(call.input) },
                        );
                    },
                    .resolve_name_use => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_name_use name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
                    ),
                    .resolve_name_assignment => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_name_assignment name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
                    ),
                    .resolve_import => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_import path={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.path), @intFromEnum(value.node) },
                    ),
                    .resolve_choice_literal => |choice| {
                        const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                        std.debug.print(
                            "global sema unresolved: module={d} dir={s} op=resolve_choice_literal name={s} source={d} payload={any} expected={any}\n",
                            .{ module_index, module.module_dir, module.text(reference.name), reference.source.offset, choice.payload, choice.expected_type },
                        );
                    },
                    .resolve_field => |field| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_field name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(field.field_name), @intFromEnum(field.node) },
                    ),
                    else => std.debug.print(
                        "global sema unresolved: module={d} dir={s} op={s}\n",
                        .{ module_index, module.module_dir, @tagName(operation) },
                    ),
                }
                shown += 1;
            }
            flat += 1;
        }
    }
    if (shown == 8) std.debug.print("global sema unresolved: additional operations omitted\n", .{});
}

fn totalPending(modules: []const module_sg.ModuleSemanticGraph) usize {
    var total: usize = 0;
    for (modules) |module| total += module.semantic.pending_operations.items.len;
    return total;
}

test "pending operation ownership is explicit" {
    try std.testing.expectEqual(PendingOwner.types, pendingOwnerTag(.resolve_type));
    try std.testing.expectEqual(PendingOwner.calls, pendingOwnerTag(.resolve_call));
    try std.testing.expectEqual(PendingOwner.indexing, pendingOwnerTag(.resolve_index));
    try std.testing.expectEqual(PendingOwner.core, pendingOwnerTag(.resolve_field));
    try std.testing.expectEqual(PendingOwner.expressions, pendingOwnerTag(.resolve_name_use));
    try std.testing.expectEqual(PendingOwner.control, pendingOwnerTag(.resolve_match));
    try std.testing.expectEqual(PendingOwner.contracts, pendingOwnerTag(.resolve_contract));
    try std.testing.expectEqual(PendingOwner.errors, pendingOwnerTag(.resolve_error_propagation));
    try std.testing.expectEqual(PendingOwner.ownership, pendingOwnerTag(.resolve_deinit));
}

test "global semantizer accepts an empty program" {
    const allocator = std.testing.allocator;
    var result = try semantize(allocator, &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.graph.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    try std.testing.expectEqual(@as(u64, 0), result.stats.pending_attempts);
    try std.testing.expect(result.graph.constructionStateEmpty());
}

test "call diagnostic type names tolerate unresolved slots" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(allocator, @enumFromInt(0));
    var name = std.array_list.Managed(u8).init(allocator);
    defer name.deinit();
    try appendTypeName(&name, &graph, @enumFromInt(0));
    try std.testing.expectEqualStrings("<unresolved>", name.items);
}

fn reportComptimeExpressionFailure(graph: *const global_sg.GlobalSemanticGraph, diagnostics: ?*diagnostics_mod.Diagnostics, generics: *const generic_mod.Resolver) !void {
    const failure = generics.comptime_failure orelse return;
    if (diagnostics) |bag| {
        try bag.add(diagnosticLocation(graph, bag, failure.source), .semantic, "{s}", .{failure.reason});
        return error.Reported;
    }
}

fn reportGenericArgumentFailure(graph: *const global_sg.GlobalSemanticGraph, diagnostics: ?*diagnostics_mod.Diagnostics, generics: *const generic_mod.Resolver) !void {
    const sink = diagnostics orelse return;
    const failure = generics.argument_failure orelse return;
    const declaration = graph.declaration(failure.declaration);
    var source = declaration.source;
    // External type holes retain the application's location in ModuleSG.
    // Recover it only on failure, without adding source maps to hot type tables.
    for (generics.modules, 0..) |*module, module_index| {
        const offsets = generics.offsets[module_index];
        const raw = @intFromEnum(failure.ty);
        if (raw < offsets.type_base or raw - offsets.type_base >= module_views.typeCount(module)) continue;
        const local = try module_views.typeView(module, @enumFromInt(raw - offsets.type_base));
        if (local == .external) {
            const reference = module.semantic.external_refs.items[@intFromEnum(local.external)];
            source = generics.globalSource(module_index, reference.source);
        }
        break;
    }
    try sink.add(diagnosticLocation(graph, sink, source), .semantic, "{s} for type '{s}'", .{ failure.reason, graph.text(declaration.name) });
}

fn reportParticipantConformanceFailure(allocator: std.mem.Allocator, graph: *const global_sg.GlobalSemanticGraph, diagnostics: ?*diagnostics_mod.Diagnostics, optional: ?contract_mod.ParticipantConformanceFailure) !void {
    const failure = optional orelse return;
    if (diagnostics) |bag| {
        var message = std.array_list.Managed(u8).init(allocator);
        defer message.deinit();
        if (failure.is_value_projection) {
            try appendFormatted(&message, allocator, "invalid associated constant projection '{s}': {s}", .{ failure.contract_name, failure.reason });
        } else if (failure.is_projection) {
            try appendFormatted(&message, allocator, "invalid associated type projection '{s}': {s}", .{ failure.contract_name, failure.reason });
        } else {
            try appendFormatted(&message, allocator, "invalid conformance for contract '{s}': {s}", .{ failure.contract_name, failure.reason });
        }
        if (failure.operation) |operation| {
            try appendFormatted(&message, allocator, "\n  required operation: {s}", .{operation});
            if (failure.input) |input| if (failure.output) |output| {
                try message.append(' ');
                try appendFieldShape(&message, graph, global_types.fields(graph, input).?);
                try message.appendSlice(" -> ");
                try appendFieldShape(&message, graph, global_types.fields(graph, output).?);
            };
        }
        try bag.add(diagnosticLocation(graph, bag, failure.source), .semantic, "{s}", .{message.items});
        return error.Reported;
    }
    return error.InvalidParticipantConformance;
}

test "pending worklists retain operation identities across module extension" {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{};
    defer first.semantic.deinit(a);
    var second: module_sg.ModuleSemanticGraph = .{};
    defer second.semantic.deinit(a);
    const operation: module_entities.PendingOperation = .{ .resolve_name_use = .{ .node = @enumFromInt(0), .name = .{ .start = 0, .len = 0 } } };
    try first.semantic.pending_operations.append(a, operation);
    try second.semantic.pending_operations.append(a, operation);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    const offsets = [_]globalizer.Offsets{ std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets) };
    var pending = try PendingWorklists.init(a, modules[0..1], offsets[0..1]);
    defer pending.deinit(a);
    const queue = pending.forPhase(pendingPhase(operation));
    try std.testing.expectEqual(@as(u32, 0), queue.items[0].flat_index);
    queue.clearRetainingCapacity();
    try pending.appendModules(a, &modules, &offsets);
    try std.testing.expectEqual(@as(usize, 1), queue.items.len);
    try std.testing.expectEqual(@as(u32, 1), queue.items[0].flat_index);
    try std.testing.expectEqual(@as(u32, 1), queue.items[0].module_index);
    try pending.appendModules(a, &modules, &offsets);
    try std.testing.expectEqual(@as(usize, 1), queue.items.len);
    try std.testing.expectError(error.InvalidPendingModulePrefix, pending.appendModules(a, modules[0..1], offsets[0..1]));
}

test "resolution state preserves statuses and rolls back failed module extension" {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{};
    defer first.semantic.deinit(a);
    var second: module_sg.ModuleSemanticGraph = .{};
    defer second.semantic.deinit(a);
    const operation: module_entities.PendingOperation = .{ .resolve_name_use = .{ .node = @enumFromInt(0), .name = .{ .start = 0, .len = 0 } } };
    try first.semantic.pending_operations.append(a, operation);
    try second.semantic.pending_operations.append(a, operation);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    const offsets = [_]globalizer.Offsets{ std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets) };
    var state = ResolutionState.init(a);
    defer state.deinit(a);
    try state.appendModules(a, modules[0..1], offsets[0..1]);
    try state.finalized_functions.put(@enumFromInt(7), {});
    state.resolved.items[0] = true;
    state.invalid.items[0] = true;
    state.worklists.operation_count = std.math.maxInt(u32);
    try std.testing.expectError(error.TooManyPendingOperations, state.appendModules(a, &modules, &offsets));
    try std.testing.expectEqual(@as(usize, 1), state.resolved.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.worklists.module_count);
    try std.testing.expectEqual(@as(usize, 1), state.worklists.forPhase(pendingPhase(operation)).items.len);
    state.worklists.operation_count = 1;
    try state.appendModules(a, &modules, &offsets);
    try std.testing.expect(state.finalized_functions.contains(@enumFromInt(7)));
    try std.testing.expectEqualSlices(bool, &.{ true, false }, state.resolved.items);
    try std.testing.expectEqualSlices(bool, &.{ true, false }, state.invalid.items);
    try state.appendModules(a, &modules, &offsets);
    try std.testing.expectEqual(@as(usize, 2), state.resolved.items.len);
}

fn extendResolutionWithAllocationFailures(allocator: std.mem.Allocator) !void {
    const fixture_allocator = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{};
    defer first.semantic.deinit(fixture_allocator);
    var second: module_sg.ModuleSemanticGraph = .{};
    defer second.semantic.deinit(fixture_allocator);
    const operation: module_entities.PendingOperation = .{ .resolve_name_use = .{ .node = @enumFromInt(0), .name = .{ .start = 0, .len = 0 } } };
    try first.semantic.pending_operations.append(fixture_allocator, operation);
    try second.semantic.pending_operations.appendNTimes(fixture_allocator, operation, 32);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    const offsets = [_]globalizer.Offsets{ std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets) };
    var state = ResolutionState.init(allocator);
    defer state.deinit(allocator);
    try state.appendModules(allocator, modules[0..1], offsets[0..1]);
    state.resolved.items[0] = true;
    state.appendModules(allocator, &modules, &offsets) catch |err| {
        try std.testing.expectEqualSlices(bool, &.{true}, state.resolved.items);
        try std.testing.expectEqualSlices(bool, &.{false}, state.invalid.items);
        try std.testing.expectEqual(@as(usize, 1), state.worklists.module_count);
        try std.testing.expectEqual(@as(u32, 1), state.worklists.operation_count);
        try std.testing.expectEqual(@as(usize, 1), state.worklists.forPhase(pendingPhase(operation)).items.len);
        return err;
    };
}

test "resolution state preserves published work on allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, extendResolutionWithAllocationFailures, .{});
}

test "semantic session retains construction state until explicit publication" {
    const a = std.testing.allocator;
    var session: Session = undefined;
    try session.init(a, &.{}, .{});
    defer session.deinit();
    try std.testing.expectError(error.InvalidSemanticSessionState, session.finish());
    try session.relocation.graph.types.append(a, .{ .builtin = .Any });
    const id: global_sg.GlobalTypeId = @enumFromInt(0);
    try session.relocation.graph.markTypeUnresolved(a, id);
    try session.advance();
    try std.testing.expect(session.relocation.graph.isTypeUnresolved(id));
    try std.testing.expect(session.resolvers.core.graph == &session.relocation.graph);
    const rounds = session.resolution.progress.profile_rounds;
    try session.relocation.graph.resolveType(id, .{ .builtin = .Int32 });
    try session.advance();
    try std.testing.expect(session.resolution.progress.profile_rounds > rounds);
    var result = try session.finish();
    defer result.graph.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), result.graph.types.items.len);
    try std.testing.expectEqual(primitives.BuiltinType.Int32, result.graph.types.items[0].builtin);
    try std.testing.expectEqual(@as(usize, 0), session.relocation.graph.types.items.len);
    try std.testing.expectError(error.InvalidSemanticSessionState, session.advance());
    try std.testing.expectError(error.InvalidSemanticSessionState, session.finish());
}

fn initializeSemanticSessionWithAllocationFailures(allocator: std.mem.Allocator) !void {
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try std.testing.allocator.dupe(u8, "session") };
    defer module.deinit(std.testing.allocator);
    var session: Session = undefined;
    try session.init(allocator, &.{module}, .{});
    defer session.deinit();
    try session.advance();
    var result = try session.finish();
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.graph.modules.items.len);
}

test "semantic session releases partially initialized state on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initializeSemanticSessionWithAllocationFailures, .{});
}

test "semantic session forbids reuse after publication fails" {
    const a = std.testing.allocator;
    var session: Session = undefined;
    try session.init(a, &.{}, .{});
    defer session.deinit();
    try session.relocation.graph.types.append(a, .{ .builtin = .Any });
    try session.relocation.graph.markTypeUnresolved(a, @enumFromInt(0));
    try session.advance();
    try std.testing.expectError(error.UnsupportedGlobalSemantic, session.finish());
    try std.testing.expectError(error.InvalidSemanticSessionState, session.advance());
    try std.testing.expectError(error.InvalidSemanticSessionState, session.finish());
}

test "semantic session appends modules and resumes with stable type identities" {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "first") };
    defer first.deinit(a);
    try first.semantic.types.append(a, .{ .resolved = .{ .builtin = .Int32 } });
    var second: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "second") };
    defer second.deinit(a);
    try second.semantic.types.append(a, .{ .resolved = .{ .builtin = .UInt8 } });
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    var session: Session = undefined;
    try session.init(a, modules[0..1], .{ .exhaustive_function_bodies = false });
    defer session.deinit();
    try session.advance();
    const first_id = globalizer.globalType(session.relocation.offsets.items[0], @enumFromInt(0));
    try session.appendModules(&modules);
    try std.testing.expectError(error.InvalidSemanticSessionState, session.finish());
    try std.testing.expectEqual(@as(usize, 2), session.resolvers.core.modules.len);
    try std.testing.expectEqual(first_id, globalizer.globalType(session.relocation.offsets.items[0], @enumFromInt(0)));
    const checkpoint = session.relocation.graph.checkpoint();
    try session.appendModules(&modules);
    try std.testing.expectEqualDeep(checkpoint, session.relocation.graph.checkpoint());
    try session.advance();
    const second_id = globalizer.globalType(session.relocation.offsets.items[1], @enumFromInt(0));
    var result = try session.finish();
    defer result.graph.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), result.graph.modules.items.len);
    try std.testing.expectEqual(primitives.BuiltinType.Int32, result.graph.types.items[@intFromEnum(first_id)].builtin);
    try std.testing.expectEqual(primitives.BuiltinType.UInt8, result.graph.types.items[@intFromEnum(second_id)].builtin);
}

fn cloneResolutionWithAllocationFailures(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var source = ResolutionState.init(a);
    defer source.deinit(a);
    source.worklists.module_count = 1;
    source.worklists.operation_count = 1;
    try source.worklists.types_and_generics.append(a, .{ .module_index = 0, .operation_index = 0, .flat_index = 0, .owner_function = null });
    try source.resolved.append(a, false);
    try source.invalid.append(a, false);
    try source.finalized_functions.put(@enumFromInt(3), {});
    source.progress.profile_rounds = 7;
    var candidate = try source.clone(allocator);
    defer candidate.deinit(allocator);
    candidate.resolved.items[0] = true;
    candidate.invalid.items[0] = true;
    candidate.worklists.types_and_generics.clearRetainingCapacity();
    _ = candidate.finalized_functions.remove(@enumFromInt(3));
    candidate.progress.profile_rounds += 1;
    try std.testing.expect(!source.resolved.items[0]);
    try std.testing.expect(!source.invalid.items[0]);
    try std.testing.expectEqual(@as(usize, 1), source.worklists.types_and_generics.items.len);
    try std.testing.expect(source.finalized_functions.contains(@enumFromInt(3)));
    try std.testing.expectEqual(@as(usize, 7), source.progress.profile_rounds);
    try std.testing.expectEqual(@as(usize, 8), candidate.progress.profile_rounds);
}

test "resolution state clones isolate pending work and finalization" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneResolutionWithAllocationFailures, .{});
}

fn forkSemanticSession(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "accepted") };
    defer module.deinit(a);
    try module.semantic.types.append(a, .{ .resolved = .{ .builtin = .Int32 } });
    var accepted: Session = undefined;
    try accepted.init(a, &.{module}, .{ .exhaustive_function_bodies = false });
    defer accepted.deinit();
    try accepted.advance();
    const saved = accepted.relocation.graph.checkpoint();
    const saved_rounds = accepted.resolution.progress.profile_rounds;
    var candidate: Session = undefined;
    try accepted.fork(&candidate, allocator, null);
    defer candidate.deinit();
    try std.testing.expect(candidate.resolvers.core.graph == &candidate.relocation.graph);
    try std.testing.expect(candidate.resolvers.generics.core == &candidate.resolvers.core);
    try candidate.relocation.graph.types.append(allocator, .{ .builtin = .Any });
    try candidate.relocation.graph.markTypeUnresolved(allocator, @enumFromInt(1));
    try candidate.advance();
    try std.testing.expectError(error.UnsupportedGlobalSemantic, candidate.finish());
    try std.testing.expectEqualDeep(saved, accepted.relocation.graph.checkpoint());
    try std.testing.expectEqual(saved_rounds, accepted.resolution.progress.profile_rounds);
    try accepted.advance();
    var result = try accepted.finish();
    defer result.graph.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), result.graph.types.items.len);
    try std.testing.expectEqual(primitives.BuiltinType.Int32, result.graph.types.items[0].builtin);
}

test "semantic session forks reject candidate edits without changing accepted state" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, forkSemanticSession, .{});
}

test "semantic session forks prepare independent module additions" {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "retained") };
    defer first.deinit(a);
    try first.semantic.types.append(a, .{ .resolved = .{ .builtin = .Int32 } });
    var second: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "submission") };
    defer second.deinit(a);
    try second.semantic.types.append(a, .{ .resolved = .{ .builtin = .UInt8 } });
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    var accepted: Session = undefined;
    try accepted.init(a, modules[0..1], .{});
    defer accepted.deinit();
    try std.testing.expectError(error.InvalidSemanticSessionState, accepted.fork(&accepted, a, null));
    try accepted.advance();
    const saved = accepted.relocation.graph.checkpoint();
    var candidate: Session = undefined;
    try accepted.fork(&candidate, a, null);
    defer candidate.deinit();
    try candidate.appendModules(&modules);
    try candidate.advance();
    try std.testing.expectEqual(@as(usize, 2), candidate.resolvers.core.modules.len);
    try std.testing.expectEqual(@as(usize, 1), accepted.resolvers.core.modules.len);
    try std.testing.expectEqualDeep(saved, accepted.relocation.graph.checkpoint());
    var result = try candidate.finish();
    defer result.graph.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), result.graph.modules.items.len);
    try std.testing.expectEqual(primitives.BuiltinType.Int32, result.graph.types.items[0].builtin);
    try std.testing.expectEqual(primitives.BuiltinType.UInt8, result.graph.types.items[1].builtin);
    try std.testing.expectEqualDeep(saved, accepted.relocation.graph.checkpoint());
}
