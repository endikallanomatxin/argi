const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/102X_duplicate_body_member" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/102X_duplicate_body_member", "duplicate associated contract member name", "panic");
}
