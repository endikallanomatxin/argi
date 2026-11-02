const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/250X_choice_field_overwrite_invalidates_tag" {
    try expectFrontendFailure(
        "tests/feature_tests/types/250X_choice_field_overwrite_invalidates_tag",
        "choice payload '..0' is not active",
    );
}
