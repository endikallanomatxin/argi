const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/216X_deinit_parameter_overwrite" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/216X_deinit_parameter_overwrite", "consumption requires an initialized owner");
}
