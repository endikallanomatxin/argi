const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/154_virtual_generation_bound_repackaged" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/154_virtual_generation_bound_repackaged");
    try runExpect("tests/feature_tests/polymorphism/154_virtual_generation_bound_repackaged", 0);
}
