const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/433X_comptime_value_reference" {
    try support.expectFrontendFailure("tests/feature_tests/types/433X_comptime_value_reference", "compile-time value parameters require immutable literal values");
}
