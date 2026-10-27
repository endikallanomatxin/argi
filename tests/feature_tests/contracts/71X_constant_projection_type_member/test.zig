const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/71X_constant_projection_type_member" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/71X_constant_projection_type_member", "associated element is not an integer constant", "panic");
}
