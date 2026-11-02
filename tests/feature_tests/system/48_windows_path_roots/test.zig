const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/48_windows_path_roots" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const test_path = "tests/feature_tests/system/48_windows_path_roots";
    try support.expectSuccessfulBuild(test_path);
    try support.runExpect(test_path, 0);
}
