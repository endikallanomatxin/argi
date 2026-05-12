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

pub const CoreResolutionOptions = struct {
    explicit_sysroot: ?[]const u8 = null,
    environ_map: ?*const std.process.Environ.Map = null,
    fallback_core_dir: []const u8 = "core",
};

const CoreCandidate = struct {
    label: []const u8,
    path: []u8,
};

fn dirExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn isProjectRoot(io: std.Io, path: []const u8) bool {
    const git_path = std.fs.path.join(std.heap.page_allocator, &.{ path, ".git" }) catch return false;
    defer std.heap.page_allocator.free(git_path);
    if (dirExists(io, git_path)) return true;

    const argi_toml_path = std.fs.path.join(std.heap.page_allocator, &.{ path, "argi.toml" }) catch return false;
    defer std.heap.page_allocator.free(argi_toml_path);
    return fileExists(io, argi_toml_path);
}

fn findProjectRoot(alloc: *const std.mem.Allocator, io: std.Io, importer_path: []const u8) ![]u8 {
    var current = try std.fs.path.resolve(alloc.*, &.{std.fs.path.dirname(importer_path) orelse "."});
    errdefer alloc.free(current);

    while (true) {
        if (isProjectRoot(io, current)) return current;

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
    io: std.Io,
    candidates: []const []const u8,
) ![]u8 {
    for (candidates) |candidate| {
        const resolved = try std.fs.path.resolve(alloc.*, &.{candidate});
        if (dirExists(io, resolved)) return resolved;
        alloc.free(resolved);
    }
    return error.FileNotFound;
}

fn appendSysrootCoreCandidate(
    alloc: *const std.mem.Allocator,
    candidates: *std.array_list.Managed(CoreCandidate),
    label: []const u8,
    sysroot: []const u8,
) !void {
    try candidates.append(.{
        .label = label,
        .path = try std.fs.path.resolve(alloc.*, &.{ sysroot, "lib", "argi", "core" }),
    });
}

fn appendSelfExeCoreCandidate(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    candidates: *std.array_list.Managed(CoreCandidate),
) !void {
    const exe_dir = try std.process.executableDirPathAlloc(io, alloc.*);
    defer alloc.free(exe_dir);

    try candidates.append(.{
        .label = "self executable",
        .path = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "lib", "argi", "core" }),
    });
}

fn printCoreResolutionFailure(candidates: []const CoreCandidate) void {
    std.debug.print("cannot find Argi core library\n", .{});
    std.debug.print("tried:\n", .{});
    for (candidates) |candidate| {
        std.debug.print("  - {s}: {s}\n", .{ candidate.label, candidate.path });
    }
    std.debug.print("--sysroot and ARGI_SYSROOT must point at an Argi installation prefix, not directly at core\n", .{});
}

fn freeCoreCandidates(alloc: *const std.mem.Allocator, candidates: *std.array_list.Managed(CoreCandidate)) void {
    for (candidates.items) |candidate| alloc.free(candidate.path);
    candidates.deinit();
}

pub fn resolveToolCoreDir(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    options: CoreResolutionOptions,
) ![]u8 {
    var candidates = std.array_list.Managed(CoreCandidate).init(alloc.*);
    defer freeCoreCandidates(alloc, &candidates);

    if (options.explicit_sysroot) |sysroot| {
        try appendSysrootCoreCandidate(alloc, &candidates, "--sysroot", sysroot);
    } else {
        if (options.environ_map) |environ_map| {
            if (environ_map.get("ARGI_SYSROOT")) |env_sysroot| {
                try appendSysrootCoreCandidate(alloc, &candidates, "ARGI_SYSROOT", env_sysroot);
            } else {
                try appendSelfExeCoreCandidate(alloc, io, &candidates);

                try candidates.append(.{
                    .label = "development fallback",
                    .path = try std.fs.path.resolve(alloc.*, &.{options.fallback_core_dir}),
                });
            }
        } else {
            try appendSelfExeCoreCandidate(alloc, io, &candidates);

            try candidates.append(.{
                .label = "development fallback",
                .path = try std.fs.path.resolve(alloc.*, &.{options.fallback_core_dir}),
            });
        }
    }

    for (candidates.items) |candidate| {
        if (!dirExists(io, candidate.path)) continue;
        return try alloc.dupe(u8, candidate.path);
    }

    printCoreResolutionFailure(candidates.items);
    return error.CoreNotFound;
}

fn resolveToolMoreDir(alloc: *const std.mem.Allocator, io: std.Io) ![]u8 {
    const exe_dir = try std.process.executableDirPathAlloc(io, alloc.*);
    defer alloc.free(exe_dir);

    const bundled_more = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "..", "..", "more" });
    defer alloc.free(bundled_more);

    return try firstExistingDir(alloc, io, &.{
        "more",
        "../more",
        bundled_more,
    });
}

fn collectRgFilesRecursively(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    seen_files: *DirSet,
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |e| {
        std.debug.print("failed to open source directory '{s}': {any}\n", .{ dir_path, e });
        return e;
    };
    defer dir.close(io);

    var walker = dir.walk(alloc.*) catch unreachable;
    defer walker.deinit();

    var paths = std.array_list.Managed([]u8).init(alloc.*);
    defer {
        for (paths.items) |path| alloc.free(path);
        paths.deinit();
    }

    while (try walker.next(io)) |entry| {
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
        try list.append(try readFile(alloc, io, full_path));
    }
}

fn collectRgFilesInDir(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    skip_path: ?[]const u8,
    seen_files: *DirSet,
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |e| {
        std.debug.print("failed to open module directory '{s}': {any}\n", .{ dir_path, e });
        return e;
    };
    defer dir.close(io);

    var paths = std.array_list.Managed([]u8).init(alloc.*);
    defer {
        for (paths.items) |path| alloc.free(path);
        paths.deinit();
    }

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
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
        try list.append(try readFile(alloc, io, full_path));
    }
}

fn collectImportDirsFromSource(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    source_path: []const u8,
    source_code: []const u8,
    imports: *ImportList,
) !void {
    var offset: usize = 0;
    while (offset < source_code.len) {
        const parsed = nextImportDirective(source_code, &offset) orelse break;
        offset = parsed.next_offset;

        const resolved = try resolveImportDir(alloc, io, source_path, parsed.path);
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
            .raw_path = try alloc.dupe(u8, parsed.path),
            .importer_path = try alloc.dupe(u8, source_path),
            .resolved_dir = resolved,
        });
    }
}

const ParsedImportDirective = struct {
    hash_offset: usize,
    path: []const u8,
    next_offset: usize,
};

pub fn firstImportDirectiveOffset(source_code: []const u8) ?usize {
    var offset: usize = 0;
    return if (nextImportDirective(source_code, &offset)) |parsed| parsed.hash_offset else null;
}

fn nextImportDirective(source_code: []const u8, offset: *usize) ?ParsedImportDirective {
    while (offset.* < source_code.len) {
        if (source_code[offset.*] == '-' and offset.* + 1 < source_code.len and source_code[offset.* + 1] == '-') {
            offset.* += 2;
            while (offset.* < source_code.len and source_code[offset.*] != '\n') : (offset.* += 1) {}
            continue;
        }

        if (source_code[offset.*] == '"') {
            skipQuoted(source_code, offset, '"');
            continue;
        }

        if (source_code[offset.*] == '\'') {
            skipQuoted(source_code, offset, '\'');
            continue;
        }

        if (source_code[offset.*] != '#') {
            offset.* += 1;
            continue;
        }

        const hash_offset = offset.*;
        const parsed = parseImportDirective(source_code, hash_offset) orelse {
            offset.* += 1;
            continue;
        };
        return parsed;
    }

    return null;
}

fn skipQuoted(source_code: []const u8, offset: *usize, quote: u8) void {
    offset.* += 1;
    while (offset.* < source_code.len) : (offset.* += 1) {
        if (source_code[offset.*] == '\\') {
            offset.* += 1;
            continue;
        }
        if (source_code[offset.*] == quote) {
            offset.* += 1;
            return;
        }
    }
}

fn skipWhitespace(source_code: []const u8, offset: *usize) void {
    while (offset.* < source_code.len and std.ascii.isWhitespace(source_code[offset.*])) : (offset.* += 1) {}
}

fn parseImportDirective(source_code: []const u8, hash_offset: usize) ?ParsedImportDirective {
    var offset = hash_offset + 1;
    skipWhitespace(source_code, &offset);

    const import_name = "import";
    if (offset + import_name.len > source_code.len) return null;
    if (!std.mem.eql(u8, source_code[offset .. offset + import_name.len], import_name)) return null;
    offset += import_name.len;

    skipWhitespace(source_code, &offset);
    if (offset >= source_code.len or source_code[offset] != '(') return null;
    offset += 1;

    skipWhitespace(source_code, &offset);
    if (offset >= source_code.len or source_code[offset] != '"') return null;
    offset += 1;

    const path_start = offset;
    while (offset < source_code.len) : (offset += 1) {
        if (source_code[offset] == '\\') {
            offset += 1;
            continue;
        }
        if (source_code[offset] == '"') {
            const path = source_code[path_start..offset];
            offset += 1;
            skipWhitespace(source_code, &offset);
            if (offset >= source_code.len or source_code[offset] != ')') return null;
            return .{
                .hash_offset = hash_offset,
                .path = path,
                .next_offset = offset + 1,
            };
        }
    }

    return null;
}

fn freeImportList(alloc: *const std.mem.Allocator, imports: *ImportList) void {
    for (imports.items) |entry| {
        alloc.free(entry.raw_path);
        alloc.free(entry.importer_path);
        alloc.free(entry.resolved_dir);
    }
    imports.deinit();
}

fn ensureImportDirExists(io: std.Io, entry: ResolvedImport) !void {
    if (dirExists(io, entry.resolved_dir)) return;
    std.debug.print(
        "cannot resolve import '{s}' from '{s}'\n",
        .{ entry.raw_path, entry.importer_path },
    );
    return error.FileNotFound;
}

pub fn resolveImportDir(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    importer_path: []const u8,
    import_path: []const u8,
) ![]u8 {
    if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
        const base_dir = std.fs.path.dirname(importer_path) orelse ".";
        return try std.fs.path.resolve(alloc.*, &.{ base_dir, import_path });
    }

    if (std.mem.startsWith(u8, import_path, ".../")) {
        const project_root = try findProjectRoot(alloc, io, importer_path);
        defer alloc.free(project_root);
        return try std.fs.path.resolve(alloc.*, &.{ project_root, import_path[4..] });
    }

    const more_root = try resolveToolMoreDir(alloc, io);
    defer alloc.free(more_root);
    return try std.fs.path.resolve(alloc.*, &.{ more_root, import_path });
}

fn scanImports(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    source: SourceFile,
    module_dirs: *DirSet,
) !void {
    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    try collectImportDirsFromSource(alloc, io, source.path, source.code, &imports);
    for (imports.items) |entry| {
        try ensureImportDirExists(io, entry);
        if (module_dirs.contains(entry.resolved_dir)) continue;
        try module_dirs.put(try alloc.dupe(u8, entry.resolved_dir), {});
    }
}

test "import scanner ignores comments strings and chars" {
    var imports = ImportList.init(std.testing.allocator);
    defer freeImportList(&std.testing.allocator, &imports);

    try collectImportDirsFromSource(
        &std.testing.allocator,
        std.testing.io,
        "tests/feature_tests/modules/example/main.rg",
        \\-- ignored := #import("./comment_dep")
        \\message := "#import(\"./string_dep\")"
        \\quote := '#'
        \\dep := #import("./real_dep")
        \\spaced := # import ( "./spaced_dep" )
    ,
        &imports,
    );

    try std.testing.expectEqual(@as(usize, 2), imports.items.len);
    try std.testing.expectEqualStrings("./real_dep", imports.items[0].raw_path);
    try std.testing.expectEqualStrings("./spaced_dep", imports.items[1].raw_path);
}

test "import scanner ignores unterminated strings" {
    var imports = ImportList.init(std.testing.allocator);
    defer freeImportList(&std.testing.allocator, &imports);

    try collectImportDirsFromSource(
        &std.testing.allocator,
        std.testing.io,
        "tests/feature_tests/modules/example/main.rg",
        "message := \"#import(\\\"./string_dep\\\")",
        &imports,
    );

    try std.testing.expectEqual(@as(usize, 0), imports.items.len);
}

test "first import offset uses lexical import scanner" {
    const source =
        \\-- ignored := #import("./comment_dep")
        \\message := "#import(\"./string_dep\")"
        \\dep := #import("./real_dep")
    ;

    const offset = firstImportDirectiveOffset(source) orelse return error.ExpectedImportOffset;
    try std.testing.expectEqualStrings("#import", source[offset .. offset + "#import".len]);
    try std.testing.expect(std.mem.indexOf(u8, source[0..offset], "dep :=") != null);
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
    io: std.Io,
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

    try collectRgFilesInDir(alloc, io, &module_files, dir_path, skip_path, &seen_module_files);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    for (module_files.items) |source| {
        try collectImportDirsFromSource(alloc, io, source.path, source.code, &imports);
    }

    for (imports.items) |entry| {
        try ensureImportDirExists(io, entry);
        try validateModuleGraphAcyclic(alloc, io, entry.resolved_dir, null, null, visited_dirs, stack);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
}

fn collectModuleOrder(
    alloc: *const std.mem.Allocator,
    io: std.Io,
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

    try collectRgFilesInDir(alloc, io, &module_files, dir_path, skip_path, &seen_module_files);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    for (module_files.items) |source| {
        try collectImportDirsFromSource(alloc, io, source.path, source.code, &imports);
    }

    for (imports.items) |entry| {
        try ensureImportDirExists(io, entry);
        try collectModuleOrder(alloc, io, entry.resolved_dir, null, null, visited_dirs, ordered_dirs);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
    try ordered_dirs.append(try alloc.dupe(u8, dir_path));
}

/// Lee un único fichero.
pub fn readFile(alloc: *const std.mem.Allocator, io: std.Io, path: []const u8) !SourceFile {
    const code = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc.*, .limited(1 << 24)); // 16 MiB máx.
    return .{ .path = try alloc.dupe(u8, path), .code = code };
}

/// Reúne todos los .rg de `core_dir` + el `user_path`.
pub fn collect(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    core_dir: []const u8,
    user_path: []const u8,
) !std.array_list.Managed(SourceFile) {
    const entry_source = try readFile(alloc, io, user_path);
    defer {
        alloc.free(entry_source.path);
        alloc.free(entry_source.code);
    }

    return try collectWithEntrySource(alloc, io, core_dir, user_path, entry_source.code);
}

pub fn collectWithOptions(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    options: CoreResolutionOptions,
    user_path: []const u8,
) !std.array_list.Managed(SourceFile) {
    const entry_source = try readFile(alloc, io, user_path);
    defer {
        alloc.free(entry_source.path);
        alloc.free(entry_source.code);
    }

    return try collectWithEntrySourceWithOptions(alloc, io, options, user_path, entry_source.code);
}

pub fn collectModule(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    core_dir: []const u8,
    module_dir: []const u8,
) !std.array_list.Managed(SourceFile) {
    return try collectModuleWithOptions(alloc, io, .{ .fallback_core_dir = core_dir }, module_dir);
}

pub fn collectModuleWithOptions(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    options: CoreResolutionOptions,
    module_dir: []const u8,
) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &list);

    const resolved_core_dir = try resolveToolCoreDir(alloc, io, options);
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

    try collectRgFilesRecursively(alloc, io, &list, resolved_core_dir, &seen_files);

    try validateModuleGraphAcyclic(
        alloc,
        io,
        resolved_module_dir,
        null,
        null,
        &acyclic_dirs,
        &stack,
    );
    try collectModuleOrder(
        alloc,
        io,
        resolved_module_dir,
        null,
        null,
        &ordered_seen,
        &ordered_dirs,
    );

    for (ordered_dirs.items) |dir_path| {
        try collectRgFilesInDir(alloc, io, &list, dir_path, null, &seen_files);
    }

    return list;
}

pub fn collectWithEntrySource(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    core_dir: []const u8,
    user_path: []const u8,
    user_code: []const u8,
) !std.array_list.Managed(SourceFile) {
    return try collectWithEntrySourceWithOptions(
        alloc,
        io,
        .{ .fallback_core_dir = core_dir },
        user_path,
        user_code,
    );
}

pub fn collectWithEntrySourceWithOptions(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    options: CoreResolutionOptions,
    user_path: []const u8,
    user_code: []const u8,
) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &list);

    const resolved_core_dir = try resolveToolCoreDir(alloc, io, options);
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
    try collectRgFilesRecursively(alloc, io, &list, resolved_core_dir, &seen_files);

    // ─── carpeta del entrypoint del usuario y imports explícitos ─────────
    const user_dir = std.fs.path.dirname(user_path) orelse ".";
    const root_module_dir = try alloc.dupe(u8, user_dir);
    defer alloc.free(root_module_dir);
    try validateModuleGraphAcyclic(
        alloc,
        io,
        root_module_dir,
        user_path,
        entry_source,
        &acyclic_dirs,
        &stack,
    );
    try collectModuleOrder(
        alloc,
        io,
        root_module_dir,
        user_path,
        entry_source,
        &ordered_seen,
        &ordered_dirs,
    );

    for (ordered_dirs.items) |dir_path| {
        const skip_path = if (std.mem.eql(u8, dir_path, user_dir)) user_path else null;
        try collectRgFilesInDir(alloc, io, &list, dir_path, skip_path, &seen_files);
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
