const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/384_slot_establishment_metadata_bound" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/384_slot_establishment_metadata_bound");
    try support.runExpect("tests/feature_tests/polymorphism/384_slot_establishment_metadata_bound", 0);
}
