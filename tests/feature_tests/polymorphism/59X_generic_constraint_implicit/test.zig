const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/59X_generic_constraint_implicit" {
    try buildExpectFail("tests/feature_tests/polymorphism/59X_generic_constraint_implicit", "contract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}
