const std = @import("std");

/// Buffer in-memory de un fichero fuente.
pub const SourceFile = struct {
    path: []const u8, // ruta (relativa a cwd)
    code: []const u8, // contenido completo
};

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
) !std.ArrayList(SourceFile) {
    var list = std.ArrayList(SourceFile).init(alloc.*);

    // ─── core/ ────────────────────────────────────────────────────────────
    // Desde Zig 0.14, `openIterableDir` fue eliminado; se usa openDir con iterate=true
    var dir = std.fs.cwd().openDir(core_dir, .{ .iterate = true }) catch |e| {
        std.debug.print("No se pudo abrir {s}: {any}\n", .{ core_dir, e });
        return list; // seguimos sin stdlib; el usuario recibirá diagnóstico
    };
    defer dir.close();

    var walker = dir.walk(alloc.*) catch unreachable;
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".rg")) continue;

        // El `walker` devuelve rutas relativas a `core_dir`; las juntamos.
        const full_path = try std.fs.path.join(alloc.*, &.{ core_dir, entry.path });
        defer alloc.free(full_path); // readFile duplica la ruta, por eso la liberamos

        try list.append(try readFile(alloc, full_path));
    }

    // ─── fuente del usuario ──────────────────────────────────────────────
    try list.append(try readFile(alloc, user_path));

    return list;
}

/// Libera los `code` y la lista.
pub fn freeList(
    alloc: *const std.mem.Allocator,
    list: *std.ArrayList(SourceFile),
) void {
    for (list.items) |f| alloc.free(f.code);
    list.deinit();
}
