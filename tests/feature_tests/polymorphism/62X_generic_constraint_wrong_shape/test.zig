const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape" {
    try buildExpectFail("tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape", "no generic function named 'accept_owned' accepts arguments");
}
