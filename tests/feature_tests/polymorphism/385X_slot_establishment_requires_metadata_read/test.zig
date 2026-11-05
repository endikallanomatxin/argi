const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/385X_slot_establishment_requires_metadata_read" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/385X_slot_establishment_requires_metadata_read", "memory access exceeds the declared reads/writes bounds involving input 'allocation'");
}
