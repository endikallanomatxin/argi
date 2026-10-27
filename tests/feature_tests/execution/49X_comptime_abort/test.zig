const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/49X_comptime_abort" {
    try buildExpectFail("tests/feature_tests/execution/49X_comptime_abort", "#run evaluation aborted");
}
