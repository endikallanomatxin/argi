const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/166X_indexed_replacement_keeps_alias_stale" {
    try expectFrontendFailure("tests/feature_tests/execution/166X_indexed_replacement_keeps_alias_stale", "root that has ended");
}
