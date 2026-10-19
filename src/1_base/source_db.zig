const std = @import("std");
const sf = @import("source_files.zig");

/// Stable identity of a source buffer within one frontend invocation. Retained
/// and cached semantic graphs match paths and content hashes instead of storing
/// this invocation-local index. Tokens keep compact indices into this database.
pub const FileId = enum(u32) { unknown = std.math.maxInt(u32), _ };

pub fn contentHash(source: []const u8) u64 {
    return std.hash.Wyhash.hash(0, source);
}

pub const File = struct {
    path: []const u8,
    source: []const u8,
    content_hash: u64,
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
    // Only files.len entries are initialized; append may relocate the index,
    // but FileIds and the borrowed path/source buffers remain unchanged.
    file_capacity: usize = 0,

    pub fn init(allocator: std.mem.Allocator, sources: []const sf.SourceFile) !SourceDb {
        const files = try allocator.alloc(File, sources.len);
        var initialized: usize = 0;
        errdefer {
            for (files[0..initialized]) |file| allocator.free(file.line_starts);
            allocator.free(files);
        }
        for (sources, 0..) |source, index| {
            files[index] = .{
                .path = source.path,
                .source = source.code,
                .content_hash = contentHash(source.code),
                .origin = source.origin,
                .line_starts = try collectLineStarts(allocator, source.code),
            };
            initialized += 1;
        }
        return .{ .files = files, .file_capacity = files.len };
    }

    pub fn append(self: *SourceDb, allocator: std.mem.Allocator, source: sf.SourceFile) !FileId {
        if (self.files.len >= std.math.maxInt(u32)) return error.SourceIdentityLimit;
        const count = self.files.len + 1;
        const previous = @constCast(self.files.ptr)[0..@max(self.file_capacity, self.files.len)];
        const grow = previous.len < count;
        const capacity = if (grow) try std.math.ceilPowerOfTwo(usize, @max(count, 4)) else previous.len;
        const files = if (grow) try allocator.alloc(File, capacity) else previous;
        errdefer if (grow) allocator.free(files);
        if (grow) @memcpy(files[0..self.files.len], self.files);
        files[self.files.len] = .{
            .path = source.path,
            .source = source.code,
            .content_hash = contentHash(source.code),
            .origin = source.origin,
            .line_starts = try collectLineStarts(allocator, source.code),
        };
        const id = self.fileId(self.files.len);
        if (grow) allocator.free(previous);
        self.file_capacity = files.len;
        self.files = files[0..count];
        return id;
    }

    pub fn deinit(self: *SourceDb, allocator: std.mem.Allocator) void {
        for (self.files) |file| allocator.free(file.line_starts);
        allocator.free(self.files.ptr[0..@max(self.file_capacity, self.files.len)]);
        self.* = .{};
    }

    /// Clones only the lookup index. Paths and source buffers are immutable
    /// source-file ownership, so locations can be retained without copying
    /// either token text or whole files.
    pub fn clone(self: *const SourceDb, allocator: std.mem.Allocator) !SourceDb {
        const files = try allocator.alloc(File, self.files.len);
        var initialized: usize = 0;
        errdefer {
            for (files[0..initialized]) |file| allocator.free(file.line_starts);
            allocator.free(files);
        }
        for (self.files, 0..) |file, index| {
            files[index] = .{
                .path = file.path,
                .source = file.source,
                .content_hash = file.content_hash,
                .origin = file.origin,
                .line_starts = try allocator.dupe(u32, file.line_starts),
            };
            initialized += 1;
        }
        return .{ .files = files, .file_capacity = files.len };
    }

    pub fn fileId(_: *const SourceDb, index: usize) FileId {
        return @enumFromInt(@as(u32, @intCast(index)));
    }

    pub fn get(self: *const SourceDb, id: FileId) *const File {
        return &self.files[@intFromEnum(id)];
    }

    pub fn findPath(self: *const SourceDb, wanted_path: []const u8) ?FileId {
        return self.findVersion(wanted_path, null);
    }

    pub fn findVersion(self: *const SourceDb, wanted_path: []const u8, content_hash: ?u64) ?FileId {
        for (self.files, 0..) |file, index| {
            if (content_hash) |hash| if (file.content_hash != hash) continue;
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
    defer starts.deinit();
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

fn exerciseSourceDbAllocationFailures(allocator: std.mem.Allocator) !void {
    const initial = [_]sf.SourceFile{ .{ .path = "first.rg", .code = "one\ntwo\n" }, .{ .path = "second.rg", .code = "other" } };
    var db = try SourceDb.init(allocator, &initial);
    defer db.deinit(allocator);
    var clone = try db.clone(allocator);
    defer clone.deinit(allocator);
    for (0..8) |_| {
        const before = db.files.len;
        const id = db.append(allocator, .{ .path = "appended.rg", .code = "a\nb\nc" }) catch |err| {
            try std.testing.expectEqual(before, db.files.len);
            try std.testing.expectEqualStrings("one\ntwo\n", db.get(db.fileId(0)).source);
            return err;
        };
        try std.testing.expectEqual(before, @as(usize, @intFromEnum(id)));
        try std.testing.expectEqual(LineColumn{ .line = 3, .column = 1 }, db.lineColumn(id, 4));
    }
    try std.testing.expectEqual(@as(usize, 2), clone.files.len);
    _ = try clone.append(allocator, .{ .path = "clone.rg", .code = "cloned" });
    try std.testing.expectEqual(@as(usize, 10), db.files.len);
}

test "SourceDb growth and cloning preserve identities on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseSourceDbAllocationFailures, .{});
}
