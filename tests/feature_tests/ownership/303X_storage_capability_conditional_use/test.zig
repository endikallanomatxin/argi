const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/303X_storage_capability_conditional_use" {
    try expectFrontendFailure("tests/feature_tests/ownership/303X_storage_capability_conditional_use", "already been consumed");
}
