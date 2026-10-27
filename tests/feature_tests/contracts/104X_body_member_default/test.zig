const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/104X_body_member_default" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/104X_body_member_default", "associated contract members are supplied by implement", "panic");
}
