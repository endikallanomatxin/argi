const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/16X_tuple_missing_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/16X_tuple_missing_operation", "missing implementation operation", "panic");
}
