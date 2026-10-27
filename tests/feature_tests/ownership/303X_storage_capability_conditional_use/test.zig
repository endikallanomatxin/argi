const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/303X_storage_capability_conditional_use" {
    try buildExpectFail("tests/feature_tests/ownership/303X_storage_capability_conditional_use", "already been consumed");
}
