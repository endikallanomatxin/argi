const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/43X_associated_kind" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/43X_associated_kind", "argument kind does not match its parameter", "panic");
}
