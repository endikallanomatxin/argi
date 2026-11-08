const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/430X_comptime_value_type" {
    try support.expectFrontendFailure("tests/feature_tests/types/430X_comptime_value_type", "compile-time value does not match its declared parameter type");
}
