const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/266X_retargeted_replacement_historical_reference" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/266X_retargeted_replacement_historical_reference", "reference depends on a root that has ended", "failed without a diagnostic");
}
