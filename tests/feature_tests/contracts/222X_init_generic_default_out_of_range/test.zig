const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/222X_init_generic_default_out_of_range" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/222X_init_generic_default_out_of_range", "integer literal 128 does not fit");
}
