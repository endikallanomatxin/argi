const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/199_conditional_consumption_preserving_state" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/199_conditional_consumption_preserving_state");
    try runExpect("tests/feature_tests/polymorphism/199_conditional_consumption_preserving_state", 0);
}
