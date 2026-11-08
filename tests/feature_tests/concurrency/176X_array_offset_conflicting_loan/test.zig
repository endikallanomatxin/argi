const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "176X_array_offset_conflicting_loan" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/176X_array_offset_conflicting_loan", "pending execution");
}
