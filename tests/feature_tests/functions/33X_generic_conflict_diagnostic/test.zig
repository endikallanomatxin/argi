const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/33X_generic_conflict_diagnostic" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/functions/33X_generic_conflict_diagnostic", "conflicting inferred generic parameters", "failed without a diagnostic");
}
