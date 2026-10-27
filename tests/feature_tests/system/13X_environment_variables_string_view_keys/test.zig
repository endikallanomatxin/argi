const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/13X_environment_variables_string_view_keys" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/13X_environment_variables_string_view_keys",
        "indexing is only supported for native arrays",
    );
}
