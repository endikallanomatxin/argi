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
    try append(allocator, graph, modules, offsets, 0);
}

/// Link only a newly relocated module suffix. Previously resolved import
/// identities stay fixed even if a later module has a matching path suffix.
/// On failure discard the entire new alias batch, preserving retained links.
pub fn append(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    first_module: usize,
) !void {
    if (first_module > modules.len or offsets.len != modules.len or graph.modules.items.len != modules.len)
        return error.InvalidModuleLinkPrefix;
    const previous = graph.module_aliases.items.len;
    errdefer graph.module_aliases.shrinkRetainingCapacity(previous);
    for (modules[first_module..], first_module..) |*module, module_index| {
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

/// Selected fragments can add edges between previously loaded modules. Source
/// discovery alone cannot detect those cycles because retained modules are not
/// reloaded. Inspect the final logical import graph before publication.
pub fn cycleSource(allocator: std.mem.Allocator, graph: *const global_sg.GlobalSemanticGraph) !?@import("../primitives/schema.zig").SourceRef {
    const dependencies = try allocator.alloc(usize, graph.modules.items.len);
    defer allocator.free(dependencies);
    @memset(dependencies, 0);
    for (graph.module_aliases.items) |alias| dependencies[@intFromEnum(graph.moduleNamespace(alias.owner))] += 1;
    var ready: std.ArrayList(global_sg.GlobalModuleId) = .empty;
    defer ready.deinit(allocator);
    for (graph.modules.items, 0..) |module, index| {
        if (module.namespace == null and dependencies[index] == 0) try ready.append(allocator, @enumFromInt(index));
    }
    while (ready.pop()) |target| {
        for (graph.module_aliases.items) |alias| {
            if (graph.moduleNamespace(alias.target) != target) continue;
            const owner = graph.moduleNamespace(alias.owner);
            const count = &dependencies[@intFromEnum(owner)];
            count.* -= 1;
            if (count.* == 0) try ready.append(allocator, owner);
        }
    }
    for (graph.module_aliases.items) |alias| {
        if (dependencies[@intFromEnum(graph.moduleNamespace(alias.owner))] != 0 and
            dependencies[@intFromEnum(graph.moduleNamespace(alias.target))] != 0) return alias.source;
    }
    return null;
}

pub fn resolveImportPath(
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
            if (!@import("../../1_base/path_identity.zig").equal(dir, resolved)) continue;
            const candidate = graph.moduleNamespace(@enumFromInt(index));
            if (found != null and found.? != candidate) return error.AmbiguousModuleReference;
            found = candidate;
        }
        return found orelse error.UnknownModuleReference;
    }

    const suffix = if (std.mem.startsWith(u8, import_path, ".../")) import_path[4..] else import_path;
    var found: ?global_sg.GlobalModuleId = null;
    for (graph.modules.items, 0..) |module, index| {
        const dir = graph.text(module.dir);
        if (!pathEndsWith(dir, suffix)) continue;
        const candidate = graph.moduleNamespace(@enumFromInt(index));
        if (found != null and found.? != candidate) return error.AmbiguousModuleReference;
        found = candidate;
    }
    return found orelse error.UnknownModuleReference;
}

/// Resolves import spellings against the discovered module directories.
/// Relative paths are based at the importing module; other spellings match a
/// unique directory suffix.
pub fn resolveImportPathFromDirs(
    allocator: std.mem.Allocator,
    module_dirs: []const []const u8,
    current_module: usize,
    spelling: []const u8,
) !usize {
    const import_path = std.mem.trim(u8, spelling, "\"'");
    if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
        const resolved = try std.fs.path.resolve(allocator, &.{ module_dirs[current_module], import_path });
        defer allocator.free(resolved);
        var found: ?usize = null;
        for (module_dirs, 0..) |dir, index| {
            if (!@import("../../1_base/path_identity.zig").equal(dir, resolved)) continue;
            if (found != null) return error.AmbiguousModuleReference;
            found = index;
        }
        return found orelse error.UnknownModuleReference;
    }

    // `.../foo` is project/dependency-root syntax. The loader has already
    // discovered concrete module directories; linking accepts only a unique
    // path suffix and converts it immediately to GlobalModuleId.
    const suffix = if (std.mem.startsWith(u8, import_path, ".../")) import_path[4..] else import_path;
    var found: ?usize = null;
    for (module_dirs, 0..) |dir, index| {
        if (!pathEndsWith(dir, suffix)) continue;
        if (found != null) return error.AmbiguousModuleReference;
        found = index;
    }
    return found orelse error.UnknownModuleReference;
}

test "import path resolver matches relative and suffix module directories" {
    const inputs = [_][]const u8{ "/project/app", "/project/more/math", "/other/math" };
    var dirs: [inputs.len][]u8 = undefined;
    for (inputs, &dirs) |input, *dir| dir.* = try std.fs.path.resolve(std.testing.allocator, &.{input});
    defer for (dirs) |dir| std.testing.allocator.free(dir);
    try std.testing.expectEqual(@as(usize, 1), try resolveImportPathFromDirs(std.testing.allocator, &dirs, 0, "../more/math"));
    try std.testing.expectEqual(@as(usize, 1), try resolveImportPathFromDirs(std.testing.allocator, &dirs, 0, ".../more/math"));
    try std.testing.expectError(error.AmbiguousModuleReference, resolveImportPathFromDirs(std.testing.allocator, &dirs, 0, "math"));
}

fn pathEndsWith(path: []const u8, suffix: []const u8) bool {
    if (std.mem.eql(u8, path, suffix)) return true;
    if (path.len < suffix.len) return false;
    const tail = path[path.len - suffix.len ..];
    for (tail, suffix) |actual, wanted| {
        if (actual == wanted) continue;
        if (@import("builtin").os.tag == .windows and std.fs.path.isSep(actual) and std.fs.path.isSep(wanted)) continue;
        return false;
    }
    if (path.len == suffix.len) return true;
    const boundary = path[path.len - suffix.len - 1];
    return boundary == '/' or boundary == '\\';
}

test "import suffixes accept language separators on Windows" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    try std.testing.expect(pathEndsWith("C:\\project\\more\\math", "more/math"));
    try std.testing.expect(!pathEndsWith("C:\\project\\notmore\\math", "more/math"));
}

test "module link extension preserves retained targets and rolls back rejected aliases" {
    const a = std.testing.allocator;
    const strings = @import("../primitives/strings.zig");
    var first: module_sg.ModuleSemanticGraph = .{};
    defer first.deinit(a);
    var target: module_sg.ModuleSemanticGraph = .{};
    defer target.deinit(a);
    var later: module_sg.ModuleSemanticGraph = .{};
    defer later.deinit(a);
    const first_path = try strings.append(&first.strings, a, "math");
    try first.semantic.module_aliases.append(a, .{ .declaration = @enumFromInt(0), .path = first_path, .source = .{ .file_index = 0, .offset = 0 } });
    const valid = try strings.append(&later.strings, a, "app");
    const missing = try strings.append(&later.strings, a, "missing");
    try later.semantic.module_aliases.append(a, .{ .declaration = @enumFromInt(0), .path = valid, .source = .{ .file_index = 0, .offset = 0 } });
    try later.semantic.module_aliases.append(a, .{ .declaration = @enumFromInt(1), .path = missing, .source = .{ .file_index = 0, .offset = 1 } });
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    for ([_][]const u8{ "project/app", "project/math" }) |dir| {
        try graph.modules.append(a, .{ .dir = try graph.addString(a, dir), .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 0 } });
    }
    const modules = [_]module_sg.ModuleSemanticGraph{ first, target, later };
    const offsets = [_]globalizer.Offsets{ std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets) };
    try link(a, &graph, modules[0..2], offsets[0..2]);
    const retained = graph.module_aliases.items[0];
    try graph.modules.append(a, .{ .dir = try graph.addString(a, "other/math"), .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 0 } });
    try std.testing.expectError(error.UnknownModuleReference, append(a, &graph, &modules, &offsets, 2));
    try std.testing.expectEqual(@as(usize, 1), graph.module_aliases.items.len);
    try std.testing.expectEqualDeep(retained, graph.module_aliases.items[0]);
    later.semantic.module_aliases.shrinkRetainingCapacity(1);
    const retried = [_]module_sg.ModuleSemanticGraph{ first, target, later };
    try append(a, &graph, &retried, &offsets, 2);
    try std.testing.expectEqual(@as(usize, 2), graph.module_aliases.items.len);
    try std.testing.expectEqualDeep(retained, graph.module_aliases.items[0]);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.module_aliases.items[1].target));
}

test "selected module import cycles follow canonical fragment namespaces" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const dir = try graph.addString(a, "/project");
    try graph.modules.appendNTimes(a, .{ .dir = dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 0 } }, 3);
    graph.modules.items[2].namespace = @enumFromInt(0);
    try graph.module_aliases.append(a, .{ .owner = @enumFromInt(0), .target = @enumFromInt(1), .declaration = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 10 } });
    try graph.module_aliases.append(a, .{ .owner = @enumFromInt(2), .target = @enumFromInt(1), .declaration = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 20 } });
    try std.testing.expectEqual(null, try cycleSource(a, &graph));
    try graph.module_aliases.append(a, .{ .owner = @enumFromInt(1), .target = @enumFromInt(0), .declaration = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 30 } });
    try std.testing.expect((try cycleSource(a, &graph)) != null);
}
