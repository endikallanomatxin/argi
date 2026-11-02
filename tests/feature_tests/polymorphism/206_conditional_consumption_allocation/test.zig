const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/206_conditional_consumption_allocation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/206_conditional_consumption_allocation");
    try runExpect("tests/feature_tests/polymorphism/206_conditional_consumption_allocation", 0);
}
