const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/78X_network_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/78X_network_missing_capability", "network");
}
