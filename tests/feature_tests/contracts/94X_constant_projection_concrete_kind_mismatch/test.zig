const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/94X_constant_projection_concrete_kind_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/94X_constant_projection_concrete_kind_mismatch", "compile-time argument kind does not match its parameter", "failed without a diagnostic");
}
