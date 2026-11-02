const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/139_virtual_nested_cleanup_effect" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/139_virtual_nested_cleanup_effect");
    try runExpect("tests/feature_tests/polymorphism/139_virtual_nested_cleanup_effect", 0);
}
