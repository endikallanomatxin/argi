const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/269X_conditional_retarget_historical_reference" {
    // The conditional target must be proved before creating a replacement
    // plan. The exact-target case in 267X reaches the historical alias check.
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/269X_conditional_retarget_historical_reference", "cannot replace owning storage through an incomplete reference target set", "failed without a diagnostic");
}
