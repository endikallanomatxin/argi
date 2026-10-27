const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/11_environment_variables" {
    const test_path = "tests/feature_tests/system/11_environment_variables";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
