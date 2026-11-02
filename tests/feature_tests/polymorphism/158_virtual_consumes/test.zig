const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/158_virtual_consumes" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/158_virtual_consumes");
    try runExpect("tests/feature_tests/polymorphism/158_virtual_consumes", 0);
}
