const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/28X_numeric_signedness_assignment" {
    try buildExpectFail("tests/feature_tests/basics/28X_numeric_signedness_assignment", "cannot assign numeric value of type");
}
