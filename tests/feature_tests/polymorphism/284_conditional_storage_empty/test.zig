const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/284_conditional_storage_empty" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/284_conditional_storage_empty");
    try runExpect("tests/feature_tests/polymorphism/284_conditional_storage_empty", 0);
}
