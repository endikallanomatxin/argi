const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/354X_init_argument_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/354X_init_argument_ambiguity", "ambiguous Init participants", "without a diagnostic");
}
