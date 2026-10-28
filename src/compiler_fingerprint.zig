const std = @import("std");

pub const Input = struct { path: []const u8, source: bool = true };
const Entry = struct { digest: [32]u8, length: u64, parsed: bool = false };

/// Fingerprint a conservative closure of literal Zig imports and embedded files.
/// Named modules are supplied by the build; their configuration belongs in roots.
/// Imports in test declarations are deliberately included when their file is used.
pub fn compute(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, roots: []const Input) ![32]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_path = root_buffer[0..try root.realPath(io, &root_buffer)];
    var pending: std.ArrayList(Input) = .empty;
    try pending.appendSlice(a, roots);
    var entries: std.StringHashMapUnmanaged(Entry) = .empty;
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const input = pending.items[cursor];
        const absolute = try std.fs.path.resolve(a, &.{ root_path, input.path });
        const path = try std.fs.path.relative(a, root_path, null, root_path, absolute);
        if (std.fs.path.isAbsolute(path) or std.mem.eql(u8, path, "..") or std.mem.startsWith(u8, path, ".." ++ std.fs.path.sep_str))
            return error.CompilerDependencyOutsideRoot;
        const entry = try entries.getOrPut(a, path);
        if (entry.found_existing and (!input.source or entry.value_ptr.parsed)) continue;
        var file_arena = std.heap.ArenaAllocator.init(allocator);
        defer file_arena.deinit();
        const transient = file_arena.allocator();
        const contents = try root.readFileAlloc(io, path, transient, .limited(16 * 1024 * 1024));
        if (!entry.found_existing) {
            var digest: [32]u8 = undefined;
            std.crypto.hash.Blake3.hash(contents, &digest, .{});
            entry.value_ptr.* = .{ .digest = digest, .length = @intCast(contents.len) };
        }
        if (!input.source) continue;
        entry.value_ptr.parsed = true;
        const source = try transient.dupeZ(u8, contents);
        var tree = try std.zig.Ast.parse(transient, source, .zig);
        defer tree.deinit(transient);
        if (tree.errors.len != 0) return error.InvalidCompilerDependencySource;
        for (0..tree.nodes.len) |raw| {
            const node: std.zig.Ast.Node.Index = @enumFromInt(raw);
            var buffer: [2]std.zig.Ast.Node.Index = undefined;
            const arguments = tree.builtinCallParams(&buffer, node) orelse continue;
            const builtin = tree.tokenSlice(tree.nodeMainToken(node));
            const imported = std.mem.eql(u8, builtin, "@import");
            if (!imported and !std.mem.eql(u8, builtin, "@embedFile")) continue;
            // Refuse to silently omit a dependency when a future source uses
            // computed import/embed paths rather than literal ones.
            if (arguments.len != 1 or tree.nodeTag(arguments[0]) != .string_literal)
                return error.ComputedCompilerDependency;
            const name = try std.zig.string_literal.parseAlloc(transient, tree.tokenSlice(tree.nodeMainToken(arguments[0])));
            if (imported and !std.mem.endsWith(u8, name, ".zig") and std.mem.indexOfAny(u8, name, "/\\") == null) continue;
            if (std.fs.path.isAbsolute(name)) return error.CompilerDependencyOutsideRoot;
            try pending.append(a, .{
                .path = try std.fs.path.join(a, &.{ std.fs.path.dirname(path) orelse "", name }),
                .source = imported,
            });
        }
    }
    const paths = try a.alloc([]const u8, entries.count());
    var keys = entries.keyIterator();
    for (paths) |*path| path.* = keys.next().?.*;
    std.mem.sort([]const u8, paths, {}, struct {
        fn lessThan(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.lessThan);
    var hash = std.crypto.hash.Blake3.init(.{});
    for (paths) |path| {
        const entry = entries.get(path).?;
        const length = std.mem.nativeToLittle(u64, @intCast(path.len));
        hash.update(std.mem.asBytes(&length));
        for (path) |byte| hash.update(&.{if (byte == std.fs.path.sep) '/' else byte});
        const content_length = std.mem.nativeToLittle(u64, entry.length);
        hash.update(std.mem.asBytes(&content_length));
        hash.update(&entry.digest);
    }
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

test "compiler fingerprints follow imports and embeds without filename exclusions" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir;
    try root.writeFile(io, .{ .sub_path = "main.zig", .data = "const child = @import(\"feature_test.zig\"); const text = @embedFile(\"prelude.rg\");" });
    try root.writeFile(io, .{ .sub_path = "feature_test.zig", .data = "const parent = @import(\"./main.zig\");" });
    try root.writeFile(io, .{ .sub_path = "prelude.rg", .data = "initial" });
    try root.writeFile(io, .{ .sub_path = "unrelated.zig", .data = "initial" });
    const roots: []const Input = &.{.{ .path = "main.zig" }};
    const initial = try compute(a, io, root, roots);
    try root.writeFile(io, .{ .sub_path = "unrelated.zig", .data = "changed" });
    try std.testing.expectEqual(initial, try compute(a, io, root, roots));
    try root.writeFile(io, .{ .sub_path = "prelude.rg", .data = "changed" });
    const embedded = try compute(a, io, root, roots);
    try std.testing.expect(!std.mem.eql(u8, &initial, &embedded));
    try root.writeFile(io, .{ .sub_path = "feature_test.zig", .data = "const parent = @import(\"./main.zig\"); const x = true;" });
    try std.testing.expect(!std.mem.eql(u8, &embedded, &(try compute(a, io, root, roots))));
    try std.testing.expectEqual(try compute(a, io, root, roots), try compute(a, io, root, &.{ .{ .path = "feature_test.zig" }, .{ .path = "main.zig" } }));
}

test "compiler fingerprints reject missing and computed dependencies" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "main.zig", .data = "const child = @import(\"missing.zig\");" });
    try std.testing.expectError(error.FileNotFound, compute(std.testing.allocator, io, directory.dir, &.{.{ .path = "main.zig" }}));
    try directory.dir.writeFile(io, .{ .sub_path = "main.zig", .data = "const name = \"child.zig\"; const child = @import(name);" });
    try std.testing.expectError(error.ComputedCompilerDependency, compute(std.testing.allocator, io, directory.dir, &.{.{ .path = "main.zig" }}));
}

test "compiler fingerprints promote embedded sources and release failed traversal allocations" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "main.zig", .data = "const text = @embedFile(\"child.zig\"); const child = @import(\"child.zig\");" });
    try directory.dir.writeFile(io, .{ .sub_path = "child.zig", .data = "const data = @embedFile(\"data.txt\");" });
    try directory.dir.writeFile(io, .{ .sub_path = "data.txt", .data = "initial" });
    const roots: []const Input = &.{.{ .path = "main.zig" }};
    const first = try compute(std.testing.allocator, io, directory.dir, roots);
    try directory.dir.writeFile(io, .{ .sub_path = "data.txt", .data = "changed" });
    try std.testing.expect(!std.mem.eql(u8, &first, &(try compute(std.testing.allocator, io, directory.dir, roots))));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator, root: std.Io.Dir) !void {
            _ = try compute(a, std.testing.io, root, &.{.{ .path = "main.zig" }});
        }
    }.run, .{directory.dir});
}

test "compiler fingerprints are checkout independent and include build configuration" {
    const io = std.testing.io;
    var left = std.testing.tmpDir(.{});
    defer left.cleanup();
    var right = std.testing.tmpDir(.{});
    defer right.cleanup();
    for ([_]std.Io.Dir{ left.dir, right.dir }) |root| {
        try root.writeFile(io, .{ .sub_path = "main.zig", .data = "const child = @import(\"child\\x2ezig\"); const template = @embedFile(\"template.zig\");" });
        try root.writeFile(io, .{ .sub_path = "child.zig", .data = "const x = 42;" });
        try root.writeFile(io, .{ .sub_path = "template.zig", .data = "not valid Zig source" });
        try root.writeFile(io, .{ .sub_path = "build.config", .data = "schema = 1" });
    }
    const roots: []const Input = &.{ .{ .path = "main.zig" }, .{ .path = "build.config", .source = false } };
    const initial = try compute(std.testing.allocator, io, left.dir, roots);
    try std.testing.expectEqual(initial, try compute(std.testing.allocator, io, right.dir, roots));
    try right.dir.writeFile(io, .{ .sub_path = "build.config", .data = "schema = 2" });
    try std.testing.expect(!std.mem.eql(u8, &initial, &(try compute(std.testing.allocator, io, right.dir, roots))));
    try left.dir.writeFile(io, .{ .sub_path = "main.zig", .data = "const outside = @import(\"../outside.zig\");" });
    try std.testing.expectError(error.CompilerDependencyOutsideRoot, compute(std.testing.allocator, io, left.dir, roots));
}
