const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/287X_aggregate_copy_after_projected_reference_write" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/287X_aggregate_copy_after_projected_reference_write",
        "reference depends on a root that has ended",
    );
}
