const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/144_hash_policy_qualified_operation" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/144_hash_policy_qualified_operation");
}
