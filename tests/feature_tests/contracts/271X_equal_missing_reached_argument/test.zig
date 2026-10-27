const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/271X_equal_missing_reached_argument" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/271X_equal_missing_reached_argument", "required reachable capabilities", "without a diagnostic");
}
