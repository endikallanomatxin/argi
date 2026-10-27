const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/293X_type_alias_cycle" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/293X_type_alias_cycle", "cyclic type alias");
}
