const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/251X_convert_owned_copy" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/251X_convert_owned_copy", "cannot be copied implicitly");
}
