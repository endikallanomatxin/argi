const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/52X_comptime_instruction_limit" {
    try expectFrontendFailure("tests/feature_tests/execution/52X_comptime_instruction_limit", "#run evaluation exceeded its instruction limit");
}
