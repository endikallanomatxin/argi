const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 112X_reference_leaf_access_composition" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/112X_reference_leaf_access_composition", "memory access exceeds the declared reads/writes bounds");
}
