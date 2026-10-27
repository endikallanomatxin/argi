const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/20X_once_duplicate_init" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/system/20X_once_duplicate_init", "once function '_acquire_token' is consumed more than once");
}
