const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/10X_abstract_wrong_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/10X_abstract_wrong_signature", "incompatible associated result", "failed without a diagnostic");
}
