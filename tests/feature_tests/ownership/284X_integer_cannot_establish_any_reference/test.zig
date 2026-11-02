const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/284X_integer_cannot_establish_any_reference" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/284X_integer_cannot_establish_any_reference",
        "no function named 'cast' exists",
    );
}
