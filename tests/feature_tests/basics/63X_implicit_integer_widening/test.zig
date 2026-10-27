const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/63X_implicit_integer_widening" {
    try buildExpectFail("tests/feature_tests/basics/63X_implicit_integer_widening", "implicit numeric conversion is not supported");
}
