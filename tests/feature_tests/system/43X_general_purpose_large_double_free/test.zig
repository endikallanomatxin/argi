const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/43X_general_purpose_large_double_free" {
    const test_path = "tests/feature_tests/system/43X_general_purpose_large_double_free";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
