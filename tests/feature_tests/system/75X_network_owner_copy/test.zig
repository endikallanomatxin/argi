const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/75X_network_owner_copy" {
    try buildExpectFail("tests/feature_tests/system/75X_network_owner_copy", "cannot be copied implicitly");
}
