const std = @import("std");
const lexical = @import("lexical.zig");

/// In-memory buffer for a source file.
pub const SourceFile = struct {
    path: []const u8, // ruta (relativa a cwd)
    code: []const u8, // contenido completo
    origin: Origin = .user,

    pub const Origin = enum { user, bundled_core };
};

fn markBundledCore(files: []SourceFile) void {
    for (files) |*file| file.origin = .bundled_core;
}

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
    target: @import("target.zig").Config = .{},
    /// Editor/session buffers participate in discovery, cycle checks, and loading.
    /// Origin is assigned by the loader, never by the supplied override.
    source_overrides: []const SourceFile = &.{},
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

    // Match the relocatable core layout. Working-tree candidates remain
    // available for library development; installed imports need no checkout.
    // TODO: Thread explicit sysroot selection through more import discovery.
    const installed_more = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "lib", "argi", "more" });
    defer alloc.free(installed_more);

    const bundled_more = try std.fs.path.resolve(alloc.*, &.{ exe_dir, "..", "..", "..", "more" });
    defer alloc.free(bundled_more);

    return try firstExistingDir(alloc, io, &.{
        "more",
        "../more",
        installed_more,
        bundled_more,
    });
}

fn collectRgFilesRecursively(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    seen_files: *DirSet,
    overrides: []const SourceFile,
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
        try list.append(try readSource(alloc, io, full_path, overrides));
    }
}

fn collectRgFilesInDir(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    list: *std.array_list.Managed(SourceFile),
    dir_path: []const u8,
    skip_path: ?[]const u8,
    seen_files: *DirSet,
    overrides: []const SourceFile,
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

    for (overrides) |source| {
        if (!std.mem.endsWith(u8, source.path, ".rg")) continue;
        if (!std.mem.eql(u8, std.fs.path.dirname(source.path) orelse ".", dir_path)) continue;
        if (skip_path) |skip| if (std.mem.eql(u8, source.path, skip)) continue;
        if (seen_files.contains(source.path)) continue;
        var found = false;
        for (paths.items) |path| if (std.mem.eql(u8, path, source.path)) {
            found = true;
            break;
        };
        if (!found) try paths.append(try alloc.dupe(u8, source.path));
    }

    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    for (paths.items) |full_path| {
        try seen_files.put(try alloc.dupe(u8, full_path), {});
        try list.append(try readSource(alloc, io, full_path, overrides));
    }
}

fn collectImportDirsFromSource(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    source_path: []const u8,
    source_code: []const u8,
    imports: *ImportList,
    target: @import("target.zig").Config,
) !void {
    var error_offset: usize = 0;
    const selected = @import("target_selection.zig").selectImports(alloc.*, source_code, target, &error_offset) catch |err| {
        var line: usize = 1;
        var column: usize = 1;
        for (source_code[0..@min(error_offset, source_code.len)]) |byte| {
            if (byte == '\n') {
                line += 1;
                column = 1;
            } else column += 1;
        }
        std.debug.print("{s}:{d}:{d}: error: invalid target selection: {s}\n", .{ source_path, line, column, @import("target_selection.zig").errorMessage(err) });
        return err;
    };
    defer alloc.free(selected);
    var offset: usize = 0;
    while (offset < source_code.len) {
        const parsed = nextImportDirective(selected, &offset) orelse break;
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

// Discover only directory prefixes actually named through an import alias.
// Tokenizing keeps strings/comments and discarded target branches out of this scan.
fn collectModuleImports(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    sources: []const SourceFile,
    imports: *ImportList,
    target: @import("target.zig").Config,
) !void {
    for (sources) |source| try collectImportDirsFromSource(alloc, io, source.path, source.code, imports, target);
    if (imports.items.len == 0) return;
    var arena = std.heap.ArenaAllocator.init(alloc.*);
    defer arena.deinit();
    const temporary = arena.allocator();
    const Token = @import("../2_tokens/token.zig");
    const Scan = struct { source: SourceFile, tokens: Token.View };
    const Alias = struct { name: []const u8, dir: []const u8 };
    var scans: std.ArrayList(Scan) = .empty;
    var aliases: std.ArrayList(Alias) = .empty;
    for (sources) |source| {
        var error_offset: usize = 0;
        const selected = try @import("target_selection.zig").select(temporary, source.code, target, &error_offset);
        var diagnostics = @import("diagnostic.zig").Diagnostics.init(&temporary, &.{source});
        var lexer = @import("../2_tokens/tokenizer.zig").Tokenizer.init(temporary, &diagnostics, selected, diagnostics.source_db.fileId(0));
        const tokens = lexer.tokenize() catch continue; // Ordinary parsing diagnoses invalid sources.
        if (diagnostics.hasErrors()) continue;
        try scans.append(temporary, .{ .source = source, .tokens = tokens });
        for (tokens.contents, 0..) |token, index| {
            if (token != .keyword_import) continue;
            // Module aliases use `name := import(...)` (also accept mutable spelling).
            var before = index;
            while (before != 0 and (tokens.contents[before - 1] == .new_line or tokens.contents[before - 1] == .comment)) before -= 1;
            if (before == 0 or tokens.contents[before - 1] != .equal) continue;
            before -= 1;
            while (before != 0 and (tokens.contents[before - 1] == .colon or tokens.contents[before - 1] == .double_colon)) before -= 1;
            if (before == 0 or tokens.contents[before - 1] != .identifier) continue;
            const directive = parseImportDirective(selected, tokens.locations[index].offset) orelse continue;
            const name = tokens.contents[before - 1].identifier.slice(selected);
            const dir = try resolveImportDir(&temporary, io, source.path, directive.path);
            try aliases.append(temporary, .{ .name = name, .dir = dir });
        }
    }
    for (scans.items) |scan| {
        for (scan.tokens.contents, 0..) |token, index| {
            if (token != .identifier) continue;
            if (index != 0 and scan.tokens.contents[index - 1] == .dot) continue;
            const name = token.identifier.slice(scan.source.code);
            for (aliases.items) |alias| {
                if (!std.mem.eql(u8, name, alias.name)) continue;
                var dir = alias.dir;
                var cursor = index + 1;
                while (cursor + 1 < scan.tokens.len and scan.tokens.contents[cursor] == .dot and scan.tokens.contents[cursor + 1] == .identifier) {
                    const child = scan.tokens.contents[cursor + 1].identifier.slice(scan.source.code);
                    const candidate = try std.fs.path.join(temporary, &.{ dir, child });
                    if (!dirExists(io, candidate)) break;
                    try validateDirectoryPrivacy(scan.source.path, candidate, alias.dir);
                    dir = candidate;
                    cursor += 2;
                    var known = false;
                    for (imports.items) |entry| if (std.mem.eql(u8, entry.resolved_dir, dir)) {
                        known = true;
                        break;
                    };
                    if (!known) try imports.append(.{
                        .raw_path = try alloc.dupe(u8, dir),
                        .importer_path = try alloc.dupe(u8, scan.source.path),
                        .resolved_dir = try alloc.dupe(u8, dir),
                    });
                }
            }
        }
    }
}

fn validateDirectoryPrivacy(importer_path: []const u8, resolved: []const u8, trusted_prefix: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const importer = try std.fs.path.resolve(allocator, &.{std.fs.path.dirname(importer_path) orelse "."});
    defer allocator.free(importer);
    var components = std.fs.path.componentIterator(resolved);
    while (components.next()) |component| {
        // Installation directories and an already-checked imported root do not
        // become private submodules merely because their host path starts '_'.
        if (trusted_prefix) |prefix| if (component.path.len <= prefix.len and std.mem.startsWith(u8, prefix, component.path)) continue;
        if (!std.mem.startsWith(u8, component.name, "_")) continue;
        const parent = std.fs.path.dirname(component.path) orelse continue;
        if (std.mem.eql(u8, importer, parent) or
            (std.mem.startsWith(u8, importer, parent) and importer.len > parent.len and std.fs.path.isSep(importer[parent.len]))) continue;
        std.debug.print("{s}: error: submodule '{s}' is private to '{s}' and its descendants\n", .{ importer_path, component.name, parent });
        return error.PrivateModule;
    }
}

const ParsedImportDirective = struct {
    import_offset: usize,
    path: []const u8,
    next_offset: usize,
};

pub fn firstImportDirectiveOffset(source_code: []const u8) ?usize {
    var offset: usize = 0;
    return if (nextImportDirective(source_code, &offset)) |parsed| parsed.import_offset else null;
}

fn nextImportDirective(source_code: []const u8, offset: *usize) ?ParsedImportDirective {
    while (offset.* < source_code.len) {
        if (source_code[offset.*] == '-' and offset.* + 1 < source_code.len and source_code[offset.* + 1] == '-') {
            offset.* = lexical.commentEnd(source_code, offset.*);
            continue;
        }

        if (source_code[offset.*] == '"' or source_code[offset.*] == '\'') {
            offset.* = lexical.quoted(source_code, offset.*).end;
            continue;
        }

        if (source_code[offset.*] != 'i' or
            (offset.* > 0 and (lexical.identifierContinue(source_code[offset.* - 1]) or source_code[offset.* - 1] == '#')))
        {
            offset.* += 1;
            continue;
        }

        const import_offset = offset.*;
        const parsed = parseImportDirective(source_code, import_offset) orelse {
            offset.* += 1;
            continue;
        };
        return parsed;
    }

    return null;
}

fn skipWhitespace(source_code: []const u8, offset: *usize) void {
    while (offset.* < source_code.len and std.ascii.isWhitespace(source_code[offset.*])) : (offset.* += 1) {}
}

fn parseImportDirective(source_code: []const u8, import_offset: usize) ?ParsedImportDirective {
    var offset = import_offset;
    const import_name = "import";
    if (offset + import_name.len > source_code.len) return null;
    if (!std.mem.eql(u8, source_code[offset .. offset + import_name.len], import_name)) return null;
    offset += import_name.len;
    if (offset < source_code.len and lexical.identifierContinue(source_code[offset])) return null;

    skipWhitespace(source_code, &offset);
    if (offset >= source_code.len or source_code[offset] != '(') return null;
    offset += 1;
    skipWhitespace(source_code, &offset);
    if (offset >= source_code.len or source_code[offset] != '"') return null;
    const literal = lexical.quoted(source_code, offset);
    if (!literal.closed) return null;
    const path = source_code[offset + 1 .. literal.content_end];
    offset = literal.end;
    skipWhitespace(source_code, &offset);
    if (offset >= source_code.len or source_code[offset] != ')') return null;
    return .{
        .import_offset = import_offset,
        .path = path,
        .next_offset = offset + 1,
    };
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
        const resolved = try std.fs.path.resolve(alloc.*, &.{ base_dir, import_path });
        errdefer alloc.free(resolved);
        try validateDirectoryPrivacy(importer_path, resolved, null);
        return resolved;
    }

    if (std.mem.startsWith(u8, import_path, ".../")) {
        const project_root = try findProjectRoot(alloc, io, importer_path);
        defer alloc.free(project_root);
        const resolved = try std.fs.path.resolve(alloc.*, &.{ project_root, import_path[4..] });
        errdefer alloc.free(resolved);
        try validateDirectoryPrivacy(importer_path, resolved, null);
        return resolved;
    }

    const more_root = try resolveToolMoreDir(alloc, io);
    defer alloc.free(more_root);
    const resolved = try std.fs.path.resolve(alloc.*, &.{ more_root, import_path });
    errdefer alloc.free(resolved);
    try validateDirectoryPrivacy(importer_path, resolved, more_root);
    return resolved;
}

fn scanImports(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    source: SourceFile,
    module_dirs: *DirSet,
    target: @import("target.zig").Config,
) !void {
    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    try collectImportDirsFromSource(alloc, io, source.path, source.code, &imports, target);
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
        \\-- ignored := import("./comment_dep")
        \\message := "import(\"./string_dep\")"
        \\quote := '#'
        \\notimport("./identifier_dep")
        \\importer("./suffix_dep")
        \\old := #import("./old_dep")
        \\dep := import("./real_dep")
        \\spaced := import ( "./spaced_dep" )
    ,
        &imports,
        .{},
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
        "message := \"import(\\\"./string_dep\\\")",
        &imports,
        .{},
    );

    try std.testing.expectEqual(@as(usize, 0), imports.items.len);
}

test "first import offset uses lexical import scanner" {
    const source =
        \\-- ignored := import("./comment_dep")
        \\message := "import(\"./string_dep\")"
        \\dep := import("./real_dep")
    ;

    const offset = firstImportDirectiveOffset(source) orelse return error.ExpectedImportOffset;
    try std.testing.expectEqualStrings("import", source[offset .. offset + "import".len]);
    try std.testing.expect(std.mem.indexOf(u8, source[0..offset], "dep :=") != null);
}

test "import discovery shares quoted boundaries with conditional selection" {
    const prefixes = [_][]const u8{
        "message := \"escaped \\\" #if hidden { import(\\\"./ignored\\\") }\"\n",
        "quote := '\\''\n-- #if hidden { import(\"./ignored\") }\n",
        "message := \"\\q #if hidden { import(\\\"./ignored\\\") }\"\n",
    };
    const suffix = "dep := import(\"./real\")";
    for (prefixes) |prefix| {
        const source = try std.mem.concat(std.testing.allocator, u8, &.{ prefix, suffix });
        defer std.testing.allocator.free(source);
        var offset: usize = 0;
        const parsed = nextImportDirective(source, &offset) orelse return error.ExpectedImport;
        try std.testing.expectEqualStrings("./real", parsed.path);
        var error_offset: usize = 0;
        var plan = try @import("conditional_source.zig").Plan.parse(std.testing.allocator, source, &error_offset);
        defer plan.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), plan.branches.items.len);
    }
    for ([_][]const u8{ "\"trailing\\", "'trailing\\", "import(\"trailing\\" }) |source| {
        var offset: usize = 0;
        try std.testing.expectEqual(null, nextImportDirective(source, &offset));
        try std.testing.expect(offset <= source.len);
    }
    const escaped = "import(\"./escaped\\\"path\") tail";
    const parsed = parseImportDirective(escaped, 0) orelse return error.ExpectedImport;
    try std.testing.expectEqualStrings("./escaped\\\"path", parsed.path);
    try std.testing.expectEqualStrings(" tail", escaped[parsed.next_offset..]);
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
    overrides: []const SourceFile,
    visited_dirs: *DirSet,
    stack: *std.array_list.Managed([]const u8),
    target: @import("target.zig").Config,
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

    try collectRgFilesInDir(alloc, io, &module_files, dir_path, skip_path, &seen_module_files, overrides);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    try collectModuleImports(alloc, io, module_files.items, &imports, target);

    for (imports.items) |entry| {
        if (visited_dirs.contains(entry.resolved_dir)) continue;
        try ensureImportDirExists(io, entry);
        try validateModuleGraphAcyclic(alloc, io, entry.resolved_dir, null, null, overrides, visited_dirs, stack, target);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
}

fn collectModuleOrder(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    dir_path: []const u8,
    skip_path: ?[]const u8,
    entry_override: ?SourceFile,
    overrides: []const SourceFile,
    visited_dirs: *DirSet,
    ordered_dirs: *std.array_list.Managed([]const u8),
    target: @import("target.zig").Config,
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

    try collectRgFilesInDir(alloc, io, &module_files, dir_path, skip_path, &seen_module_files, overrides);
    if (entry_override) |entry_source| {
        try module_files.append(.{
            .path = try alloc.dupe(u8, entry_source.path),
            .code = try alloc.dupe(u8, entry_source.code),
        });
    }

    var imports = ImportList.init(alloc.*);
    defer freeImportList(alloc, &imports);

    try collectModuleImports(alloc, io, module_files.items, &imports, target);

    for (imports.items) |entry| {
        if (visited_dirs.contains(entry.resolved_dir)) continue;
        try ensureImportDirExists(io, entry);
        try collectModuleOrder(alloc, io, entry.resolved_dir, null, null, overrides, visited_dirs, ordered_dirs, target);
    }

    try visited_dirs.put(try alloc.dupe(u8, dir_path), {});
    try ordered_dirs.append(try alloc.dupe(u8, dir_path));
}

fn readSource(alloc: *const std.mem.Allocator, io: std.Io, path: []const u8, overrides: []const SourceFile) !SourceFile {
    for (overrides) |source| {
        if (!std.mem.eql(u8, source.path, path)) continue;
        const owned_path = try alloc.dupe(u8, path);
        errdefer alloc.free(owned_path);
        return .{ .path = owned_path, .code = try alloc.dupe(u8, source.code) };
    }
    return readFile(alloc, io, path);
}

/// Reads a single file.
pub fn readFile(alloc: *const std.mem.Allocator, io: std.Io, path: []const u8) !SourceFile {
    const code = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc.*, .limited(1 << 24)); // 16 MiB maximum.
    return .{ .path = try alloc.dupe(u8, path), .code = code };
}

/// Collects all `.rg` files from `core_dir` and `user_path`.
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

/// Load the installed core without inventing a user module or an entrypoint.
/// Retained interactive frontends can prepare these same module artifacts once.
pub fn collectCoreWithOptions(alloc: *const std.mem.Allocator, io: std.Io, options: CoreResolutionOptions) !std.array_list.Managed(SourceFile) {
    var list = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &list);
    const directory = try resolveToolCoreDir(alloc, io, options);
    defer alloc.free(directory);
    var seen = DirSet.init(alloc.*);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| alloc.free(entry.key_ptr.*);
        seen.deinit();
    }
    try collectRgFilesRecursively(alloc, io, &list, directory, &seen, options.source_overrides);
    markBundledCore(list.items);
    return list;
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

    const core_start = list.items.len;
    try collectRgFilesRecursively(alloc, io, &list, resolved_core_dir, &seen_files, options.source_overrides);
    markBundledCore(list.items[core_start..]);

    try validateModuleGraphAcyclic(
        alloc,
        io,
        resolved_module_dir,
        null,
        null,
        options.source_overrides,
        &acyclic_dirs,
        &stack,
        options.target,
    );
    try collectModuleOrder(
        alloc,
        io,
        resolved_module_dir,
        null,
        null,
        options.source_overrides,
        &ordered_seen,
        &ordered_dirs,
        options.target,
    );

    for (ordered_dirs.items) |dir_path| {
        const before = list.items.len;
        try collectRgFilesInDir(alloc, io, &list, dir_path, null, &seen_files, options.source_overrides);
        // Retain namespace-only modules in the frontend's directory grouping.
        // This empty buffer is in memory only; no source file is created on disk.
        if (list.items.len == before) try list.append(.{
            .path = try std.fs.path.join(alloc.*, &.{ dir_path, ".argi-empty-module.rg" }),
            .code = try alloc.dupe(u8, ""),
        });
    }

    return list;
}

/// Discover only an in-memory submission's dependencies. Accepted module
/// directories are immutable leaves: neither reread nor rediscover their files.
/// Source paths use the caller's real import base, independently of submission IDs.
pub fn collectImportedModules(
    alloc: *const std.mem.Allocator,
    io: std.Io,
    source: SourceFile,
    retained_dirs: []const []const u8,
    options: CoreResolutionOptions,
) !std.array_list.Managed(SourceFile) {
    var arena = std.heap.ArenaAllocator.init(alloc.*);
    defer arena.deinit();
    const scratch = arena.allocator();
    var imports = ImportList.init(scratch);
    try collectImportDirsFromSource(&scratch, io, source.path, source.code, &imports, options.target);
    var visited = DirSet.init(scratch);
    var ordered_seen = DirSet.init(scratch);
    for (retained_dirs) |dir| {
        try visited.put(dir, {});
        try ordered_seen.put(dir, {});
    }
    var stack = std.array_list.Managed([]const u8).init(scratch);
    var ordered = std.array_list.Managed([]const u8).init(scratch);
    for (imports.items) |entry| {
        if (visited.contains(entry.resolved_dir)) continue;
        try ensureImportDirExists(io, entry);
        try validateModuleGraphAcyclic(&scratch, io, entry.resolved_dir, null, null, options.source_overrides, &visited, &stack, options.target);
    }
    for (imports.items) |entry|
        try collectModuleOrder(&scratch, io, entry.resolved_dir, null, null, options.source_overrides, &ordered_seen, &ordered, options.target);
    var files = std.array_list.Managed(SourceFile).init(scratch);
    var seen = DirSet.init(scratch);
    for (ordered.items) |dir|
        try collectRgFilesInDir(&scratch, io, &files, dir, null, &seen, options.source_overrides);
    var result = std.array_list.Managed(SourceFile).init(alloc.*);
    errdefer freeList(alloc, &result);
    for (files.items) |file| {
        const path = try alloc.dupe(u8, file.path);
        errdefer alloc.free(path);
        const code = try alloc.dupe(u8, file.code);
        errdefer alloc.free(code);
        try result.append(.{ .path = path, .code = code });
    }
    return result;
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
    const core_start = list.items.len;
    try collectRgFilesRecursively(alloc, io, &list, resolved_core_dir, &seen_files, options.source_overrides);
    markBundledCore(list.items[core_start..]);

    // ─── user entry-point directory and explicit imports ────────────────
    const user_dir = std.fs.path.dirname(user_path) orelse ".";
    const root_module_dir = try alloc.dupe(u8, user_dir);
    defer alloc.free(root_module_dir);
    try validateModuleGraphAcyclic(
        alloc,
        io,
        root_module_dir,
        user_path,
        entry_source,
        options.source_overrides,
        &acyclic_dirs,
        &stack,
        options.target,
    );
    try collectModuleOrder(
        alloc,
        io,
        root_module_dir,
        user_path,
        entry_source,
        options.source_overrides,
        &ordered_seen,
        &ordered_dirs,
        options.target,
    );

    for (ordered_dirs.items) |dir_path| {
        const skip_path = if (std.mem.eql(u8, dir_path, user_dir)) user_path else null;
        const before = list.items.len;
        try collectRgFilesInDir(alloc, io, &list, dir_path, skip_path, &seen_files, options.source_overrides);
        if (list.items.len == before and !std.mem.eql(u8, dir_path, user_dir)) try list.append(.{
            .path = try std.fs.path.join(alloc.*, &.{ dir_path, ".argi-empty-module.rg" }),
            .code = try alloc.dupe(u8, ""),
        });
    }

    // ─── user entry point at the end ────────────────────────────────────
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

/// Frees the `code` buffers and the list.
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

test "module directory privacy ignores the installation prefix" {
    try validateDirectoryPrivacy("/outside/main.rg", "/tools/_installation/more/math/linear_algebra", "/tools/_installation/more");
    try validateDirectoryPrivacy("/project/tree/branch/main.rg", "/project/tree/_detail", null);
    try validateDirectoryPrivacy("/outside/main.rg", "/tools/_installation/more/math/linear_algebra", "/tools/_installation/more/math");
}
