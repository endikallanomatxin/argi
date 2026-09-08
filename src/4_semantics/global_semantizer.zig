const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const global_verify = @import("global_semantic_verify.zig");
const core_mod = @import("global_semantic_core.zig");
const control_mod = @import("global_semantic_control.zig");
const generic_mod = @import("global_semantic_generics.zig");

pub const Stats = struct {
    core: core_mod.Stats = .{},
    control: control_mod.Stats = .{},
    generics: generic_mod.Stats = .{},
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
                    if (!done) done = (try generics.tryResolve(module_index, module, o, operation)) orelse false;
                    if (!done) done = (try control.tryResolve(module_index, module, o, operation)) orelse false;
                    if (done) {
                        resolved[flat] = true;
                        changed = true;
                    }
                }
                flat += 1;
            }
        }
        if (try generics.materializeKnownTypes()) changed = true;
        // Generic materialization may append Nullable/Errable sugar types.
        try control.materializeSugarTypes();
    }

    control.annotateChoiceTests();

    var resolved_count: usize = 0;
    for (resolved) |done| if (done) { resolved_count += 1; };
    const remaining = total - resolved_count;
    var stats = Stats{
        .core = core.stats,
        .control = control.stats,
        .generics = generics.stats,
        .pending_total = @intCast(total),
        .pending_resolved = @intCast(resolved_count),
        .remaining = @intCast(remaining),
    };

    // Generic function templates, abstracts and ownership are plugged into this
    // same fixpoint by later resolvers. Until then, never let placeholders escape.
    if (remaining != 0 or hasUnresolvedExternalTypes(modules, core.stats.external_types + generics.stats.type_holes) or hasUnconsumedProgramTemplates(modules))
        return error.UnsupportedGlobalSemantic;

    try global_verify.verifyGlobal(&relocation.graph);
    stats.remaining = 0;
    return .{ .graph = relocation.takeGraph(allocator), .stats = stats };
}

fn totalPending(modules: []const module_sg.ModuleSemanticGraph) usize {
    var total: usize = 0;
    for (modules) |module| total += module.semantic.pending_operations.items.len;
    return total;
}

fn hasUnconsumedProgramTemplates(modules: []const module_sg.ModuleSemanticGraph) bool {
    for (modules) |module| {
        const storage = &module.semantic.templates;
        if (storage.generic_function_templates.items.len != 0 or
            storage.abstract_definitions.items.len != 0 or
            storage.abstract_implementations.items.len != 0 or
            storage.abstract_implementation_templates.items.len != 0 or
            storage.abstract_defaults.items.len != 0 or
            storage.abstract_default_templates.items.len != 0)
            return true;
    }
    return false;
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
