const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/66X_comptime_argument_safety" {
    try expectFrontendFailure("tests/feature_tests/execution/66X_comptime_argument_safety", "consumption requires an initialized owner");
}
