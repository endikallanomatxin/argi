const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/63X_comptime_projection_bounds" {
    try buildExpectFail("tests/feature_tests/execution/63X_comptime_projection_bounds", "#run array index is out of bounds");
}
