const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/266X_add_missing_reached_argument" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/266X_add_missing_reached_argument", "required reachable capabilities", "without a diagnostic");
}
