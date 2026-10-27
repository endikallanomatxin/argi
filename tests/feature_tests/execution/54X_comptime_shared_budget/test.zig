const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/54X_comptime_shared_budget" {
    try buildExpectFail("tests/feature_tests/execution/54X_comptime_shared_budget", "#run evaluation exceeded its instruction limit");
}
