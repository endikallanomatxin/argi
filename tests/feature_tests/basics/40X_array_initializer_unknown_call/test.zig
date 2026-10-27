const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/40X_array_initializer_unknown_call" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/40X_array_initializer_unknown_call", "no function named 'missing_value' exists", "cannot infer the array type");
}
