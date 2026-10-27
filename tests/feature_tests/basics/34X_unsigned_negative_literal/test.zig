const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/34X_unsigned_negative_literal" {
    try buildExpectFail("tests/feature_tests/basics/34X_unsigned_negative_literal", "does not fit in");
}
