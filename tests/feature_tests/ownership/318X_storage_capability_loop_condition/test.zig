const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/318X_storage_capability_loop_condition" {
    try buildExpectFail("tests/feature_tests/ownership/318X_storage_capability_loop_condition", "more than once");
}
