const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/61X_projection_duplicate_after_resolution" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/61X_projection_duplicate_after_resolution", "ambiguous conformances for the same participant tuple", "panic");
}
