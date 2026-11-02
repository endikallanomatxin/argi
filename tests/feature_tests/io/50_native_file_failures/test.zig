const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/50_native_file_failures" {
    const os = @import("builtin").os.tag;
    if (os != .linux and os != .macos) return error.SkipZigTest;
    try support.checkNativeCFixture("tests/feature_tests/io/50_native_file_failures", &.{});
}
