const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/192_conditional_consumption_cleanup_alias" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/192_conditional_consumption_cleanup_alias");
    try runExpect("tests/feature_tests/polymorphism/192_conditional_consumption_cleanup_alias", 0);
}
