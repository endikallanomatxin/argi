const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 76X_union_sibling_execution_access" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/76X_union_sibling_execution_access", "concurrent access conflicts with a pending execution");
}
