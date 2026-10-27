const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/49X_comptime_abort" {
    try expectFrontendFailure("tests/feature_tests/execution/49X_comptime_abort", "#run evaluation aborted");
}
