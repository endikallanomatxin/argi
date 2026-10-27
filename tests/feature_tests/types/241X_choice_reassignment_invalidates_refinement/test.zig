const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/241X_choice_reassignment_invalidates_refinement" {
    try buildExpectFail(
        "tests/feature_tests/types/241X_choice_reassignment_invalidates_refinement",
        "choice payload '..0' is not active",
    );
}
