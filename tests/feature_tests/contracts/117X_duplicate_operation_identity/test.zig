const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/117X_duplicate_operation_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/117X_duplicate_operation_identity", "duplicate contract operation identity", "panic");
}
