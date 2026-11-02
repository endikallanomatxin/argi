const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/207X_deinit_result" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/207X_deinit_result", "operation returns an incompatible associated result");
}
