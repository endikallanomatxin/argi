const std = @import("std");
const sf = @import("source_files.zig");

/// Stable identity of a source buffer within one frontend invocation. The
/// numeric representation is deliberately suitable for persisted frontend
/// artifacts; paths remain SourceDb metadata rather than token payload.
pub const FileId = enum(u32) { _ };

pub const File = struct {
    path: []const u8,
    source: []const u8,
    origin: sf.SourceFile.Origin,
    /// Byte starts for one-based diagnostic lines. This is metadata, not part
    /// of a token or syntax artifact, and lets locations stay offset-only.
    line_starts: []const u32,
};

pub const LineColumn = struct {
    line: u32,
    column: u32,
};

/// File metadata shared by tokenizing, syntaxing, and diagnostics. Locations
/// will resolve their display path and line/column through this database.
pub const SourceDb = struct {
    files: []const File = &.{},

    pub fn init(allocator: std.mem.Allocator, sources: []const sf.SourceFile) !SourceDb {
        const files = try allocator.alloc(File, sources.len);
        for (sources, 0..) |source, index| {
            files[index] = .{
                .path = source.path,
                .source = source.code,
                .origin = source.origin,
                .line_starts = try collectLineStarts(allocator, source.code),
            };
        }
        return .{ .files = files };
    }

    pub fn deinit(self: *SourceDb, allocator: std.mem.Allocator) void {
        for (self.files) |file| allocator.free(file.line_starts);
        allocator.free(self.files);
        self.* = .{};
    }

    /// Clones only the lookup index. Paths and source buffers are immutable
    /// source-file ownership, so locations can be retained without copying
    /// either token text or whole files.
    pub fn clone(self: *const SourceDb, allocator: std.mem.Allocator) !SourceDb {
        const files = try allocator.alloc(File, self.files.len);
        for (self.files, 0..) |file, index| {
            files[index] = .{
                .path = file.path,
                .source = file.source,
                .origin = file.origin,
                .line_starts = try allocator.dupe(u32, file.line_starts),
            };
        }
        return .{ .files = files };
    }

    pub fn fileId(_: *const SourceDb, index: usize) FileId {
        return @enumFromInt(@as(u32, @intCast(index)));
    }

    pub fn get(self: *const SourceDb, id: FileId) *const File {
        return &self.files[@intFromEnum(id)];
    }

    pub fn findPath(self: *const SourceDb, wanted_path: []const u8) ?FileId {
        for (self.files, 0..) |file, index| {
            if (std.mem.eql(u8, file.path, wanted_path)) return self.fileId(index);
        }
        return null;
    }

    pub fn path(self: *const SourceDb, id: FileId) []const u8 {
        return self.get(id).path;
    }

    pub fn lineColumn(self: *const SourceDb, id: FileId, offset: u32) LineColumn {
        const starts = self.get(id).line_starts;
        var low: usize = 0;
        var high: usize = starts.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (starts[middle] <= offset) low = middle + 1 else high = middle;
        }
        const line_index = low - 1;
        return .{
            .line = @intCast(line_index + 1),
            .column = offset - starts[line_index] + 1,
        };
    }
};

fn collectLineStarts(allocator: std.mem.Allocator, source: []const u8) ![]const u32 {
    var starts = std.array_list.Managed(u32).init(allocator);
    try starts.append(0);
    for (source, 0..) |byte, index| {
        if (byte == '\n' and index + 1 <= std.math.maxInt(u32)) {
            try starts.append(@intCast(index + 1));
        }
    }
    return try starts.toOwnedSlice();
}

test "SourceDb resolves file positions from byte offsets" {
    const sources = [_]sf.SourceFile{.{ .path = "sample.rg", .code = "one\ntwo\nthree" }};
    const db = try SourceDb.init(std.testing.allocator, &sources);
    defer {
        for (db.files) |file| std.testing.allocator.free(file.line_starts);
        std.testing.allocator.free(db.files);
    }

    const id = db.fileId(0);
    try std.testing.expectEqualStrings("sample.rg", db.path(id));
    try std.testing.expectEqual(LineColumn{ .line = 2, .column = 2 }, db.lineColumn(id, 5));
    try std.testing.expectEqual(LineColumn{ .line = 3, .column = 5 }, db.lineColumn(id, 12));
}
