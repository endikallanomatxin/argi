const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/63X_comptime_projection_bounds" {
    try expectFrontendFailure("tests/feature_tests/execution/63X_comptime_projection_bounds", "#run array index is out of bounds");
}
