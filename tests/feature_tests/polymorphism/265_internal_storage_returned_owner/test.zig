const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/265_internal_storage_returned_owner" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/265_internal_storage_returned_owner");
    try runExpect("tests/feature_tests/polymorphism/265_internal_storage_returned_owner", 0);
}
