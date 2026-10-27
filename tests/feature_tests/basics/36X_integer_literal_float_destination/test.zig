const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/36X_integer_literal_float_destination" {
    try buildExpectFail("tests/feature_tests/basics/36X_integer_literal_float_destination", "cannot assign numeric value of type");
}
