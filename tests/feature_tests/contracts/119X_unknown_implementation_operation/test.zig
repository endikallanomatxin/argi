const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/119X_unknown_implementation_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/119X_unknown_implementation_operation", "unknown implementation operation", "panic");
}
