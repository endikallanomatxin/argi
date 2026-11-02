const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/294_conditional_storage_empty_known_input" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/294_conditional_storage_empty_known_input");
    try runExpect("tests/feature_tests/polymorphism/294_conditional_storage_empty_known_input", 0);
}
