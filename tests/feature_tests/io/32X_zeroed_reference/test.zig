const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/32X_zeroed_reference" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/io/32X_zeroed_reference", "zeroed requires a numeric type or a fixed array of numeric types");
}
