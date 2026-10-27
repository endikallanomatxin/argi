const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/230X_structural_args_ambiguous" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/230X_structural_args_ambiguous", "ambiguous maximal patterns");
}
