const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/35X_specialized_function_rebinding" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/modules/35X_specialized_function_rebinding", "too many compile-time arguments", "failed without a diagnostic");
}
