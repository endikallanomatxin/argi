const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "166X_reference_forwarding_wrapper_unknown_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/166X_reference_forwarding_wrapper_unknown_alias", "reference access has unknown memory effects");
}
