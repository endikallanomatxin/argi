const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/168_virtual_consumes_guarded" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/168_virtual_consumes_guarded");
    try runExpect("tests/feature_tests/polymorphism/168_virtual_consumes_guarded", 0);
}
