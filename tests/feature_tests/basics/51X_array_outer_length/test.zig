const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/51X_array_outer_length" {
    try buildExpectFail("tests/feature_tests/basics/51X_array_outer_length", "array initializer has 2 elements; expected 3");
}
