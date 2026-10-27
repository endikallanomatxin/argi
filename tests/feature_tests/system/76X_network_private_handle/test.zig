const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/76X_network_private_handle" {
    try buildExpectFail("tests/feature_tests/system/76X_network_private_handle", "field '_handle' is private");
}
