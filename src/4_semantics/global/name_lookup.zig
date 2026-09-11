const std = @import("std");
const module_sg = @import("../module/graph.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

pub fn binding(
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    module_index: usize,
    name: []const u8,
) ?global_sg.GlobalBindingId {
    if (bindingInModule(modules, offsets, module_index, name)) |value| return value;

    var found: ?global_sg.GlobalBindingId = null;
    for (modules, 0..) |*candidate, candidate_index| {
        if (candidate_index == module_index or !candidate.is_bundled_core) continue;
        if (std.mem.startsWith(u8, name, "_")) continue;
        const value = bindingInModule(modules, offsets, candidate_index, name) orelse continue;
        if (found != null) return null;
        found = value;
    }
    return found;
}

fn bindingInModule(
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
