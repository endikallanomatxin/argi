const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/331X_nested_family_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/331X_nested_family_signature", "type-family argument does not match its parameter signature", "without a diagnostic");
}
