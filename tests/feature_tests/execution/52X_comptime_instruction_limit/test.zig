const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/52X_comptime_instruction_limit" {
    try buildExpectFail("tests/feature_tests/execution/52X_comptime_instruction_limit", "#run evaluation exceeded its instruction limit");
}
