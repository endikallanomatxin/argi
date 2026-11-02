const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/332X_generic_array_element" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/332X_generic_array_element", "integer literal 256 does not fit in 'UInt8'", "failed without a diagnostic");
}
