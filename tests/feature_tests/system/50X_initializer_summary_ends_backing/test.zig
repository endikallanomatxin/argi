const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/50X_initializer_summary_ends_backing" {
    try buildExpectFail("tests/feature_tests/system/50X_initializer_summary_ends_backing", "reference depends on a root that has ended");
}
