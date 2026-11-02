const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/34X_specialized_function_argument" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/modules/34X_specialized_function_argument", "arguments do not match this specialized function definition", "failed without a diagnostic");
}
