const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/163X_custom_hash_policy_required" {
    try buildExpectFail("tests/feature_tests/collections/163X_custom_hash_policy_required", "construction arguments cannot infer a matching Init target");
}
