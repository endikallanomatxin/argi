const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/278_conditional_storage_extraction" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/278_conditional_storage_extraction");
    try runExpect("tests/feature_tests/polymorphism/278_conditional_storage_extraction", 0);
}
