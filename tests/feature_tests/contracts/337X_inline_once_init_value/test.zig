const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/337X_inline_once_init_value" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/337X_inline_once_init_value", "is consumed more than once", "without a diagnostic");
}
