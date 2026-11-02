const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/57X_clock_missing_capability" {
    try expectFrontendFailure("tests/feature_tests/system/57X_clock_missing_capability", "call to 'monotonic_now' is missing required argument '.self'");
}
