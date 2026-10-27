const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/195X_init_generic_default_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/195X_init_generic_default_type", "arguments do not match the selected contract operation, including completed defaults", "no function named");
}
