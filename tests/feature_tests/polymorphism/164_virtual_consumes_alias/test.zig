const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/164_virtual_consumes_alias" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/164_virtual_consumes_alias");
    try runExpect("tests/feature_tests/polymorphism/164_virtual_consumes_alias", 0);
}
