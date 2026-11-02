const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const source_db = @import("../../1_base/source_db.zig");

/// Qualifiers retain their first token; the final member token bounds the path.
/// This preserves compact syntax storage and keeps whitespace out of identity.
pub fn build(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8, first: syn.TokenIndex, member: syn.TokenIndex, root: []const u8) ![]u8 {
    var result: std.Io.Writer.Allocating = .init(allocator);
    defer result.deinit();
    try result.writer.writeAll(std.mem.trim(u8, root, "\"'"));
    for (@intFromEnum(first) + 1..@intFromEnum(member)) |index| {
        const token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(index)));
        if (tree.tokens.items(.content)[index] == .identifier) {
            try result.writer.writeByte('/');
            try result.writer.writeAll(tree.tokenTextFromSource(source, token));
        }
    }
    return allocator.dupe(u8, result.written());
}

pub fn symbolic(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8, first: syn.TokenIndex, member: syn.TokenIndex) ![]u8 {
    const name = tree.tokenTextFromSource(source, first);
    const root = if (@intFromEnum(member) > @intFromEnum(first) + 2)
        try std.fmt.allocPrint(allocator, "@alias:{s}", .{name})
    else
        try allocator.dupe(u8, name);
    defer allocator.free(root);
    return build(allocator, tree, source, first, member, root);
}

/// Only discovered modules can turn a field prefix into a namespace path.
/// Other prefixes remain ordinary record/value projections.
pub fn isDiscovered(allocator: std.mem.Allocator, db: *const source_db.SourceDb, owner_dir: []const u8, path: []const u8) !bool {
    const relative = std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../");
    const resolved = if (relative) try std.fs.path.resolve(allocator, &.{ owner_dir, path }) else null;
    defer if (resolved) |value| allocator.free(value);
    for (db.files) |file| {
        const dir = std.fs.path.dirname(file.path) orelse continue;
        if (resolved) |value| {
            if (std.mem.eql(u8, dir, value)) return true;
        } else {
            const suffix = if (std.mem.startsWith(u8, path, ".../")) path[4..] else path;
            if (std.mem.eql(u8, dir, suffix)) return true;
            if (dir.len > suffix.len and std.mem.endsWith(u8, dir, suffix) and std.fs.path.isSep(dir[dir.len - suffix.len - 1])) return true;
        }
    }
    return false;
}

pub fn intern(writer: anytype, tree: *const syn.FileSyntaxTree, source: []const u8, first: syn.TokenIndex, member: syn.TokenIndex) !@import("../primitives/schema.zig").StringRange {
    const path = try symbolic(writer.allocator, tree, source, first, member);
    defer writer.allocator.free(path);
    return writer.addString(path);
}
