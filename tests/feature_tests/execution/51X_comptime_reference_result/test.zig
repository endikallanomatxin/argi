const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/51X_comptime_reference_result" {
    try buildExpectFail("tests/feature_tests/execution/51X_comptime_reference_result", "#run cannot return references or values requiring cleanup");
}
