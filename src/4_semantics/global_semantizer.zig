const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
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
                    var done = (try core.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try expressions.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try generics.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try generic_functions.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try abstracts.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try control.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try errors.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try ownership.tryResolve(module_index, module, o, operation)) orelse false;
                    if (done) {
                        resolved[flat] = true;
                        changed = true;
                    }
                }
                flat += 1;
            }
        }
        if (try generics.materializeKnownTypes()) changed = true;
        try control.materializeSugarTypes();
    }

    try abstracts.validateGenericFunctionInstances();
    control.annotateChoiceTests();

    var resolved_count: usize = 0;
    for (resolved) |done| if (done) { resolved_count += 1; };
    const remaining = total - resolved_count;
    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        return error.UnsupportedGlobalSemantic;
    }
    if (hasUnresolvedExternalTypes(modules, core.stats.external_types + generics.stats.type_holes)) {
        std.debug.print("global sema unresolved external types: resolved={d}\n", .{core.stats.external_types + generics.stats.type_holes});
        return error.UnsupportedGlobalSemantic;
    }

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

fn dumpUnresolved(modules: []const module_sg.ModuleSemanticGraph, resolved: []const bool) void {
    var flat: usize = 0;
    var shown: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items) |operation| {
            if (!resolved[flat] and shown < 8) {
                switch (operation) {
                    .resolve_expression => |expression| std.debug.print(
                        "global sema unresolved: module={d} op=resolve_expression kind={s} node={d}\n",
                        .{ module_index, @tagName(expression.kind), @intFromEnum(expression.node) },
                    ),
                    else => std.debug.print(
                        "global sema unresolved: module={d} op={s}\n",
                        .{ module_index, @tagName(operation) },
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

fn hasUnresolvedExternalTypes(modules: []const module_sg.ModuleSemanticGraph, resolved_count: u32) bool {
    var external_count: usize = 0;
    for (modules) |module| {
        external_count += module.semantic.external_types.items.len;
        for (module.semantic.types.items) |ty| switch (ty) {
            .external => external_count += 1,
            .resolved => {},
        };
    }
    return external_count > resolved_count;
}

test "global semantizer accepts an empty program" {
    const allocator = std.testing.allocator;
    var result = try semantize(allocator, &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.graph.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
}
