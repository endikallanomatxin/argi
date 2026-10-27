const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/60X_projection_nested_cycle" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/60X_projection_nested_cycle", "cyclic or unresolved associated type projection", "panic");
}
