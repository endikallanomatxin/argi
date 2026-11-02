const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/63X_generic_constraint_qualified" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/63X_generic_constraint_qualified", "contract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}
