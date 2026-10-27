const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/20_assume_arguments" {
    const test_path = "tests/feature_tests/functions/20_assume_arguments";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
