const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/60X_generic_constraint_explicit" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/60X_generic_constraint_explicit", "contract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}
