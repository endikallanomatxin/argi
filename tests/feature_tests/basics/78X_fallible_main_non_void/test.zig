const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/78X_fallible_main_non_void" {
    try buildExpectFail("tests/feature_tests/basics/78X_fallible_main_non_void", "main must return no values or (.status_code: Int32)");
}
