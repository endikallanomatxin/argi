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
};

/// File metadata shared by tokenizing, syntaxing, and diagnostics. This first
/// migration stage keeps existing Locations compatible; the next stage will
/// make Location carry FileId and resolve paths/line columns through this DB.
pub const SourceDb = struct {
    files: []const File = &.{},

    pub fn init(allocator: std.mem.Allocator, sources: []const sf.SourceFile) !SourceDb {
        const files = try allocator.alloc(File, sources.len);
        for (sources, 0..) |source, index| {
            files[index] = .{
                .path = source.path,
                .source = source.code,
                .origin = source.origin,
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

    pub fn findPath(self: *const SourceDb, path: []const u8) ?FileId {
        for (self.files, 0..) |file, index| {
            if (std.mem.eql(u8, file.path, path)) return self.fileId(index);
        }
        return null;
    }
};
