const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape", "no generic function named 'accept_owned' accepts arguments");
}
