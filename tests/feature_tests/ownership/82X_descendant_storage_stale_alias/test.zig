const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/82X_descendant_storage_stale_alias" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/82X_descendant_storage_stale_alias",
        "reference depends on a root that has ended",
    );
}
