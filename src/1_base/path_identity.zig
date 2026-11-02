const std = @import("std");
const builtin = @import("builtin");

/// Compare already-resolved source/module paths without changing their display
/// spelling. Windows accepts both separators; POSIX backslashes name characters.
/// This is lexical identity, not filesystem case folding or symlink resolution.
pub fn equal(left: []const u8, right: []const u8) bool {
    return equalFor(builtin.os.tag, left, right);
}

fn equalFor(os: std.Target.Os.Tag, left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a == b) continue;
        if (os == .windows and (a == '/' or a == '\\') and (b == '/' or b == '\\')) continue;
        return false;
    }
    return true;
}

test "resolved path identity accepts Windows separators without merging POSIX names" {
    try std.testing.expect(equalFor(.windows, "C:/project/app/main.rg", "C:\\project\\app\\main.rg"));
    try std.testing.expect(equalFor(.windows, "/project/app", "\\project\\app"));
    try std.testing.expect(!equalFor(.linux, "/project/app", "/project\\app"));
    try std.testing.expect(!equalFor(.windows, "C:/app", "D:/app"));
    try std.testing.expect(!equalFor(.windows, "C:/app", "C:/apple"));
}
