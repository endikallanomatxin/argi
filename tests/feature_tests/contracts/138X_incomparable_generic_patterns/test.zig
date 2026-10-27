const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/138X_incomparable_generic_patterns" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/138X_incomparable_generic_patterns", "ambiguous maximal patterns", "panic");
}
