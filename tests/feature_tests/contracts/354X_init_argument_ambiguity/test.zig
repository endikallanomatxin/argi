const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/354X_init_argument_ambiguity" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/354X_init_argument_ambiguity", "ambiguous Init participants", "without a diagnostic");
}
