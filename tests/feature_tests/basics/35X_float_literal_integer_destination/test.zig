const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/35X_float_literal_integer_destination" {
    try buildExpectFail("tests/feature_tests/basics/35X_float_literal_integer_destination", "cannot assign numeric value of type");
}
