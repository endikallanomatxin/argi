const std = @import("std");
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
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_mod = @import("generics.zig");
const generic_functions_mod = @import("generic_functions.zig");
const abstract_mod = @import("abstracts.zig");
const error_mod = @import("errors.zig");
const ownership_mod = @import("ownership.zig");
const resolution = @import("resolution.zig");
const dispatch_mod = @import("dispatch.zig");
const reachability_mod = @import("reachability.zig");
const reach_context = @import("reach_context.zig");

pub const Options = struct {
    selected_test_name: ?[]const u8 = null,
    exhaustive_function_bodies: bool = true,
    diagnostics: ?*diagnostics_mod.Diagnostics = null,
    profile_io: ?std.Io = null,
};

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
        fixed_point_ns: u64 = 0,
        pending_ns: u64 = 0,
        type_reconciliation_ns: u64 = 0,
        binding_reconciliation_ns: u64 = 0,
        runtime_binding_defaults_ns: u64 = 0,
        string_literal_types_ns: u64 = 0,
        binding_types_ns: u64 = 0,
        assignment_values_ns: u64 = 0,
        dereferences_ns: u64 = 0,
        addresses_ns: u64 = 0,
        known_generic_types_ns: u64 = 0,
        abstract_field_storage_ns: u64 = 0,
        sugar_types_ns: u64 = 0,
        error_inference_ns: u64 = 0,
        cleanup_ns: u64 = 0,
        implicit_destructor_ns: u64 = 0,
        implicit_generic_lookup_ns: u64 = 0,
        generic_constraints_ns: u64 = 0,
        generic_selection_prefilter_ns: u64 = 0,
        generic_selection_constraints_ns: u64 = 0,
        generic_selection_scoring_ns: u64 = 0,
        generic_selection_arguments_ns: u64 = 0,
        generic_selection_instantiation_ns: u64 = 0,
        source_generic_selection_ns: u64 = 0,
        source_generic_completion_ns: u64 = 0,
        generic_instantiation_ns: u64 = 0,
        generic_instantiation_lookup_ns: u64 = 0,
        generic_instantiation_body_ns: u64 = 0,
        generic_instance_context_init_ns: u64 = 0,
        named_call_empty_initializer_ns: u64 = 0,
        named_call_reach_copy_ns: u64 = 0,
        named_call_ordinary_lookup_ns: u64 = 0,
        named_call_generic_selection_ns: u64 = 0,
        named_call_completion_ns: u64 = 0,
        resolved_body_node_ns: u64 = 0,
        pending_body_node_ns: u64 = 0,
        post_resolution_ns: u64 = 0,
        verify_ns: u64 = 0,
    };

    core: core_mod.Stats = .{},
    expressions: expression_mod.Stats = .{},
    control: control_mod.Stats = .{},
    generics: generic_mod.Stats = .{},
    generic_functions: generic_functions_mod.Stats = .{},
    generic_selection: generic_functions_mod.SelectionProfile = .{},
    abstracts: abstract_mod.Stats = .{},
    errors: error_mod.Stats = .{},
    ownership: ownership_mod.Stats = .{},
    implicit_lookup: dispatch_mod.ImplicitLookupStats = .{},
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
    cached_implementation_hits: u64 = 0,
    cached_nonimplementation_hits: u64 = 0,
    generic_instantiation_calls: u64 = 0,
    generic_existing_instances: u64 = 0,
    generic_bodies_built: u64 = 0,
    generic_bodies_unreachable: u64 = 0,
    generic_reachability_tracked: bool = false,
    resolved_body_nodes: u64 = 0,
    pending_body_nodes: u64 = 0,
    pending_body_kinds: [@typeInfo(@import("../module/parameterized/ir.zig").Pending).@"union".fields.len]generic_functions_mod.BodyNodeProfile = @splat(.{}),
    expression_kinds: [@typeInfo(@import("../module/parameterized/ir.zig").PendingExpressionKind).@"enum".fields.len]generic_functions_mod.BodyNodeProfile = @splat(.{}),
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
    abstracts,
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
    control_and_abstracts,
    errors,
    ownership,
};

const pending_phases = [_]PendingPhase{
    .types_and_generics,
    .expressions_and_calls,
    .control_and_abstracts,
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
    control_and_abstracts: std.ArrayList(PendingWorkItem) = .empty,
    errors: std.ArrayList(PendingWorkItem) = .empty,
    ownership: std.ArrayList(PendingWorkItem) = .empty,

    fn init(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !PendingWorklists {
        var result: PendingWorklists = .{};
        errdefer result.deinit(allocator);
        var flat: u32 = 0;
        for (modules, 0..) |*module, module_index| {
            for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
                try result.forPhase(pendingPhase(operation)).append(allocator, .{
                    .module_index = @intCast(module_index),
                    .operation_index = @intCast(operation_index),
                    .flat_index = flat,
                    .owner_function = if (operation_index < module.semantic.pending_owner_functions.items.len)
                        if (module.semantic.pending_owner_functions.items[operation_index]) |owner|
                            globalizer.globalFunction(offsets[module_index], owner)
                        else
                            null
                    else
                        null,
                });
                flat = std.math.add(u32, flat, 1) catch return error.TooManyPendingOperations;
            }
        }
        return result;
    }

    fn deinit(self: *PendingWorklists, allocator: std.mem.Allocator) void {
        self.types_and_generics.deinit(allocator);
        self.expressions_and_calls.deinit(allocator);
        self.control_and_abstracts.deinit(allocator);
        self.errors.deinit(allocator);
        self.ownership.deinit(allocator);
    }

    fn forPhase(self: *PendingWorklists, phase: PendingPhase) *std.ArrayList(PendingWorkItem) {
        return switch (phase) {
            .types_and_generics => &self.types_and_generics,
            .expressions_and_calls => &self.expressions_and_calls,
            .control_and_abstracts => &self.control_and_abstracts,
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
            .control_and_abstracts => &self.control_and_abstracts,
            .errors => &self.errors,
            .ownership => &self.ownership,
        };
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
    const profile_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);
    errdefer relocation.deinit(allocator);
    try module_linker.link(allocator, &relocation.graph, modules, relocation.offsets.items);
    const profile_relocated = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;

    // The globalizer preallocates stable GlobalTypeId slots. Record which of
    // those slots are genuinely unresolved before any resolver can inspect
    // them; unresolved is construction state, not the language type `Any`.
    try markUnresolvedTypeSlots(allocator, &relocation.graph, modules, relocation.offsets.items);

    var core = core_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .profile_io = options.profile_io,
    };
    if (try resolveQualifiedChoiceOptions(&core, options.diagnostics)) return error.Reported;
    var expressions = expression_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
    };
    var constructors = constructor_mod.Resolver{
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var control = control_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var generics = generic_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .profile_io = options.profile_io,
    };
    defer generics.deinit();
    var generic_functions = generic_functions_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
        .profile_io = options.profile_io,
    };
    var abstracts = abstract_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
        .profile_implementation_scans = options.profile_io != null,
        .profile_io = options.profile_io,
    };
    constructors.abstracts = &abstracts;
    control.generic_functions = &generic_functions;
    control.abstracts = &abstracts;
    defer abstracts.deinit();
    generic_functions.nested_call_context = &abstracts;
    generic_functions.nested_call_resolver = abstract_mod.Resolver.resolveNestedCall;
    generic_functions.nested_constructor_context = &constructors;
    generic_functions.nested_constructor_resolver = constructor_mod.Resolver.resolveNestedCall;
    // These resolvers call back into one another while materializing generic
    // bodies, so wire their stable stack-owned instances after both exist.
    constructors.generics = &generics;
    constructors.generic_functions = &generic_functions;
    var errors = error_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var dispatch = dispatch_mod.Resolver{
        .core = &core,
        .generic_functions = &generic_functions,
        .constructors = &constructors,
        .abstracts = &abstracts,
        .control = &control,
        .errors = &errors,
        .profile_io = options.profile_io,
    };
    var ownership = ownership_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .dispatch = &dispatch,
        .profile_io = options.profile_io,
    };
    defer ownership.deinit();
    generic_functions.ownership_context = &ownership;
    generic_functions.register_defer = ownership_mod.Resolver.registerParameterizedDefer;

    try core.resolveExternalTypes();
    try generics.resolveExternalTypes();
    _ = relocation.graph.reconcileTypeResolution();
    _ = try generics.materializeKnownTypes();
    _ = try control.materializeSugarTypes();

    if (options.diagnostics) |diagnostics| {
        if (try abstracts.findConcreteImplementationConflict()) |conflict| {
            var concrete_name = std.array_list.Managed(u8).init(allocator);
            defer concrete_name.deinit();
            try appendTypeName(&concrete_name, &relocation.graph, conflict.concrete);
            try diagnostics.add(
                diagnosticLocation(&relocation.graph, diagnostics, conflict.source),
                .semantic,
                "conflicting implementations of abstract '{s}' for type '{s}' produce different associated arguments",
                .{
                    relocation.graph.text(relocation.graph.declaration(conflict.abstract_decl).name),
                    concrete_name.items,
                },
            );
            return error.Reported;
        }

        if (try abstracts.findConcreteRequirementFailure()) |failure| {
            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try appendFormatted(
                &message,
                allocator,
                "type does not implement abstract '{s}':\n  missing function: {s} ",
                .{
                    relocation.graph.text(relocation.graph.declaration(failure.abstract_decl).name),
                    failure.method_name,
                },
            );
            const expected_input = global_types.fields(&relocation.graph, failure.input) orelse return error.InvalidAbstractRequirementInput;
            try appendFieldShape(&message, &relocation.graph, expected_input);

            var candidate_count: usize = 0;
            for (relocation.graph.functions.items) |function| {
                const declaration = relocation.graph.declaration(function.declaration);
                if (!std.mem.eql(u8, relocation.graph.text(declaration.name), failure.method_name)) continue;
                if (!abstracts.requirementCandidateInputMatches(failure.input, function)) continue;
                candidate_count += 1;
            }
            if (candidate_count != 0) {
                try message.appendSlice("\n  possible overloads:");
                for (relocation.graph.functions.items) |function| {
                    const declaration = relocation.graph.declaration(function.declaration);
                    if (!std.mem.eql(u8, relocation.graph.text(declaration.name), failure.method_name)) continue;
                    if (!abstracts.requirementCandidateInputMatches(failure.input, function)) continue;
                    try appendFormatted(&message, allocator, "\n  - {s} ", .{failure.method_name});
                    try appendFieldShape(&message, &relocation.graph, function.input);
                    try message.appendSlice(" -> ");
                    try appendFieldShape(&message, &relocation.graph, function.output);
                    const function_location = diagnosticLocation(&relocation.graph, diagnostics, declaration.source);
                    const position = diagnostics.lineColumn(function_location);
                    try appendFormatted(
                        &message,
                        allocator,
                        "\n      file: {s}:{d}:{d}",
                        .{ diagnostics.path(function_location), position.line, position.column },
                    );
                }
            }

            try diagnostics.add(
                diagnosticLocation(&relocation.graph, diagnostics, failure.source),
                .semantic,
                "{s}",
                .{message.items},
            );
            return error.Reported;
        }

        for (relocation.graph.functions.items) |function| {
            for (relocation.graph.fields.items[function.output.start..][0..function.output.len]) |field| {
                const abstract_use = abstracts.typeAbstractUse(field.ty) orelse continue;
                if ((try abstracts.defaultType(abstract_use.declaration, abstract_use.arguments)) != null) continue;
                const declaration = relocation.graph.declaration(function.declaration);
                try diagnostics.add(
                    diagnosticLocation(&relocation.graph, diagnostics, declaration.source),
                    .codegen,
                    "error generating function {s}: InvalidType",
                    .{relocation.graph.text(declaration.name)},
                );
                return error.Reported;
            }
        }
    }

    const total = totalPending(modules);
    const resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);
    const invalid = try allocator.alloc(bool, total);
    defer allocator.free(invalid);
    @memset(invalid, false);
    var worklists = try PendingWorklists.init(allocator, modules, relocation.offsets.items);
    defer worklists.deinit(allocator);
    var pending_resolution_stats: PendingResolutionStats = .{};
    if (options.profile_io != null) {
        for (modules) |module| for (module.semantic.pending_operations.items) |operation| {
            pending_resolution_stats.initial(operation);
        };
    }
    var reachable_storage: reachability_mod.FunctionSet = undefined;
    var reachable: ?*reachability_mod.FunctionSet = null;
    if (!options.exhaustive_function_bodies) {
        reachable_storage = try reachability_mod.roots(allocator, &relocation.graph, options.selected_test_name);
        reachable = &reachable_storage;
    }
    defer if (reachable) |set| set.deinit();
    var pending_attempts: u64 = 0;
    const profile_preloop = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
    var profile_rounds: usize = 0;
    var profile_pending_ns: i96 = 0;
    var profile_type_reconciliation_ns: i96 = 0;
    var profile_binding_reconciliation_ns: i96 = 0;
    var profile_runtime_binding_defaults_ns: i96 = 0;
    var profile_string_literal_types_ns: i96 = 0;
    var profile_binding_types_ns: i96 = 0;
    var profile_assignment_values_ns: i96 = 0;
    var profile_dereferences_ns: i96 = 0;
    var profile_addresses_ns: i96 = 0;
    var profile_known_generic_types_ns: i96 = 0;
    var profile_abstract_field_storage_ns: i96 = 0;
    var profile_sugar_types_ns: i96 = 0;
    var profile_errors_ns: i96 = 0;
    var profile_finalize_ns: i96 = 0;
    var profile_finalize_count: usize = 0;

    // GlobalSema is staged by semantic domain. Ownership finalization can add
    // cleanup calls to functions absent from the source call graph. Each newly
    // reachable body gets another resolution pass before its cleanup is built.
    var finalized_functions = std.AutoHashMap(global_sg.GlobalFunctionId, void).init(allocator);
    defer finalized_functions.deinit();
    var changed = true;
    while (true) {
        while (changed) {
            profile_rounds += 1;
            // Pending resolution can fill existing type slots without growing
            // a pool, so failed conformance checks cannot cross rounds.
            abstracts.invalidate_negative_implementation_cache();
            changed = false;
            const pending_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            for (pending_phases) |phase| {
                if (try resolvePendingPhase(
                    &core,
                    &expressions,
                    &dispatch,
                    &control,
                    &generics,
                    &abstracts,
                    &errors,
                    &ownership,
                    modules,
                    relocation.offsets.items,
                    resolved,
                    invalid,
                    worklists.forPhase(phase),
                    reachable,
                    &pending_attempts,
                    if (options.profile_io != null) &pending_resolution_stats else null,
                    options.profile_io,
                )) changed = true;
            }
            if (options.profile_io) |io| profile_pending_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - pending_start;

            var sweep_start = profileTimestamp(options.profile_io);
            if (relocation.graph.reconcileTypeResolution()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_type_reconciliation_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_binding_reconciliation_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try abstracts.materializeRuntimeBindingDefaults()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_runtime_binding_defaults_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeStringLiteralTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_string_literal_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeBindingTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_binding_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            const binding_reconciled = relocation.graph.reconcileBindingTypeResolution();
            profileAccumulate(options.profile_io, sweep_start, &profile_binding_reconciliation_ns);
            if (binding_reconciled) {
                changed = true;
                const nested_binding_start = profileTimestamp(options.profile_io);
                if (core.materializeBindingTypes()) changed = true;
                profileAccumulate(options.profile_io, nested_binding_start, &profile_binding_types_ns);
            }
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeAssignmentValues()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_assignment_values_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (core.materializeDereferences()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_dereferences_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try core.materializeAddresses()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_addresses_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try generics.materializeKnownTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_known_generic_types_ns);
            sweep_start = profileTimestamp(options.profile_io);
            if (try abstracts.materializeAbstractFieldStorage()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_abstract_field_storage_ns);
            // Generic instantiation can intern nullable or inferred Errable
            // types during this pass. Their materialization must schedule a
            // further pass so pending uses can observe the final choice shape.
            sweep_start = profileTimestamp(options.profile_io);
            if (try control.materializeSugarTypes()) changed = true;
            profileAccumulate(options.profile_io, sweep_start, &profile_sugar_types_ns);
            const errors_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            if (try errors.inferFunctionErrorReasons()) changed = true;
            if (options.profile_io) |io| profile_errors_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - errors_start;
            if (try completePropagatedReachCalls(&core, modules, relocation.offsets.items)) changed = true;
            if (reachable) |set| {
                if (try reachability_mod.expand(allocator, &relocation.graph, set)) changed = true;
            }
        }
        abstracts.invalidate_negative_implementation_cache();
        var finalized_any = false;
        const finalization_count = relocation.graph.functions.items.len;
        var raw: usize = 0;
        while (raw < finalization_count) : (raw += 1) {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (finalized_functions.contains(id)) continue;
            if (reachable) |set| {
                if (!set.contains(id)) continue;
            }
            if (relocation.graph.functions.items[raw].body == null) continue;
            const finalize_start = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const did_finalize = try ownership.finalizeFunctionBody(id);
            if (options.profile_io) |io| profile_finalize_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - finalize_start;
            profile_finalize_count += 1;
            if (!did_finalize) continue;
            try finalized_functions.put(id, {});
            finalized_any = true;
        }
        const reached_cleanup = if (reachable) |set|
            try reachability_mod.expand(allocator, &relocation.graph, set)
        else
            false;
        if (!finalized_any and !reached_cleanup) break;
        changed = true;
    }
    const profile_postloop = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;

    try abstracts.validateGenericFunctionInstances();
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
                "for expects a type implementing abstract '{s}', got '{s}'",
                .{ failure.contract_name, actual_name.items },
            );
            return error.Reported;
        }
        return error.InvalidForEach;
    }

    if (abstracts.field_storage_conflict) |conflict| {
        if (options.diagnostics) |diagnostics| {
            var abstract_name = std.array_list.Managed(u8).init(allocator);
            defer abstract_name.deinit();
            var existing_name = std.array_list.Managed(u8).init(allocator);
            defer existing_name.deinit();
            var actual_name = std.array_list.Managed(u8).init(allocator);
            defer actual_name.deinit();
            try appendTypeName(&abstract_name, &relocation.graph, conflict.abstract_type);
            try appendTypeName(&existing_name, &relocation.graph, conflict.existing_type);
            try appendTypeName(&actual_name, &relocation.graph, conflict.actual_type);
            try diagnostics.add(
                diagnosticLocation(&relocation.graph, diagnostics, conflict.source),
                .semantic,
                "field '.{s}' already stores '{s}' for abstract type '{s}', so it cannot also store '{s}'",
                .{ relocation.graph.text(conflict.field_name), existing_name.items, abstract_name.items, actual_name.items },
            );
            return error.Reported;
        }
        return error.ConflictingAbstractFieldStorage;
    }

    if (options.diagnostics) |diagnostics| {
        if (try diagnoseUnresolvedPropagatedReach(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
            return error.Reported;
        if (try diagnosePrivateFields(&relocation.graph, modules, reachable, relocation.offsets.items, diagnostics))
            return error.Reported;
        if (try diagnoseAbstractRuntimeBindings(&relocation.graph, &abstracts, diagnostics))
            return error.Reported;
    }

    const remaining = worklists.remaining(reachable);
    var resolved_count: usize = 0;
    for (resolved) |done| if (done) {
        resolved_count += 1;
    };
    if (remaining != 0) {
        if (options.diagnostics) |diagnostics| {
            if (try diagnoseUnresolvedPointerArithmetic(&relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnoseUnresolvedQualifiedNames(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
            if (try diagnoseUnresolvedCopy(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
            // A denied copy may already be represented in the graph so Safety
            // can prefer a preceding move error. If another operation remains
            // unresolved, report that definite copy failure before unrelated
            // overload diagnostics prevent Safety from running.
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
            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, &generic_functions, &abstracts, diagnostics))
                return error.Reported;
        }
        dumpUnresolved(modules, resolved, reachable, relocation.offsets.items);
        return error.UnsupportedGlobalSemantic;
    }
    _ = relocation.graph.reconcileTypeResolution();
    _ = relocation.graph.reconcileBindingTypeResolution();
    if (relocation.graph.hasUnresolvedTypes()) {
        if (options.diagnostics) |diagnostics|
            if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))
                return error.Reported;
        std.debug.print("global sema unresolved global type slots remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }
    if (relocation.graph.hasUnresolvedBindingTypes()) {
        std.debug.print("global sema unresolved binding types remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    if (try diagnoseInvalidMatchPayloadCopies(
        allocator,
        &relocation.graph,
        &ownership,
        reachable,
        options.diagnostics,
    ))
        return if (options.diagnostics != null) error.Reported else error.InvalidImplicitCopy;

    if (ownership.invalidKeep()) |keep| {
        if (options.diagnostics) |diagnostics| {
            const binding = relocation.graph.binding(keep.binding);
            try diagnostics.add(
                diagnosticLocation(&relocation.graph, diagnostics, keep.source),
                .semantic,
                "cannot keep binding '{s}': no automatic deinit is scheduled",
                .{relocation.graph.text(binding.name)},
            );
        }
        return if (options.diagnostics != null) error.Reported else error.InvalidKeep;
    }

    if (try diagnoseInvalidPointerOperations(allocator, &relocation.graph, reachable, options.diagnostics))
        return if (options.diagnostics != null) error.Reported else error.InvalidPointerOperation;

    if (options.diagnostics) |diagnostics|
        if (try abstracts.findGenericTypeConstraintFailure()) |failure| {
            var actual_name = std.array_list.Managed(u8).init(allocator);
            defer actual_name.deinit();
            try appendTypeName(&actual_name, &relocation.graph, failure.actual);
            try diagnostics.add(
                diagnosticLocation(&relocation.graph, diagnostics, failure.source),
                .semantic,
                "type '{s}' does not implement abstract '{s}' required by generic type parameter '.{s}' of '{s}'",
                .{
                    actual_name.items,
                    relocation.graph.text(relocation.graph.declaration(failure.abstract_decl).name),
                    failure.parameter_name,
                    relocation.graph.text(relocation.graph.declaration(failure.generic_decl).name),
                },
            );
            return error.Reported;
        };

    try abstracts.closeVirtualMethodRegistries();

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);
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
        .abstracts = abstracts.stats,
        .errors = errors.stats,
        .ownership = ownership.stats,
        .implicit_lookup = dispatch.implicit_lookup_stats,
        .pending_call_stages = dispatch.pending_call_stages,
        .pending_total = @intCast(total),
        .pending_resolved = @intCast(resolved_count),
        .pending_attempts = pending_attempts,
        .pending_by_owner = pending_resolution_stats.owners,
        .pending_by_operation = pending_resolution_stats.operations,
        .remaining = 0,
        .rounds = @intCast(profile_rounds),
        .cleanup_attempts = @intCast(profile_finalize_count),
        .destructor_lookups = @intCast(ownership.profile_destructor_calls),
        .cached_implementation_hits = abstracts.cached_implementation_hits,
        .cached_nonimplementation_hits = abstracts.cached_nonimplementation_hits,
        .generic_instantiation_calls = generic_functions.profile_instantiate_calls,
        .generic_existing_instances = generic_functions.profile_instantiate_existing,
        .generic_bodies_built = generic_bodies_built,
        .generic_bodies_unreachable = generic_bodies_unreachable,
        .generic_reachability_tracked = reachable != null,
        .resolved_body_nodes = generic_functions.profile_resolved_body_nodes,
        .pending_body_nodes = generic_functions.profile_pending_body_nodes,
        .pending_body_kinds = generic_functions.profile_pending_body_kinds,
        .expression_kinds = generic_functions.profile_expression_kinds,
    };

    const profile_preverify = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
    try global_verify.verifyGlobal(&relocation.graph);
    const profile_end = if (options.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
    stats.remaining = 0;
    if (options.profile_io != null) stats.timings = .{
        .relocation_ns = @intCast(profile_relocated - profile_start),
        .setup_ns = @intCast(profile_preloop - profile_relocated),
        .fixed_point_ns = @intCast(profile_postloop - profile_preloop),
        .pending_ns = @intCast(profile_pending_ns),
        .type_reconciliation_ns = @intCast(profile_type_reconciliation_ns),
        .binding_reconciliation_ns = @intCast(profile_binding_reconciliation_ns),
        .runtime_binding_defaults_ns = @intCast(profile_runtime_binding_defaults_ns),
        .string_literal_types_ns = @intCast(profile_string_literal_types_ns),
        .binding_types_ns = @intCast(profile_binding_types_ns),
        .assignment_values_ns = @intCast(profile_assignment_values_ns),
        .dereferences_ns = @intCast(profile_dereferences_ns),
        .addresses_ns = @intCast(profile_addresses_ns),
        .known_generic_types_ns = @intCast(profile_known_generic_types_ns),
        .abstract_field_storage_ns = @intCast(profile_abstract_field_storage_ns),
        .sugar_types_ns = @intCast(profile_sugar_types_ns),
        .error_inference_ns = @intCast(profile_errors_ns),
        .cleanup_ns = @intCast(profile_finalize_ns),
        .implicit_destructor_ns = @intCast(ownership.profile_destructor_ns),
        .implicit_generic_lookup_ns = @intCast(dispatch.profile_generic_ns),
        .source_generic_selection_ns = @intCast(generic_functions.profile_source_selection_ns),
        .source_generic_completion_ns = @intCast(generic_functions.profile_source_completion_ns),
        .generic_instantiation_ns = @intCast(generic_functions.profile_instantiate_ns),
        .generic_instantiation_lookup_ns = @intCast(generic_functions.profile_instantiate_lookup_ns),
        .generic_instantiation_body_ns = @intCast(generic_functions.profile_instantiate_body_ns),
        .generic_instance_context_init_ns = @intCast(generic_functions.profile_instance_context_init_ns),
        .named_call_empty_initializer_ns = @intCast(generic_functions.profile_named_call_empty_initializer_ns),
        .named_call_reach_copy_ns = @intCast(generic_functions.profile_named_call_reach_copy_ns),
        .named_call_ordinary_lookup_ns = @intCast(generic_functions.profile_named_call_ordinary_lookup_ns),
        .named_call_generic_selection_ns = @intCast(generic_functions.profile_named_call_generic_selection_ns),
        .named_call_completion_ns = @intCast(generic_functions.profile_named_call_completion_ns),
        .resolved_body_node_ns = @intCast(generic_functions.profile_resolved_body_node_ns),
        .pending_body_node_ns = @intCast(generic_functions.profile_pending_body_node_ns),
        .generic_constraints_ns = @intCast(generic_functions.profile_constraints_ns),
        .post_resolution_ns = @intCast(profile_preverify - profile_postloop),
        .verify_ns = @intCast(profile_end - profile_preverify),
    };
    return .{ .graph = relocation.takeGraph(allocator), .stats = stats };
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

fn diagnoseUnresolvedPointerArithmetic(
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
            if (graph.semanticType(left_ty) != .pointer and graph.semanticType(right_ty) != .pointer) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, graph.node(left).source),
                .semantic,
                "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
                .{},
            );
            return true;
        }
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
                if (pointer.mutability != .read_only) continue;
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
    var changed = false;
    for (modules, offsets) |*module, offset| {
        for (module.semantic.pending_operations.items) |operation| {
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const node = core.graph.nodes.items[@intFromEnum(globalizer.globalNode(offset, call.node))];
            const resolved = switch (node.content) {
                .function_call => |value| value,
                else => continue,
            };
            const input = core.graph.nodes.items[@intFromEnum(resolved.input)];
            const literal = switch (input.content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            const fields = core.graph.functions.items[@intFromEnum(resolved.callee)].input;
            if (literal.fields.len == fields.len) continue;
            const context = reach_context.Context.fromModule(module, offset, call.visible_bindings, call.owner_function);
            if (try core.completeCallInputFieldsWithReach(fields, resolved.input, context)) changed = true;
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
    abstracts: *abstract_mod.Resolver,
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
        const result = resolvePendingOperation(
            core,
            expressions,
            dispatch,
            control,
            generics,
            abstracts,
            errors,
            ownership,
            module_index,
            module,
            offsets[module_index],
            operation,
        ) catch |err| return err;
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
    const limit = @min(graph.binding_type_resolution.items.len, graph.bindings.items.len);
    for (graph.binding_type_resolution.items[0..limit], 0..) |*state, raw| {
        if (state.* != .unresolved) continue;
        const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable.containsBinding(binding)) continue;
        graph.bindings.items[raw].ty = dormant_type;
        state.* = .resolved;
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
        .resolve_abstract => .abstracts,
        .resolve_error_propagation => .errors,
        .resolve_defer,
        .resolve_keep,
        .resolve_keep_name,
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
        .abstracts,
        => .control_and_abstracts,
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
    const result = if (reference.generic_arguments != null)
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
    abstracts: *abstract_mod.Resolver,
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
        .indexing => dispatch.resolveIndex(module_index, module, o, operation),
        .core => blk: {
            const core_result = try core.tryResolve(module_index, module, o, operation);
            if (core_result == .resolved or operation != .resolve_binary) break :blk ownedResult(core_result);
            const generic_result = try dispatch.generic_functions.resolveGenericAddition(module_index, module, o, operation.resolve_binary);
            break :blk if (generic_result == .resolved) generic_result else ownedResult(core_result);
        },
        .expressions => ownedResult(try expressions.tryResolve(module_index, module, o, operation)),
        .control => ownedResult(try control.tryResolve(module_index, module, o, operation)),
        .abstracts => ownedResult(try abstracts.tryResolve(module_index, module, o, operation)),
        .errors => ownedResult(try errors.tryResolve(module_index, module, o, operation)),
        .ownership => ownedResult(try ownership.tryResolve(module_index, module, o, operation)),
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
            if (@intFromEnum(target) == module_index) continue;
            const name = module.text(reference.name);
            if (!std.mem.startsWith(u8, name, "_")) continue;
            if (!declarationNameExistsInModule(graph, target, name, &.{ .type, .abstract_type })) continue;
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
            if (@intFromEnum(owner_module) == module_index) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], access.source)),
                .semantic,
                "field '{s}' is private to its module",
                .{name},
            );
            return true;
        }
    }
    return false;
}

fn diagnoseAbstractRuntimeBindings(
    graph: *const global_sg.GlobalSemanticGraph,
    abstracts: *abstract_mod.Resolver,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (graph.bindings.items, 0..) |binding, raw| {
        const binding_id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        const abstract_use = abstracts.runtimeBindingAbstract(binding_id) orelse continue;
        if (try abstracts.hasDefaultDeclaration(abstract_use.declaration)) continue;
        const name = graph.text(graph.declarations.items[@intFromEnum(abstract_use.declaration)].name);
        try diagnostics.add(
            diagnosticLocation(graph, diagnostics, binding.source),
            .semantic,
            "cannot use abstract '{s}' as a type for a symbol. Use a concrete type or add a default concrete type to the abstract type ('{s} defaultsto <Type>')",
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

fn functionDeclarationVisibleForDiagnostic(
    graph: *const global_sg.GlobalSemanticGraph,
    current_module: usize,
    declaration: global_sg.GlobalDeclId,
    qualified_module: ?global_sg.GlobalModuleId,
) bool {
    const owner = graph.moduleForDeclaration(declaration) orelse return false;
    const own_module = @intFromEnum(owner) == current_module;
    const name = graph.text(graph.declarations.items[@intFromEnum(declaration)].name);
    if (!own_module and std.mem.startsWith(u8, name, "_")) return false;
    if (qualified_module) |wanted| return owner == wanted;
    return own_module or graph.modules.items[@intFromEnum(owner)].is_bundled_core;
}

fn visibleFunctionNameExists(
    graph: *const global_sg.GlobalSemanticGraph,
    current_module: usize,
    qualified_module: ?global_sg.GlobalModuleId,
    name: []const u8,
) bool {
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .function and declaration.kind != .test_function) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (functionDeclarationVisibleForDiagnostic(graph, current_module, id, qualified_module)) return true;
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
                        graph.node(target).ty orelse continue;
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
                    if (graph.isTypeUnresolved(choice_ty) or global_types.variants(graph, choice_ty) == null) continue;
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
    abstracts: *abstract_mod.Resolver,
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

            if (reference.module_path) |path| {
                const target = qualified_module orelse continue;
                const has_name = declarationNameExistsInModule(graph, target, name, &.{ .function, .test_function });
                if (has_name and @intFromEnum(target) != module_index and std.mem.startsWith(u8, name, "_")) {
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
            } else if (!visibleFunctionNameExists(graph, module_index, null, name)) {
                // A type constructor with a visible initializer is still a
                // constructor call when its arguments fail overload matching.
                // Report the initializer signatures instead of treating the
                // type name as a missing function.
                for (graph.declarations.items, 0..) |declaration, raw_decl| {
                    if (declaration.kind != .type or !std.mem.eql(u8, graph.text(declaration.name), name)) continue;
                    const type_id = declaration.type_id orelse continue;
                    var constructor_core = core_mod.Resolver{
                        .allocator = allocator,
                        .graph = graph,
                        .modules = modules,
                        .offsets = offsets,
                    };
                    if (!constructor_core.declarationVisible(module_index, @enumFromInt(@as(u32, @intCast(raw_decl))), null)) continue;
                    const input_id = globalizer.globalNode(offsets[module_index], call.input);
                    const input = switch (graph.node(input_id).content) {
                        .struct_value_literal => |value| value,
                        else => continue,
                    };
                    var message = std.array_list.Managed(u8).init(allocator);
                    defer message.deinit();
                    for (graph.functions.items) |function| {
                        const init_decl = graph.declaration(function.declaration);
                        if (!std.mem.eql(u8, graph.text(init_decl.name), "init") or function.input.len == 0) continue;
                        if (!constructor_core.declarationVisible(module_index, function.declaration, null)) continue;
                        const receiver = graph.fields.items[function.input.start].ty;
                        const pointer = switch (graph.types.items[@intFromEnum(receiver)]) {
                            .pointer => |value| value,
                            else => continue,
                        };
                        if (!global_types.equal(graph, pointer.child, type_id)) continue;
                        if (message.items.len == 0) {
                            try message.print("failed to initialize type '{s}': no visible 'init' overload accepts arguments ", .{name});
                            try appendValueShape(&message, graph, input);
                            try message.appendSlice(". Available overloads:");
                        }
                        try message.appendSlice("\n  - init ");
                        try appendFieldShape(&message, graph, function.input);
                        try message.appendSlice(" -> ");
                        try appendFieldShape(&message, graph, function.output);
                    }
                    if (message.items.len != 0) {
                        try diagnostics.add(location, .semantic, "{s}", .{message.items});
                        return true;
                    }
                }
                try diagnostics.add(location, .semantic, "no function named '{s}' exists", .{name});
                return true;
            }

            const input_id = globalizer.globalNode(offsets[module_index], call.input);
            const input = switch (graph.node(input_id).content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
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
            if (!input_complete) continue;

            var candidates: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer candidates.deinit(allocator);
            for (graph.functions.items, 0..) |function, raw| {
                const declaration = graph.declaration(function.declaration);
                if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
                if (!functionDeclarationVisibleForDiagnostic(graph, module_index, function.declaration, qualified_module)) continue;
                try candidates.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));
            }
            if (candidates.items.len == 0) {
                if (generic_functions.hasVisibleParameterizedFunctionName(module_index, name, qualified_module)) {
                    var generic_ties: std.ArrayList(global_sg.GlobalDeclId) = .empty;
                    defer generic_ties.deinit(allocator);
                    if (try generic_functions.collectImplicitGenericAmbiguity(
                        module_index,
                        module,
                        reference,
                        input_id,
                        &generic_ties,
                    )) {
                        var ambiguity = std.array_list.Managed(u8).init(allocator);
                        defer ambiguity.deinit();
                        try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                        try appendValueShape(&ambiguity, graph, input);
                        try ambiguity.appendSlice(". Possible overloads:");
                        try diagnostics.add(
                            if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "{s}",
                            .{ambiguity.items},
                        );
                        return true;
                    }

                    try diagnostics.add(
                        if (reference.module_path != null) location else diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "no function named '{s}' exists",
                        .{name},
                    );
                    return true;
                }
                continue;
            }

            // Reuse Core's matcher to distinguish a deterministic ambiguity
            // from a genuine no-match. Resolution and diagnostics must agree
            // on compatibility and scoring rather than maintaining parallel
            // overload rules.
            var diagnostic_core = core_mod.Resolver{
                .allocator = allocator,
                .graph = graph,
                .modules = modules,
                .offsets = offsets,
            };
            var best_matches: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer best_matches.deinit(allocator);
            var best_score: ?u32 = null;
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                if (function.flags.is_abstract_dispatch) continue;
                const score = switch (diagnostic_core.matchCallInput(function.input, input_id)) {
                    .score => |value| value,
                    .no_match, .deferred => continue,
                };
                if (best_score == null or score > best_score.?) {
                    best_score = score;
                    best_matches.clearRetainingCapacity();
                    try best_matches.append(allocator, candidate);
                } else if (score == best_score.?) {
                    try best_matches.append(allocator, candidate);
                }
            }
            if (best_matches.items.len > 1) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Possible overloads:");
                for (best_matches.items) |candidate| {
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

            var generic_ties: std.ArrayList(global_sg.GlobalDeclId) = .empty;
            defer generic_ties.deinit(allocator);
            if (try generic_functions.collectImplicitGenericAmbiguity(
                module_index,
                module,
                reference,
                input_id,
                &generic_ties,
            )) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try appendAmbiguousCallPrefix(&ambiguity, graph, diagnostics, source, module, reference);
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Possible overloads:");
                for (generic_ties.items) |declaration_id| {
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
                var missing_abstract: ?struct {
                    actual: global_sg.GlobalTypeId,
                    abstract_type: global_sg.GlobalTypeId,
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

                    var expected_abstract_type = field.ty;
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
                            expected_abstract_type = expected_pointer.child;
                            actual_concrete = actual_pointer.child;
                        },
                        else => {},
                    }

                    const declaration = abstracts.abstractDeclarationForType(expected_abstract_type) orelse {
                        other_mismatch = true;
                        continue;
                    };
                    if (abstracts.concreteImplements(actual_concrete, expected_abstract_type)) {
                        other_mismatch = true;
                        continue;
                    }
                    if (missing_abstract != null) {
                        other_mismatch = true;
                    } else {
                        missing_abstract = .{
                            .actual = actual_concrete,
                            .abstract_type = expected_abstract_type,
                            .declaration = declaration,
                            .field = field,
                            .source = graph.node(supplied_node).source,
                        };
                    }
                }
                if (!other_mismatch) if (missing_abstract) |missing| {
                    var actual_name = std.array_list.Managed(u8).init(allocator);
                    defer actual_name.deinit();
                    try appendTypeName(&actual_name, graph, missing.actual);
                    var message = std.array_list.Managed(u8).init(allocator);
                    defer message.deinit();
                    try appendFormatted(
                        &message,
                        allocator,
                        "type '{s}' does not implement abstract '{s}' required by parameter '.{s}' of '{s}'",
                        .{
                            actual_name.items,
                            graph.text(graph.declaration(missing.declaration).name),
                            graph.text(missing.field.name),
                            name,
                        },
                    );
                    if (try abstracts.requirementFailureForAbstractType(
                        missing.actual,
                        missing.abstract_type,
                        missing.source,
                    )) |requirement_failure| {
                        try message.appendSlice(":\nmissing function: ");
                        try message.appendSlice(requirement_failure.method_name);
                        try message.append(' ');
                        const required_input = global_types.fields(graph, requirement_failure.input) orelse return false;
                        try appendFieldShape(&message, graph, required_input);

                        var candidate_count: usize = 0;
                        for (graph.functions.items) |candidate| {
                            const declaration = graph.declaration(candidate.declaration);
                            if (!std.mem.eql(u8, graph.text(declaration.name), requirement_failure.method_name)) continue;
                            if (!abstracts.requirementCandidateInputMatches(requirement_failure.input, candidate)) continue;
                            candidate_count += 1;
                        }
                        if (candidate_count != 0) {
                            try message.appendSlice("\npossible overloads:");
                            for (graph.functions.items) |candidate| {
                                const candidate_declaration = graph.declaration(candidate.declaration);
                                if (!std.mem.eql(u8, graph.text(candidate_declaration.name), requirement_failure.method_name)) continue;
                                if (!abstracts.requirementCandidateInputMatches(requirement_failure.input, candidate)) continue;
                                try message.appendSlice("\n  - ");
                                try message.appendSlice(requirement_failure.method_name);
                                try message.append(' ');
                                try appendFieldShape(&message, graph, candidate.input);
                                try message.appendSlice(" -> ");
                                try appendFieldShape(&message, graph, candidate.output);
                                const candidate_location = diagnosticLocation(graph, diagnostics, candidate_declaration.source);
                                const position = diagnostics.lineColumn(candidate_location);
                                try appendFormatted(
                                    &message,
                                    allocator,
                                    "\n      file: {s}:{d}:{d}",
                                    .{ diagnostics.path(candidate_location), position.line, position.column },
                                );
                            }
                        }
                    }
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
                if (diagnostic_core.matchCallInput(function.input, input_id) != .score) continue;
                if (try appendOmittedReachDefaults(&reach_details, graph, name, function, input))
                    reach_candidate_count += 1;
            }
            if (reach_candidate_count != 0) {
                var message = std.array_list.Managed(u8).init(allocator);
                defer message.deinit();
                try message.print("function '{s}' exists, but no overload matches the provided arguments.\nOverloads with omitted #reach defaults:\n", .{name});
                try message.appendSlice(reach_details.items);
                try message.appendSlice("\n\nAdd a reachable value in the caller, for example:\n  main(.system: System = System()) -> (.status_code: Int32 = 0) := { ... }\n\nOr pass the omitted argument explicitly.");
                try diagnostics.add(location, .semantic, "{s}", .{message.items});
                return true;
            }

            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try message.appendSlice("no overload of '");
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
        try buffer.appendSlice(" = #reach ");
        try appendReachAlternatives(buffer, graph, reach_id);
    }
    try buffer.appendSlice(") -> ");
    try appendFieldShape(buffer, graph, function.output);
    try buffer.appendSlice("\n    omitted #reach defaults:");

    for (graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, field_index| {
        if (callInputSuppliesField(graph, input, field, field_index)) continue;
        const fallback = field.default_value orelse continue;
        const reach_id = switch (graph.node(fallback).content) {
            .reach_directive => |value| value,
            else => continue,
        };
        try buffer.appendSlice("\n      - .");
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(" uses #reach [");
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
                    .resolve_keep_name => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_keep_name name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
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
    try std.testing.expectEqual(PendingOwner.abstracts, pendingOwnerTag(.resolve_abstract));
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
    try std.testing.expectEqual(@as(usize, 0), result.graph.type_resolution.items.len);
}
