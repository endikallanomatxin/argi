const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/163X_array_cleanup_keeps_alias_stale" {
    try expectFrontendFailure("tests/feature_tests/execution/163X_array_cleanup_keeps_alias_stale", "root that has ended");
}
