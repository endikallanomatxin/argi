const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/14X_get_and_set_index_operators" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/basics/14X_get_and_set_index_operators",
        "unsupported operator 'get'",
    );
}
