const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/303_concrete_opaque_contents_live" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/303_concrete_opaque_contents_live");
    try runExpect("tests/feature_tests/polymorphism/303_concrete_opaque_contents_live", 0);
}
