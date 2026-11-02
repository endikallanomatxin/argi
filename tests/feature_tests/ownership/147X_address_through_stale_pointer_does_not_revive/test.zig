const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/147X_address_through_stale_pointer_does_not_revive" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/147X_address_through_stale_pointer_does_not_revive",
        "reference depends on a root that has ended",
    );
}
