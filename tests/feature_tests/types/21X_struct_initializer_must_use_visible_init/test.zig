const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/21X_struct_initializer_must_use_visible_init" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/21X_struct_initializer_must_use_visible_init", "construction arguments cannot infer a matching Init target");
}
