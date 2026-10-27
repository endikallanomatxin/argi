const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/171_virtual_consumes_large_return" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/171_virtual_consumes_large_return");
    try runExpect("tests/feature_tests/polymorphism/171_virtual_consumes_large_return", 0);
}
