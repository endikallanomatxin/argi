const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/313X_storage_capability_post_state_alias" {
    try expectFrontendFailure("tests/feature_tests/ownership/313X_storage_capability_post_state_alias", "already been consumed");
}
