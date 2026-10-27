const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/112X_comptime_unknown_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/112X_comptime_unknown_value", "unknown name 'unknown_value' in this scope", "global sema unresolved");
}
