const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/319X_storage_capability_consumed_post_state" {
    try buildExpectFail("tests/feature_tests/ownership/319X_storage_capability_consumed_post_state", "already been consumed");
}
