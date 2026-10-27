const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/29X_numeric_float_assignment" {
    try buildExpectFail("tests/feature_tests/basics/29X_numeric_float_assignment", "cannot assign numeric value of type");
}
