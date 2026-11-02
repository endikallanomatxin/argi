const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/52_virtual_bound_values" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/52_virtual_bound_values");
    try runExpect("tests/feature_tests/polymorphism/52_virtual_bound_values", 0);
}
