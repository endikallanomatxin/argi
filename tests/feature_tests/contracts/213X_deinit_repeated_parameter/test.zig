const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/213X_deinit_repeated_parameter" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/213X_deinit_repeated_parameter", "consumption requires an initialized owner");
}
