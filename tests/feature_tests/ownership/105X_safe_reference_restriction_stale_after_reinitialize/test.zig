const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize",
        "reference depends on a root that has ended",
    );
}
