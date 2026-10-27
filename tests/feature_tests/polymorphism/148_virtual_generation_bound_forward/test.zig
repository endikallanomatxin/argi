const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/148_virtual_generation_bound_forward" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/148_virtual_generation_bound_forward");
    try runExpect("tests/feature_tests/polymorphism/148_virtual_generation_bound_forward", 0);
}
