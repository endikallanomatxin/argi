const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/48X_numeric_record_field" {
    try buildExpectFail("tests/feature_tests/basics/48X_numeric_record_field", "cannot assign numeric value of type");
}
