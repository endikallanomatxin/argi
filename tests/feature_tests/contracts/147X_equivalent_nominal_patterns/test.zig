const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/147X_equivalent_nominal_patterns" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/147X_equivalent_nominal_patterns", "equivalent implementation participant patterns", "panic");
}
