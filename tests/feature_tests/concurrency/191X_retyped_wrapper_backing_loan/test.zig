const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "191X_retyped_wrapper_backing_loan" {
    const path = "tests/feature_tests/concurrency/191X_retyped_wrapper_backing_loan";
    try support.expectFrontendFailure(path, "pending execution");
}
