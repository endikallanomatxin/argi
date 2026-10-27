const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/123X_operation_requires_explicit_implementation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/123X_operation_requires_explicit_implementation", "missing implementation operation", "panic");
}
