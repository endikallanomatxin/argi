const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/418X_loop_propagates_retired_reference" {
    try support.expectFrontendFailure(
        "tests/feature_tests/ownership/418X_loop_propagates_retired_reference",
        "reference depends on a root that has ended",
    );
}
