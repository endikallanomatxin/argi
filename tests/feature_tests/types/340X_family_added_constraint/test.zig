const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/340X_family_added_constraint" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/types/340X_family_added_constraint", "type-family argument does not match its parameter signature", "failed without a diagnostic");
}
