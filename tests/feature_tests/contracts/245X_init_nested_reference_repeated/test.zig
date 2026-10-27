const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/245X_init_nested_reference_repeated" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/245X_init_nested_reference_repeated", "consumption requires an initialized owner");
}
