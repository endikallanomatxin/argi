const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/27X_standalone_legacy" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/27X_standalone_legacy", "legacy conformance declarations are unsupported", "panic");
}
