const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/28_assume_constructor_temporary" {
    try expectSuccessfulBuild("tests/feature_tests/functions/28_assume_constructor_temporary");
    try runExpect("tests/feature_tests/functions/28_assume_constructor_temporary", 0);
}
