const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 39X_conditional_access_bound" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/39X_conditional_access_bound", "access bounds must be declared outside on clauses");
}
