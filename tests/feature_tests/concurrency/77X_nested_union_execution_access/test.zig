const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 77X_nested_union_execution_access" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/77X_nested_union_execution_access", "concurrent access conflicts with a pending execution");
}
