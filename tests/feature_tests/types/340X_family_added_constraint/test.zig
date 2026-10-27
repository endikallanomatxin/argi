const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/340X_family_added_constraint" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/340X_family_added_constraint", "type-family argument does not match its parameter signature", "failed without a diagnostic");
}
