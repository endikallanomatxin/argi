const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/236X_init_target_not_inferred_from_result" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/236X_init_target_not_inferred_from_result", "construction arguments cannot infer a matching Init target");
}
