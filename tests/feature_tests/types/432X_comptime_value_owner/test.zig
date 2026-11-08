const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/432X_comptime_value_owner" {
    try support.expectFrontendFailure("tests/feature_tests/types/432X_comptime_value_owner", "compile-time value parameters require implicitly copyable values");
}
