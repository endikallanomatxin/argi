const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/273X_borrowed_call_keeps_copy_stale" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/273X_borrowed_call_keeps_copy_stale", "reference depends on a root that has ended", "failed without a diagnostic");
}
