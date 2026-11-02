const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/50X_comptime_cycle" {
    try expectFrontendFailure("tests/feature_tests/execution/50X_comptime_cycle", "cyclic dependency between #run evaluations");
}
