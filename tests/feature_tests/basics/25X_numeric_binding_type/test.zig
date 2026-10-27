const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/25X_numeric_binding_type" {
    try buildExpectFail("tests/feature_tests/basics/25X_numeric_binding_type", "cannot assign numeric value of type");
}
