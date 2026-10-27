const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/149_virtual_generation_bound_move" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/149_virtual_generation_bound_move");
    try runExpect("tests/feature_tests/polymorphism/149_virtual_generation_bound_move", 0);
}
