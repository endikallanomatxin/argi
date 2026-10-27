const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/24X_abort_is_not_a_call" {
    try buildExpectFail("tests/feature_tests/basics/24X_abort_is_not_a_call", "abort");
}
