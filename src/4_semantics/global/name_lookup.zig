const std = @import("std");
const module_sg = @import("../module/graph.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

pub fn binding(
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    module_index: usize,
    name: []const u8,
) ?global_sg.GlobalBindingId {
    if (bindingInNamespace(graph, modules, offsets, module_index, name)) |value| return value;

    var found: ?global_sg.GlobalBindingId = null;
    for (modules, 0..) |*candidate, candidate_index| {
        if (graph.sameModuleNamespace(@enumFromInt(candidate_index), @enumFromInt(module_index)) or !candidate.is_bundled_core) continue;
        if (std.mem.startsWith(u8, name, "_")) continue;
        const value = bindingInModule(modules, offsets, candidate_index, name) orelse continue;
        if (found != null) return null;
        found = value;
    }
    return found;
}

pub fn bindingInNamespace(graph: *const global_sg.GlobalSemanticGraph, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets, module_index: usize, name: []const u8) ?global_sg.GlobalBindingId {
    var found: ?global_sg.GlobalBindingId = null;
    for (modules, 0..) |_, index| {
        if (!graph.sameModuleNamespace(@enumFromInt(index), @enumFromInt(module_index))) continue;
        const value = bindingInModule(modules, offsets, index, name) orelse continue;
        if (found != null) return null;
        found = value;
    }
    return found;
}

pub fn bindingInModule(
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    module_index: usize,
    name: []const u8,
) ?global_sg.GlobalBindingId {
    const module = &modules[module_index];
    var found: ?global_sg.GlobalBindingId = null;
    for (module.semantic.declaration_bindings.items) |relation| {
        const declaration = module.declarations.items[@intFromEnum(relation.declaration)];
        if (!std.mem.eql(u8, module.text(declaration.name), name)) continue;
        if (found != null) return null;
        found = globalizer.globalBinding(offsets[module_index], relation.binding);
    }
    return found;
}
