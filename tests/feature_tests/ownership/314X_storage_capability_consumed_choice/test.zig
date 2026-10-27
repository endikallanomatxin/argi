const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/314X_storage_capability_consumed_choice" {
    try buildExpectFail("tests/feature_tests/ownership/314X_storage_capability_consumed_choice", "already been consumed");
}
