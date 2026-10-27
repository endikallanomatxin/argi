const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/306X_storage_capability_consumed_acquisition" {
    try buildExpectFail("tests/feature_tests/ownership/306X_storage_capability_consumed_acquisition", "already been consumed");
}
