const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/417X_loop_condition_observes_retired_generation" {
    try support.expectFrontendFailure(
        "tests/feature_tests/ownership/417X_loop_condition_observes_retired_generation",
        "reference depends on a root that has ended",
    );
}
