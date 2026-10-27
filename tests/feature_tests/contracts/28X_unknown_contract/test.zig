const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/28X_unknown_contract" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/28X_unknown_contract", "unknown or inaccessible contract", "panic");
}
