const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/314X_storage_capability_consumed_choice" {
    try expectFrontendFailure("tests/feature_tests/ownership/314X_storage_capability_consumed_choice", "already been consumed");
}
