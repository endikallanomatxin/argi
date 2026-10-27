const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/52X_array_inner_length" {
    try buildExpectFail("tests/feature_tests/basics/52X_array_inner_length", "array initializer has 2 elements; expected 3");
}
