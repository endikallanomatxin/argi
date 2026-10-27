const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/46X_tuple_default" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/46X_tuple_default", "defaultsto is unsupported", "panic");
}
