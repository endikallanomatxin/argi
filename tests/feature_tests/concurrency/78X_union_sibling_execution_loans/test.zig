const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 78X_union_sibling_execution_loans" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/78X_union_sibling_execution_loans", "concurrent access conflicts with a pending execution");
}
