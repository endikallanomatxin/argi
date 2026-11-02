const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/255_opaque_storage_discards_input" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/255_opaque_storage_discards_input");
    try runExpect("tests/feature_tests/polymorphism/255_opaque_storage_discards_input", 0);
}
