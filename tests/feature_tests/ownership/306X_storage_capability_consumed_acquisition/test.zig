const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/306X_storage_capability_consumed_acquisition" {
    try expectFrontendFailure("tests/feature_tests/ownership/306X_storage_capability_consumed_acquisition", "already been consumed");
}
