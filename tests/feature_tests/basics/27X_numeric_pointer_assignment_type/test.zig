const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/27X_numeric_pointer_assignment_type" {
    try buildExpectFail("tests/feature_tests/basics/27X_numeric_pointer_assignment_type", "cannot assign numeric value of type");
}
