const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/17X_tuple_ambiguous_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/17X_tuple_ambiguous_operation", "ambiguous conformances for the same participant tuple", "panic");
}
