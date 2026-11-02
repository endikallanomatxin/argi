const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/241X_choice_reassignment_invalidates_refinement" {
    try expectFrontendFailure(
        "tests/feature_tests/types/241X_choice_reassignment_invalidates_refinement",
        "choice payload '..0' is not active",
    );
}
