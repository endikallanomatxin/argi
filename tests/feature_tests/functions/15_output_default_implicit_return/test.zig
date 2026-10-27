const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/15_output_default_implicit_return" {
    const test_path = "tests/feature_tests/functions/15_output_default_implicit_return";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
