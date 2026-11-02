const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/279X_infallible_copy_is_not_implicit" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/279X_infallible_copy_is_not_implicit",
        "type 'LargeValue' cannot be copied implicitly",
    );
}
