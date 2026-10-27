const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/166_virtual_consumes_multiple" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/166_virtual_consumes_multiple");
    try runExpect("tests/feature_tests/polymorphism/166_virtual_consumes_multiple", 0);
}
