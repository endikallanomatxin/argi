const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/35X_specialized_function_rebinding" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/35X_specialized_function_rebinding", "too many compile-time arguments", "failed without a diagnostic");
}
