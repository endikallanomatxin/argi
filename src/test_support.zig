const std = @import("std");

pub fn tmpRootPath(tmp: *const std.testing.TmpDir) ![:0]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &buffer);
    return std.testing.allocator.dupeZ(u8, buffer[0..n]);
}

pub fn tmpFilePath(tmp: *const std.testing.TmpDir, rel_path: []const u8) ![:0]u8 {
    return tmp.dir.realPathFileAlloc(std.testing.io, rel_path, std.testing.allocator);
}
