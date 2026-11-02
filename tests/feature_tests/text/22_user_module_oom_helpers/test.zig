const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/22_user_module_oom_helpers" {
    const test_path = "tests/feature_tests/text/22_user_module_oom_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
