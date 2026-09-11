const std = @import("std");
const module_sg = @import("../module/graph.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

/// Link every source-level import exactly once. Path spelling belongs to the
/// loader/link boundary; after this pass semantic lookup uses GlobalModuleId.
pub fn link(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
) !void {
    graph.module_aliases.clearRetainingCapacity();
    for (modules, 0..) |*module, module_index| {
        const owner: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(module_index)));
        for (module.semantic.module_aliases.items) |alias| {
            const target = try resolveImportPath(allocator, graph, modules, module_index, module.text(alias.path));
            try graph.module_aliases.append(allocator, .{
                .owner = owner,
                .declaration = globalizer.globalDecl(offsets[module_index], alias.declaration),
                .target = target,
                .source = .{
                    .file_index = offsets[module_index].file_base + alias.source.file_index,
                    .offset = alias.source.offset,
                },
            });
        }
    }
}

fn resolveImportPath(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    current_module: usize,
    spelling: []const u8,
) !global_sg.GlobalModuleId {
    const import_path = std.mem.trim(u8, spelling, "\"'");
    if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
        const resolved = try std.fs.path.resolve(allocator, &.{ modules[current_module].module_dir, import_path });
        defer allocator.free(resolved);
        var found: ?global_sg.GlobalModuleId = null;
        for (graph.modules.items, 0..) |module, index| {
            const dir = graph.text(module.dir);
            if (!std.mem.eql(u8, dir, resolved)) continue;
            if (found != null) return error.AmbiguousModuleReference;
            found = @enumFromInt(@as(u32, @intCast(index)));
        }
        return found orelse error.UnknownModuleReference;
    }

    // `.../foo` is project/dependency-root syntax. The loader has already
    // discovered concrete module directories; linking accepts only a unique
    // path suffix and converts it immediately to GlobalModuleId.
    const suffix = if (std.mem.startsWith(u8, import_path, ".../")) import_path[4..] else import_path;
    var found: ?global_sg.GlobalModuleId = null;
    for (graph.modules.items, 0..) |module, index| {
        const dir = graph.text(module.dir);
        if (!pathEndsWith(dir, suffix)) continue;
        if (found != null) return error.AmbiguousModuleReference;
        found = @enumFromInt(@as(u32, @intCast(index)));
    }
    return found orelse error.UnknownModuleReference;
}

fn pathEndsWith(path: []const u8, suffix: []const u8) bool {
    if (std.mem.eql(u8, path, suffix)) return true;
    if (!std.mem.endsWith(u8, path, suffix) or path.len <= suffix.len) return false;
    const boundary = path[path.len - suffix.len - 1];
    return boundary == '/' or boundary == '\\';
}
