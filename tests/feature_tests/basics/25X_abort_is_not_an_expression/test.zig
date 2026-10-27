const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/25X_abort_is_not_an_expression" {
    try buildExpectFail("tests/feature_tests/basics/25X_abort_is_not_an_expression", "abort");
}
