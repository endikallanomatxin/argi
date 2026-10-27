const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/131X_private_operation_alias" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/131X_private_operation_alias", "unknown or inaccessible implementation function", "panic");
}
