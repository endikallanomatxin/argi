const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/195X_init_generic_default_type" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/195X_init_generic_default_type", "arguments do not match the selected contract operation, including defaults", "no function named");
}
