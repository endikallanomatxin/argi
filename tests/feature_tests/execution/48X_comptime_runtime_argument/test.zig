const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/48X_comptime_runtime_argument" {
    try expectFrontendFailure("tests/feature_tests/execution/48X_comptime_runtime_argument", "#run arguments must be compile-time constants");
}
