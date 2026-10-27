const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/186_virtual_transfer_local_chain" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/186_virtual_transfer_local_chain");
    try runExpect("tests/feature_tests/polymorphism/186_virtual_transfer_local_chain", 0);
}
