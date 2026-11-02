const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/85_handle_evaluation_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/errors/85_handle_evaluation_cleanup");
    try runExpect("tests/feature_tests/errors/85_handle_evaluation_cleanup", 0);
}
