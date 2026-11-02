const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/88_handle_without_result" {
    try expectSuccessfulBuild("tests/feature_tests/errors/88_handle_without_result");
    try runExpect("tests/feature_tests/errors/88_handle_without_result", 0);
}
