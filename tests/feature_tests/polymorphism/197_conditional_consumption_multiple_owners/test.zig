const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/197_conditional_consumption_multiple_owners" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/197_conditional_consumption_multiple_owners");
    try runExpect("tests/feature_tests/polymorphism/197_conditional_consumption_multiple_owners", 0);
}
