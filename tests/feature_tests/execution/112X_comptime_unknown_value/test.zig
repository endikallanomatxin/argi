const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/112X_comptime_unknown_value" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/112X_comptime_unknown_value", "unknown name 'unknown_value' in this scope", "global sema unresolved");
}
