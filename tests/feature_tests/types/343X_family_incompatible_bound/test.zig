const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/343X_family_incompatible_bound" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/343X_family_incompatible_bound", "type-family argument does not match its parameter signature", "without a diagnostic");
}
