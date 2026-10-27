const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/311X_nominal_construction_recontextualization" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/311X_nominal_construction_recontextualization", "distinct nominal types require explicit conversion", "without a diagnostic");
}
