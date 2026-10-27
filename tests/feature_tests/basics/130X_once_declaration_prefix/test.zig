const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/130X_once_declaration_prefix" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/130X_once_declaration_prefix", "place once after :=, before the function definition", "without a diagnostic");
}
