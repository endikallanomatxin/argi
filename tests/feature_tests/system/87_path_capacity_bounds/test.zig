const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/87_path_capacity_bounds" {
    try expectSuccessfulBuild("tests/feature_tests/system/87_path_capacity_bounds");
    try runExpect("tests/feature_tests/system/87_path_capacity_bounds", 0);
}
