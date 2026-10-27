const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/11X_missing_conformance_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/11X_missing_conformance_type", "legacy conformance declarations are unsupported", "panic");
}
