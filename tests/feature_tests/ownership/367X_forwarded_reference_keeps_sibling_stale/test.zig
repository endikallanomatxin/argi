const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/367X_forwarded_reference_keeps_sibling_stale" {
    try expectFrontendFailure("tests/feature_tests/ownership/367X_forwarded_reference_keeps_sibling_stale", "reference depends on a root that has ended");
}
