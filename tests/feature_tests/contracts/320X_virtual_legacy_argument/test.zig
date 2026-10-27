const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/320X_virtual_legacy_argument" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/320X_virtual_legacy_argument", "unknown virtual compile-time argument; use .contract: Contract", "panic");
}
