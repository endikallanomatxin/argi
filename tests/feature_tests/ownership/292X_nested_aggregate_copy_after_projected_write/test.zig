const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/292X_nested_aggregate_copy_after_projected_write" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/292X_nested_aggregate_copy_after_projected_write",
        "reference depends on a root that has ended",
    );
}
