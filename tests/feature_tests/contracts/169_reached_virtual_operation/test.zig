const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/169_reached_virtual_operation" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/169_reached_virtual_operation");
    try support.runExpect("tests/feature_tests/contracts/169_reached_virtual_operation", 0);
}
