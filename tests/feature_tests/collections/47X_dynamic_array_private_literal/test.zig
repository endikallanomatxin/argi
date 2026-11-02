const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/47X_dynamic_array_private_literal" {
    try expectFrontendFailure(
        "tests/feature_tests/collections/47X_dynamic_array_private_literal",
        "field '_allocation' is private to its module",
    );
}
