const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "184X_checked_array_access_through_retargeted_reference" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/184X_checked_array_access_through_retargeted_reference", "pending execution");
}
