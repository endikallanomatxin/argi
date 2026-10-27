const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/65X_comptime_noninteger_argument" {
    try buildExpectFail("tests/feature_tests/execution/65X_comptime_noninteger_argument", "compile-time integer argument requires an integer result");
}
