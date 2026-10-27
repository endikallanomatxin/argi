const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/157X_selected_runtime_comptime_capture" {
    try buildExpectFail("tests/feature_tests/execution/157X_selected_runtime_comptime_capture", "runtime values cannot be used");
}
