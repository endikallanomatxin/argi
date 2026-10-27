const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/24X_duplicate_parameter" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/24X_duplicate_parameter", "duplicate participant or associated parameter name", "panic");
}
