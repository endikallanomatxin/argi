const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/292X_annotated_alias_range" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/292X_annotated_alias_range", "integer literal 256 does not fit in 'UInt8'");
}
