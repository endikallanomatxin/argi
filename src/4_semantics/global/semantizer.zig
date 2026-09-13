const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const global_sg = @import("graph.zig");
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

pub const Stats = struct {
    core: core_mod.Stats = .{},
    expressions: expression_mod.Stats = .{},
    control: control_mod.Stats = .{},
    generics: generic_mod.Stats = .{},
    generic_functions: generic_functions_mod.Stats = .{},
    abstracts: abstract_mod.Stats = .{},
    errors: error_mod.Stats = .{},
    ownership: ownership_mod.Stats = .{},
    pending_total: u32 = 0,
    pending_resolved: u32 = 0,
    remaining: u32 = 0,
};

pub const Result = struct {
    graph: global_sg.GlobalSemanticGraph,
    stats: Stats,
};

/// Top-level semantic ownership is stable for the lifetime of a pending
/// operation. Composite owners such as calls and indexing may try multiple
/// implementation strategies internally, but those strategies never compete
/// for ownership at the GlobalSema boundary.
const PendingOwner = enum {
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

const PendingTag = @typeInfo(module_entities.PendingOperation).@"union".tag_type.?;

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

pub fn semantize(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
) !Result {
    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);
    errdefer relocation.deinit(allocator);
    try module_linker.link(allocator, &relocation.graph, modules, relocation.offsets.items);

    // The globalizer preallocates stable GlobalTypeId slots. Record which of
    // those slots are genuinely unresolved before any resolver can inspect
    // them; unresolved is construction state, not the language type `Any`.
    try markUnresolvedTypeSlots(allocator, &relocation.graph, modules, relocation.offsets.items);

    var core = core_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
    };
    var expressions = expression_mod.Resolver{
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
    };
    var generic_functions = generic_functions_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
    };
    var abstracts = abstract_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
    };
    defer abstracts.deinit();
    generic_functions.nested_call_context = &abstracts;
    generic_functions.nested_call_resolver = abstract_mod.Resolver.resolveNestedCall;
    var errors = error_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var ownership = ownership_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    defer ownership.deinit();
    var dispatch = dispatch_mod.Resolver{
        .core = &core,
        .generic_functions = &generic_functions,
        .constructors = &constructors,
        .abstracts = &abstracts,
        .control = &control,
    };

    try core.resolveExternalTypes();
    try generics.resolveExternalTypes();
    _ = relocation.graph.reconcileTypeResolution();
    _ = try generics.materializeKnownTypes();
    try control.materializeSugarTypes();

    const total = totalPending(modules);
    const resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);

    // GlobalSema is staged by semantic domain. The outer fixed point remains
    // while dependencies between phases are still being made explicit; every
    // PendingOperation now has one stable top-level owner across all retries.
    var changed = true;
    while (changed) {
        changed = false;
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
                phase,
            )) changed = true;
        }

        if (relocation.graph.reconcileTypeResolution()) changed = true;
        if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
        if (core.materializeStringLiteralTypes()) changed = true;
        if (core.materializeBindingTypes()) changed = true;
        if (core.materializeDereferences()) changed = true;
        if (try core.materializeAddresses()) changed = true;
        if (try generics.materializeKnownTypes()) changed = true;
        try control.materializeSugarTypes();
    }

    try abstracts.validateGenericFunctionInstances();
    control.annotateChoiceTests();

    var resolved_count: usize = 0;
    for (resolved) |done| if (done) {
        resolved_count += 1;
    };
    const remaining = total - resolved_count;
    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        return error.UnsupportedGlobalSemantic;
    }
    _ = relocation.graph.reconcileTypeResolution();
    _ = relocation.graph.reconcileBindingTypeResolution();
    if (relocation.graph.hasUnresolvedTypes()) {
        std.debug.print("global sema unresolved global type slots remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }
    if (relocation.graph.hasUnresolvedBindingTypes()) {
        std.debug.print("global sema unresolved binding types remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);
    try relocation.graph.finishBindingTypeResolution(allocator);

    // Cleanup is finalized only after all calls/types/abstract dispatch decisions
    // are stable. Safety and Codegen consume these explicit cleanup edges.
    try ownership.finalize();

    var stats = Stats{
        .core = core.stats,
        .expressions = expressions.stats,
        .control = control.stats,
        .generics = generics.stats,
        .generic_functions = generic_functions.stats,
        .abstracts = abstracts.stats,
        .errors = errors.stats,
        .ownership = ownership.stats,
        .pending_total = @intCast(total),
        .pending_resolved = @intCast(resolved_count),
        .remaining = 0,
    };

    try global_verify.verifyGlobal(&relocation.graph);
    stats.remaining = 0;
    return .{ .graph = relocation.takeGraph(allocator), .stats = stats };
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
    phase: PendingPhase,
) !bool {
    var changed = false;
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        const o = offsets[module_index];
        for (module.semantic.pending_operations.items) |operation| {
            if (!resolved[flat] and pendingPhase(operation) == phase) {
                const result = try resolvePendingOperation(
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
                    o,
                    operation,
                );
                if (result.isResolved()) {
                    resolved[flat] = true;
                    changed = true;
                }
            }
            flat += 1;
        }
    }
    return changed;
}

fn pendingOwnerTag(tag: PendingTag) PendingOwner {
    return switch (tag) {
        .resolve_type => .types,
        .resolve_call => .calls,
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
        .calls => dispatch.resolveCall(module_index, module, o, operation),
        .indexing => dispatch.resolveIndex(module_index, module, o, operation),
        .core => ownedResult(try core.tryResolve(module_index, module, o, operation)),
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



fn dumpUnresolved(modules: []const module_sg.ModuleSemanticGraph, resolved: []const bool) void {
    var flat: usize = 0;
    var shown: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items) |operation| {
            if (!resolved[flat] and shown < 8) {
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
    try std.testing.expectEqual(@as(usize, 0), result.graph.type_resolution.items.len);
}