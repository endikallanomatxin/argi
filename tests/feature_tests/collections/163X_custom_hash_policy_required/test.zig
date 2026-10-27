const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/163X_custom_hash_policy_required" {
    try expectFrontendFailure("tests/feature_tests/collections/163X_custom_hash_policy_required", "construction arguments cannot infer a matching Init target");
}
