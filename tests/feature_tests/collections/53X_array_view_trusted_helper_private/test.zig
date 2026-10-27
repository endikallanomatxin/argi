const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/53X_array_view_trusted_helper_private" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/53X_array_view_trusted_helper_private",
        "no function named '_trusted_mutable_array_view' exists",
    );
}
