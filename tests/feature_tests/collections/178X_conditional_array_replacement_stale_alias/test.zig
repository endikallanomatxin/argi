const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/178X_conditional_array_replacement_stale_alias" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/178X_conditional_array_replacement_stale_alias",
        "root that has ended",
    );
}
