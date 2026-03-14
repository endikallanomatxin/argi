const std = @import("std");

/// Buffer in-memory de un fichero fuente.
pub const SourceFile = struct {
    path: []const u8, // ruta (relativa a cwd)
    code: []const u8, // contenido completo
};

const DirSet = std.StringHashMap(void);

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn firstExistingDir(
    alloc: *const std.mem.Allocator,
    candidates: []const []const u8,
) ![]u8 {
    for (candidates) |candidate| {
        const resolved = try std.fs.path.resolve(alloc.*, &.{candidate});
        if (dirExists(resolved)) return resolved;
        alloc.free(resolved);
    }
    return error.FileNotFound;
}

fn resolveToolCoreDir(alloc: *const std.mem.Allocator, preferred: []const u8) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc.*);
    defer alloc.free(exe_dir);

    const bundled_core = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "..", "core" });
    defer alloc.free(bundled_core);

    return try firstExistingDir(alloc, &.{
        preferred,
        "compiler/core",
        bundled_core,
    });
}

fn resolveToolMoreDir(alloc: *const std.mem.Allocator) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc.*);
    defer alloc.free(exe_dir);

    const bundled_more = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "..", "..", "more" });
    defer alloc.free(bundled_more);

    return try firstExistingDir(alloc, &.{
        "more",
        "../more",
        bundled_more,
    });
}

fn collectRgFilesRecursively(
    alloc: *const std.mem.Allocator,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    seen_files: *DirSet,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |e| {
        std.debug.print("failed to open source directory '{s}': {any}\n", .{ dir_path, e });
        return e;
    };
    defer dir.close();

    var walker = dir.walk(alloc.*) catch unreachable;
    defer walker.deinit();

    var paths = std.array_list.Managed([]u8).init(alloc.*);
    defer {
        for (paths.items) |path| alloc.free(path);
        paths.deinit();
    }

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".rg")) continue;

        const full_path = try std.fs.path.join(alloc.*, &.{ dir_path, entry.path });
        errdefer alloc.free(full_path);
        if (seen_files.contains(full_path)) {
            alloc.free(full_path);
            continue;
        }

        try paths.append(full_path);
    }

    for (paths.items) |full_path| {
        try seen_files.put(try alloc.dupe(u8, full_path), {});
        try list.append(try readFile(alloc, full_path));
    }
}

fn collectRgFilesInDir(
    alloc: *const std.mem.Allocator,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    skip_path: ?[]const u8,
    seen_files: *DirSet,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |e| {
        std.debug.print("failed to open module directory '{s}': {any}\n", .{ dir_path, e });
        return e;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".rg")) continue;

        const full_path = try std.fs.path.join(alloc.*, &.{ dir_path, entry.name });
        defer alloc.free(full_path);

        if (skip_path) |skip| {
            if (std.mem.eql(u8, full_path, skip)) continue;
        }
        if (seen_files.contains(full_path)) continue;

        try seen_files.put(try alloc.dupe(u8, full_path), {});
        try list.append(try readFile(alloc, full_path));
    }
}

pub fn resolveImportDir(
    alloc: *const std.mem.Allocator,
    importer_path: []const u8,
    import_path: []const u8,
) ![]u8 {
    if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
        const base_dir = std.fs.path.dirname(importer_path) orelse ".";
        return try std.fs.path.resolve(alloc.*, &.{ base_dir, import_path });
    }

    if (std.mem.startsWith(u8, import_path, "/")) {
        return try std.fs.path.resolve(alloc.*, &.{ ".", import_path[1..] });
    }

    const more_root = try resolveToolMoreDir(alloc);
    defer alloc.free(more_root);
    return try std.fs.path.resolve(alloc.*, &.{ more_root, import_path });
}

fn scanImports(
    alloc: *const std.mem.Allocator,
    source: SourceFile,
    module_dirs: *DirSet,
) !void {
    var rest = source.code;
    const needle = "#import(\"";

    while (std.mem.indexOf(u8, rest, needle)) |idx| {
        rest = rest[idx + needle.len ..];
        const end_idx = std.mem.indexOfScalar(u8, rest, '"') orelse break;
        const import_path = rest[0..end_idx];
        rest = rest[end_idx + 1 ..];

        const resolved = try resolveImportDir(alloc, source.path, import_path);
        defer alloc.free(resolved);

        if (module_dirs.contains(resolved)) continue;
        try module_dirs.put(try alloc.dupe(u8, resolved), {});
    }
}

/// Lee un único fichero.
pub fn readFile(alloc: *const std.mem.Allocator, path: []const u8) !SourceFile {
    const code = try std.fs.cwd().readFileAlloc(alloc.*, path, 1 << 24); // 16 MiB máx.
    return .{ .path = try alloc.dupe(u8, path), .code = code };
}

/// Reúne todos los .rg de `core_dir` + el `user_path`.
pub fn collect(
    alloc: *const std.mem.Allocator,
    core_dir: []const u8,
    user_path: []const u8,
) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    const resolved_core_dir = try resolveToolCoreDir(alloc, core_dir);
    defer alloc.free(resolved_core_dir);
    const entry_source = try readFile(alloc, user_path);
    errdefer {
        alloc.free(entry_source.path);
        alloc.free(entry_source.code);
    }
    var seen_files = DirSet.init(alloc.*);
    defer {
        var it = seen_files.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen_files.deinit();
    }
    var module_dirs = DirSet.init(alloc.*);
    defer {
        var it = module_dirs.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        module_dirs.deinit();
    }

    // ─── core/ ────────────────────────────────────────────────────────────
    try collectRgFilesRecursively(alloc, &list, resolved_core_dir, &seen_files);

    // ─── carpeta del entrypoint del usuario y imports explícitos ─────────
    const user_dir = std.fs.path.dirname(user_path) orelse ".";
    const root_module_dir = try alloc.dupe(u8, user_dir);
    try module_dirs.put(root_module_dir, {});
    try scanImports(alloc, entry_source, &module_dirs);

    var dir_queue = std.array_list.Managed([]const u8).init(alloc.*);
    defer dir_queue.deinit();
    try dir_queue.append(root_module_dir);

    var dir_index: usize = 0;
    while (dir_index < dir_queue.items.len) : (dir_index += 1) {
        const dir_path = dir_queue.items[dir_index];
        const skip_path = if (std.mem.eql(u8, dir_path, user_dir)) user_path else null;
        const start_len = list.items.len;
        try collectRgFilesInDir(alloc, &list, dir_path, skip_path, &seen_files);

        var idx = start_len;
        while (idx < list.items.len) : (idx += 1) {
            try scanImports(alloc, list.items[idx], &module_dirs);
        }

        var keys_it = module_dirs.keyIterator();
        while (keys_it.next()) |key_ptr| {
            var known = false;
            for (dir_queue.items) |queued| {
                if (std.mem.eql(u8, queued, key_ptr.*)) {
                    known = true;
                    break;
                }
            }
            if (!known) try dir_queue.append(key_ptr.*);
        }
    }

    // ─── entrypoint del usuario al final ─────────────────────────────────
    if (!seen_files.contains(user_path)) {
        try seen_files.put(try alloc.dupe(u8, user_path), {});
    }
    try list.append(entry_source);

    return list;
}

/// Libera los `code` y la lista.
pub fn freeList(
    alloc: *const std.mem.Allocator,
    list: *std.array_list.Managed(SourceFile),
) void {
    for (list.items) |f| {
        alloc.free(f.path);
        alloc.free(f.code);
    }
    list.deinit();
}
