const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "164X_reference_forwarding_mixed_target_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/164X_reference_forwarding_mixed_target_alias", "reference access has unknown memory effects");
}
