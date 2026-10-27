const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/50X_projection_missing_tuple" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/50X_projection_missing_tuple", "no conformance for the projected participant tuple", "panic");
}
