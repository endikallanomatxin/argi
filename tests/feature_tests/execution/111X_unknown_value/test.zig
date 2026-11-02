const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/111X_unknown_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/111X_unknown_value", "unknown name 'unknown_value' in this scope", "global sema unresolved");
    try vmExpect("tests/feature_tests/execution/111X_unknown_value", 1, "unknown name 'unknown_value' in this scope");
}
