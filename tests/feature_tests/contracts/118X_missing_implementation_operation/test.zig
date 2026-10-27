const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/118X_missing_implementation_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/118X_missing_implementation_operation", "missing implementation operation", "panic");
}
