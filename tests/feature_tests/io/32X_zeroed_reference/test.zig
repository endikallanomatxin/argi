const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/32X_zeroed_reference" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/io/32X_zeroed_reference", "zeroed requires a numeric type or a fixed array of numeric types");
}
