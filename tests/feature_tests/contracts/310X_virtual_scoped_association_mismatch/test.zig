const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/310X_virtual_scoped_association_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/310X_virtual_scoped_association_mismatch", "incompatible associated elements", "failed without a diagnostic");
}
