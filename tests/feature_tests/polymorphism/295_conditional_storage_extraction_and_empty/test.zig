const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/295_conditional_storage_extraction_and_empty" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/295_conditional_storage_extraction_and_empty");
    try runExpect("tests/feature_tests/polymorphism/295_conditional_storage_extraction_and_empty", 0);
}
