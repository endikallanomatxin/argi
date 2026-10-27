const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/244X_init_nested_reference_consumed" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/244X_init_nested_reference_consumed", "value was deinitialized");
}
