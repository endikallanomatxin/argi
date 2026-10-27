const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/21X_terminal_duplicate_init" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/21X_terminal_duplicate_init",
        "once function '_acquire_terminal' is consumed more than once",
    );
}
