const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/38X_c_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/38X_c_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
