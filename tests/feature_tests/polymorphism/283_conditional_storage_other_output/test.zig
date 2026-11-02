const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/283_conditional_storage_other_output" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/283_conditional_storage_other_output");
    try runExpect("tests/feature_tests/polymorphism/283_conditional_storage_other_output", 0);
}
