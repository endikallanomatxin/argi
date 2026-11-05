const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "ownership 404X_helper_retains_local_in_borrowed_storage" {
    try support.expectFrontendFailure("tests/feature_tests/ownership/404X_helper_retains_local_in_borrowed_storage", "caller storage cannot depend on a local storage generation");
}
