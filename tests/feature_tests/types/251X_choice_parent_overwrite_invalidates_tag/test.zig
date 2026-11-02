const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/251X_choice_parent_overwrite_invalidates_tag" {
    try expectFrontendFailure(
        "tests/feature_tests/types/251X_choice_parent_overwrite_invalidates_tag",
        "choice payload '..0' is not active",
    );
}
