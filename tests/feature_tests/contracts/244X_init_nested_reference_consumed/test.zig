const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/244X_init_nested_reference_consumed" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/244X_init_nested_reference_consumed", "value was deinitialized");
}
