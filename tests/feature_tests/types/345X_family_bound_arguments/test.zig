const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/345X_family_bound_arguments" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/345X_family_bound_arguments", "type-family argument does not match its parameter signature", "without a diagnostic");
}
