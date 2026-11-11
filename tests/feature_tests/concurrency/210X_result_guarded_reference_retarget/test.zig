const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "210X_result_guarded_reference_retarget" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/210X_result_guarded_reference_retarget", "pending execution");
}
