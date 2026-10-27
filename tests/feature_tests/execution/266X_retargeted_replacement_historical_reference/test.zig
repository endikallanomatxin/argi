const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/266X_retargeted_replacement_historical_reference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/266X_retargeted_replacement_historical_reference", "reference depends on a root that has ended", "failed without a diagnostic");
}
