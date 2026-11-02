const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/271_internal_storage_independent_domains" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/271_internal_storage_independent_domains");
    try runExpect("tests/feature_tests/polymorphism/271_internal_storage_independent_domains", 0);
}
