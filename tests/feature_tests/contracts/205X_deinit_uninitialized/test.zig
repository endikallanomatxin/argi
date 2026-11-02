const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/205X_deinit_uninitialized" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/205X_deinit_uninitialized", "consumption requires an initialized owner");
}
