const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/57X_clock_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/57X_clock_missing_capability", ".self uses reach [clock] expected as '&Clock'");
}
