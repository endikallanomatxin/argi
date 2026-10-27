const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/330_generic_contextual_arrays" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/330_generic_contextual_arrays");
    try runExpect("tests/feature_tests/polymorphism/330_generic_contextual_arrays", 0);
}
