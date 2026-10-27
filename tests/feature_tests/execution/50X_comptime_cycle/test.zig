const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/50X_comptime_cycle" {
    try buildExpectFail("tests/feature_tests/execution/50X_comptime_cycle", "cyclic dependency between #run evaluations");
}
