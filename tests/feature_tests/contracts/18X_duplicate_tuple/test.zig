const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/18X_duplicate_tuple" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/18X_duplicate_tuple", "ambiguous conformances for the same participant tuple", "panic");
}
