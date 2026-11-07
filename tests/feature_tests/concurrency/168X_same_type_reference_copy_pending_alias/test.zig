const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "168X_same_type_reference_copy_pending_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/168X_same_type_reference_copy_pending_alias", "reference access has unknown memory effects");
}
