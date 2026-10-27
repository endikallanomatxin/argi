const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/53X_array_reference_shape" {
    try buildExpectFail("tests/feature_tests/basics/53X_array_reference_shape", "array value has type '&[3][3]Int32'; expected '&[2][2]Int32'");
}
