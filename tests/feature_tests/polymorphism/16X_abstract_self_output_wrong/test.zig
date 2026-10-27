const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/16X_abstract_self_output_wrong" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/16X_abstract_self_output_wrong", "incompatible associated result", "failed without a diagnostic");
}
