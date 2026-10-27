const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/32X_tuple_virtual" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/32X_tuple_virtual", "explicit participants require joint virtual evidence", "panic");
}
