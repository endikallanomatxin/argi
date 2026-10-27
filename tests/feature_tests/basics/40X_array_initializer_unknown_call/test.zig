const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/40X_array_initializer_unknown_call" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/basics/40X_array_initializer_unknown_call", "no function named 'missing_value' exists", "cannot infer the array type");
}
