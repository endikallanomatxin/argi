const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/246_virtual_opaque_storage" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/246_virtual_opaque_storage");
    try runExpect("tests/feature_tests/polymorphism/246_virtual_opaque_storage", 0);
}
