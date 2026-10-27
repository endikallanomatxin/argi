const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/20X_once_duplicate_init" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/system/20X_once_duplicate_init", "once function '_acquire_token' is consumed more than once");
}
