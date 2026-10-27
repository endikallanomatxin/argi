const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/32X_int64_negative_literal_overflow" {
    try buildExpectFail("tests/feature_tests/basics/32X_int64_negative_literal_overflow", "does not fit in");
}
