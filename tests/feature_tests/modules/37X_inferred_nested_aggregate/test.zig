const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/37X_inferred_nested_aggregate" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/37X_inferred_nested_aggregate", "cannot infer the type of 'record'; add an explicit type annotation", "without a diagnostic");
}
