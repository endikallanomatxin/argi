const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/86X_fallible_main_removed" {
    try buildExpectFail("tests/feature_tests/basics/86X_fallible_main_removed", "main must return no values or (.status_code: Int32)");
}
