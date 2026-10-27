const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias",
        "root that has ended",
    );
}
