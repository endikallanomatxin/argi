const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/37X_tuple_invisible_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/37X_tuple_invisible_operation", "missing implementation operation", "panic");
}
