const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/193_conditional_consumption_cleanup_large" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/193_conditional_consumption_cleanup_large");
    try runExpect("tests/feature_tests/polymorphism/193_conditional_consumption_cleanup_large", 0);
}
