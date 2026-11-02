const std = @import("std");
const graph = @import("graph.zig");
const diagnostics = @import("../../1_base/diagnostic.zig");
const source_db = @import("../../1_base/source_db.zig");
const source = @import("../primitives/schema.zig");
const token = @import("../../2_tokens/token.zig");

/// Match the retained graph's original source version, not just its path.
/// Content hashes survive module caching; invocation-local source IDs do not.
/// Synthetic graphs without source metadata retain their path-only lookup.
pub fn find(g: *const graph.GlobalSemanticGraph, db: *const source_db.SourceDb, ref: source.SourceRef) ?token.Location {
    if (ref.file_index >= g.files.items.len) return null;
    const file = g.files.items[ref.file_index];
    const directory = g.text(g.modules.items[@intFromEnum(file.module)].dir);
    for (db.files, 0..) |candidate, index| {
        if (file.content_hash) |hash| if (candidate.content_hash != hash) continue;
        if (std.mem.eql(u8, std.fs.path.basename(candidate.path), g.text(file.path)) and
            std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", directory))
            return .{ .file = db.fileId(index), .offset = ref.offset };
    }
    return null;
}

pub fn location(g: *const graph.GlobalSemanticGraph, bag: *const diagnostics.Diagnostics, ref: source.SourceRef) token.Location {
    return find(g, &bag.source_db, ref) orelse .{ .file = .unknown, .offset = ref.offset };
}

test "retained source lookup distinguishes versions sharing one path" {
    const a = std.testing.allocator;
    const files = [_]@import("../../1_base/source_files.zig").SourceFile{
        .{ .path = "/library/main.rg", .code = "old source" },
        .{ .path = "/library/main.rg", .code = "new source\nsecond line" },
    };
    var db = try source_db.SourceDb.init(a, &files);
    defer db.deinit(a);
    try std.testing.expectEqual(db.fileId(1), db.findVersion(files[1].path, db.files[1].content_hash).?);
    var retained = try db.clone(a);
    defer retained.deinit(a);
    var g: graph.GlobalSemanticGraph = .{};
    defer g.deinit(a);
    try g.modules.append(a, .{ .dir = try g.addString(a, "/library"), .files = .{ .start = 0, .len = 1 }, .declarations = .{ .start = 0, .len = 0 } });
    try g.files.append(a, .{ .module = @enumFromInt(0), .path = try g.addString(a, "main.rg"), .content_hash = db.files[1].content_hash });
    const ref: source.SourceRef = .{ .file_index = 0, .offset = 11 };
    try std.testing.expectEqual(db.fileId(1), find(&g, &retained, ref).?.file);
    g.files.items[0].content_hash = db.files[0].content_hash;
    try std.testing.expectEqual(db.fileId(0), find(&g, &retained, ref).?.file);
    g.files.items[0].content_hash = source_db.contentHash("unretained version");
    try std.testing.expectEqual(null, find(&g, &retained, ref));
    g.files.items[0].content_hash = null;
    try std.testing.expectEqual(db.fileId(0), find(&g, &retained, ref).?.file);
}
