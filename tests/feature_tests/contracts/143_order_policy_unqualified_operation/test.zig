const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/143_order_policy_unqualified_operation" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/143_order_policy_unqualified_operation");
}
