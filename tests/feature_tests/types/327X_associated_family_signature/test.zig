const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/327X_associated_family_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/327X_associated_family_signature", "associated type-family argument does not match its parameter signature", "without a diagnostic");
}
