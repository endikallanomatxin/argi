const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/12X_numeric_readonly" {
    try buildExpectFail("tests/feature_tests/python/12X_numeric_readonly", "no generic function named 'copy_numeric'");
}
