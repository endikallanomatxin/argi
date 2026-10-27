const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/120X_duplicate_implementation_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/120X_duplicate_implementation_operation", "duplicate implementation operation", "panic");
}
