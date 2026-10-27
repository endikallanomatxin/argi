const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/229X_structural_args_repeated_type" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/229X_structural_args_repeated_type", "no conformance");
}
