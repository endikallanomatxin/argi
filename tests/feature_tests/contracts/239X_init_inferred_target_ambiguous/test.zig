const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/239X_init_inferred_target_ambiguous" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/239X_init_inferred_target_ambiguous", "ambiguous Init participants");
}
