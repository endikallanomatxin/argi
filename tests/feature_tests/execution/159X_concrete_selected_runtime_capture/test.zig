const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/159X_concrete_selected_runtime_capture" {
    try buildExpectFail("tests/feature_tests/execution/159X_concrete_selected_runtime_capture", "runtime values cannot be used");
}
