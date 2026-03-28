const std = @import("std");

/// Buffer in-memory de un fichero fuente.
pub const SourceFile = struct {
    path: []const u8, // ruta (relativa a cwd)
    code: []const u8, // contenido completo
};

const DirSet = std.StringHashMap(void);
const ImportList = std.array_list.Managed(ResolvedImport);

const ResolvedImport = struct {
    raw_path: []const u8,
    importer_path: []const u8,
    resolved_dir: []u8,
};

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn isProjectRoot(path: []const u8) bool {
    const git_path = std.fs.path.join(std.heap.page_allocator, &.{ path, ".git" }) catch return false;
    defer std.heap.page_allocator.free(git_path);
    if (dirExists(git_path)) return true;

    const argi_toml_path = std.fs.path.join(std.heap.page_allocator, &.{ path, "argi.toml" }) catch return false;
    defer std.heap.page_allocator.free(argi_toml_path);
    return fileExists(argi_toml_path);
}

fn findProjectRoot(alloc: *const std.mem.Allocator, importer_path: []const u8) ![]u8 {
    var current = try std.fs.path.resolve(alloc.*, &.{std.fs.path.dirname(importer_path) orelse "."});
    errdefer alloc.free(current);

    while (true) {
        if (isProjectRoot(current)) return current;

        const parent = std.fs.path.dirname(current) orelse return current;
        const resolved_parent = try std.fs.path.resolve(alloc.*, &.{parent});
        if (std.mem.eql(u8, resolved_parent, current)) {
            alloc.free(resolved_parent);
            return current;
        }

        alloc.free(current);
        current = resolved_parent;
    }
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
        "core",
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

    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

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

    var paths = std.array_list.Managed([]u8).init(alloc.*);
    defer {
        for (paths.items) |path| alloc.free(path);
        paths.deinit();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".rg")) continue;

        const full_path = try std.fs.path.join(alloc.*, &.{ dir_path, entry.name });

        if (skip_path) |skip| {
            if (std.mem.eql(u8, full_path, skip)) {
                alloc.free(full_path);
                continue;
            }
        }
        if (seen_files.contains(full_path)) {
            alloc.free(full_path);
            continue;
        }

        try paths.append(full_path);
    }

    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    for (paths.items) |full_path| {
        try seen_files.put(try alloc.dupe(u8, full_path), {});
        try list.append(try readFile(alloc, full_path));
    }
}

fn collectImportDirsFromSource(
    alloc: *const std.mem.Allocator,
    source_path: []const u8,
    source_code: []const u8,
    imports: *ImportList,
) !void {
    var rest = source_code;
    const needle = "#import(\"";

    while (std.mem.indexOf(u8, rest, needle)) |idx| {
        rest = rest[idx + needle.len ..];
        const end_idx = std.mem.indexOfScalar(u8, rest, '"') orelse break;
        const import_path = rest[0..end_idx];
        rest = rest[end_idx + 1 ..];

        const resolved = try resolveImportDir(alloc, source_path, import_path);
        errdefer alloc.free(resolved);
        var already_known = false;

        for (imports.items) |existing| {
            if (std.mem.eql(u8, existing.resolved_dir, resolved)) {
                already_known = true;
                break;
            }
        }
        if (already_known) {
            alloc.free(resolved);
            continue;
        }

        try imports.append(.{
            .raw_path = try alloc.dupe(u8, import_path),
            .importer_path = try alloc.dupe(u8, source_path),
            .resolved_dir = resolved,
        });
    }
}

fn freeImportList(alloc: *const std.mem.Allocator, imports: *ImportList) void {
    for (imports.items) |entry| {
        alloc.free(entry.raw_path);
        alloc.free(entry.importer_path);
        alloc.free(entry.resolved_dir);
    }
    imports.deinit();
}

fn ensureImportDirExists(entry: ResolvedImport) !void {
    if (dirExists(entry.resolved_dir)) return;
    std.debug.print(
        "cannot resolve import '{s}' from '{s}'\n",
        .{ entry.raw_path, entry.importer_path },
    );
    return error.FileNotFound;
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

    if (std.mem.startsWith(u8, import_path, ".../")) {
        const project_root = try findProjectRoot(alloc, importer_path);
        defer alloc.free(project_root);
        return try std.fs.path.resolve(alloc.*, &.{ project_root, import_path[4..] });
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
    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    try collectImportDirsFromSource(alloc, source.path, source.code, &imports);
    for (imports.items) |entry| {
        try ensureImportDirExists(entry);
        if (module_dirs.contains(entry.resolved_dir)) continue;
        try module_dirs.put(try alloc.dupe(u8, entry.resolved_dir), {});
    }
}

fn printImportCycle(stack: []const []const u8, repeated_dir: []const u8) void {
    std.debug.print("import cycle detected: ", .{});
    var start_idx: usize = 0;
    while (start_idx < stack.len) : (start_idx += 1) {
        if (std.mem.eql(u8, stack[start_idx], repeated_dir)) break;
    }

    var idx = start_idx;
    while (idx < stack.len) : (idx += 1) {
        if (idx != start_idx) std.debug.print(" -> ", .{});
        std.debug.print("{s}", .{stack[idx]});
    }
    std.debug.print(" -> {s}\n", .{repeated_dir});
}

fn validateModuleGraphAcyclic(
    alloc: *const std.mem.Allocator,
    dir_path: []const u8,
    skip_path: ?[]const u8,
    entry_override: ?SourceFile,
    visited_dirs: *DirSet,
    stack: *std.array_list.Managed([]const u8),
) !void {
    for (stack.items) |active_dir| {
        if (std.mem.eql(u8, active_dir, dir_path)) {
            printImportCycle(stack.items, dir_path);
            return error.ImportCycle;
        }
    }
    if (visited_dirs.contains(dir_path)) return;

    try stack.append(dir_path);
    defer _ = stack.pop();

    var module_files = std.array_list.Managed(SourceFile).init(alloc.*);
    defer freeList(alloc, &module_files);
    var seen_module_files = DirSet.init(alloc.*);
    defer {
        var it = seen_module_files.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen_module_files.deinit();
    }

    try collectRgFilesInDir(alloc, &module_files, dir_path, skip_path, &seen_module_files);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    for (module_files.items) |source| {
        try collectImportDirsFromSource(alloc, source.path, source.code, &imports);
    }

    for (imports.items) |entry| {
        try ensureImportDirExists(entry);
        try validateModuleGraphAcyclic(alloc, entry.resolved_dir, null, null, visited_dirs, stack);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
}

fn collectModuleOrder(
    alloc: *const std.mem.Allocator,
    dir_path: []const u8,
    skip_path: ?[]const u8,
    entry_override: ?SourceFile,
    visited_dirs: *DirSet,
    ordered_dirs: *std.array_list.Managed([]const u8),
) !void {
    if (visited_dirs.contains(dir_path)) return;

    var module_files = std.array_list.Managed(SourceFile).init(alloc.*);
    defer freeList(alloc, &module_files);
    var seen_module_files = DirSet.init(alloc.*);
    defer {
        var it = seen_module_files.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen_module_files.deinit();
    }

    try collectRgFilesInDir(alloc, &module_files, dir_path, skip_path, &seen_module_files);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    for (module_files.items) |source| {
        try collectImportDirsFromSource(alloc, source.path, source.code, &imports);
    }

    for (imports.items) |entry| {
        try ensureImportDirExists(entry);
        try collectModuleOrder(alloc, entry.resolved_dir, null, null, visited_dirs, ordered_dirs);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
    try ordered_dirs.append(try alloc.dupe(u8, dir_path));
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
    const entry_source = try readFile(alloc, user_path);
    defer {
        alloc.free(entry_source.path);
        alloc.free(entry_source.code);
    }

    return try collectWithEntrySource(alloc, core_dir, user_path, entry_source.code);
}

pub fn collectModule(
    alloc: *const std.mem.Allocator,
    core_dir: []const u8,
    module_dir: []const u8,
) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &list);

    const resolved_core_dir = try resolveToolCoreDir(alloc, core_dir);
    defer alloc.free(resolved_core_dir);
    const resolved_module_dir = try std.fs.path.resolve(alloc.*, &.{module_dir});
    defer alloc.free(resolved_module_dir);

    var seen_files = DirSet.init(alloc.*);
    defer {
        var it = seen_files.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen_files.deinit();
    }
    var acyclic_dirs = DirSet.init(alloc.*);
    defer {
        var it = acyclic_dirs.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        acyclic_dirs.deinit();
    }
    var stack = std.array_list.Managed([]const u8).init(alloc.*);
    defer stack.deinit();
    var ordered_dirs = std.array_list.Managed([]const u8).init(alloc.*);
    defer {
        for (ordered_dirs.items) |path| alloc.free(path);
        ordered_dirs.deinit();
    }
    var ordered_seen = DirSet.init(alloc.*);
    defer {
        var it = ordered_seen.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        ordered_seen.deinit();
    }

    try collectRgFilesRecursively(alloc, &list, resolved_core_dir, &seen_files);

    try validateModuleGraphAcyclic(
        alloc,
        resolved_module_dir,
        null,
        null,
        &acyclic_dirs,
        &stack,
    );
    try collectModuleOrder(
        alloc,
        resolved_module_dir,
        null,
        null,
        &ordered_seen,
        &ordered_dirs,
    );

    for (ordered_dirs.items) |dir_path| {
        try collectRgFilesInDir(alloc, &list, dir_path, null, &seen_files);
    }

    return list;
}

pub fn collectWithEntrySource(
    alloc: *const std.mem.Allocator,
    core_dir: []const u8,
    user_path: []const u8,
    user_code: []const u8,
) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &list);

    const resolved_core_dir = try resolveToolCoreDir(alloc, core_dir);
    defer alloc.free(resolved_core_dir);
    const entry_source = SourceFile{
        .path = try alloc.dupe(u8, user_path),
        .code = try alloc.dupe(u8, user_code),
    };
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
    var acyclic_dirs = DirSet.init(alloc.*);
    defer {
        var it = acyclic_dirs.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        acyclic_dirs.deinit();
    }
    var stack = std.array_list.Managed([]const u8).init(alloc.*);
    defer stack.deinit();
    var ordered_dirs = std.array_list.Managed([]const u8).init(alloc.*);
    defer {
        for (ordered_dirs.items) |path| alloc.free(path);
        ordered_dirs.deinit();
    }
    var ordered_seen = DirSet.init(alloc.*);
    defer {
        var it = ordered_seen.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        ordered_seen.deinit();
    }

    // ─── core/ ────────────────────────────────────────────────────────────
    try collectRgFilesRecursively(alloc, &list, resolved_core_dir, &seen_files);

    // ─── carpeta del entrypoint del usuario y imports explícitos ─────────
    const user_dir = std.fs.path.dirname(user_path) orelse ".";
    const root_module_dir = try alloc.dupe(u8, user_dir);
    try validateModuleGraphAcyclic(
        alloc,
        root_module_dir,
        user_path,
        entry_source,
        &acyclic_dirs,
        &stack,
    );
    try collectModuleOrder(
        alloc,
        root_module_dir,
        user_path,
        entry_source,
        &ordered_seen,
        &ordered_dirs,
    );

    for (ordered_dirs.items) |dir_path| {
        const skip_path = if (std.mem.eql(u8, dir_path, user_dir)) user_path else null;
        try collectRgFilesInDir(alloc, &list, dir_path, skip_path, &seen_files);
    }

    // ─── entrypoint del usuario al final ─────────────────────────────────
    for (list.items) |*source_file| {
        if (!std.mem.eql(u8, source_file.path, user_path)) continue;

        alloc.free(source_file.code);
        source_file.code = entry_source.code;
        alloc.free(entry_source.path);
        return list;
    }

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
