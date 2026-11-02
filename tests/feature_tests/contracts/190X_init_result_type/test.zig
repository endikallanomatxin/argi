const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/190X_init_result_type" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/190X_init_result_type", "Init.Result must be its participant type or one Errable containing that type");
}
