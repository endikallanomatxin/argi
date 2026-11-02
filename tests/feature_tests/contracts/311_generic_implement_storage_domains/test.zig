const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/311_generic_implement_storage_domains" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/311_generic_implement_storage_domains");
    try runExpect("tests/feature_tests/contracts/311_generic_implement_storage_domains", 0);
}
