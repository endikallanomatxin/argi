const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/208X_deinit_implicit_copy" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/208X_deinit_implicit_copy", "cannot be copied implicitly");
}
