const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/54X_comptime_shared_budget" {
    try expectFrontendFailure("tests/feature_tests/execution/54X_comptime_shared_budget", "#run evaluation exceeded its instruction limit");
}
