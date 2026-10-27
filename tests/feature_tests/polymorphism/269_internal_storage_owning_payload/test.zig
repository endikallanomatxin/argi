const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/269_internal_storage_owning_payload" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/269_internal_storage_owning_payload");
    try runExpect("tests/feature_tests/polymorphism/269_internal_storage_owning_payload", 0);
}
