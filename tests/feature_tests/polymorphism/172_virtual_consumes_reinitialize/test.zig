const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/172_virtual_consumes_reinitialize" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/172_virtual_consumes_reinitialize");
    try runExpect("tests/feature_tests/polymorphism/172_virtual_consumes_reinitialize", 0);
}
