const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/51X_array_view_private_constructor" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/51X_array_view_private_constructor",
        "field '_data' is private to its module",
    );
}
