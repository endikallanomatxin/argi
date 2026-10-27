const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/242X_choice_move_invalidates_source" {
    try buildExpectFail(
        "tests/feature_tests/types/242X_choice_move_invalidates_source",
        "choice payload '..0' requires its variant to be proven active",
    );
}
