const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/21X_index_operator_reached_default" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/collections/21X_index_operator_reached_default",
        "unsupported operator 'get'",
    );
}
