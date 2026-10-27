const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/156X_nested_comptime_reference_output" {
    try buildExpectFail("tests/feature_tests/execution/156X_nested_comptime_reference_output", "cannot return references or values requiring cleanup");
}
