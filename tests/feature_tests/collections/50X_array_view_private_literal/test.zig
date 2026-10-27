const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/50X_array_view_private_literal" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/50X_array_view_private_literal",
        "field '_data' is private to its module",
    );
}
