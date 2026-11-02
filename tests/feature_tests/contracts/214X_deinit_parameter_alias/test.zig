const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/214X_deinit_parameter_alias" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/214X_deinit_parameter_alias", "consumption requires an initialized owner");
}
