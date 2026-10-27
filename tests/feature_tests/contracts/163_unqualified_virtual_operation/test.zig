const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/163_unqualified_virtual_operation" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/163_unqualified_virtual_operation");
}
