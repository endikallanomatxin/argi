const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/108X_shared_generic_associated_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/108X_shared_generic_associated_mismatch", "constraint", "panic");
}
