const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const module_views = @import("module_semantic_views.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const global_verify = @import("global_semantic_verify.zig");
const core_mod = @import("global_semantic_core.zig");
const expression_mod = @import("global_semantic_expressions.zig");
const control_mod = @import("global_semantic_control.zig");
const generic_mod = @import("global_semantic_generics.zig");
const generic_functions_mod = @import("global_semantic_generic_functions.zig");
const abstract_mod = @import("global_semantic_abstracts.zig");
const error_mod = @import("global_semantic_errors.zig");
const ownership_mod = @import("global_semantic_ownership.zig");

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

pub fn semantize(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
) !Result {
    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);
    errdefer relocation.deinit(allocator);

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
    core.abstract_context = &abstracts;
    core.abstract_compatible = abstract_mod.Resolver.concreteImplements;
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

    try core.resolveExternalTypes();
    try generics.resolveExternalTypes();
    _ = relocation.graph.reconcileTypeResolution();
    _ = try generics.materializeKnownTypes();
    try control.materializeSugarTypes();

    const total = totalPending(modules);
    var resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);

    var changed = true;
    while (changed) {
        changed = false;
        var flat: usize = 0;
        for (modules, 0..) |*module, module_index| {
            const o = relocation.offsets.items[module_index];
            for (module.semantic.pending_operations.items) |operation| {
                if (!resolved[flat]) {
                    const done = try resolvePendingOperation(
                        &core,
                        &expressions,
                        &control,
                        &generics,
                        &generic_functions,
                        &abstracts,
                        &errors,
                        &ownership,
                        module_index,
                        module,
                        o,
                        operation,
                    );
                    if (done) {
                        resolved[flat] = true;
                        changed = true;
                    }
                }
                flat += 1;
            }
        }
        if (relocation.graph.reconcileTypeResolution()) changed = true;
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
    if (relocation.graph.hasUnresolvedTypes()) {
        std.debug.print("global sema unresolved global type slots remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);

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

/// Route each pending semantic operation only to the subsystem(s) that own it.
/// A small number of operations deliberately have a staged fallback because
/// their final category cannot be known in ModuleSema (for example an ordinary,
/// generic, virtual or intrinsic-looking call). Keeping those chains explicit
/// makes resolver precedence part of the architecture instead of an accidental
/// consequence of trying every resolver in sequence.
fn resolvePendingOperation(
    core: *core_mod.Resolver,
    expressions: *expression_mod.Resolver,
    control: *control_mod.Resolver,
    generics: *generic_mod.Resolver,
    generic_functions: *generic_functions_mod.Resolver,
    abstracts: *abstract_mod.Resolver,
    errors: *error_mod.Resolver,
    ownership: *ownership_mod.Resolver,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !bool {
    return switch (operation) {
        .resolve_type => blk: {
            if ((try core.tryResolve(module_index, module, o, operation)) orelse false) break :blk true;
            break :blk (try generics.tryResolve(module_index, module, o, operation)) orelse false;
        },
        .resolve_call => blk: {
            if ((try core.tryResolve(module_index, module, o, operation)) orelse false) break :blk true;
            if ((try generic_functions.tryResolve(module_index, module, o, operation)) orelse false) break :blk true;
            if ((try abstracts.tryResolve(module_index, module, o, operation)) orelse false) break :blk true;
            break :blk (try control.tryResolve(module_index, module, o, operation)) orelse false;
        },
        .resolve_index => blk: {
            if ((try core.tryResolve(module_index, module, o, operation)) orelse false) break :blk true;
            break :blk (try generic_functions.tryResolve(module_index, module, o, operation)) orelse false;
        },
        .resolve_field,
        .resolve_binary,
        .resolve_comparison,
        => (try core.tryResolve(module_index, module, o, operation)) orelse false,
        .resolve_expression => (try expressions.tryResolve(module_index, module, o, operation)) orelse false,
        .resolve_choice_literal,
        .resolve_choice_payload,
        .resolve_nullable_unwrap,
        .resolve_nullable_test,
        .resolve_for_each,
        .resolve_match,
        .resolve_match_case,
        => (try control.tryResolve(module_index, module, o, operation)) orelse false,
        .resolve_abstract => (try abstracts.tryResolve(module_index, module, o, operation)) orelse false,
        .resolve_error_propagation => (try errors.tryResolve(module_index, module, o, operation)) orelse false,
        .resolve_defer,
        .resolve_keep,
        .resolve_copy,
        .resolve_deinit,
        => (try ownership.tryResolve(module_index, module, o, operation)) orelse false,
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
                    .resolve_expression => |expression| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_expression kind={s} name={s} node={d}\n",
                        .{ module_index, module.module_dir, @tagName(expression.kind), if (expression.name) |name| module.text(name) else "", @intFromEnum(expression.node) },
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

test "global semantizer accepts an empty program" {
    const allocator = std.testing.allocator;
    var result = try semantize(allocator, &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.graph.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    try std.testing.expectEqual(@as(usize, 0), result.graph.type_resolution.items.len);
}
