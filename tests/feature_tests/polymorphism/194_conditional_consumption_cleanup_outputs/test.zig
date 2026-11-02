const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/194_conditional_consumption_cleanup_outputs" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/194_conditional_consumption_cleanup_outputs");
    try runExpect("tests/feature_tests/polymorphism/194_conditional_consumption_cleanup_outputs", 0);
}
