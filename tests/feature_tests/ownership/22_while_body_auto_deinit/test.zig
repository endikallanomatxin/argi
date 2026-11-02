const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/22_while_body_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/22_while_body_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
