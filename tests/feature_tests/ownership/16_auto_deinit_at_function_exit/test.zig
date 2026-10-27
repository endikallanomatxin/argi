const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/16_auto_deinit_at_function_exit" {
    const test_path = "tests/feature_tests/ownership/16_auto_deinit_at_function_exit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
