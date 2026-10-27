const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/31X_int64_positive_literal_overflow" {
    try buildExpectFail("tests/feature_tests/basics/31X_int64_positive_literal_overflow", "does not fit in");
}
