const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/152X_array_write_through_stale_pointer_fails" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/152X_array_write_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}
