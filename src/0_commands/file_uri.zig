const std = @import("std");

// File URIs always use forward slashes. A Windows drive is part of the URI
// path, while a UNC server is its authority; neither is a POSIX root prefix.
pub fn encode(allocator: std.mem.Allocator, path: []const u8, windows: bool) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.appendSlice(allocator, "file://");
    const unc = windows and path.len >= 2 and separator(path[0]) and separator(path[1]);
    if (windows and !unc) try result.append(allocator, '/');
    const bytes = if (unc) path[2..] else path;
    const hex = "0123456789ABCDEF";
    for (bytes) |byte| {
        const value: u8 = if (windows and byte == '\\') '/' else byte;
        if (std.ascii.isAlphanumeric(value) or std.mem.indexOfScalar(u8, "-._~/:", value) != null) {
            try result.append(allocator, value);
        } else {
            try result.appendSlice(allocator, &.{ '%', hex[value >> 4], hex[value & 15] });
        }
    }
    return result.toOwnedSlice(allocator);
}

fn separator(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

pub fn decode(allocator: std.mem.Allocator, uri: []const u8, windows: bool) !?[]u8 {
    if (!std.mem.startsWith(u8, uri, "file://")) return null;
    const rest = uri[7..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const authority = rest[0..slash];
    const local = authority.len == 0 or std.ascii.eqlIgnoreCase(authority, "localhost");
    if (!local and !windows) return null;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    if (!local) {
        try result.appendSlice(allocator, "//");
        try result.appendSlice(allocator, authority);
    }
    var path = rest[slash..];
    if (windows and local and path.len >= 3 and path[0] == '/' and std.ascii.isAlphabetic(path[1]) and path[2] == ':') path = path[1..];
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        var byte = path[index];
        if (byte == '?' or byte == '#') return null;
        if (byte == '%') {
            if (index + 2 >= path.len) return null;
            const high = std.fmt.charToDigit(path[index + 1], 16) catch return null;
            const low = std.fmt.charToDigit(path[index + 2], 16) catch return null;
            byte = @intCast(high * 16 + low);
            index += 2;
        }
        if (byte == 0) return null;
        try result.append(allocator, byte);
    }
    return try result.toOwnedSlice(allocator);
}

test "file URIs preserve Windows drives, UNC paths and escaped names" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { path: []const u8, uri: []const u8, decoded: []const u8, windows: bool }{
        .{ .path = "C:\\project files\\main#.rg", .uri = "file:///C:/project%20files/main%23.rg", .decoded = "C:/project files/main#.rg", .windows = true },
        .{ .path = "\\\\server\\share\\main.rg", .uri = "file://server/share/main.rg", .decoded = "//server/share/main.rg", .windows = true },
        .{ .path = "/tmp/a% b.rg", .uri = "file:///tmp/a%25%20b.rg", .decoded = "/tmp/a% b.rg", .windows = false },
    };
    for (cases) |case| {
        const uri = try encode(allocator, case.path, case.windows);
        defer allocator.free(uri);
        try std.testing.expectEqualStrings(case.uri, uri);
        const path = (try decode(allocator, uri, case.windows)).?;
        defer allocator.free(path);
        try std.testing.expectEqualStrings(case.decoded, path);
    }
    const local = (try decode(allocator, "file://localhost/C:/main.rg", true)).?;
    defer allocator.free(local);
    try std.testing.expectEqualStrings("C:/main.rg", local);
    for ([_][]const u8{ "file:///a%00b", "file:///a%xx", "file:///a%", "file://remote/a", "https://host/a" }) |uri| {
        try std.testing.expectEqual(@as(?[]u8, null), try decode(allocator, uri, false));
    }
}
