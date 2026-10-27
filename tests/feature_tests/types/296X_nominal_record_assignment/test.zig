const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/296X_nominal_record_assignment" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/296X_nominal_record_assignment", "distinct nominal types require explicit conversion");
}
