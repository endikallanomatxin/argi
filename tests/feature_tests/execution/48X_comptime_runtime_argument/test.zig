const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/48X_comptime_runtime_argument" {
    try buildExpectFail("tests/feature_tests/execution/48X_comptime_runtime_argument", "#run arguments must be compile-time constants");
}
