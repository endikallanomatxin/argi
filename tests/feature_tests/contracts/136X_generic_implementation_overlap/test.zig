const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/136X_generic_implementation_overlap" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/136X_generic_implementation_overlap", "equivalent implementation participant patterns", "panic");
}
