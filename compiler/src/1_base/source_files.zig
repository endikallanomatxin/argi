const std = @import("std");

/// Buffer in-memory de un fichero fuente.
pub const SourceFile = struct {
    path: []const u8, // ruta (relativa a cwd)
    code: []const u8, // contenido completo
};

fn collectRgFilesFromDir(
    alloc: *const std.mem.Allocator,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    skip_path: ?[]const u8,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |e| {
        std.debug.print("No se pudo abrir {s}: {any}\n", .{ dir_path, e });
        return;
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

        if (skip_path) |skip| {
            if (std.mem.eql(u8, full_path, skip)) {
                alloc.free(full_path);
                continue;
            }
        }

        try paths.append(full_path);
    }

    for (paths.items) |full_path| {
        try list.append(try readFile(alloc, full_path));
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

    // ─── core/ ────────────────────────────────────────────────────────────
    try collectRgFilesFromDir(alloc, &list, core_dir, null);

    // ─── carpeta del entrypoint del usuario ──────────────────────────────
    // For folder-level modules, use `main.rg` as the entrypoint of the folder.
    if (std.mem.eql(u8, std.fs.path.basename(user_path), "main.rg")) {
        const user_dir = std.fs.path.dirname(user_path) orelse ".";
        try collectRgFilesFromDir(alloc, &list, user_dir, user_path);
    }

    // ─── entrypoint del usuario al final ─────────────────────────────────
    try list.append(try readFile(alloc, user_path));

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
