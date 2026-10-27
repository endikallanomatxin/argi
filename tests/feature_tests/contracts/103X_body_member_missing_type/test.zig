const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/103X_body_member_missing_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/103X_body_member_missing_type", "associated contract members require a type declaration", "panic");
}
