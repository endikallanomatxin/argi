const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/280X_conditional_storage_wrong_variant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/280X_conditional_storage_wrong_variant", "undeclared output dependency", "failed without a diagnostic");
}
