const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/37X_record_reference_keeps_sibling_stale" {
    try expectFrontendFailure("tests/feature_tests/execution/37X_record_reference_keeps_sibling_stale", "reference depends on a root that has ended");
}
