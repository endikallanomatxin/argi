const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/109X_shared_direct_associated_conflict" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/109X_shared_direct_associated_conflict", "ambiguous conformances for the same participant tuple", "panic");
}
