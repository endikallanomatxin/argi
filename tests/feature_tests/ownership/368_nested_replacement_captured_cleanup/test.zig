const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/368_nested_replacement_captured_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/368_nested_replacement_captured_cleanup");
    try runExpect("tests/feature_tests/ownership/368_nested_replacement_captured_cleanup", 42);
}
