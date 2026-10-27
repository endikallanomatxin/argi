const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/85_void_main" {
    try expectSuccessfulBuild("tests/feature_tests/basics/85_void_main");
    try runExpect("tests/feature_tests/basics/85_void_main", 0);
}
