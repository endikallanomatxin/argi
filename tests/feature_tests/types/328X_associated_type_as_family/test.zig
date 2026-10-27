const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/328X_associated_type_as_family" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/328X_associated_type_as_family", "associated element is not a type family", "without a diagnostic");
}
