const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/301_opaque_metadata_cleanup_after_referent" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/301_opaque_metadata_cleanup_after_referent");
    try runExpect("tests/feature_tests/polymorphism/301_opaque_metadata_cleanup_after_referent", 0);
}
