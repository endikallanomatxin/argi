const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/282X_conditional_storage_inherited_identity" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/282X_conditional_storage_inherited_identity", "from_storage cannot be combined with exact transfers for the same output", "failed without a diagnostic");
}
