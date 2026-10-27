const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/309_virtual_bound_scoped_associations" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/309_virtual_bound_scoped_associations");
    try runExpect("tests/feature_tests/contracts/309_virtual_bound_scoped_associations", 0);
}
