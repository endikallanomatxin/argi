const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "291X_constant_array_projection_conflicting_loan" {
    const path = "tests/feature_tests/concurrency/291X_constant_array_projection_conflicting_loan";
    try support.expectFrontendFailure(path, "concurrent access conflicts with a pending execution");
}
