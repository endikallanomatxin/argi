const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/431X_comptime_value_overflow" {
    try support.expectFrontendFailure("tests/feature_tests/types/431X_comptime_value_overflow", "compile-time value does not match its declared parameter type");
}
