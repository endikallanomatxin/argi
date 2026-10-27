const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/51X_comptime_reference_result" {
    try expectFrontendFailure("tests/feature_tests/execution/51X_comptime_reference_result", "#run cannot return references or values requiring cleanup");
}
