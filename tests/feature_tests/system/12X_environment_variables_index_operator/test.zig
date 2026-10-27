const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/12X_environment_variables_index_operator" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/12X_environment_variables_index_operator",
        "indexing is only supported for native arrays",
    );
}
