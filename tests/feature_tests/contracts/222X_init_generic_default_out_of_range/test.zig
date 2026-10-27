const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/222X_init_generic_default_out_of_range" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/222X_init_generic_default_out_of_range", "integer literal 128 does not fit");
}
