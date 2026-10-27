const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/281X_fallible_copy_is_not_implicit" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/281X_fallible_copy_is_not_implicit",
        "type 'FallibleValue' cannot be copied implicitly",
    );
}
