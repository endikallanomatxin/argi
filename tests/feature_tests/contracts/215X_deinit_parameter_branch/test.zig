const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/215X_deinit_parameter_branch" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/215X_deinit_parameter_branch", "consumption requires an initialized owner");
}
