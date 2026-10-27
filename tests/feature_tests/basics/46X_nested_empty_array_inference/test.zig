const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/46X_nested_empty_array_inference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/46X_nested_empty_array_inference", "cannot infer the array type of 'values' from this literal; add an explicit array type annotation", "UnsupportedGlobalSemantic");
}
