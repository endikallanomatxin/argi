const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/41X_c_allocator_zero_alignment" {
    const test_path = "tests/feature_tests/system/41X_c_allocator_zero_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
