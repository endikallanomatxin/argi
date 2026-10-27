const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/37X_system_local_resource_escape" {
    try buildExpectFail("tests/feature_tests/system/37X_system_local_resource_escape", "local storage generation");
}
